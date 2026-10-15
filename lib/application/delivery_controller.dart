import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../data/cloud_service.dart';
import '../data/local_store.dart';
import '../domain/models.dart';
import '../domain/maps_location.dart';
import '../domain/shop_import.dart';

class DeliveryController extends ChangeNotifier {
  DeliveryController({
    required this.store,
    required this.photoDirectory,
    this.cloud,
    required this.accountId,
  });
  final LocalStore store;
  final Directory photoDirectory;
  final CloudService? cloud;
  final String accountId;
  AppProfile? profile;
  List<AppProfile> profiles = [];
  List<Shop> shops = [];
  List<DeliveryStop> stops = [];
  List<PendingVisit> pending = [];
  bool busy = false;
  Completer<void>? _idle;
  String? syncError;
  DateTime? lastSynced;

  bool get shared => cloud != null;
  bool get isOwner => profile?.role == UserRole.owner;
  List<AppProfile> get drivers =>
      profiles.where((p) => p.role == UserRole.driver).toList();
  Set<String> get pendingStopIds => pending.map((p) => p.stopId).toSet();
  Future<void> get whenIdle => _idle?.future ?? Future<void>.value();

  Future<void> initialize() async {
    await photoDirectory.create(recursive: true);
    await reloadLocal();
    final cached = await store.getSetting('profiles');
    if (cached != null) {
      profiles = (jsonDecode(cached) as List)
          .map((p) => AppProfile.fromMap(Map<String, dynamic>.from(p as Map)))
          .toList();
      profile = profiles.where((p) => p.id == accountId).firstOrNull;
    }
    final stamp = await store.getSetting('last_synced');
    lastSynced = stamp == null ? null : DateTime.tryParse(stamp);
    if (!shared) {
      profile = const AppProfile(
        id: 'local-owner',
        name: 'Owner',
        role: UserRole.owner,
      );
      profiles = [
        profile!,
        const AppProfile(
          id: 'local-driver',
          name: 'Delivery person',
          role: UserRole.driver,
        ),
      ];
    } else {
      try {
        profile = await cloud!.profile();
      } catch (_) {
        if (profile == null) rethrow;
      }
      await refresh();
    }
    notifyListeners();
  }

  Future<void> reloadLocal() async {
    shops = await store.shops();
    stops = await store.stops();
    pending = await store.pendingVisits();
  }

  Future<void> _exclusive(Future<void> Function() operation) async {
    if (busy) throw StateError('Wait for the current update to finish.');
    busy = true;
    _idle = Completer<void>();
    notifyListeners();
    try {
      await operation();
      await reloadLocal();
    } finally {
      busy = false;
      _idle!.complete();
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (busy) return;
    await _exclusive(() async {
      if (!shared) return;
      syncError = null;
      try {
        for (final visit in await store.pendingVisits()) {
          // The operation ID is durable: a retry after a lost response is idempotent.
          try {
            final result = await cloud!.updateVisit(visit);
            await store.acknowledgeVisit(visit, result);
          } catch (error) {
            syncError ??= errorText(error);
          }
        }
        final snapshot = await cloud!.snapshot();
        profiles = snapshot.profiles;
        profile = profiles.where((p) => p.id == accountId).firstOrNull;
        if (profile == null) {
          throw StateError('Your account needs an owner-assigned role.');
        }
        final oldPhotos = {
          for (final shop in shops) shop.photoPath: shop.localPhotoPath,
        };
        final cachedShops = <Shop>[];
        for (final shop in snapshot.shops) {
          String? localPath = oldPhotos[shop.photoPath];
          if (localPath != null && !await File(localPath).exists()) {
            localPath = null;
          }
          if (shop.photoPath != null && localPath == null) {
            try {
              final photoFile = File(
                p.join(photoDirectory.path, p.basename(shop.photoPath!)),
              );
              if (!await photoFile.exists()) {
                await photoFile.writeAsBytes(
                  await cloud!.downloadPhoto(shop.photoPath!),
                );
              }
              localPath = photoFile.path;
            } catch (_) {
              // A missing photo must not stop location and route synchronization.
            }
          }
          cachedShops.add(shop.withPhoto(shop.photoPath, localPath));
        }
        await store.replaceSnapshot(cachedShops, snapshot.stops);
        await store.setting(
          'profiles',
          jsonEncode(profiles.map((p) => p.toMap()).toList()),
        );
        lastSynced = DateTime.now();
        await store.setting('last_synced', lastSynced!.toIso8601String());
      } catch (error) {
        syncError = errorText(error);
      }
    });
  }

  Future<void> saveShop(Shop shop, {String? pickedPhoto}) async {
    _requireOwner();
    if (shop.name.trim().isEmpty || shop.area.trim().isEmpty) {
      throw ArgumentError('Enter the shop name and area.');
    }
    if ((shop.latitude != null || shop.longitude != null) &&
        !shop.hasCoordinates) {
      throw ArgumentError('Enter valid latitude and longitude together.');
    }
    if (shop.verified && !shop.hasCoordinates) {
      throw ArgumentError('Capture a location before verifying it.');
    }
    if (shop.mapsUrl.isNotEmpty) googleMapsUri(shop.mapsUrl);
    await _exclusive(() async {
      String? localPath = shop.localPhotoPath;
      String? remotePath = shop.photoPath;
      if (pickedPhoto != null) {
        final destination = p.join(
          photoDirectory.path,
          '${const Uuid().v4()}.jpg',
        );
        localPath = (await File(pickedPhoto).copy(destination)).path;
        if (shared) remotePath = await cloud!.uploadPhoto(shop.id, localPath);
      }
      final updated = shop.withPhoto(remotePath, localPath);
      final saved = shared ? await cloud!.saveShop(updated) : updated;
      await store.saveShop(saved.withPhoto(saved.photoPath, localPath));
    });
  }

  Future<ShopImportResult> importShops(
    List<ShopImportRow> rows, {
    void Function(int completed, int total)? onProgress,
  }) async {
    _requireOwner();
    var saved = 0, skipped = 0;
    final failures = <int, String>{};
    await _exclusive(() async {
      // Refresh the owner's directory before comparing an Excel file to it.
      // Failure stops the import; a stale directory must not cause duplicates.
      final existing = shared
          ? (await cloud!.snapshot()).shops
          : await store.shops();
      final keys = existing.map(shopImportKey).toSet();
      final ids = existing.map((s) => s.id).toSet();
      if (shared) await cloud!.ensureOwnerImportSchema();
      String? stoppedBecause;
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i], shop = row.shop;
        if (shop == null || row.error != null) {
          failures[row.number] = row.error ?? 'Invalid row.';
        } else if (keys.contains(shopImportKey(shop)) ||
            ids.contains(shop.id)) {
          skipped++;
        } else if (stoppedBecause != null) {
          failures[row.number] =
              'Not imported. Fix the earlier error and retry this file.';
        } else {
          try {
            final result = shared ? await cloud!.saveImportedShop(shop) : shop;
            await store.saveShop(result);
            keys.add(shopImportKey(shop));
            ids.add(shop.id);
            saved++;
          } catch (error) {
            stoppedBecause = errorText(error);
            failures[row.number] = stoppedBecause;
          }
        }
        onProgress?.call(i + 1, rows.length);
      }
    });
    return ShopImportResult(saved, skipped, failures);
  }

  Future<void> addStop(Shop shop, DateTime date, String driverId) async {
    _requireOwner();
    if (!shop.readyForDelivery) {
      throw StateError(
        'Add a Google Maps link or verify this shop’s entrance location before assigning it.',
      );
    }
    final day = dateKey(date);
    if (stops.any((s) => s.date == day && s.shopId == shop.id)) {
      throw StateError('This shop is already on the list for that day.');
    }
    if (!drivers.any((d) => d.id == driverId)) {
      throw StateError('Select a delivery person.');
    }
    await _exclusive(() async {
      final today = stops.where((s) => s.date == day).toList();
      final order =
          today.fold<int>(0, (max, s) => s.order > max ? s.order : max) + 1;
      final stop = DeliveryStop(
        id: const Uuid().v4(),
        shopId: shop.id,
        date: day,
        driverId: driverId,
        order: order,
      );
      final saved = shared ? await cloud!.addStop(stop) : stop;
      await store.saveStop(saved);
    });
  }

  Future<void> recordVisit(
    DeliveryStop stop,
    VisitStatus status, {
    String reason = '',
  }) async {
    if (status == VisitStatus.failed && reason.trim().isEmpty) {
      throw ArgumentError('Enter why the delivery could not be completed.');
    }
    if (!isOwner && stop.driverId != accountId) {
      throw StateError('This delivery is not assigned to you.');
    }
    if (pendingStopIds.contains(stop.id)) {
      throw StateError('Sync the pending result first.');
    }
    await _exclusive(() async {
      final updated = stop.withStatus(
        status,
        status == VisitStatus.failed ? reason.trim() : '',
      );
      if (!shared) {
        await store.saveStop(updated);
      } else {
        await store.queueVisit(
          updated,
          PendingVisit(
            operationId: const Uuid().v4(),
            stopId: stop.id,
            status: status,
            reason: updated.reason,
            expectedVersion: stop.version,
          ),
        );
      }
    });
    if (shared) await refresh();
  }

  Future<void> removeStop(DeliveryStop stop) async {
    _requireOwner();
    if (stop.status != VisitStatus.pending ||
        pendingStopIds.contains(stop.id)) {
      throw StateError(
        'Only a pending delivery without queued changes can be removed.',
      );
    }
    await _exclusive(() async {
      if (shared) await cloud!.removeStop(stop);
      await store.database.delete(
        'stops',
        where: 'id = ?',
        whereArgs: [stop.id],
      );
    });
  }

  Future<void> discardPending() async {
    if (!shared) return;
    // Verify that the server is reachable BEFORE discarding local results.
    final snapshot = await cloud!.snapshot();
    await _exclusive(() async {
      await store.discardPendingVisits();
      final localPhotos = {
        for (final s in shops) s.photoPath: s.localPhotoPath,
      };
      await store.replaceSnapshot(
        snapshot.shops
            .map((s) => s.withPhoto(s.photoPath, localPhotos[s.photoPath]))
            .toList(),
        snapshot.stops,
      );
      syncError = null;
    });
  }

  void _requireOwner() {
    if (!isOwner) {
      throw StateError('Only an owner can change shops and assignments.');
    }
  }

  Shop? shopFor(String id) => shops.where((s) => s.id == id).firstOrNull;
  List<DeliveryStop> stopsFor(DateTime date) =>
      stops
          .where(
            (s) =>
                s.date == dateKey(date) && (isOwner || s.driverId == accountId),
          )
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
}

String errorText(Object error) {
  final raw = error.toString();
  if (error is FormatException) return error.message;
  if (raw.contains('OWNER_IMPORT_MIGRATION_REQUIRED')) {
    return 'The owner import database update is needed. Run the SQL in supabase/migrations/20261014_owner_import.sql, then retry.';
  }
  if (raw.contains('LOCATION_NOT_VERIFIED')) {
    return 'For delivery using saved Maps links, run supabase/migrations/20261015_maps_link_delivery.sql in Supabase, then retry. Coordinate-only locations still need entrance verification.';
  }
  if (raw.contains('LOCATION_REQUIRED')) {
    return 'Refresh the shop and add a Google Maps link or verify its entrance location.';
  }
  if (raw.contains('SocketException') ||
      raw.contains('ClientException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('TimeoutException')) {
    return 'Cannot connect. Downloaded shops remain available; pending results are saved on this phone.';
  }
  if (raw.contains('VERSION_CONFLICT')) {
    return 'This record changed on another phone. Refresh and review before trying again.';
  }
  if (raw.contains('23505')) {
    return 'This shop is already assigned for that date. Refresh the list.';
  }
  if (raw.contains('NOT_ASSIGNED')) {
    return 'This stop was reassigned. Ask an owner to review the pending result.';
  }
  if (raw.contains('OWNER_REQUIRED') || raw.contains('permission denied')) {
    return 'Your account does not have permission for this action.';
  }
  if (raw.contains('Invalid login credentials')) {
    return 'Check your email and password.';
  }
  if (error is StateError || error is ArgumentError) {
    return raw.replaceFirst(
      RegExp(r'^(Bad state: |Invalid argument\(s\): )'),
      '',
    );
  }
  return 'The update could not be completed. Check your connection and try again.';
}

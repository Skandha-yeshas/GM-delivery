import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../data/cloud_service.dart';
import '../data/local_store.dart';
import '../domain/models.dart';
import '../domain/maps_location.dart';
import '../domain/shop_import.dart';
import '../domain/ledger.dart';
import '../domain/settlement.dart';
import '../domain/route_order.dart';
part 'collection_controller.dart';
part 'settlement_controller.dart';

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
  List<LedgerEntry> ledger = [];
  List<CreditBalance> creditBalances = [];
  List<PendingLedger> pendingLedger = [];
  List<SettlementDay> settlements = [];
  List<PendingSettlement> pendingSettlements = [];
  String? settlementSyncError;
  List<LedgerEntry>? _ledgerProjection;
  final Map<String, CreditBalance> _balanceProjection = {};
  Set<String> _ledgerIds = {};
  String? ledgerSyncError;
  bool busy = false;
  Completer<void>? _idle;
  Completer<void>? _phoneIdle;
  bool _phoneWriting = false, _refreshRequested = false;
  String? syncError;
  DateTime? lastSynced;

  bool get shared => cloud != null;
  bool get isOwner => profile?.role == UserRole.owner;
  List<AppProfile> get drivers =>
      profiles.where((p) => p.role == UserRole.driver).toList();
  Set<String> get pendingStopIds => {
    ...pending.map((p) => p.stopId),
    ...pendingLedger.map((p) => p.command.stopId).whereType<String>(),
  };
  int get pendingCount =>
      pending.length + pendingLedger.length + pendingSettlements.length;
  Future<void> get whenIdle async {
    // A phone save can request another sync while the first one is finishing.
    // Account retirement must also wait for that follow-up work.
    while (busy || _phoneWriting) {
      await Future.wait<void>([
        _idle?.future ?? Future<void>.value(),
        _phoneIdle?.future ?? Future<void>.value(),
      ]);
    }
  }

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

  // Keep protected ChangeNotifier calls inside the notifier subclass.
  void _notifyLocalChange() => notifyListeners();

  Future<void> reloadLocal() async {
    shops = await store.shops();
    stops = await store.stops();
    pending = await store.pendingVisits();
    ledger = await store.ledgerEntries();
    creditBalances = await store.balances();
    pendingLedger = await store.ledgerQueue();
    settlements = await store.settlementDays();
    pendingSettlements = await store.settlementQueue();
    _ledgerProjection = null;
    _balanceProjection.clear();
    _ledgerIds = ledger.map((e) => e.id).toSet();
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
      _startRequestedSync();
    }
  }

  Future<void> refresh() async {
    if (busy) return;
    await _exclusive(() async {
      if (!shared) return;
      syncError = null;
      ledgerSyncError = null;
      settlementSyncError = null;
      try {
        for (final visit in await store.pendingVisits()) {
          // The operation ID is durable: a retry after a lost response is idempotent.
          try {
            final result = await cloud!.updateVisit(visit);
            await store.acknowledgeVisit(visit, result);
          } catch (error) {
            syncError ??= ledgerError(error);
          }
        }
        await _syncLedgerQueue();
        await _syncSettlementQueue();
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
        try {
          final financial = await cloud!.ledgerSnapshot();
          await store.replaceLedgerSnapshot(
            financial.entries,
            financial.balances,
          );
        } catch (error) {
          ledgerSyncError = ledgerError(error);
        }
        try {
          await store.replaceSettlementSnapshot(
            await cloud!.settlementSnapshot(),
          );
        } catch (error) {
          settlementSyncError = settlementError(error);
        }
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
    if (shop.contactName.length > 200 ||
        (shop.postalCode.isNotEmpty &&
            !RegExp(r'^[1-9][0-9]{5}$').hasMatch(shop.postalCode))) {
      throw ArgumentError(
        'Enter a contact name up to 200 characters and a valid six-digit PIN code, or leave them empty.',
      );
    }
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
      if (shared) {
        await cloud!.ensureOwnerImportSchema();
        await cloud!.ensureShopProfileSchema();
      }
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
      if (shared) await cloud!.ensureShopProfileSchema();
      // Failure stops the import; a stale directory must not cause duplicates.
      final existing = shared
          ? (await cloud!.snapshot()).shops
          : await store.shops();
      if (shared && rows.any((row) => row.openingBalancePaise != null)) {
        final financial = await cloud!.ledgerSnapshot();
        await store.replaceLedgerSnapshot(
          financial.entries,
          financial.balances,
        );
      }
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
          if (row.openingBalancePaise != null) {
            final existingShop =
                existing
                    .where(
                      (s) =>
                          shopImportKey(s) == shopImportKey(shop) ||
                          s.id == shop.id,
                    )
                    .firstOrNull ??
                shop;
            try {
              await _importOpening(existingShop, row.openingBalancePaise!);
            } catch (error) {
              failures[row.number] = ledgerError(error);
            }
          }
        } else if (stoppedBecause != null) {
          failures[row.number] =
              'Not imported. Fix the earlier error and retry this file.';
        } else {
          try {
            final result = shared ? await cloud!.saveImportedShop(shop) : shop;
            await store.saveShop(result);
            if (row.openingBalancePaise != null) {
              await _importOpening(result, row.openingBalancePaise!);
            }
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
    if (shared && pendingLedger.isNotEmpty) unawaited(refresh());
    return ShopImportResult(saved, skipped, failures);
  }

  Future<void> addStop(Shop shop, DateTime date, String driverId) async {
    _requireOwner();
    if (isSettlementLocked(driverId, dateKey(date))) {
      throw StateError(
        'Reopen this day’s settlement before adding deliveries.',
      );
    }
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
      final today = stops
          .where((s) => s.date == day && s.driverId == driverId)
          .toList();
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

  Future<void> saveRouteOrder(RouteOrderCommand command) async {
    _requireOwner();
    final arranged = command.arrange();
    await _exclusive(() async {
      if (!drivers.any((d) => d.id == command.driverId)) {
        throw StateError('Select a delivery person.');
      }
      if (isSettlementLocked(command.driverId, command.date)) {
        throw StateError(
          'Reopen this day’s settlement before changing the route.',
        );
      }
      final current = stops
          .where(
            (s) => s.driverId == command.driverId && s.date == command.date,
          )
          .toList();
      if (!command.matches(current)) throw StateError('ROUTE_CHANGED');
      if (current.any((s) => pendingStopIds.contains(s.id))) {
        throw StateError(
          'Sync pending delivery and collection records before changing this route.',
        );
      }
      final ordered = shared ? await cloud!.saveRouteOrder(command) : arranged;
      await store.saveRouteOrder(ordered, expected: shared ? null : command);
    });
  }

  Future<void> recordVisit(
    DeliveryStop stop,
    VisitStatus status, {
    String reason = '',
  }) async {
    if (status == VisitStatus.delivered &&
        !projectedLedger.any(
          (e) =>
              e.command.stopId == stop.id &&
              [LedgerKind.bill, LedgerKind.payment].contains(e.command.kind),
        )) {
      throw StateError('Use the collection form to mark this stop delivered.');
    }
    if (status == VisitStatus.failed && reason.trim().isEmpty) {
      throw ArgumentError('Enter why the delivery could not be completed.');
    }
    if (!isOwner && stop.driverId != accountId) {
      throw StateError('This delivery is not assigned to you.');
    }
    if (pendingStopIds.contains(stop.id)) {
      throw StateError('Sync the pending result first.');
    }
    await _saveOnPhone(() async {
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
    _requestSync();
  }

  Future<void> removeStop(DeliveryStop stop) async {
    _requireOwner();
    if (ledger.any((e) => e.command.stopId == stop.id) ||
        pendingLedger.any((e) => e.command.stopId == stop.id)) {
      throw StateError(
        'Deliveries with ledger records must be kept for audit.',
      );
    }
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
    if (pending.any((p) => p.status == VisitStatus.delivered)) {
      throw StateError(
        'Complete the collection form for older delivered results before resolving other visit conflicts.',
      );
    }
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
        ..sort(compareRouteStops);
}

String errorText(Object error) {
  final raw = error.toString();
  if (raw.contains('ROUTE_ORDER_MIGRATION_REQUIRED')) {
    return 'Run supabase/migrations/20261023_delivery_order.sql in Supabase, then retry saving the route.';
  }
  if (raw.contains('ROUTE_CHANGED')) {
    return 'This route changed on another phone. Reset the draft, sync and review the updated stops.';
  }
  if (raw.contains('SETTLEMENT_LOCKED')) {
    return 'Reopen this day’s settlement before changing deliveries.';
  }
  if (raw.contains('SHOP_PROFILE_MIGRATION_REQUIRED')) {
    return 'Run supabase/migrations/20261020_shop_profiles.sql in Supabase, then retry saving shop details.';
  }
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

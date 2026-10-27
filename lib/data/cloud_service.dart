import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import '../domain/ledger.dart';
import '../domain/settlement.dart';
import '../domain/route_order.dart';
part 'ledger_cloud.dart';
part 'settlement_cloud.dart';

class CloudSnapshot {
  const CloudSnapshot(this.shops, this.stops, this.profiles);
  final List<Shop> shops;
  final List<DeliveryStop> stops;
  final List<AppProfile> profiles;
}

class CloudService {
  CloudService(this.client);
  final SupabaseClient client;
  bool _ownerImportSchemaReady = false;
  bool _shopProfileSchemaReady = false;
  Future<void> ensureShopProfileSchema() async {
    if (_shopProfileSchemaReady) return;
    try {
      await client.from('shops').select('id,contact_name,postal_code').limit(1);
    } on PostgrestException catch (error) {
      if (['42703', 'PGRST204'].contains(error.code)) {
        throw StateError('SHOP_PROFILE_MIGRATION_REQUIRED');
      }
      rethrow;
    }
    _shopProfileSchemaReady = true;
  }

  Future<LedgerSnapshot> ledgerSnapshot() => _ledgerSnapshot();
  Future<LedgerReceipt> sendLedger(LedgerCommand command) =>
      _sendLedger(command);
  Future<List<SettlementDay>> settlementSnapshot() => _settlementSnapshot();
  Future<SettlementDay> sendSettlement(SettlementCommand command) =>
      _sendSettlement(command);

  Future<void> ensureOwnerImportSchema() async {
    if (_ownerImportSchemaReady) return;
    try {
      await client.from('shops').select('id,maps_url').limit(1);
    } on PostgrestException catch (error) {
      if (['42703', 'PGRST204'].contains(error.code)) {
        throw StateError('OWNER_IMPORT_MIGRATION_REQUIRED');
      }
      rethrow;
    }
    _ownerImportSchemaReady = true;
  }

  Future<AppProfile> profile() async {
    final row = await client
        .from('profiles')
        .select()
        .eq('id', client.auth.currentUser!.id)
        .single();
    return AppProfile.fromMap(row);
  }

  Future<CloudSnapshot> snapshot() async {
    // Owners manage all shops; drivers receive only shops they are assigned.
    final rows = await Future.wait([
      _allRows('shops', 'id'),
      _allRows('delivery_stops', 'id'),
      client.from('profiles').select(),
    ]);
    return CloudSnapshot(
      rows[0].map((row) => Shop.fromMap(row)).toList(),
      rows[1].map((row) => DeliveryStop.fromMap(row)).toList(),
      rows[2].map((row) => AppProfile.fromMap(row)).toList(),
    );
  }

  Future<List<Map<String, dynamic>>> _allRows(String table, String sort) async {
    final result = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await client
          .from(table)
          .select()
          .order(sort)
          .range(offset, offset + 499);
      result.addAll(page);
      if (page.length < 500) return result;
      offset += page.length;
    }
  }

  Future<Shop> saveShop(Shop shop) async {
    await ensureOwnerImportSchema();
    await ensureShopProfileSchema();
    final result = await client.rpc(
      'save_shop',
      params: {'p_shop': shop.toMap(), 'p_expected_version': shop.version},
    );
    final row = Map<String, dynamic>.from(result as Map);
    if (!row.containsKey('maps_url')) {
      throw StateError('OWNER_IMPORT_MIGRATION_REQUIRED');
    }
    if (!row.containsKey('contact_name') || !row.containsKey('postal_code')) {
      throw StateError('SHOP_PROFILE_MIGRATION_REQUIRED');
    }
    return Shop.fromMap(row);
  }

  Future<Shop> saveImportedShop(Shop shop) async {
    try {
      return await saveShop(shop);
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
      // A simultaneous import or retry after a lost response already inserted
      // the stable ID. Return its server state without overwriting owner edits.
      final row = await client
          .from('shops')
          .select()
          .eq('id', shop.id)
          .single();
      return Shop.fromMap(row);
    }
  }

  Future<DeliveryStop> addStop(DeliveryStop stop) async {
    final row = await client
        .from('delivery_stops')
        .insert(stop.toMap()..remove('version'))
        .select()
        .single();
    return DeliveryStop.fromMap(row);
  }

  Future<List<DeliveryStop>> saveRouteOrder(RouteOrderCommand command) async {
    try {
      final result = await client.rpc(
        'save_route_order',
        params: {'p_payload': command.toMap()},
      );
      return (result as List)
          .map(
            (row) =>
                DeliveryStop.fromMap(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw StateError('ROUTE_ORDER_MIGRATION_REQUIRED');
      }
      rethrow;
    }
  }

  Future<DeliveryStop> updateVisit(PendingVisit visit) async {
    final result = await client.rpc(
      'record_visit',
      params: {
        'p_operation_id': visit.operationId,
        'p_stop_id': visit.stopId,
        'p_status': visit.status.name,
        'p_reason': visit.reason,
        'p_expected_version': visit.expectedVersion,
      },
    );
    return DeliveryStop.fromMap(Map<String, dynamic>.from(result as Map));
  }

  Future<void> removeStop(DeliveryStop stop) async => client.rpc(
    'remove_stop',
    params: {'p_stop_id': stop.id, 'p_expected_version': stop.version},
  );

  Future<String> uploadPhoto(String shopId, String localPath) async {
    final path = '$shopId/${const Uuid().v4()}.jpg';
    await client.storage
        .from('shop-photos')
        .upload(
          path,
          File(localPath),
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  Future<List<int>> downloadPhoto(String path) =>
      client.storage.from('shop-photos').download(path);
}

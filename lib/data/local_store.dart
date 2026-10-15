import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../domain/models.dart';

class LocalStore {
  LocalStore(this.database);
  final Database database;

  static Future<LocalStore> open(String accountId) async {
    final path = p.join(await getDatabasesPath(), 'gm_delivery_$accountId.db');
    return LocalStore(
      await openDatabase(
        path,
        version: 2,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => createSchema(db),
        onUpgrade: upgradeSchema,
      ),
    );
  }

  static Future<void> upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE shops ADD COLUMN maps_url TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  static Future<void> createSchema(Database db) async {
    await db.execute('''CREATE TABLE shops (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, area TEXT NOT NULL,
      address TEXT NOT NULL, landmark TEXT NOT NULL, phone TEXT NOT NULL,
      notes TEXT NOT NULL, maps_url TEXT NOT NULL DEFAULT '', latitude REAL, longitude REAL,
      verified INTEGER NOT NULL, photo_path TEXT, local_photo_path TEXT,
      version INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE stops (
      id TEXT PRIMARY KEY, shop_id TEXT NOT NULL REFERENCES shops(id),
      service_date TEXT NOT NULL, driver_id TEXT NOT NULL,
      stop_order INTEGER NOT NULL, status TEXT NOT NULL, reason TEXT NOT NULL,
      version INTEGER NOT NULL, UNIQUE(shop_id, service_date))''');
    await db.execute(
      '''CREATE TABLE pending_visits (
      stop_id TEXT PRIMARY KEY REFERENCES stops(id), operation_id TEXT NOT NULL,
      status TEXT NOT NULL, reason TEXT NOT NULL, expected_version INTEGER NOT NULL)''',
    );
    await db.execute(
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  Future<List<Shop>> shops() async => (await database.query(
    'shops',
    orderBy: 'name COLLATE NOCASE',
  )).map(Shop.fromMap).toList();
  Future<List<DeliveryStop>> stops() async => (await database.query(
    'stops',
    orderBy: 'service_date, stop_order, id',
  )).map(DeliveryStop.fromMap).toList();
  Future<List<PendingVisit>> pendingVisits() async => (await database.query(
    'pending_visits',
  )).map(PendingVisit.fromMap).toList();

  Future<void> saveShop(Shop shop) => database.transaction((txn) async {
    // UPDATE instead of REPLACE: REPLACE can cascade-delete related records.
    final changed = await txn.update(
      'shops',
      shop.toMap(local: true),
      where: 'id = ?',
      whereArgs: [shop.id],
    );
    if (changed == 0) await txn.insert('shops', shop.toMap(local: true));
  });

  Future<void> saveStop(DeliveryStop stop) => database.transaction((txn) async {
    final changed = await txn.update(
      'stops',
      stop.toMap(),
      where: 'id = ?',
      whereArgs: [stop.id],
    );
    if (changed == 0) await txn.insert('stops', stop.toMap());
  });

  Future<void> queueVisit(DeliveryStop stop, PendingVisit visit) =>
      database.transaction((txn) async {
        final existing = await txn.query(
          'pending_visits',
          where: 'stop_id = ?',
          whereArgs: [stop.id],
        );
        if (existing.isNotEmpty) {
          throw StateError('Sync this stop before changing its result again.');
        }
        await txn.update(
          'stops',
          stop.toMap(),
          where: 'id = ?',
          whereArgs: [stop.id],
        );
        await txn.insert('pending_visits', visit.toMap());
      });

  Future<void> acknowledgeVisit(PendingVisit visit, DeliveryStop remote) =>
      database.transaction((txn) async {
        await txn.update(
          'stops',
          remote.toMap(),
          where: 'id = ?',
          whereArgs: [remote.id],
        );
        await txn.delete(
          'pending_visits',
          where: 'operation_id = ?',
          whereArgs: [visit.operationId],
        );
      });

  Future<void> replaceSnapshot(
    List<Shop> shops,
    List<DeliveryStop> stops,
  ) => database.transaction((txn) async {
    final pending = await txn.query('pending_visits');
    final pendingIds = pending.map((r) => r['stop_id'] as String).toSet();
    for (final stop in await txn.query('stops')) {
      if (!pendingIds.contains(stop['id'])) {
        await txn.delete('stops', where: 'id = ?', whereArgs: [stop['id']]);
      }
    }
    // Retain only shops referenced by pending local updates when access changes.
    final retainedStops = await txn.query('stops');
    final retainedShopIds = retainedStops
        .map((r) => r['shop_id'] as String)
        .toSet();
    for (final shop in await txn.query('shops')) {
      if (!retainedShopIds.contains(shop['id'])) {
        await txn.delete('shops', where: 'id = ?', whereArgs: [shop['id']]);
      }
    }
    for (final shop in shops) {
      final changed = await txn.update(
        'shops',
        shop.toMap(local: true),
        where: 'id = ?',
        whereArgs: [shop.id],
      );
      if (changed == 0) await txn.insert('shops', shop.toMap(local: true));
    }
    for (final stop in stops) {
      if (!pendingIds.contains(stop.id)) {
        await txn.insert('stops', stop.toMap());
      }
    }
  });

  Future<void> discardPendingVisits() =>
      database.delete('pending_visits').then((_) {});

  Future<void> setting(String key, String value) async => database
      .insert('settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});

  Future<String?> getSetting(String key) async {
    final rows = await database.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> close() => database.close();
}

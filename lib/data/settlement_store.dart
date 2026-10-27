part of 'local_store.dart';

Future<void> createSettlementTables(DatabaseExecutor db) async {
  await db.execute(
    'CREATE TABLE IF NOT EXISTS settlement_days (driver_id TEXT NOT NULL, service_date TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY(driver_id,service_date))',
  );
  await db.execute(
    'CREATE TABLE IF NOT EXISTS pending_settlements (operation_id TEXT PRIMARY KEY, driver_id TEXT NOT NULL, service_date TEXT NOT NULL, payload TEXT NOT NULL, last_error TEXT, rejected INTEGER NOT NULL DEFAULT 0, UNIQUE(driver_id,service_date))',
  );
}

extension SettlementStore on LocalStore {
  Future<List<SettlementDay>> settlementDays() async =>
      (await database.query('settlement_days'))
          .map(
            (r) => SettlementDay.fromMap(
              jsonDecode(r['data'] as String) as Map<String, dynamic>,
            ),
          )
          .toList();
  Future<List<PendingSettlement>> settlementQueue() async =>
      (await database.query('pending_settlements', orderBy: 'rowid'))
          .map(
            (r) => PendingSettlement(
              SettlementCommand.fromMap(
                jsonDecode(r['payload'] as String) as Map<String, dynamic>,
              ),
              error: r['last_error'] as String?,
              rejected: r['rejected'] == 1,
            ),
          )
          .toList();

  Future<void> queueSettlement(SettlementCommand c) =>
      database.transaction((txn) async {
        final previous = await txn.query(
          'pending_settlements',
          where: 'operation_id=?',
          whereArgs: [c.operationId],
        );
        if (previous.isNotEmpty) {
          if (previous.single['payload'] != jsonEncode(c.toMap())) {
            throw StateError('Operation ID already used for different data.');
          }
          return;
        }
        if ((await txn.query('pending_visits')).isNotEmpty ||
            (await txn.query('pending_ledger')).isNotEmpty ||
            (await txn.query('pending_settlements')).isNotEmpty) {
          throw StateError('Sync all pending operations before settlement.');
        }
        await txn.insert('pending_settlements', {
          'operation_id': c.operationId,
          'driver_id': c.driverId,
          'service_date': c.date,
          'payload': jsonEncode(c.toMap()),
        });
      });

  Future<void> settlementFailure(
    String id,
    String message, {
    bool rejected = false,
  }) async {
    await database.update(
      'pending_settlements',
      {'last_error': message, 'rejected': rejected ? 1 : 0},
      where: 'operation_id=?',
      whereArgs: [id],
    );
  }

  Future<void> discardRejectedSettlement(String id) async {
    final changed = await database.delete(
      'pending_settlements',
      where: 'operation_id=? AND rejected=1',
      whereArgs: [id],
    );
    if (changed == 0) {
      throw StateError(
        'A request with an uncertain result must be retried with its saved ID.',
      );
    }
  }

  Future<void> acknowledgeSettlement(String id, SettlementDay day) =>
      database.transaction((txn) async {
        if (!day.events.any((e) => e.command.operationId == id)) {
          throw StateError(
            'Settlement receipt does not contain this operation.',
          );
        }
        await _cacheSettlementDay(txn, day);
        await txn.delete(
          'pending_settlements',
          where: 'operation_id=?',
          whereArgs: [id],
        );
        await txn.delete(
          'settings',
          where: 'key=?',
          whereArgs: ['settlement-draft:${day.driverId}:${day.date}'],
        );
      });
  Future<void> replaceSettlementSnapshot(List<SettlementDay> days) =>
      database.transaction((txn) async {
        final pending = await txn.query('pending_settlements');
        for (final row in await txn.query('settlement_days')) {
          if (!days.any(
                (d) =>
                    d.driverId == row['driver_id'] &&
                    d.date == row['service_date'],
              ) &&
              !pending.any(
                (p) =>
                    p['driver_id'] == row['driver_id'] &&
                    p['service_date'] == row['service_date'],
              )) {
            await txn.delete(
              'settlement_days',
              where: 'driver_id=? AND service_date=?',
              whereArgs: [row['driver_id'], row['service_date']],
            );
          }
        }
        for (final day in days) {
          await _cacheSettlementDay(txn, day);
        }
      });
}

Future<void> _cacheSettlementDay(DatabaseExecutor db, SettlementDay day) async {
  final rows = await db.query(
    'settlement_days',
    where: 'driver_id=? AND service_date=?',
    whereArgs: [day.driverId, day.date],
  );
  if (rows.isNotEmpty) {
    final old = SettlementDay.fromMap(
      jsonDecode(rows.single['data'] as String) as Map<String, dynamic>,
    );
    if (old.revision > day.revision ||
        (old.revision == day.revision &&
            old.totals.ledgerVersion > day.totals.ledgerVersion)) {
      return;
    }
  }
  await db.insert('settlement_days', {
    'driver_id': day.driverId,
    'service_date': day.date,
    'data': jsonEncode(day.toMap()),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> assertCollectionDayOpen(
  DatabaseExecutor db,
  String? stopId,
) async {
  if (stopId == null) return;
  final stops = await db.query('stops', where: 'id=?', whereArgs: [stopId]);
  if (stops.isEmpty) return;
  final s = stops.single;
  final pending = await db.query(
    'pending_settlements',
    where: 'driver_id=? AND service_date=? AND rejected=0',
    whereArgs: [s['driver_id'], s['service_date']],
  );
  final days = await db.query(
    'settlement_days',
    where: 'driver_id=? AND service_date=?',
    whereArgs: [s['driver_id'], s['service_date']],
  );
  if (pending.isNotEmpty ||
      (days.isNotEmpty &&
          SettlementDay.fromMap(
            jsonDecode(days.single['data'] as String) as Map<String, dynamic>,
          ).locked)) {
    throw StateError(
      'This day is locked for settlement. An owner must reopen it before collections change.',
    );
  }
}

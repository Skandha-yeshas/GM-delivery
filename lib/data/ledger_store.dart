part of 'local_store.dart';

Future<void> createLedgerTables(DatabaseExecutor db) async {
  await db.execute(
    'CREATE TABLE ledger_cache (operation_id TEXT PRIMARY KEY, shop_id TEXT NOT NULL, sequence INTEGER NOT NULL, data TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE credit_balances (shop_id TEXT PRIMARY KEY, version INTEGER NOT NULL, data TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE pending_ledger (queue_order INTEGER PRIMARY KEY AUTOINCREMENT, operation_id TEXT NOT NULL UNIQUE, payload TEXT NOT NULL, actor_id TEXT NOT NULL, last_error TEXT)',
  );
}

extension LedgerStore on LocalStore {
  Future<List<LedgerEntry>> ledgerEntries() async =>
      (await database.query('ledger_cache', orderBy: 'sequence'))
          .map(
            (r) => LedgerEntry.fromMap(
              jsonDecode(r['data'] as String) as Map<String, dynamic>,
            ),
          )
          .toList();
  Future<List<CreditBalance>> balances() async =>
      (await database.query('credit_balances'))
          .map(
            (r) => CreditBalance.fromMap(
              jsonDecode(r['data'] as String) as Map<String, dynamic>,
            ),
          )
          .toList();
  Future<List<PendingLedger>> ledgerQueue() async =>
      (await database.query('pending_ledger', orderBy: 'queue_order'))
          .map(
            (r) => PendingLedger(
              LedgerCommand.fromMap(
                jsonDecode(r['payload'] as String) as Map<String, dynamic>,
              ),
              r['actor_id'] as String,
              error: r['last_error'] as String?,
            ),
          )
          .toList();

  Future<void> queueLedger(PendingLedger pending) =>
      database.transaction((txn) async {
        final c = pending.command;
        final prior = await txn.query(
          'pending_ledger',
          where: 'operation_id = ?',
          whereArgs: [c.operationId],
        );
        if (prior.isNotEmpty) {
          if (prior.single['payload'] != jsonEncode(c.toMap()) ||
              prior.single['actor_id'] != pending.actorId) {
            throw StateError('Operation ID already used for different data.');
          }
          return;
        }
        await assertCollectionDayOpen(txn, c.stopId);
        if ([LedgerKind.bill, LedgerKind.payment].contains(c.kind)) {
          final legacy = await txn.query(
            'pending_visits',
            where: 'stop_id = ?',
            whereArgs: [c.stopId],
          );
          if (legacy.isNotEmpty &&
              (legacy.single['status'] != 'delivered' ||
                  legacy.single['operation_id'] != c.legacyVisitOperationId ||
                  legacy.single['expected_version'] != c.expectedStopVersion)) {
            throw StateError(
              'Sync the existing visit result before recording a collection.',
            );
          }
          final rows = await txn.query(
            'stops',
            where: 'id = ?',
            whereArgs: [c.stopId],
          );
          if (rows.isEmpty || rows.single['version'] != c.expectedStopVersion) {
            throw StateError('Delivery changed. Reopen its collection form.');
          }
          await txn.update(
            'stops',
            {
              'status': 'delivered',
              'reason': '',
              'version': c.expectedStopVersion! + 1,
            },
            where: 'id = ?',
            whereArgs: [c.stopId],
          );
        }
        await txn.insert('pending_ledger', {
          'operation_id': c.operationId,
          'payload': jsonEncode(c.toMap()),
          'actor_id': pending.actorId,
        });
        if (c.legacyVisitOperationId != null) {
          await txn.delete(
            'pending_visits',
            where: 'operation_id = ? AND stop_id = ?',
            whereArgs: [c.legacyVisitOperationId, c.stopId],
          );
        }
      });

  Future<void> ledgerFailure(String operationId, String message) async {
    await database.update(
      'pending_ledger',
      {'last_error': message},
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }

  Future<void> acknowledgeLedger(LedgerEntry entry, CreditBalance balance) =>
      database.transaction((txn) async {
        await txn.insert('ledger_cache', {
          'operation_id': entry.id,
          'shop_id': entry.command.shopId,
          'sequence': entry.sequence,
          'data': jsonEncode(entry.toMap()),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        final cached = await txn.query(
          'credit_balances',
          where: 'shop_id = ?',
          whereArgs: [balance.shopId],
        );
        if (cached.isEmpty ||
            (cached.single['version'] as int) <= balance.version) {
          await txn.insert('credit_balances', {
            'shop_id': balance.shopId,
            'version': balance.version,
            'data': jsonEncode(balance.toMap()),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await txn.delete(
          'pending_ledger',
          where: 'operation_id = ?',
          whereArgs: [entry.id],
        );
        final later = (await txn.query('pending_ledger')).map(
          (r) => LedgerCommand.fromMap(
            jsonDecode(r['payload'] as String) as Map<String, dynamic>,
          ),
        );
        if (entry.stopAfter != null &&
            !later.any(
              (c) =>
                  [LedgerKind.bill, LedgerKind.payment].contains(c.kind) &&
                  c.stopId == entry.stopAfter!.id,
            )) {
          await txn.update(
            'stops',
            entry.stopAfter!.toMap(),
            where: 'id = ?',
            whereArgs: [entry.stopAfter!.id],
          );
        }
      });

  Future<void> replaceLedgerSnapshot(
    List<LedgerEntry> entries,
    List<CreditBalance> balances,
  ) => database.transaction((txn) async {
    final pendingShops = (await txn.query('pending_ledger'))
        .map((r) => (jsonDecode(r['payload'] as String) as Map)['shop_id'])
        .toSet();
    final visible = balances.map((b) => b.shopId).toSet();
    for (final row in await txn.query('ledger_cache')) {
      if (!pendingShops.contains(row['shop_id'])) {
        await txn.delete(
          'ledger_cache',
          where: 'operation_id = ?',
          whereArgs: [row['operation_id']],
        );
      }
    }
    for (final row in await txn.query('credit_balances')) {
      if (!visible.contains(row['shop_id']) &&
          !pendingShops.contains(row['shop_id'])) {
        await txn.delete(
          'credit_balances',
          where: 'shop_id = ?',
          whereArgs: [row['shop_id']],
        );
      }
    }
    for (final entry in entries) {
      await txn.insert('ledger_cache', {
        'operation_id': entry.id,
        'shop_id': entry.command.shopId,
        'sequence': entry.sequence,
        'data': jsonEncode(entry.toMap()),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final balance in balances) {
      final old = await txn.query(
        'credit_balances',
        where: 'shop_id = ?',
        whereArgs: [balance.shopId],
      );
      if (old.isEmpty || (old.single['version'] as int) <= balance.version) {
        await txn.insert('credit_balances', {
          'shop_id': balance.shopId,
          'version': balance.version,
          'data': jsonEncode(balance.toMap()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  });
}

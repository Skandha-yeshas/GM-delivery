import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gm_delivery/application/delivery_controller.dart';
import 'package:gm_delivery/data/local_store.dart';
import 'package:gm_delivery/domain/ledger.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/domain/shop_import.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test(
    'Excel opening balances use paise and retries preserve existing and corrected openings',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gm_opening_import_',
      );
      final store = LocalStore(
        await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            onCreate: (db, _) => LocalStore.createSchema(db),
            version: 3,
          ),
        ),
      );
      final c = DeliveryController(
        store: store,
        photoDirectory: directory,
        accountId: 'local',
      );
      try {
        await c.initialize();
        await c.saveShop(const Shop(id: 'known', name: 'Alpha', area: 'East'));
        final excel = Excel.createExcel(), sheetName = 'Sheet1';
        excel[sheetName].appendRow([
          TextCellValue('Name'),
          TextCellValue('Area'),
          TextCellValue('Opening balance'),
        ]);
        excel[sheetName].appendRow([
          TextCellValue('Alpha'),
          TextCellValue('East'),
          TextCellValue('100.01'),
        ]);
        excel[sheetName].appendRow([
          TextCellValue('Beta'),
          TextCellValue('West'),
          DoubleCellValue(42.50),
        ]);
        excel[sheetName].appendRow([
          TextCellValue('Bad amount'),
          TextCellValue('West'),
          TextCellValue('1.001'),
        ]);
        final rows = parseShopWorkbook(
          Uint8List.fromList(excel.encode()!),
        ).single.rows;
        expect(rows[0].openingBalancePaise, 10001);
        expect(rows[1].openingBalancePaise, 4250);
        expect(rows[2].error, isNotNull);
        final first = await c.importShops(rows);
        expect(first.saved, 1);
        expect(first.skipped, 1);
        expect(first.failures.length, 1);
        expect(c.balanceFor('known').balancePaise, 10001);
        expect(c.ledger, hasLength(2));
        final opening = c.ledger.singleWhere(
          (e) => e.command.shopId == 'known',
        );
        await c.submitLedger(
          LedgerCommand(
            operationId: 'correct-opening',
            shopId: 'known',
            kind: LedgerKind.correction,
            capturedAt: DateTime.now().toUtc(),
            originalId: opening.id,
            expectedRevision: 1,
            billPaise: 9001,
            reason: 'Owner verified starting debt',
          ),
        );
        await c.importShops(rows);
        expect(c.balanceFor('known').balancePaise, 9001);
        expect(c.ledger, hasLength(3));
        expect(
          c.ledger.where((e) => e.command.kind == LedgerKind.opening),
          hasLength(2),
        );
      } finally {
        c.dispose();
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'SQLite v2 upgrade retains shops, stops and durable visit queue',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gm_ledger_upgrade_',
      );
      final path = '${directory.path}/v2.db';
      final old = LocalStore(
        await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 2,
            onCreate: (db, _) async {
              await LocalStore.createSchema(db);
              await db.execute('DROP TABLE ledger_cache');
              await db.execute('DROP TABLE credit_balances');
              await db.execute('DROP TABLE pending_ledger');
            },
          ),
        ),
      );
      await old.saveShop(const Shop(id: 'shop', name: 'Shop', area: 'Area'));
      const stop = DeliveryStop(
        id: 'stop',
        shopId: 'shop',
        date: '2026-10-16',
        driverId: 'driver',
        order: 1,
        version: 1,
      );
      await old.saveStop(stop);
      await old.queueVisit(
        stop.withStatus(VisitStatus.failed, 'Closed'),
        const PendingVisit(
          operationId: 'old-operation',
          stopId: 'stop',
          status: VisitStatus.failed,
          reason: 'Closed',
          expectedVersion: 1,
        ),
      );
      await old.close();
      final upgraded = LocalStore(
        await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 3,
            onUpgrade: LocalStore.upgradeSchema,
          ),
        ),
      );
      try {
        expect((await upgraded.shops()).single.name, 'Shop');
        expect((await upgraded.stops()).single.reason, 'Closed');
        expect(
          (await upgraded.pendingVisits()).single.operationId,
          'old-operation',
        );
        expect(await upgraded.ledgerEntries(), isEmpty);
        expect(await upgraded.ledgerQueue(), isEmpty);
      } finally {
        await upgraded.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

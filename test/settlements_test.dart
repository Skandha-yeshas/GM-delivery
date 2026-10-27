import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gm_delivery/application/delivery_controller.dart';
import 'package:gm_delivery/data/cloud_service.dart';
import 'package:gm_delivery/data/local_store.dart';
import 'package:gm_delivery/domain/ledger.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/domain/settlement.dart';
import 'package:gm_delivery/presentation/settlement_screen.dart';

const owner = AppProfile(id: 'owner', name: 'Owner', role: UserRole.owner);
const driver = AppProfile(id: 'driver', name: 'Ravi', role: UserRole.driver);
const shop = Shop(
  id: 'shop',
  name: 'Alpha',
  area: 'Market',
  mapsUrl: 'https://maps.app.goo.gl/example',
);
const stop = DeliveryStop(
  id: 'stop',
  shopId: 'shop',
  date: '2026-10-15',
  driverId: 'driver',
  order: 1,
  version: 1,
);

class SettlementTransport extends CloudService {
  SettlementTransport()
    : super(SupabaseClient('https://example.supabase.co', 'public-test'));
  bool loseReply = false, offline = false;
  Object? failure;
  final requests = <String>[];
  SettlementDay day = const SettlementDay(
    driverId: 'driver',
    date: '2026-10-15',
    totals: SettlementTotals(
      cash: 40000,
      bills: 100000,
      credit: 60000,
      ledgerVersion: 1,
    ),
  );
  @override
  Future<AppProfile> profile() async => driver;
  @override
  Future<CloudSnapshot> snapshot() async =>
      const CloudSnapshot([shop], [stop], [owner, driver]);
  @override
  Future<LedgerSnapshot> ledgerSnapshot() async => const LedgerSnapshot([], []);
  @override
  Future<List<SettlementDay>> settlementSnapshot() async {
    if (offline) throw const SocketException('offline');
    return [day];
  }

  @override
  Future<SettlementDay> sendSettlement(SettlementCommand c) async {
    requests.add(jsonEncode(c.toMap()));
    if (offline) throw const SocketException('offline');
    if (failure != null) throw failure!;
    if (!day.events.any((e) => e.command.operationId == c.operationId)) {
      day = SettlementDay(
        driverId: day.driverId,
        date: day.date,
        totals: day.totals,
        events: [
          ...day.events,
          SettlementEvent(
            command: c,
            actorId: 'driver',
            revision: day.revision + 1,
            recordedAt: DateTime.now(),
            totals: day.totals,
          ),
        ],
      );
      if (loseReply) {
        loseReply = false;
        throw const SocketException('reply lost');
      }
    }
    return day;
  }
}

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory dir;
  late LocalStore store;
  late DeliveryController c;
  Future<LocalStore> openStore() async => LocalStore(
    await databaseFactoryFfi.openDatabase(
      '${dir.path}/state.db',
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) => LocalStore.createSchema(db),
        onUpgrade: LocalStore.upgradeSchema,
      ),
    ),
  );
  Future<void> switchTo(AppProfile p) async {
    c.profile = p;
    await c.reloadLocal();
  }

  Future<void> connect(SettlementTransport cloud) async {
    c.dispose();
    c = DeliveryController(
      store: store,
      photoDirectory: dir,
      accountId: 'driver',
      cloud: cloud,
    );
    await c.initialize();
  }

  LedgerCommand bill(
    String id, {
    int amount = 100000,
    int paid = 40000,
    PaymentMode mode = PaymentMode.cash,
  }) => LedgerCommand(
    operationId: id,
    shopId: 'shop',
    kind: LedgerKind.bill,
    capturedAt: DateTime(2026, 10, 17),
    stopId: 'stop',
    expectedStopVersion: c.stops.single.version,
    billNumber: id,
    billPaise: amount,
    collectedPaise: paid,
    mode: mode,
  );
  SettlementCommand action(
    String id,
    SettlementAction action, {
    int handed = 40000,
    String reason = '',
  }) {
    final day = c.settlementFor('driver', '2026-10-15');
    return SettlementCommand(
      operationId: id,
      driverId: 'driver',
      date: day.date,
      action: action,
      expectedRevision: day.revision,
      ledgerVersion: day.totals.ledgerVersion,
      handedPaise: handed,
      reason: reason,
      capturedAt: DateTime.now(),
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gm_settlement_');
    store = await openStore();
    c = DeliveryController(
      store: store,
      photoDirectory: dir,
      accountId: 'driver',
    );
    await c.initialize();
    await store.saveShop(shop);
    await store.saveStop(stop);
    await c.reloadLocal();
  });
  tearDown(() async {
    await c.whenIdle;
    c.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });

  test(
    'corrected effective totals stay on original delivery day and include payment modes',
    () async {
      await c.submitLedger(bill('cash'));
      await c.submitLedger(
        bill('upi', amount: 10000, paid: 10000, mode: PaymentMode.upi),
      );
      await c.submitLedger(
        bill('cheque', amount: 5000, paid: 5000, mode: PaymentMode.cheque),
      );
      await c.submitLedger(
        bill('credit', amount: 20000, paid: 0, mode: PaymentMode.credit),
      );
      await c.submitLedger(
        LedgerCommand(
          operationId: 'old',
          shopId: 'shop',
          kind: LedgerKind.payment,
          capturedAt: DateTime.now(),
          stopId: 'stop',
          expectedStopVersion: c.stops.single.version,
          collectedPaise: 10000,
          mode: PaymentMode.cash,
        ),
      );
      await c.submitLedger(
        LedgerCommand(
          operationId: 'fix',
          shopId: 'shop',
          kind: LedgerKind.correction,
          originalId: 'cash',
          expectedRevision: 1,
          capturedAt: DateTime(2026, 10, 18),
          stopId: 'stop',
          billNumber: 'cash',
          billPaise: 90000,
          collectedPaise: 30000,
          mode: PaymentMode.cash,
          reason: 'Receipt checked',
        ),
      );
      final t = c.settlementFor('driver', '2026-10-15').totals;
      expect(t.bills, 125000);
      expect(t.cash, 40000);
      expect(t.oldPayments, 10000);
      expect(t.upi, 10000);
      expect(t.cheque, 5000);
      expect(t.credit, 80000);
      expect(t.expectedCash, 40000);
      expect(c.settlementFor('driver', '2026-10-18').totals.cash, 0);
    },
  );
  test(
    'difference requires reason; submission locks additions and owner corrections; approval/reopen is audited',
    () async {
      await c.submitLedger(bill('cash'));
      await switchTo(driver);
      await expectLater(
        c.submitSettlement(
          action('s1', SettlementAction.submit, handed: 39000),
        ),
        throwsStateError,
      );
      await c.submitSettlement(
        action(
          's1',
          SettlementAction.submit,
          handed: 39000,
          reason: 'Short 10, informed owner',
        ),
      );
      expect(c.isSettlementLocked('driver', '2026-10-15'), isTrue);
      await expectLater(c.submitLedger(bill('extra')), throwsStateError);
      await expectLater(
        c.submitSettlement(
          action('bad', SettlementAction.approve, handed: 39000),
        ),
        throwsStateError,
      );
      await switchTo(owner);
      await expectLater(
        c.submitLedger(
          LedgerCommand(
            operationId: 'fix',
            shopId: 'shop',
            kind: LedgerKind.correction,
            originalId: 'cash',
            expectedRevision: 1,
            stopId: 'stop',
            capturedAt: DateTime.now(),
            billNumber: 'cash',
            billPaise: 100000,
            collectedPaise: 39000,
            mode: PaymentMode.cash,
            reason: 'Fix',
          ),
        ),
        throwsStateError,
      );
      await c.submitSettlement(
        action('a1', SettlementAction.approve, handed: 39000),
      );
      await expectLater(
        c.submitSettlement(action('r1', SettlementAction.reopen)),
        throwsFormatException,
      );
      await c.submitSettlement(
        action(
          'r1',
          SettlementAction.reopen,
          handed: 39000,
          reason: 'Recheck the receipt',
        ),
      );
      expect(c.isSettlementLocked('driver', '2026-10-15'), isFalse);
      expect(
        c
            .settlementFor('driver', '2026-10-15')
            .events
            .map((e) => e.command.action),
        [
          SettlementAction.submit,
          SettlementAction.approve,
          SettlementAction.reopen,
        ],
      );
      await c.submitLedger(bill('extra'));
    },
  );
  test(
    'both unsynced visit and money queues block settlement atomically',
    () async {
      final cloud = SettlementTransport();
      await connect(cloud);
      await store.queueVisit(
        stop.withStatus(VisitStatus.failed, 'Closed'),
        const PendingVisit(
          operationId: 'visit-op',
          stopId: 'stop',
          status: VisitStatus.failed,
          reason: 'Closed',
          expectedVersion: 1,
        ),
      );
      await c.reloadLocal();
      expect(c.pendingOperationDetails.single, contains('visit-op'));
      await expectLater(
        c.submitSettlement(action('s1', SettlementAction.submit)),
        throwsStateError,
      );
      await store.database.delete('pending_visits');
      await store.saveStop(stop);
      await store.queueLedger(PendingLedger(bill('queued-money'), driver.id));
      await c.reloadLocal();
      expect(c.pendingOperationDetails.single, contains('queued-money'));
      await expectLater(
        c.submitSettlement(action('s2', SettlementAction.submit)),
        throwsStateError,
      );
      expect(await store.settlementQueue(), isEmpty);
    },
  );
  test(
    'lost settlement reply survives SQLite restart, retains exact payload and replays once',
    () async {
      final cloud = SettlementTransport()..loseReply = true;
      await connect(cloud);
      await c.submitSettlement(action('lost', SettlementAction.submit));
      await c.whenIdle;
      expect(c.pendingSettlements, isNotEmpty);
      expect(cloud.day.events.length, 1);
      expect(c.isSettlementLocked('driver', '2026-10-15'), isTrue);
      await expectLater(c.discardRejectedSettlement('lost'), throwsStateError);
      final payload = cloud.requests.single;
      c.dispose();
      await store.close();
      store = await openStore();
      c = DeliveryController(
        store: store,
        photoDirectory: dir,
        accountId: 'driver',
        cloud: cloud,
      );
      await c.initialize();
      await c.whenIdle;
      expect(cloud.requests.last, payload);
      expect(cloud.day.events.length, 1);
      expect(c.pendingSettlements, isEmpty);
      expect(c.settlementFor('driver', '2026-10-15').status, 'Submitted');
    },
  );
  test(
    'server revision rejection is retained for explicit review; drafts survive restart',
    () async {
      final cloud = SettlementTransport()
        ..failure = const PostgrestException(
          message: 'SETTLEMENT_DAY_CHANGED',
          code: 'P0001',
        );
      await connect(cloud);
      await c.saveSettlementDraft('driver', '2026-10-15', '390.00', 'Short 10');
      await c.submitSettlement(action('stale', SettlementAction.submit));
      await c.whenIdle;
      expect(c.pendingSettlements.single.rejected, isTrue);
      expect(cloud.day.events, isEmpty);
      await c.discardRejectedSettlement('stale');
      expect(c.pendingCount, 0);
      c.dispose();
      await store.close();
      store = await openStore();
      c = DeliveryController(
        store: store,
        photoDirectory: dir,
        accountId: 'driver',
      );
      await c.initialize();
      final saved =
          jsonDecode(
                (await store.getSetting('settlement-draft:driver:2026-10-15'))!,
              )
              as Map;
      expect(saved['amount'], '390.00');
      expect(saved['reason'], 'Short 10');
    },
  );
  test('v3 upgrade preserves finance history and queued IDs', () async {
    await c.submitLedger(bill('saved'));
    await store.queueLedger(PendingLedger(bill('queued'), driver.id));
    c.dispose();
    await store.close();
    final db = await databaseFactoryFfi.openDatabase('${dir.path}/state.db');
    await db.execute('DROP TABLE pending_settlements');
    await db.execute('DROP TABLE settlement_days');
    await db.setVersion(3);
    await db.close();
    store = await openStore();
    c = DeliveryController(
      store: store,
      photoDirectory: dir,
      accountId: 'driver',
    );
    await c.initialize();
    expect(c.ledger.single.id, 'saved');
    expect(c.pendingLedger.single.command.operationId, 'queued');
    expect(c.stops.single.version, 3);
    expect(await store.settlementDays(), isEmpty);
  });
  testWidgets(
    '390px driver screen explains a shortage and owner sees approval and reopening',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await c.submitLedger(bill('cash'));
        await switchTo(driver);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SettlementScreen(
            controller: c,
            driverId: 'driver',
            date: '2026-10-15',
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> visible(Finder finder, {double delta = 200}) async {
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            delta,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
        await tester.pumpAndSettle();
      }

      final amount = find.byKey(const Key('settlement-cash')),
          reason = find.byKey(const Key('settlement-reason'));
      await visible(amount);
      await tester.enterText(amount, '390.00');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cash shortage'), findsOneWidget);
      final submit = find.byKey(const Key('settlement-submit'));
      await visible(submit);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('settlement-submit')))
            .onPressed,
        isNull,
      );
      await visible(reason, delta: -200);
      await tester.enterText(reason, 'Short 10, owner informed');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      await visible(submit);
      await tester.runAsync(() async {
        await tester.tap(submit);
        await c.whenIdle;
      });
      await tester.pumpAndSettle();
      expect(c.settlementFor('driver', '2026-10-15').status, 'Submitted');
      await tester.runAsync(() => switchTo(owner));
      await tester.pumpWidget(
        MaterialApp(
          home: SettlementScreen(
            key: const Key('owner'),
            controller: c,
            driverId: 'driver',
            date: '2026-10-15',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await visible(find.text('Confirm cash received & approve'));
      expect(find.text('Confirm cash received & approve'), findsOneWidget);
      expect(find.text('Reopen with reason'), findsOneWidget);
      await tester.runAsync(
        () => tester.tap(find.text('Confirm cash received & approve')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Confirm cash received'), findsOneWidget);
      await tester.runAsync(() => tester.tap(find.text('Confirm & approve')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => c.whenIdle);
      await tester.pumpAndSettle();
      expect(c.settlementFor('driver', '2026-10-15').status, 'Approved');
      await visible(find.text('Reopen with reason'));
      await tester.runAsync(() => tester.tap(find.text('Reopen with reason')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Reopen day'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byType(TextField),
        'Owner rechecking counted notes',
      );
      await tester.pump();
      await tester.runAsync(() => tester.tap(find.text('Reopen day')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => c.whenIdle);
      await tester.pumpAndSettle();
      expect(c.settlementFor('driver', '2026-10-15').status, 'Reopened');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gm_delivery/application/delivery_controller.dart';
import 'package:gm_delivery/data/cloud_service.dart';
import 'package:gm_delivery/data/local_store.dart';
import 'package:gm_delivery/domain/ledger.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/domain/settlement.dart';

const linkedShop = Shop(
  id: 'shop',
  name: 'Alpha',
  area: 'Market',
  mapsUrl: 'https://maps.app.goo.gl/example',
);
const assignedStop = DeliveryStop(
  id: 'stop',
  shopId: 'shop',
  date: '2026-10-16',
  driverId: 'driver',
  order: 1,
  version: 1,
);
const driverProfile = AppProfile(
  id: 'driver',
  name: 'Driver',
  role: UserRole.driver,
);

// Transport simulator: actual financial constraints are tested in PostgreSQL.
class LedgerTransport extends CloudService {
  LedgerTransport()
    : super(SupabaseClient('https://example.supabase.co', 'test-public-key'));
  bool offline = false, loseReplyOnce = false;
  Completer<void>? snapshotGate;
  DeliveryStop remoteStop = assignedStop;
  final entries = <LedgerEntry>[];
  final requests = <String>[];
  @override
  Future<List<SettlementDay>> settlementSnapshot() async => [];
  @override
  Future<AppProfile> profile() async {
    if (offline) throw const SocketException('offline');
    return driverProfile;
  }

  @override
  Future<CloudSnapshot> snapshot() async {
    await snapshotGate?.future;
    if (offline) throw const SocketException('offline');
    return CloudSnapshot([linkedShop], [remoteStop], [driverProfile]);
  }

  @override
  Future<LedgerSnapshot> ledgerSnapshot() async {
    if (offline) throw const SocketException('offline');
    return LedgerSnapshot(List.of(entries), [
      calculateCreditBalance('shop', entries),
    ]);
  }

  @override
  Future<LedgerReceipt> sendLedger(LedgerCommand command) async {
    requests.add(jsonEncode(command.toMap()));
    await snapshotGate?.future;
    if (offline) throw const SocketException('offline');
    var entry = entries.where((e) => e.id == command.operationId).firstOrNull;
    if (entry == null) {
      if (command.expectedStopVersion != remoteStop.version) {
        throw StateError('VERSION_CONFLICT');
      }
      remoteStop = DeliveryStop(
        id: 'stop',
        shopId: 'shop',
        date: '2026-10-16',
        driverId: 'driver',
        order: 1,
        status: VisitStatus.delivered,
        version: remoteStop.version + 1,
      );
      entry = LedgerEntry(
        command: command,
        actorId: 'driver',
        sequence: entries.length + 1,
        revision: 1,
        debitDelta: command.billPaise,
        creditDelta: command.collectedPaise,
        recordedAt: DateTime.now().toUtc(),
        stopAfter: remoteStop,
      );
      entries.add(entry);
      if (loseReplyOnce) {
        loseReplyOnce = false;
        throw const SocketException('reply lost after commit');
      }
    }
    return LedgerReceipt(entry, calculateCreditBalance('shop', entries));
  }
}

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late LocalStore store;
  late DeliveryController c;
  Future<LocalStore> openStore() async => LocalStore(
    await databaseFactoryFfi.openDatabase(
      '${directory.path}/state.db',
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) => LocalStore.createSchema(db),
      ),
    ),
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gm_collections_');
    store = await openStore();
    c = DeliveryController(
      store: store,
      photoDirectory: directory,
      accountId: 'local',
    );
    await c.initialize();
    await c.saveShop(linkedShop);
    await c.addStop(linkedShop, DateTime(2026, 10, 16), 'local-driver');
  });
  tearDown(() async {
    await c.whenIdle;
    c.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });
  LedgerCommand command(
    String id,
    LedgerKind kind, {
    int bill = 0,
    int paid = 0,
    String? original,
    int revision = 0,
    String reason = '',
    bool? flag,
  }) => LedgerCommand(
    operationId: id,
    shopId: 'shop',
    kind: kind,
    capturedAt: DateTime.utc(2026, 10, 16),
    stopId:
        [
          LedgerKind.bill,
          LedgerKind.payment,
          LedgerKind.correction,
        ].contains(kind)
        ? c.stops.single.id
        : null,
    expectedStopVersion: c.stops.single.version,
    originalId: original,
    expectedRevision: revision,
    billNumber: kind == LedgerKind.bill || kind == LedgerKind.correction
        ? 'B-$id'
        : '',
    billPaise: bill,
    collectedPaise: paid,
    mode: paid == 0 ? PaymentMode.credit : PaymentMode.cash,
    reason: reason,
    collectNextVisit: flag,
  );

  test(
    'money is exact paise and fractional, negative or overflowing values are rejected',
    () {
      expect(parsePaise('0.10') + parsePaise('0.20'), 30);
      expect(parsePaise('₹ 123.4'), 12340);
      expect(rupees(-1), '-₹0.01');
      expect(parsePaise('1000000000.00'), maxMoneyPaise);
      for (final invalid in [
        '',
        '-1',
        '1.001',
        '1e2',
        'NaN',
        '1,000',
        '1000000000.01',
        '9223372036854775807',
      ]) {
        expect(
          () => parsePaise(invalid),
          throwsFormatException,
          reason: invalid,
        );
      }
    },
  );
  test(
    'partial bills, old payments and reasoned corrections keep original history',
    () async {
      await c.submitLedger(command('opening', LedgerKind.opening, bill: 50000));
      await c.submitLedger(
        command('bill', LedgerKind.bill, bill: 100000, paid: 40000),
      );
      expect(c.balanceFor('shop').balancePaise, 110000);
      await c.submitLedger(command('payment', LedgerKind.payment, paid: 30000));
      expect(c.balanceFor('shop').balancePaise, 80000);
      final correction = LedgerCommand(
        operationId: 'correct',
        shopId: 'shop',
        kind: LedgerKind.correction,
        capturedAt: DateTime.utc(2026, 10, 16),
        stopId: c.stops.single.id,
        originalId: 'bill',
        expectedRevision: 1,
        billNumber: 'Corrected reference',
        billPaise: 90000,
        collectedPaise: 50000,
        mode: PaymentMode.cash,
        reason: 'Owner checked receipt',
      );
      await c.submitLedger(correction);
      expect(c.balanceFor('shop').balancePaise, 60000);
      expect(c.ledger, hasLength(4));
      expect(
        c.ledger.singleWhere((e) => e.id == 'bill').command.billPaise,
        100000,
      );
      expect(
        effectiveLedger(
          c.ledger,
        ).singleWhere((e) => e.original.id == 'bill').latest.revision,
        2,
      );
      await expectLater(
        c.submitLedger(
          LedgerCommand.fromMap({
            ...correction.toMap(),
            'operation_id': 'stale',
          }),
        ),
        throwsStateError,
      );
      await expectLater(
        c.submitLedger(
          command('second-opening', LedgerKind.opening, bill: 123),
        ),
        throwsStateError,
      );
      await expectLater(
        c.submitLedger(command('overpayment', LedgerKind.payment, paid: 60001)),
        throwsStateError,
      );
      expect(c.stops.single.status, VisitStatus.delivered);
    },
  );
  test(
    'drivers cannot create openings/corrections and duplicate bill numbers are refused',
    () async {
      await c.submitLedger(
        command('first', LedgerKind.bill, bill: 10000, paid: 3000),
      );
      await expectLater(
        c.submitLedger(
          LedgerCommand.fromMap({
            ...command('second', LedgerKind.bill, bill: 10000).toMap(),
            'bill_number': 'b-FIRST',
          }),
        ),
        throwsStateError,
      );
      c.profile = const AppProfile(
        id: 'local-driver',
        name: 'Driver',
        role: UserRole.driver,
      );
      await expectLater(
        c.submitLedger(command('opening', LedgerKind.opening, bill: 1)),
        throwsStateError,
      );
      await expectLater(
        c.submitLedger(
          command(
            'correction',
            LedgerKind.correction,
            bill: 10000,
            original: 'first',
            revision: 1,
            reason: 'not owner',
          ),
        ),
        throwsStateError,
      );
      expect(c.ledger, hasLength(1));
    },
  );
  test('collection reminders are versioned', () async {
    await c.submitLedger(command('flag', LedgerKind.flag, flag: true));
    expect(c.balanceFor('shop').collectNextVisit, isTrue);
    await expectLater(
      c.submitLedger(command('stale-flag', LedgerKind.flag, flag: false)),
      throwsStateError,
    );
    await c.reloadLocal();
    expect(c.balanceFor('shop').flagRevision, 1);
    await c.submitLedger(
      command('clear', LedgerKind.flag, flag: false, revision: 1),
    );
    expect(c.balanceFor('shop').collectNextVisit, isFalse);
  });
  test(
    'a failed queue insert rolls back the delivered status and keeps money unsaved',
    () async {
      await store.database.execute(
        "CREATE TRIGGER simulate_full_disk BEFORE INSERT ON pending_ledger BEGIN SELECT RAISE(ABORT,'simulated storage failure'); END",
      );
      await expectLater(
        c.submitLedger(command('disk-full', LedgerKind.bill, bill: 10000)),
        throwsA(anything),
      );
      expect((await store.stops()).single.status, VisitStatus.pending);
      expect(await store.ledgerQueue(), isEmpty);
      expect(await store.ledgerEntries(), isEmpty);
    },
  );

  Future<LedgerTransport> sharedController() async {
    c.dispose();
    final transport = LedgerTransport();
    c = DeliveryController(
      store: store,
      photoDirectory: directory,
      accountId: 'driver',
      cloud: transport,
    );
    await c.initialize();
    return transport;
  }

  test(
    'a stalled network refresh does not block saving a collection on the phone',
    () async {
      final transport = await sharedController();
      final gate = Completer<void>();
      transport.snapshotGate = gate;
      final refreshing = c.refresh();
      try {
        expect(c.busy, isTrue);
        await c
            .submitLedger(
              command(
                'during-network-stall',
                LedgerKind.bill,
                bill: 10000,
                paid: 4000,
              ),
            )
            .timeout(const Duration(seconds: 3));
        expect(
          (await store.ledgerQueue()).single.command.operationId,
          'during-network-stall',
        );
        expect((await store.stops()).single.status, VisitStatus.delivered);
      } finally {
        gate.complete();
        await refreshing;
        await c.whenIdle;
      }
      expect(c.pendingLedger, isEmpty);
      expect(c.balanceFor('shop').balancePaise, 6000);
    },
  );

  test(
    'an older unsynced delivered result transfers atomically into the financial queue',
    () async {
      final transport = await sharedController();
      transport.offline = true;
      final stop = c.stops.single;
      await store.queueVisit(
        stop.withStatus(VisitStatus.delivered, ''),
        PendingVisit(
          operationId: 'legacy-visit',
          stopId: stop.id,
          status: VisitStatus.delivered,
          reason: '',
          expectedVersion: stop.version,
        ),
      );
      await c.reloadLocal();
      final restored = LedgerCommand.fromMap({
        ...command(
          'upgraded-bill',
          LedgerKind.bill,
          bill: 10000,
          paid: 4000,
        ).toMap(),
        'legacy_visit_operation_id': 'legacy-visit',
      });
      await c.submitLedger(restored);
      await c.whenIdle;
      expect(c.pending, isEmpty);
      expect(
        c.pendingLedger.single.command.legacyVisitOperationId,
        'legacy-visit',
      );
      expect(c.balanceFor('shop').balancePaise, 6000);
      transport.offline = false;
      await c.refresh();
      expect(c.pendingLedger, isEmpty);
      expect(c.ledger.single.command.legacyVisitOperationId, 'legacy-visit');
    },
  );

  test(
    'offline collection survives an actual SQLite close and reopen',
    () async {
      final transport = await sharedController();
      transport.offline = true;
      await c.submitLedger(
        command('offline-bill', LedgerKind.bill, bill: 12345, paid: 2345),
      );
      await c.whenIdle;
      final id = c.pendingLedger.single.command.operationId;
      expect(c.balanceFor('shop').balancePaise, 10000);
      expect(c.stops.single.status, VisitStatus.delivered);
      c.dispose();
      await store.close();
      store = await openStore();
      c = DeliveryController(
        store: store,
        photoDirectory: directory,
        accountId: 'driver',
        cloud: transport,
      );
      await c.initialize();
      expect(c.pendingLedger.single.command.operationId, id);
      expect(c.balanceFor('shop').balancePaise, 10000);
      expect(c.stops.single.status, VisitStatus.delivered);
      transport.offline = false;
      await c.refresh();
      expect(c.pendingLedger, isEmpty);
      expect(transport.entries, hasLength(1));
      expect(c.balanceFor('shop').balancePaise, 10000);
    },
  );
  test(
    'a lost server reply retries identical data and never double-counts money',
    () async {
      final transport = await sharedController();
      transport.loseReplyOnce = true;
      await c.submitLedger(
        command('lost-reply', LedgerKind.bill, bill: 10000, paid: 2500),
      );
      await c.whenIdle;
      expect(transport.entries, hasLength(1));
      expect(c.pendingLedger, hasLength(1));
      expect(c.balanceFor('shop').balancePaise, 7500);
      await c.refresh();
      expect(transport.requests, hasLength(2));
      expect(transport.requests[0], transport.requests[1]);
      expect(c.pendingLedger, isEmpty);
      expect(c.ledger, hasLength(1));
      expect(c.balanceFor('shop').balancePaise, 7500);
    },
  );
  test(
    'multiple offline actions retain stop versions and survive snapshot refresh',
    () async {
      final transport = await sharedController();
      transport.offline = true;
      await c.submitLedger(command('first', LedgerKind.bill, bill: 10000));
      await c.whenIdle;
      await c.submitLedger(
        command('second', LedgerKind.bill, bill: 20000, paid: 10000),
      );
      await c.whenIdle;
      await c.submitLedger(
        command('old-payment', LedgerKind.payment, paid: 5000),
      );
      await c.whenIdle;
      expect(c.pendingLedger.map((p) => p.command.expectedStopVersion), [
        1,
        2,
        3,
      ]);
      expect(c.stops.single.version, 4);
      await store.replaceSnapshot([], []);
      expect((await store.stops()).single.version, 4);
      expect(await store.shops(), hasLength(1));
      transport.offline = false;
      await c.refresh();
      expect(c.pendingLedger, isEmpty);
      expect(c.stops.single.version, 4);
      expect(c.balanceFor('shop').balancePaise, 15000);
    },
  );
}

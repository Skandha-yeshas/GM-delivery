import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gm_delivery/application/delivery_controller.dart';
import 'package:gm_delivery/data/local_store.dart';
import 'package:gm_delivery/data/cloud_service.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/domain/route_order.dart';
import 'package:gm_delivery/presentation/owner_route_planner.dart';
import 'package:gm_delivery/presentation/shop_directory.dart';

class RouteTransport extends CloudService {
  RouteTransport(this.remote)
    : super(SupabaseClient('https://example.supabase.co', 'test-public-key'));
  List<DeliveryStop> remote;
  final requests = <String>[];
  bool loseReply = true;
  @override
  Future<List<DeliveryStop>> saveRouteOrder(RouteOrderCommand command) async {
    if (!requests.contains(command.operationId)) {
      if (!command.matches(remote)) throw StateError('ROUTE_CHANGED');
      remote = command.arrange();
    }
    requests.add(command.operationId);
    if (loseReply) {
      loseReply = false;
      throw const SocketException('Reply lost');
    }
    return List.of(remote);
  }
}

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late LocalStore store;
  late DeliveryController c;
  final day = DateTime(2026, 10, 23);
  Future<LocalStore> openStore() async => LocalStore(
    await databaseFactoryFfi.openDatabase(
      '${directory.path}/routes.db',
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, _) => LocalStore.createSchema(db),
      ),
    ),
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gm_route_');
    store = await openStore();
    c = DeliveryController(
      store: store,
      photoDirectory: directory,
      accountId: 'local-owner',
    );
    await c.initialize();
    for (var i = 1; i <= 4; i++) {
      await store.saveShop(
        Shop(
          id: 'shop-$i',
          name: 'Stationery $i',
          area: 'Market Road',
          contactName: 'Shop owner $i',
          mapsUrl: 'https://maps.app.goo.gl/example',
        ),
      );
      await store.saveStop(
        DeliveryStop(
          id: 'stop-$i',
          shopId: 'shop-$i',
          date: dateKey(day),
          driverId: i == 4 ? 'other-driver' : 'local-driver',
          order: i,
          status: i == 2 ? VisitStatus.failed : VisitStatus.pending,
          reason: i == 2 ? 'Shop closed' : '',
          version: i == 2 ? 2 : 1,
        ),
      );
    }
    await c.reloadLocal();
  });
  tearDown(() async {
    await c.whenIdle;
    c.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });
  RouteOrderCommand command({List<String> ids = const ['stop-3', 'stop-1']}) =>
      RouteOrderCommand(
        operationId: 'order-1',
        driverId: 'local-driver',
        date: dateKey(day),
        expected: c
            .stopsFor(day)
            .where((s) => s.driverId == 'local-driver')
            .toList(),
        pendingIds: ids,
      );

  test(
    'saved route survives restart, keeps completed positions and visit versions, and drives the driver list',
    () async {
      final original = command();
      await c.saveRouteOrder(original);
      expect(
        c
            .stopsFor(day)
            .where((s) => s.driverId == 'local-driver')
            .map((s) => s.id),
        ['stop-3', 'stop-2', 'stop-1'],
      );
      final fixed = c.stops.firstWhere((s) => s.id == 'stop-2');
      expect(fixed.order, 2);
      expect(fixed.reason, 'Shop closed');
      expect(fixed.version, 2);
      expect(c.stops.firstWhere((s) => s.id == 'stop-3').version, 1);
      expect(c.stops.firstWhere((s) => s.id == 'stop-4').order, 4);
      await store.close();
      store = await openStore();
      final driver = DeliveryController(
        store: store,
        photoDirectory: directory,
        accountId: 'local-driver',
      );
      await driver.reloadLocal();
      driver.profile = const AppProfile(
        id: 'local-driver',
        name: 'Driver',
        role: UserRole.driver,
      );
      expect(driver.stopsFor(day).map((s) => s.id), [
        'stop-3',
        'stop-2',
        'stop-1',
      ]);
      driver.dispose();
    },
  );

  test(
    'stale drafts, omitted shops and moving a completed stop cannot partially overwrite a route',
    () async {
      final stale = command();
      final before = c.stops.map((s) => s.toMap()).toList();
      await expectLater(
        c.saveRouteOrder(command(ids: ['stop-1'])),
        throwsStateError,
      );
      await expectLater(
        c.saveRouteOrder(command(ids: ['stop-2', 'stop-1'])),
        throwsStateError,
      );
      expect((await store.stops()).map((s) => s.toMap()).toList(), before);
      await store.saveStop(
        c.stops.first.withStatus(VisitStatus.failed, 'Just closed'),
      );
      await c.reloadLocal();
      await expectLater(
        c.saveRouteOrder(stale),
        throwsA(
          isA<StateError>().having((e) => e.message, 'reason', 'ROUTE_CHANGED'),
        ),
      );
      expect(c.stops.firstWhere((s) => s.id == 'stop-1').order, 1);
    },
  );

  test('driver and pending phone updates cannot reorder routes', () async {
    final request = command();
    c.profile = const AppProfile(
      id: 'local-driver',
      name: 'Driver',
      role: UserRole.driver,
    );
    await expectLater(c.saveRouteOrder(request), throwsStateError);
    c.profile = const AppProfile(
      id: 'local-owner',
      name: 'Owner',
      role: UserRole.owner,
    );
    await store.queueVisit(
      c.stops.first,
      const PendingVisit(
        operationId: 'queued',
        stopId: 'stop-1',
        status: VisitStatus.pending,
        reason: '',
        expectedVersion: 1,
      ),
    );
    await c.reloadLocal();
    await expectLater(c.saveRouteOrder(request), throwsStateError);
    expect((await store.pendingVisits()).single.operationId, 'queued');
  });

  test('a failed local write rolls back the entire route', () async {
    await store.database.execute(
      """CREATE TRIGGER reject_route BEFORE UPDATE OF stop_order ON stops
      WHEN NEW.id = 'stop-1' BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END""",
    );
    await expectLater(
      c.saveRouteOrder(command()),
      throwsA(isA<DatabaseException>()),
    );
    final saved = await store.stops();
    expect(saved.firstWhere((s) => s.id == 'stop-3').order, 3);
    expect(saved.firstWhere((s) => s.id == 'stop-1').order, 1);
  });

  test(
    'lost cloud confirmation retains the old local sequence and safely retries the same request',
    () async {
      final request = command();
      final transport = RouteTransport(request.expected.toList());
      final shared = DeliveryController(
        store: store,
        photoDirectory: directory,
        accountId: 'local-owner',
        cloud: transport,
      );
      shared.profile = c.profile;
      shared.profiles = List.of(c.profiles);
      await shared.reloadLocal();
      await expectLater(
        shared.saveRouteOrder(request),
        throwsA(isA<SocketException>()),
      );
      expect(
        (await store.stops()).firstWhere((s) => s.id == 'stop-1').order,
        1,
      );
      await shared.saveRouteOrder(request);
      expect(shared.stops.firstWhere((s) => s.id == 'stop-3').order, 1);
      expect(transport.requests, [request.operationId, request.operationId]);
      shared.dispose();
      await transport.client.dispose();
    },
  );

  testWidgets(
    'route controls fit at 140% text and a changed visit blocks a stale draft',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var scans = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: DirectoryDesign.theme(ThemeData()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (context, _) => OwnerRoutePlanner(
                controller: c,
                date: day,
                onScan: () => scans++,
                onAddStops: () {},
                onChooseDate: () {},
                onDraftChanged: (_) {},
                stopBuilder: (stop, number) => Text(stop.id),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Scan whole bill'));
      await tester.tap(find.text('Scan whole bill'));
      expect(scans, 1);
      final down = find.byKey(const ValueKey('route-down-stop-1'));
      await tester.scrollUntilVisible(
        down,
        150,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('owner-dispatch-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(tester.element(down), alignment: .4);
      await tester.pumpAndSettle();
      await tester.tap(down);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => c.recordVisit(
          c.stops.firstWhere((s) => s.id == 'stop-3'),
          VisitStatus.failed,
          reason: 'Closed',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('route-save')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('route-reset')));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'owner can drag pending shops, reset, then save with arrows on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var dirty = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: DirectoryDesign.theme(ThemeData()),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (context, _) => OwnerRoutePlanner(
                controller: c,
                date: day,
                onScan: () {},
                onAddStops: () {},
                onChooseDate: () {},
                onDraftChanged: (value) => dirty = value,
                stopBuilder: (stop, number) => Text('Details ${stop.id}'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = find.byKey(const Key('owner-dispatch-scroll'));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('route-drag-stop-1')),
        150,
        scrollable: find
            .descendant(of: scroll, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
      final handle = find.byKey(const ValueKey('route-drag-stop-1'));
      await Scrollable.ensureVisible(tester.element(handle), alignment: .25);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(dirty, isTrue);
      expect(
        c.stops.firstWhere((s) => s.id == 'stop-1').order,
        1,
        reason: 'drag is a draft until saved',
      );
      await tester.tap(find.byKey(const Key('route-reset')));
      await tester.pumpAndSettle();
      expect(dirty, isFalse);
      await tester.ensureVisible(
        find.byKey(const ValueKey('route-down-stop-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('route-down-stop-1')));
      await tester.pumpAndSettle();
      expect(dirty, isTrue);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('route-save')));
        await c.whenIdle;
      });
      await tester.pumpAndSettle();
      expect(c.stops.firstWhere((s) => s.id == 'stop-3').order, 1);
      expect(dirty, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

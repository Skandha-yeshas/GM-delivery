import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gm_delivery/application/delivery_controller.dart';
import 'package:gm_delivery/data/local_store.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/domain/ledger.dart';
import 'package:gm_delivery/domain/route_order.dart';
import 'package:gm_delivery/presentation/driver_delivery_board.dart';
import 'package:gm_delivery/presentation/home_screen.dart';
import 'package:gm_delivery/presentation/collection_form.dart';
import 'package:gm_delivery/presentation/settlement_screen.dart';
import 'package:gm_delivery/presentation/shop_directory.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late LocalStore store;
  late Directory photos;
  late DeliveryController owner, driver;
  final day = DateTime.now();

  Future<void> setup() async {
    store = LocalStore(
      await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (db, _) => LocalStore.createSchema(db),
        ),
      ),
    );
    photos = await Directory.systemTemp.createTemp('gm_driver_ui_');
    owner = DeliveryController(
      store: store,
      photoDirectory: photos,
      accountId: 'local-owner',
    );
    await owner.initialize();
    for (final entry in {
      'alpha': 'Alpha Stationery',
      'beta': 'Beta Pen House',
      'gamma': 'Gamma Supplies',
    }.entries) {
      await owner.saveShop(
        Shop(
          id: entry.key,
          name: entry.value,
          area: 'Central Market',
          address: '12 Market Road',
          contactName: 'Shop contact',
          phone: '+919876543210',
          notes: 'Use the side entrance',
          mapsUrl: 'https://maps.app.goo.gl/${entry.key}',
        ),
      );
      await owner.addStop(owner.shopFor(entry.key)!, day, 'local-driver');
    }
    final alpha = owner.stops.firstWhere((s) => s.shopId == 'alpha');
    await owner.submitLedger(
      LedgerCommand(
        operationId: 'alpha-bill',
        shopId: 'alpha',
        kind: LedgerKind.bill,
        capturedAt: DateTime.now().toUtc(),
        stopId: alpha.id,
        expectedStopVersion: alpha.version,
        billNumber: 'GM-1',
        billPaise: 10000,
        collectedPaise: 0,
        mode: PaymentMode.credit,
      ),
    );
    final route = owner.stopsFor(day);
    await owner.saveRouteOrder(
      RouteOrderCommand(
        operationId: 'owner-sequence',
        driverId: 'local-driver',
        date: dateKey(day),
        expected: route,
        pendingIds: [
          route.firstWhere((s) => s.shopId == 'gamma').id,
          route.firstWhere((s) => s.shopId == 'beta').id,
        ],
      ),
    );
    for (final entry in {
      'other': 'Other driver shop',
      'past': 'Yesterday shop',
    }.entries) {
      await store.saveShop(
        Shop(id: entry.key, name: entry.value, area: 'Elsewhere'),
      );
      await store.saveStop(
        DeliveryStop(
          id: entry.key,
          shopId: entry.key,
          date: dateKey(
            entry.key == 'past' ? day.subtract(const Duration(days: 1)) : day,
          ),
          driverId: entry.key == 'past' ? 'local-driver' : 'another-driver',
          order: 1,
        ),
      );
    }
    driver = DeliveryController(
      store: store,
      photoDirectory: photos,
      accountId: 'local-driver',
    );
    await driver.initialize();
    driver.profile = const AppProfile(
      id: 'local-driver',
      name: 'Ramesh Kumar',
      role: UserRole.driver,
    );
    driver.profiles = [
      ...owner.profiles.where((p) => p.id != 'local-driver'),
      driver.profile!,
    ];
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await owner.whenIdle;
      await driver.whenIdle;
      owner.dispose();
      driver.dispose();
      await store.close();
      await photos.delete(recursive: true);
    });
  }

  void size(WidgetTester tester, {bool compact = false}) {
    tester.view.physicalSize = Size(compact ? 320 : 390, compact ? 740 : 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final scroll = find
        .descendant(
          of: find.byKey(const Key('driver-delivery-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(target, 180, scrollable: scroll);
    await Scrollable.ensureVisible(tester.element(target), alignment: .45);
    await tester.pumpAndSettle();
  }

  Widget board({DateTime? date, ValueChanged<Shop>? navigate}) =>
      DriverDeliveryBoard(
        controller: driver,
        date: date ?? day,
        onChooseDate: () {},
        onNavigate: navigate ?? (_) {},
        onCall: (_) {},
        onShop: (_) {},
        onDelivered: (_) {},
        onFailed: (_) {},
        onReopen: (_) {},
        onLedger: (_) {},
        onCollection: (_) {},
        onSettlement: () {},
      );

  testWidgets(
    'driver follows persisted owner order and Maps-only navigation targets the next assigned shop',
    (tester) async {
      size(tester);
      await tester.runAsync(setup);
      try {
        Shop? destination;
        await tester.pumpWidget(
          MaterialApp(
            theme: DirectoryDesign.theme(ThemeData()),
            home: Scaffold(body: board(navigate: (shop) => destination = shop)),
          ),
        );
        await tester.pumpAndSettle();
        expect(driver.stopsFor(day).map((s) => s.shopId), [
          'alpha',
          'gamma',
          'beta',
        ]);
        expect(find.text('33% delivered'), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('driver-next-shop'))).data,
          'Gamma Supplies',
        );
        await reveal(tester, find.byKey(const Key('driver-navigate-next')));
        await tester.tap(find.byKey(const Key('driver-navigate-next')));
        expect(destination?.id, 'gamma');
        expect(
          navigationUri(destination!).toString(),
          'https://maps.app.goo.gl/gamma',
        );
        expect(find.text('Add New Shop'), findsNothing);
        expect(find.textContaining('Optimized'), findsNothing);
        expect(find.byType(SliverReorderableList), findsNothing);
        await tester.drag(
          find.byKey(const Key('driver-delivery-scroll')),
          const Offset(0, -1500),
        );
        await tester.pumpAndSettle();
        expect(find.text('Other driver shop'), findsNothing);
        expect(find.text('Yesterday shop'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await close(tester);
      }
    },
  );

  testWidgets(
    'driver opens on deliveries and saving a collection advances the next stop without changing owner order',
    (tester) async {
      size(tester);
      await tester.runAsync(setup);
      try {
        await tester.pumpWidget(
          MaterialApp(home: HomeScreen(controller: driver)),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          1,
        );
        expect(find.text('Ramesh Kumar'), findsOneWidget);
        final gamma = driver.stops.firstWhere((s) => s.shopId == 'gamma');
        final action = find.byKey(ValueKey('driver-delivered-${gamma.id}'));
        await reveal(tester, action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(CollectionForm), findsOneWidget);
        Future<void> type(String label, String value) async {
          final field = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == label,
          );
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          await tester.enterText(field, value);
          await tester.pump();
        }

        await type('Bill number', 'GM-2');
        await type('Bill amount (₹)', '50.00');
        final save = find.text('Save collection & mark delivered');
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(save);
          await driver.whenIdle;
        });
        await tester.pumpAndSettle();
        expect(
          driver.stops.firstWhere((s) => s.shopId == 'gamma').status,
          VisitStatus.delivered,
        );
        expect(driver.balanceFor('gamma').balancePaise, 5000);
        expect(driver.stopsFor(day).map((s) => s.shopId), [
          'alpha',
          'gamma',
          'beta',
        ]);
        await tester.drag(
          find.byKey(const Key('driver-delivery-scroll')),
          const Offset(0, 2000),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('driver-next-shop')),
          -200,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('driver-delivery-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('driver-next-shop'))).data,
          'Beta Pen House',
        );
        expect(find.text('67% delivered'), findsOneWidget);
        expect(find.text('Import Excel'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await close(tester);
      }
    },
  );

  testWidgets(
    'narrow large-text screen keeps queued actions disabled and an empty date can refresh',
    (tester) async {
      size(tester, compact: true);
      await tester.runAsync(setup);
      try {
        final gamma = driver.stops.firstWhere((s) => s.shopId == 'gamma');
        await tester.runAsync(() async {
          await store.queueVisit(
            gamma,
            PendingVisit(
              operationId: 'queued-visit',
              stopId: gamma.id,
              status: VisitStatus.pending,
              reason: '',
              expectedVersion: gamma.version,
            ),
          );
          await driver.reloadLocal();
        });
        Widget app(Widget child) => MaterialApp(
          theme: DirectoryDesign.theme(ThemeData()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(body: child),
        );
        await tester.pumpWidget(app(board()));
        await tester.pumpAndSettle();
        final action = find.byKey(ValueKey('driver-delivered-${gamma.id}'));
        await reveal(tester, action);
        expect(tester.widget<FilledButton>(action).onPressed, isNull);
        expect(find.text('Waiting to sync'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          app(board(date: day.add(const Duration(days: 1)))),
        );
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Check for deliveries'));
        await tester.runAsync(() async {
          await tester.tap(find.text('Check for deliveries'));
          await driver.whenIdle;
        });
        await tester.pumpAndSettle();
        expect(find.text('No assigned deliveries'), findsOneWidget);
        expect(find.byKey(const Key('driver-navigate-next')), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await close(tester);
      }
    },
  );

  testWidgets(
    'failed stops keep their reasons and do not claim all deliveries succeeded',
    (tester) async {
      size(tester);
      await tester.runAsync(setup);
      try {
        await tester.runAsync(() async {
          for (final stop
              in driver
                  .stopsFor(day)
                  .where((s) => s.status == VisitStatus.pending)
                  .toList()) {
            await driver.recordVisit(
              stop,
              VisitStatus.failed,
              reason: 'Shop closed',
            );
          }
        });
        await tester.pumpWidget(
          MaterialApp(home: HomeScreen(controller: driver)),
        );
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Daily settlement'));
        expect(find.text('All stops have a result'), findsOneWidget);
        expect(find.text('All assigned stops delivered'), findsNothing);
        expect(find.byKey(const Key('driver-navigate-next')), findsNothing);
        await tester.tap(find.text('Daily settlement'));
        await tester.pumpAndSettle();
        expect(find.byType(SettlementScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await close(tester);
      }
    },
  );

  testWidgets(
    'driver shop tab searches only assigned records and returning to deliveries preserves owner order',
    (tester) async {
      size(tester);
      await tester.runAsync(setup);
      try {
        final initialOrder = driver.stopsFor(day).map((s) => s.id).toList();
        await tester.pumpWidget(
          MaterialApp(home: HomeScreen(controller: driver)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shops'));
        await tester.pumpAndSettle();
        expect(
          find.text('All shops (4)'),
          findsOneWidget,
          reason: 'Includes historical assignments, excludes the other driver',
        );
        expect(find.text('Assigned shops'), findsOneWidget);
        final field = find.byKey(const Key('driver-shop-search'));
        await tester.enterText(field, 'Other driver');
        await tester.pumpAndSettle();
        expect(find.text('0 shops shown'), findsOneWidget);
        await tester.enterText(field, 'Gamma');
        await tester.pumpAndSettle();
        expect(find.text('1 shop shown'), findsOneWidget);
        expect(find.text('Add shop'), findsNothing);
        expect(find.text('Import Excel'), findsNothing);
        await tester.tap(find.text('Deliveries'));
        await tester.pumpAndSettle();
        expect(driver.stopsFor(day).map((s) => s.id), initialOrder);
        expect(
          tester.widget<Text>(find.byKey(const Key('driver-next-shop'))).data,
          'Gamma Supplies',
        );
        await tester.tap(find.text('Shops'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller!.text, 'Gamma');
        expect(find.text('1 shop shown'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await close(tester);
      }
    },
  );
}

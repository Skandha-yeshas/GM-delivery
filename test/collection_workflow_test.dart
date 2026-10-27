import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gm_delivery/application/delivery_controller.dart';
import 'package:gm_delivery/data/local_store.dart';
import 'package:gm_delivery/data/collection_location_service.dart';
import 'package:gm_delivery/domain/ledger.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/presentation/collection_form.dart';
import 'package:gm_delivery/presentation/ledger_screen.dart';
import 'package:gm_delivery/presentation/home_screen.dart';

class NoGps implements CollectionLocationService {
  @override
  Future<CollectionLocation> capture() async =>
      const CollectionLocation(status: 'denied');
}

void main() {
  setUpAll(sqfliteFfiInit);
  late LocalStore store;
  late DeliveryController c;
  late Directory photos;
  Future<void> setup() async {
    store = LocalStore(
      await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) => LocalStore.createSchema(db),
        ),
      ),
    );
    photos = await Directory.systemTemp.createTemp('gm_collection_ui_');
    c = DeliveryController(
      store: store,
      photoDirectory: photos,
      accountId: 'local',
    );
    await c.initialize();
    await c.saveShop(
      const Shop(
        id: 'alpha',
        name: 'Alpha',
        area: 'East',
        mapsUrl: 'https://maps.app.goo.gl/example',
      ),
    );
    await c.addStop(c.shops.single, DateTime.now(), 'local-driver');
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.runAsync(() async {
      await store.close();
      await photos.delete(recursive: true);
    });
  }

  Future<void> size(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> type(WidgetTester tester, String label, String value) async {
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, value);
    await tester.pump();
  }

  testWidgets(
    'small-phone collection form saves exact partial cash despite denied GPS and owner correction preserves history',
    (tester) async {
      await size(tester);
      await tester.runAsync(setup);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CollectionForm(
                        controller: c,
                        shopId: 'alpha',
                        stopId: c.stops.single.id,
                        locationService: NoGps(),
                      ),
                    ),
                  ),
                  child: const Text('Record bill'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Record bill'));
        await tester.pumpAndSettle();
        await type(tester, 'Bill number', 'B-123');
        await type(tester, 'Bill amount (₹)', '100.50');
        final mode = find.byType(DropdownButtonFormField<PaymentMode>);
        await tester.ensureVisible(mode);
        await tester.pumpAndSettle();
        await tester.tap(mode);
        await tester.pumpAndSettle();
        await tester.tap(find.text('CASH').last);
        await tester.pumpAndSettle();
        await type(tester, 'Amount collected (₹)', '40.25');
        expect(find.text('This bill balance: ₹60.25'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('Save collection & mark delivered'));
          await c.whenIdle;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(c.balanceFor('alpha').balancePaise, 6025);
        expect(c.ledger.single.command.location.status, 'denied');
        expect(c.stops.single.status, VisitStatus.delivered);
        await tester.pumpWidget(
          MaterialApp(
            home: ShopLedgerScreen(controller: c, shopId: 'alpha'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Correct entry'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(find.text('Correct entry')),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Correct entry'));
        await tester.pumpAndSettle();
        await type(tester, 'Bill amount (₹)', '90.50');
        await tester.scrollUntilVisible(
          find.text('Correction reason'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await type(tester, 'Correction reason', 'Owner checked the paper bill');
        await tester.runAsync(() async {
          await tester.tap(find.text('Save correction'));
          await c.whenIdle;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(c.ledger, hasLength(2));
        expect(c.ledger.first.command.billPaise, 10050);
        expect(c.balanceFor('alpha').balancePaise, 5025);
        expect(tester.takeException(), isNull);
      } finally {
        await close(tester);
      }
    },
  );

  testWidgets(
    'owner reminder preselects the next delivery and outstanding area filter works',
    (tester) async {
      await size(tester);
      await tester.runAsync(() async {
        await setup();
        await c.submitLedger(
          LedgerCommand(
            operationId: 'opening-a',
            shopId: 'alpha',
            kind: LedgerKind.opening,
            capturedAt: DateTime.utc(2026, 10, 10),
            billPaise: 20000,
          ),
        );
        await c.saveShop(
          const Shop(
            id: 'beta',
            name: 'Beta',
            area: 'West',
            mapsUrl: 'https://maps.app.goo.gl/example',
          ),
        );
        await c.submitLedger(
          LedgerCommand(
            operationId: 'opening-b',
            shopId: 'beta',
            kind: LedgerKind.opening,
            capturedAt: DateTime.utc(2026, 10, 12),
            billPaise: 40000,
          ),
        );
        await c.submitLedger(
          LedgerCommand(
            operationId: 'flag',
            shopId: 'alpha',
            kind: LedgerKind.flag,
            capturedAt: DateTime.now().toUtc(),
            collectNextVisit: true,
          ),
        );
      });
      try {
        await tester.pumpWidget(
          MaterialApp(home: OutstandingScreen(controller: c)),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('Beta · ₹400.00')).dy,
          lessThan(tester.getTopLeft(find.text('Alpha · ₹200.00')).dy),
        );
        await tester.tap(find.text('Oldest first'));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('Alpha · ₹200.00')).dy,
          lessThan(tester.getTopLeft(find.text('Beta · ₹400.00')).dy),
        );
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('East').last);
        await tester.pumpAndSettle();
        expect(find.text('Beta · ₹400.00'), findsNothing);
        expect(find.text('Alpha · ₹200.00'), findsOneWidget);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () => showAddStops(
                    context,
                    c,
                    DateTime.now().add(const Duration(days: 1)),
                  ),
                  child: const Text('Plan'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Plan'));
        await tester.pumpAndSettle();
        final alpha = find.ancestor(
          of: find.text('Alpha'),
          matching: find.byType(CheckboxListTile),
        );
        expect(tester.widget<CheckboxListTile>(alpha).value, isTrue);
        expect(find.text('Add 1 selected stops'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await close(tester);
      }
    },
  );
}

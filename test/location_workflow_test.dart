import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gm_delivery/application/delivery_controller.dart';
import 'package:gm_delivery/data/local_store.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/presentation/home_screen.dart';
import 'package:gm_delivery/presentation/shop_import_screen.dart';
import 'package:gm_delivery/presentation/settlement_screen.dart';
import 'package:gm_delivery/presentation/ledger_screen.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets(
    'owner can search shops and prepare a persisted delivery list on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late LocalStore store;
      late Directory photos;
      late DeliveryController controller;
      await tester.runAsync(() async {
        store = LocalStore(
          await databaseFactoryFfi.openDatabase(
            inMemoryDatabasePath,
            options: OpenDatabaseOptions(
              version: 1,
              onCreate: (db, _) => LocalStore.createSchema(db),
            ),
          ),
        );
        photos = await Directory.systemTemp.createTemp('gm_ui_test_');
        controller = DeliveryController(
          store: store,
          photoDirectory: photos,
          accountId: 'local',
        );
        await controller.initialize();
        await controller.saveShop(
          const Shop(
            id: 'shop-a',
            name: 'Alpha Stationery',
            area: 'East',
            latitude: 12.3,
            longitude: 77.5,
            verified: true,
          ),
        );
        await controller.saveShop(
          const Shop(id: 'shop-b', name: 'Beta Stationery', area: 'West'),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: HomeScreen(controller: controller),
        ),
      );
      expect(
        find.text('Saved on this phone only. Sharing is not enabled yet.'),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDestination), findsNWidgets(2));
      expect(find.text('Overview'), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await tester.tap(find.byTooltip('Account and saved records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily settlements'));
      await tester.pumpAndSettle();
      expect(find.byType(SettlementsScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Account and saved records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Outstanding balances'));
      await tester.pumpAndSettle();
      expect(find.byType(OutstandingScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Shops'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha Stationery'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pump();
      expect(find.text('Beta Stationery'), findsNothing);
      await tester.tap(find.text('Assign Delivery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepare delivery list'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha Stationery'), findsOneWidget);
      expect(find.text('Beta Stationery'), findsNothing);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Add 1 selected stops'));
        await controller.whenIdle;
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(controller.stops, hasLength(1));
      await tester.runAsync(() async {
        expect((await store.stops()).single.shopId, 'shop-a');
      });
      await tester.ensureVisible(
        find.byKey(ValueKey('route-details-${controller.stops.single.id}')),
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Details & delivery actions')),
        alignment: .3,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details & delivery actions'));
      await tester.pumpAndSettle();
      expect(find.text('Update result'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('All Shops'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import Excel'));
      await tester.pumpAndSettle();
      expect(find.byType(ShopImportScreen), findsOneWidget);
      expect(find.text('Choose Excel file'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add shop'));
      await tester.pumpAndSettle();
      Future<void> fill(String label, String value) async {
        final field = find.descendant(
          of: find.byKey(ValueKey('shop-field-$label')),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, value);
      }

      await fill('Shop name', 'Maps Only Shop');
      await fill('Proprietor / contact person', 'Rajesh');
      await fill('Contact number', '9876543210');
      await fill('Address', '12 Market Road');
      await fill('PIN code', '560001');
      await fill(
        'Google Maps link (optional)',
        'https://maps.app.goo.gl/example',
      );
      await tester.pumpAndSettle();
      expect(find.text('Maps location ready for delivery'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('save-shop')));
        await controller.whenIdle;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final linked = controller.shops.singleWhere(
        (s) => s.name == 'Maps Only Shop',
      );
      expect(linked.hasCoordinates, isFalse);
      expect(linked.readyForDelivery, isTrue);
      await tester.tap(find.text('Assign Delivery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add stops'));
      await tester.pumpAndSettle();
      expect(find.text('Maps Only Shop'), findsOneWidget);
      expect(find.text('Beta Stationery'), findsNothing);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Add 1 selected stops'));
        await controller.whenIdle;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(controller.stops, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(() async {
        await store.close();
        await photos.delete(recursive: true);
      });
    },
  );
}

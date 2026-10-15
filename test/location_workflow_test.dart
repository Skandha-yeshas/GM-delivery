import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gm_delivery/application/delivery_controller.dart';
import 'package:gm_delivery/data/local_store.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/presentation/home_screen.dart';
import 'package:gm_delivery/presentation/shop_import_screen.dart';

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
      await tester.tap(find.text('Shops'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha Stationery'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pump();
      expect(find.text('Beta Stationery'), findsNothing);
      await tester.tap(find.text('Deliveries'));
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
      expect(find.text('Update result'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Shops'));
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
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Shop name',
        ),
        'Maps Only Shop',
      );
      await tester.scrollUntilVisible(
        find.text('Google Maps link (optional)'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      final mapField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Google Maps link (optional)',
      );
      await tester.enterText(mapField, 'https://maps.app.goo.gl/example');
      await tester.pumpAndSettle();
      expect(find.text('Maps location ready for delivery'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await controller.whenIdle;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final linked = controller.shops.singleWhere(
        (s) => s.name == 'Maps Only Shop',
      );
      expect(linked.hasCoordinates, isFalse);
      expect(linked.readyForDelivery, isTrue);
      await tester.tap(find.text('Deliveries'));
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

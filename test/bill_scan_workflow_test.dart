import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gm_delivery/application/delivery_controller.dart';
import 'package:gm_delivery/data/bill_scan_service.dart';
import 'package:gm_delivery/data/local_store.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/presentation/bill_scan_screen.dart';

class FakeScanner implements BillScanService {
  FakeScanner(this.path);
  final String path;
  String text = 'G.M. Enterprises\nBill To:\nAlpha Stationery\nCity Market';
  int reads = 0, recoveries = 0;
  ImageSource? source;
  @override
  Future<String?> pick(ImageSource source) async {
    this.source = source;
    return path;
  }

  @override
  Future<String?> recoverLostImage() async {
    recoveries++;
    return path;
  }

  @override
  Future<String> readText(String path) async {
    reads++;
    return text;
  }
}

Future<void> settleScan(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find.text('Finding matching shops…').evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Bill scanning did not finish within the test deadline.');
}

void main() {
  setUpAll(sqfliteFfiInit);
  late LocalStore store;
  late Directory photos;
  late DeliveryController controller;
  late FakeScanner scanner;
  final date = DateTime(2026, 10, 15);

  Future<void> setup() async {
    store = LocalStore(
      await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) => LocalStore.createSchema(db),
        ),
      ),
    );
    photos = await Directory.systemTemp.createTemp('gm_bill_scan_');
    controller = DeliveryController(
      store: store,
      photoDirectory: photos,
      accountId: 'local',
    );
    await controller.initialize();
    await controller.saveShop(
      const Shop(
        id: 'alpha',
        name: 'Alpha Stationery',
        area: 'City Market',
        latitude: 12.3,
        longitude: 77.5,
        verified: true,
      ),
    );
    await controller.saveShop(
      const Shop(id: 'beta', name: 'Beta Stores', area: 'North'),
    );
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 10, 10),
      Paint()..color = Colors.white,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(10, 10);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = await File(
      '${photos.path}/camera.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
    scanner = FakeScanner(file.path);
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.runAsync(() async {
      await store.close();
      await photos.delete(recursive: true);
    });
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: BillScanScreen(
          controller: controller,
          date: date,
          scanner: scanner,
        ),
      ),
    );
    await settleScan(tester);
  }

  testWidgets(
    'whole-bill scan shows only shop name, finds GPS and requires confirmation to assign',
    (tester) async {
      await tester.runAsync(setup);
      try {
        await mount(tester);
        await tester.runAsync(() async {
          await tester.tap(find.text('Scan whole bill'));
        });
        await settleScan(tester);
        expect(scanner.source, ImageSource.camera);
        expect(scanner.reads, 1);
        expect(controller.stops, isEmpty);
        await tester.scrollUntilVisible(
          find.text('Alpha Stationery'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.scrollUntilVisible(
          find.text('GPS: 12.300000, 77.500000'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('GPS: 12.300000, 77.500000'), findsOneWidget);
        expect(find.text('Shop found'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('Confirm shop & add delivery'));
          await controller.whenIdle;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(controller.stops.single.shopId, 'alpha');
        expect(controller.stops.single.date, '2026-10-15');
        expect(controller.stops.single.driverId, 'local-driver');
        expect(find.text('Scan next shop'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester);
      }
    },
  );

  testWidgets(
    'manual fallback shows missing GPS and refuses assignment; driver cannot scan',
    (tester) async {
      await tester.runAsync(setup);
      try {
        await mount(tester);
        final search = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Shop name',
        );
        await tester.ensureVisible(search);
        await tester.enterText(search, 'Beta');
        await tester.pump(const Duration(milliseconds: 350));
        await settleScan(tester);
        await tester.scrollUntilVisible(
          find.text('Beta Stores'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Beta Stores'));
        await tester.pump();
        await tester.scrollUntilVisible(
          find.textContaining('Add a Google Maps link or capture'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.textContaining('Add a Google Maps link or capture'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(
                  FilledButton,
                  'Confirm shop & add delivery',
                ),
              )
              .onPressed,
          isNull,
        );
        expect(controller.stops, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.profile = const AppProfile(
          id: 'driver',
          name: 'Driver',
          role: UserRole.driver,
        );
        await mount(tester);
        expect(
          find.text('Only owners can prepare deliveries.'),
          findsOneWidget,
        );
        expect(find.text('Scan whole bill'), findsNothing);
        expect(scanner.reads, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester);
      }
    },
  );

  testWidgets(
    'scanned shop with only a Maps link can be confirmed without GPS',
    (tester) async {
      await tester.runAsync(() async {
        await setup();
        await controller.saveShop(
          const Shop(
            id: 'alpha',
            name: 'Alpha Stationery',
            area: 'City Market',
            mapsUrl: 'https://maps.app.goo.gl/example',
          ),
        );
      });
      try {
        await mount(tester);
        await tester.runAsync(
          () async => tester.tap(find.text('Scan whole bill')),
        );
        await settleScan(tester);
        await tester.scrollUntilVisible(
          find.text(
            'Google Maps location saved. Coordinates are not required.',
          ),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Needs location'), findsNothing);
        expect(find.textContaining('GPS:'), findsNothing);
        expect(find.text('View location in Maps'), findsOneWidget);
        expect(controller.stops, isEmpty);
        await tester.runAsync(() async {
          await tester.tap(find.text('Confirm shop & add delivery'));
          await controller.whenIdle;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(controller.stops.single.shopId, 'alpha');
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester);
      }
    },
  );

  testWidgets('camera result is recovered after Android restarts the app', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await setup();
      await store.setting('bill_scan_state', 'picking');
    });
    try {
      await mount(tester);
      await settleScan(tester);
      expect(scanner.recoveries, 1);
      expect(scanner.reads, 1);
      await tester.scrollUntilVisible(
        find.text('Alpha Stationery'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Alpha Stationery'), findsOneWidget);
      expect(controller.stops, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await cleanup(tester);
    }
  });

  testWidgets(
    'unknown scanned shop is created with its name and returns to delivery preparation',
    (tester) async {
      await tester.runAsync(setup);
      try {
        scanner.text =
            'G.M. ENTERPRISES\nTax Invoice\nBuyer (Bill to): Omega Paper House\n18 Main Road\nGSTIN 29ABCDE1234F1Z5\nGrand Total 500';
        await mount(tester);
        await tester.runAsync(() async {
          await tester.tap(find.text('Scan whole bill'));
        });
        await settleScan(tester);
        await tester.scrollUntilVisible(
          find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Shop name',
          ),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        final nameField = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Shop name',
        );
        expect(
          tester.widget<TextField>(nameField).controller!.text,
          'Omega Paper House',
        );
        expect(find.textContaining('Grand Total'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Add new shop'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Add new shop'));
        await tester.pumpAndSettle();
        final prefilled = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Shop name',
        );
        expect(
          tester.widget<TextField>(prefilled).controller!.text,
          'Omega Paper House',
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('Save'));
          await controller.whenIdle;
        });
        await settleScan(tester);
        final added = controller.shops.singleWhere(
          (s) => s.name == 'Omega Paper House',
        );
        expect(added.area, 'Area not set');
        expect(added.hasLocation, isFalse);
        expect(controller.stops, isEmpty);
        await tester.scrollUntilVisible(
          find.textContaining('Add a Google Maps link or capture'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.textContaining('Add a Google Maps link or capture'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await cleanup(tester);
      }
    },
  );
}

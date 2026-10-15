import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gm_delivery/application/delivery_controller.dart';
import 'package:gm_delivery/data/local_store.dart';
import 'package:gm_delivery/data/bill_scan_service.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/main.dart';
import 'package:gm_delivery/presentation/home_screen.dart';
import 'package:gm_delivery/presentation/bill_scan_screen.dart';

class PreviewScanner implements BillScanService {
  PreviewScanner(this.path);
  final String path;
  String name = 'Lakshmi Stationery';
  @override
  Future<String?> pick(ImageSource source) async => path;
  @override
  Future<String?> recoverLostImage() async => null;
  @override
  Future<String> readText(String path) async =>
      'G.M. ENTERPRISES\nTax Invoice\nBill To: $name\n12 Market Road\nGrand Total 500';
}

// Explicit output capture, not part of the normal test suite. The sample records
// live only in an in-memory database and are never written to an Android phone.
void main() {
  testWidgets('export actual Flutter phone screens', (tester) async {
    final previousDisableShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = previousDisableShadows);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sqfliteFfiInit();
    late LocalStore store;
    late DeliveryController controller;
    late Directory photos;
    await tester.runAsync(() async {
      final sdk = Platform.environment['GM_PREVIEW_FLUTTER_ROOT'];
      if (sdk == null) {
        throw StateError('Run scripts/verify.ps1 -Preview.');
      }
      final fonts = p.join(sdk, 'bin', 'cache', 'artifacts', 'material_fonts');
      final roboto = FontLoader('Roboto');
      for (final name in [
        'roboto-regular.ttf',
        'roboto-medium.ttf',
        'roboto-bold.ttf',
      ]) {
        roboto.addFont(
          File(p.join(fonts, name)).readAsBytes().then(ByteData.sublistView),
        );
      }
      await roboto.load();
      await (FontLoader('MaterialIcons')..addFont(
            File(
              p.join(fonts, 'materialicons-regular.otf'),
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
      store = LocalStore(
        await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) => LocalStore.createSchema(db),
          ),
        ),
      );
      photos = await Directory.systemTemp.createTemp('gm_screen_capture_');
      controller = DeliveryController(
        store: store,
        photoDirectory: photos,
        accountId: 'local',
      );
      await controller.initialize();
      await Directory('preview').create(recursive: true);
    });
    await tester.pumpWidget(const SizedBox.shrink());
    // Reuse the real app's theme without initializing phone-only plugins.
    final app =
        const GmApp().build(tester.element(find.byType(SizedBox)))
            as MaterialApp;
    final boundaryKey = GlobalKey();
    Future<void> mount(Widget screen) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            key: UniqueKey(),
            theme: app.theme,
            debugShowCheckedModeBanner: false,
            home: screen,
          ),
        ),
      );
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
            find.text('Finding matching shops…').evaluate().isEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();
    }

    await mount(HomeScreen(controller: controller));

    Future<void> capture(String name) async {
      expect(
        tester.takeException(),
        isNull,
        reason: 'No overflow or render error in $name',
      );
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'preview/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.tap(find.text('Shops'));
    await tester.pumpAndSettle();
    await capture('01-empty-directory');
    await tester.runAsync(() async {
      const samples = [
        Shop(
          id: 'sample-1',
          name: 'Lakshmi Stationery',
          area: 'Market Road',
          landmark: 'Beside the main bus stop',
          phone: '9000000001',
          address: '12 Market Road',
          notes: 'Use the front entrance. Opens after 10 AM.',
          latitude: 12.9716,
          longitude: 77.5946,
          verified: true,
        ),
        Shop(
          id: 'sample-2',
          name: 'City Book House',
          area: 'Market Road',
          landmark: 'Opposite the post office',
          latitude: 12.975,
          longitude: 77.599,
          verified: true,
        ),
        Shop(
          id: 'sample-3',
          name: 'Student Corner',
          area: 'College Road',
          landmark: 'Entrance next to the bakery',
          latitude: 12.98,
          longitude: 77.6,
          verified: true,
        ),
        Shop(id: 'sample-4', name: 'New Friends Stores', area: 'College Road'),
      ];
      for (final shop in samples) {
        await controller.saveShop(shop);
      }
      for (final id in ['sample-1', 'sample-2', 'sample-3']) {
        await controller.addStop(
          controller.shopFor(id)!,
          DateTime.now(),
          'local-driver',
        );
      }
      await controller.recordVisit(
        controller.stops.firstWhere((s) => s.shopId == 'sample-3'),
        VisitStatus.delivered,
      );
    });
    await tester.pumpAndSettle();
    await capture('02-shop-directory');
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    await capture('06-owner-overview');
    await mount(ShopDetails(controller: controller, shopId: 'sample-1'));
    await capture('03-shop-details');
    await mount(HomeScreen(controller: controller));
    await tester.tap(find.text('Deliveries'));
    await tester.pumpAndSettle();
    await capture('04-delivery-list');
    await tester.tap(find.text('Add stops'));
    await tester.pumpAndSettle();
    await capture('05-prepare-deliveries');
    final scanner = PreviewScanner('preview/02-shop-directory.png');
    await mount(
      BillScanScreen(
        controller: controller,
        date: DateTime.now(),
        scanner: scanner,
      ),
    );
    await capture('07-scan-shop-name');
    await tester.runAsync(() async {
      await tester.tap(find.text('Scan whole bill'));
    });
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.text('Finding matching shops…').evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('GPS:'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await capture('08-shop-found');
    await tester.runAsync(
      () => controller.saveShop(
        const Shop(
          id: 'sample-1',
          name: 'Lakshmi Stationery',
          area: 'Market Road',
          address: '12 Market Road',
          mapsUrl:
              'https://www.google.com/maps/search/?api=1&query=Lakshmi+Stationery+Market+Road',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Google Maps location saved. Coordinates are not required.'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await capture('10-maps-link-location');
    scanner.name = 'Omega Paper House';
    await tester.scrollUntilVisible(
      find.text('Scan whole bill'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Scan whole bill'));
    });
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.text('Finding matching shops…').evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Add new shop'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await capture('09-add-missing-shop');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.runAsync(() async {
      await store.close();
      await photos.delete(recursive: true);
    });
    // Flutter checks painting invariants before registered tear-down callbacks.
    debugDisableShadows = previousDisableShadows;
  });
}

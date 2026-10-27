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
import 'package:gm_delivery/domain/ledger.dart';
import 'package:gm_delivery/domain/settlement.dart';
import 'package:gm_delivery/main.dart';
import 'package:gm_delivery/presentation/home_screen.dart';
import 'package:gm_delivery/presentation/bill_scan_screen.dart';
import 'package:gm_delivery/presentation/collection_form.dart';
import 'package:gm_delivery/presentation/ledger_screen.dart';
import 'package:gm_delivery/presentation/settlement_screen.dart';
import 'package:gm_delivery/data/collection_location_service.dart';
import 'package:gm_delivery/data/shop_location_service.dart';
import 'package:gm_delivery/presentation/shop_form.dart';

class PreviewShopLocation implements ShopLocationService {
  @override
  Future<ShopGpsFix> capture() async => const ShopGpsFix(12.9716, 77.5946, 3);
  @override
  Future<ShopAddress?> addressFor(ShopGpsFix fix) async => const ShopAddress(
    address: 'Shop 12, Market Road, Bengaluru',
    area: 'Central Market',
    postalCode: '560001',
  );
}

class PreviewCollectionGps implements CollectionLocationService {
  @override
  Future<CollectionLocation> capture() async => const CollectionLocation(
    latitude: 12.9716,
    longitude: 77.5946,
    accuracy: 8,
    status: 'available',
  );
}

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
      await (FontLoader('PlusJakartaSans')..addFont(
            File(
              'assets/fonts/PlusJakartaSans.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
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

    await tester.tap(find.text('All Shops'));
    await tester.pumpAndSettle();
    await capture('01-empty-directory');
    await tester.runAsync(() async {
      const samples = [
        Shop(
          id: 'sample-1',
          name: 'Lakshmi Stationery',
          contactName: 'Rajesh Sharma',
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
          contactName: 'Govind Narang',
          phone: '9000000002',
          address: '21 Palace Road, Heritage Market',
          area: 'Market Road',
          landmark: 'Opposite the post office',
          latitude: 12.975,
          longitude: 77.599,
          verified: true,
        ),
        Shop(
          id: 'sample-3',
          name: 'Student Corner',
          contactName: 'Farhan Ali',
          phone: '9000000003',
          address: '8 College Road, near the clock tower',
          area: 'College Road',
          landmark: 'Entrance next to the bakery',
          latitude: 12.98,
          longitude: 77.6,
          verified: true,
        ),
        Shop(
          id: 'sample-4',
          name: 'New Friends Stores',
          area: 'College Road',
          contactName: 'Aryan Patel',
          phone: '9000000004',
          address: '102 Cross Bazaar',
        ),
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
      final delivered = controller.stops.firstWhere(
        (s) => s.shopId == 'sample-3',
      );
      await controller.submitLedger(
        LedgerCommand(
          operationId: 'preview-completed-bill',
          shopId: delivered.shopId,
          kind: LedgerKind.bill,
          capturedAt: DateTime.now().toUtc(),
          stopId: delivered.id,
          expectedStopVersion: delivered.version,
          billNumber: 'PREVIEW-001',
          billPaise: 10000,
          collectedPaise: 10000,
          mode: PaymentMode.cash,
        ),
      );
    });
    await tester.pumpAndSettle();
    await capture('02-shop-directory');
    await tester.tap(find.byKey(const ValueKey('directory-range-A–D')));
    await tester.pumpAndSettle();
    await capture('20-directory-filter');
    await tester.tap(find.byKey(const ValueKey('directory-range-All')));
    await tester.pumpAndSettle();
    await mount(ShopDetails(controller: controller, shopId: 'sample-1'));
    await capture('03-shop-details');
    await mount(HomeScreen(controller: controller));
    await tester.tap(find.text('Assign Delivery'));
    await tester.pumpAndSettle();
    await capture('04-delivery-list');
    final firstPending = controller
        .stopsFor(DateTime.now())
        .firstWhere((s) => s.status == VisitStatus.pending);
    await tester.ensureVisible(
      find.byKey(ValueKey('route-down-${firstPending.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('route-down-${firstPending.id}')));
    await tester.pumpAndSettle();
    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('owner-dispatch-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await capture('22-delivery-order-draft');
    await tester.tap(find.byKey(const Key('route-reset')));
    await tester.pumpAndSettle();
    final routeDriver = DeliveryController(
      store: store,
      photoDirectory: photos,
      accountId: 'local-driver',
    );
    await tester.runAsync(() async {
      await routeDriver.initialize();
      routeDriver.profile = const AppProfile(
        id: 'local-driver',
        name: 'Ramesh Kumar',
        role: UserRole.driver,
      );
      routeDriver.profiles = [
        ...controller.profiles.where((p) => p.id != 'local-driver'),
        routeDriver.profile!,
      ];
    });
    await mount(HomeScreen(controller: routeDriver));
    await capture('23-driver-deliveries');
    final routeStop = routeDriver
        .stopsFor(DateTime.now())
        .firstWhere((s) => s.status == VisitStatus.pending);
    final driverCard = find.byKey(ValueKey('driver-stop-${routeStop.id}'));
    await tester.scrollUntilVisible(
      driverCard,
      220,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('driver-delivery-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(tester.element(driverCard), alignment: 0);
    await tester.pumpAndSettle();
    await capture('24-driver-stop');
    await tester.tap(find.text('Shops'));
    await tester.pumpAndSettle();
    await capture('25-driver-shop-search');
    await tester.enterText(
      find.byKey(const Key('driver-shop-search')),
      'Rajesh',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await capture('27-driver-search-result');
    final savedMap = find.byKey(const ValueKey('driver-search-map-sample-1'));
    await tester.scrollUntilVisible(
      savedMap,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('driver-shop-results')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(savedMap);
    await tester.pumpAndSettle();
    await tester.tap(savedMap);
    await tester.pumpAndSettle();
    await capture('26-driver-shop-location');
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    await mount(HomeScreen(controller: controller));
    routeDriver.dispose();
    await tester.tap(find.text('Assign Delivery'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add stops'));
    await tester.pumpAndSettle();
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
      find.text('GPS entrance saved and verified.'),
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
          contactName: 'Rajesh Sharma',
          phone: '9000000001',
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
    scanner.name = 'Lakshmi Stationery';
    await mount(
      BillScanScreen(
        controller: controller,
        date: DateTime.now().add(const Duration(days: 1)),
        scanner: scanner,
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('confirm-dispatch')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('confirm-dispatch')));
    await tester.pumpAndSettle();
    await capture('21-confirm-dispatch');
    await tester.runAsync(() async {
      await controller.submitLedger(
        LedgerCommand(
          operationId: 'preview-opening-a',
          shopId: 'sample-1',
          kind: LedgerKind.opening,
          capturedAt: DateTime.now().toUtc().subtract(const Duration(days: 20)),
          billPaise: 50050,
        ),
      );
      await controller.submitLedger(
        LedgerCommand(
          operationId: 'preview-opening-b',
          shopId: 'sample-2',
          kind: LedgerKind.opening,
          capturedAt: DateTime.now().toUtc().subtract(const Duration(days: 10)),
          billPaise: 30000,
        ),
      );
    });
    final stop = controller.stops.firstWhere((s) => s.shopId == 'sample-1');
    await mount(
      CollectionForm(
        controller: controller,
        shopId: 'sample-1',
        stopId: stop.id,
        locationService: PreviewCollectionGps(),
      ),
    );
    Future<void> typeAmount(String label, String value) async {
      final shopField = find.byKey(ValueKey('shop-field-$label'));
      final field = shopField.evaluate().isNotEmpty
          ? find.descendant(of: shopField, matching: find.byType(TextField))
          : find.byWidgetPredicate(
              (w) => w is TextField && w.decoration?.labelText == label,
            );
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, value);
      await tester.pump();
    }

    await typeAmount('Bill number', 'GM-1042');
    await typeAmount('Bill amount (₹)', '750.00');
    final mode = find.byType(DropdownButtonFormField<PaymentMode>);
    await tester.ensureVisible(mode);
    await tester.pumpAndSettle();
    await tester.tap(mode);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CASH').last);
    await tester.pumpAndSettle();
    await typeAmount('Amount collected (₹)', '500.00');
    await Scrollable.ensureVisible(
      tester.element(find.text('This bill balance: ₹250.00')),
      alignment: 0.6,
    );
    await tester.pumpAndSettle();
    await capture('11-collection-entry');
    await tester.runAsync(
      () => controller.submitLedger(
        LedgerCommand(
          operationId: 'preview-partial-bill',
          shopId: 'sample-1',
          kind: LedgerKind.bill,
          capturedAt: DateTime.now().toUtc(),
          stopId: stop.id,
          expectedStopVersion: stop.version,
          billNumber: 'GM-1042',
          billPaise: 75000,
          collectedPaise: 50000,
          mode: PaymentMode.cash,
          location: const CollectionLocation(
            latitude: 12.9716,
            longitude: 77.5946,
            accuracy: 8,
            status: 'available',
          ),
        ),
      ),
    );
    await mount(ShopLedgerScreen(controller: controller, shopId: 'sample-1'));
    await capture('12-shop-ledger');
    await mount(OutstandingScreen(controller: controller));
    await capture('13-outstanding-balances');
    final ownerProfile = controller.profile!;
    final driverProfile = controller.profiles
        .where((p) => p.id == stop.driverId)
        .first;
    // Screenshots use a separate local controller so driver authorization remains
    // identical to the production account-ID checks.
    final driverController = DeliveryController(
      store: store,
      photoDirectory: photos,
      accountId: driverProfile.id,
    );
    await tester.runAsync(() async {
      await driverController.initialize();
      driverController.profile = driverProfile;
    });
    final sampleHanded =
        driverController.settlementFor(stop.driverId, stop.date).totals.cash -
        1000;
    await mount(
      SettlementScreen(
        controller: driverController,
        driverId: stop.driverId,
        date: stop.date,
      ),
    );
    final handedField = find.byKey(const Key('settlement-cash'));
    await tester.ensureVisible(handedField);
    await tester.pumpAndSettle();
    await tester.enterText(handedField, rupees(sampleHanded, symbol: false));
    final reasonField = find.byKey(const Key('settlement-reason'));
    await tester.ensureVisible(reasonField);
    await tester.pumpAndSettle();
    await tester.enterText(
      reasonField,
      '₹10 shortage reported to owner; recount requested.',
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await capture('14-driver-settlement');
    await tester.runAsync(() async {
      final day = driverController.settlementFor(stop.driverId, stop.date);
      await driverController.submitSettlement(
        SettlementCommand(
          operationId: 'preview-settlement',
          driverId: stop.driverId,
          date: stop.date,
          action: SettlementAction.submit,
          expectedRevision: day.revision,
          ledgerVersion: day.totals.ledgerVersion,
          capturedAt: DateTime.now(),
          handedPaise: sampleHanded,
          reason: '₹10 shortage reported to owner; recount requested.',
        ),
      );
      await controller.reloadLocal();
      controller.profile = ownerProfile;
    });
    await mount(
      SettlementScreen(
        controller: controller,
        driverId: stop.driverId,
        date: stop.date,
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Confirm cash received & approve'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Confirm cash received & approve')),
      alignment: .8,
    );
    await tester.pumpAndSettle();
    await capture('15-owner-settlement-review');
    await mount(
      ShopForm(controller: controller, locationService: PreviewShopLocation()),
    );
    await typeAmount('Shop name', 'National Pen Corner');
    await typeAmount('Proprietor / contact person', 'Rajesh Sharma');
    await typeAmount('Contact number', '+91 98765 43210');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shop-field-Shop name')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('shop-field-Shop name'))),
      alignment: .18,
    );
    await tester.pumpAndSettle();
    await capture('16-add-shop');
    const profileShop = Shop(
      id: 'preview-profile',
      name: 'National Pen Corner',
      area: 'Central Market',
      contactName: 'Rajesh Sharma',
      phone: '+91 98765 43210',
      address: 'Shop 12, Market Road, Bengaluru',
      landmark: 'Opposite Central Bank',
      postalCode: '560001',
      latitude: 12.9716,
      longitude: 77.5946,
      verified: true,
    );
    await mount(
      ShopForm(
        controller: controller,
        shop: profileShop,
        locationService: PreviewShopLocation(),
      ),
    );
    await capture('17-edit-shop');
    final gpsButton = find.byKey(const Key('shop-capture-gps'));
    await tester.scrollUntilVisible(
      gpsButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.runAsync(() => tester.tap(gpsButton));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shop-field-PIN code')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('shop-field-Address'))),
      alignment: .35,
    );
    await tester.pumpAndSettle();
    await capture('18-shop-location');
    await Scrollable.ensureVisible(
      tester.element(find.byType(CheckboxListTile)),
      alignment: .85,
    );
    await tester.pumpAndSettle();
    await capture('19-shop-entrance');
    await tester.pumpWidget(const SizedBox.shrink());
    driverController.dispose();
    controller.dispose();
    await tester.runAsync(() async {
      await store.close();
      await photos.delete(recursive: true);
    });
    // Flutter checks painting invariants before registered tear-down callbacks.
    debugDisableShadows = previousDisableShadows;
  });
}

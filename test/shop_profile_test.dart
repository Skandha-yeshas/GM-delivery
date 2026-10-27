import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gm_delivery/application/delivery_controller.dart';
import 'package:gm_delivery/data/local_store.dart';
import 'package:gm_delivery/data/shop_location_service.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/presentation/shop_form.dart';

class TestShopLocation implements ShopLocationService {
  Object? failure;
  bool unavailable = false;
  Completer<ShopAddress?>? addressGate;
  @override
  Future<ShopGpsFix> capture() async {
    if (failure != null) throw failure!;
    return const ShopGpsFix(12.9716, 77.5946, 7);
  }

  @override
  Future<ShopAddress?> addressFor(ShopGpsFix fix) async {
    if (addressGate != null) return addressGate!.future;
    if (unavailable) throw const SocketException('offline');
    return const ShopAddress(
      address: '12 Market Road, Bengaluru',
      area: 'Central Market',
      postalCode: '560001',
    );
  }
}

void main() {
  setUpAll(sqfliteFfiInit);
  late LocalStore store;
  late Directory photos;
  late DeliveryController c;
  setUp(() async {
    store = LocalStore(
      await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (db, _) => LocalStore.createSchema(db),
        ),
      ),
    );
    photos = await Directory.systemTemp.createTemp('gm_shop_profile_');
    c = DeliveryController(
      store: store,
      photoDirectory: photos,
      accountId: 'local',
    );
    await c.initialize();
  });
  tearDown(() async {
    await c.whenIdle;
    c.dispose();
    await store.close();
    await photos.delete(recursive: true);
  });

  test(
    'contact and PIN survive photo copies and v4-to-v5 upgrade preserves pending records',
    () async {
      const shop = Shop(
        id: 'shop',
        name: 'National',
        area: 'Market',
        contactName: 'Rajesh',
        postalCode: '560001',
        notes: 'Side entrance',
      );
      expect(Shop.fromMap(shop.toMap()).contactName, 'Rajesh');
      expect(shop.withPhoto('photo.jpg', 'local.jpg').postalCode, '560001');
      expect(
        Shop.fromMap({
          'id': 'old',
          'name': 'Legacy',
          'area': 'Market',
        }).postalCode,
        '',
      );
      await store.saveShop(shop);
      await store.saveStop(
        const DeliveryStop(
          id: 'stop',
          shopId: 'shop',
          date: '2026-10-20',
          driverId: 'driver',
          order: 1,
          version: 1,
        ),
      );
      await store.queueVisit(
        const DeliveryStop(
          id: 'stop',
          shopId: 'shop',
          date: '2026-10-20',
          driverId: 'driver',
          order: 1,
          version: 2,
          status: VisitStatus.failed,
          reason: 'Closed',
        ),
        const PendingVisit(
          operationId: 'op',
          stopId: 'stop',
          status: VisitStatus.failed,
          reason: 'Closed',
          expectedVersion: 1,
        ),
      );
      await store.database.execute(
        'ALTER TABLE shops DROP COLUMN contact_name',
      );
      await store.database.execute('ALTER TABLE shops DROP COLUMN postal_code');
      await LocalStore.upgradeSchema(store.database, 4, 5);
      expect((await store.shops()).single.notes, 'Side entrance');
      expect((await store.shops()).single.contactName, '');
      expect((await store.pendingVisits()).single.operationId, 'op');
    },
  );

  Future<void> size(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Finder field(String label) => find.descendant(
    of: find.byKey(ValueKey('shop-field-$label')),
    matching: find.byType(TextField),
  );
  Future<void> show(
    WidgetTester tester,
    Finder target, {
    double delta = 220,
  }) async {
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        delta,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await Scrollable.ensureVisible(tester.element(target), alignment: .5);
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> type(WidgetTester tester, String label, String text) async {
    await show(tester, field(label));
    await tester.enterText(field(label), text);
    await tester.pump();
  }

  Future<void> mount(
    WidgetTester tester, {
    Shop? shop,
    TestShopLocation? gps,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ShopForm(controller: c, shop: shop, locationService: gps),
                ),
              ),
              child: const Text('Open form'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => tester.tap(find.text('Open form')));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('save-shop')));
      await c.whenIdle;
    });
    await tester.pumpAndSettle();
  }

  testWidgets('all marked fields are required even below the screen', (
    tester,
  ) async {
    await size(tester);
    await mount(tester);
    await save(tester);
    expect(c.shops, isEmpty);
    expect(find.text('Enter Shop name.'), findsOneWidget);
    expect(find.text('Enter Proprietor / contact person.'), findsOneWidget);
    expect(find.text('Enter a 10-digit mobile number.'), findsOneWidget);
    expect(find.text('Enter Address.'), findsOneWidget);
    expect(find.text('Enter a valid 6-digit PIN.'), findsOneWidget);
    await type(tester, 'Shop name', 'Required fields shop');
    await type(tester, 'Proprietor / contact person', 'Rajesh');
    await type(tester, 'Contact number', '98765');
    await type(tester, 'Address', '12 Market Road');
    await type(tester, 'PIN code', '560001');
    await save(tester);
    expect(c.shops, isEmpty);
    expect(find.text('Enter a 10-digit mobile number.'), findsOneWidget);
    await type(tester, 'Contact number', '9876543210');
    await save(tester);
    expect(c.shops.single.phone, '+919876543210');
    expect(c.shops.single.hasLocation, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'coordinates remain private and cancel preserves the saved shop',
    (tester) async {
      await size(tester);
      const shop = Shop(
        id: 'existing',
        name: 'Saved shop',
        area: 'Market',
        contactName: 'Rajesh',
        phone: '+919876543210',
        address: '12 Market Road',
        postalCode: '560001',
        latitude: 12.9716,
        longitude: 77.5946,
        verified: true,
      );
      await tester.runAsync(() => c.saveShop(shop));
      await mount(tester, shop: shop);
      await type(tester, 'Shop name', 'Unsaved name');
      final extras = find.byKey(const Key('shop-additional-details'));
      await show(tester, extras);
      await tester.tap(extras);
      await tester.pumpAndSettle();
      expect(field('Latitude'), findsNothing);
      expect(field('Longitude'), findsNothing);
      expect(find.textContaining('12.9716'), findsNothing);
      expect(find.textContaining('77.5946'), findsNothing);
      expect(find.text('Coordinates'), findsNothing);
      expect(find.text('Shop entrance pin saved'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.shops.single.name, 'Saved shop');
      expect(c.shops.single.latitude, 12.9716);
      expect(c.shops.single.verified, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'small screen and enlarged text retain location and save controls without overflow',
    (tester) async {
      await size(tester);
      tester.view.physicalSize = const Size(320, 740);
      await mount(
        tester,
        textScale: 1.4,
        shop: const Shop(
          id: 'compact',
          name: 'Compact shop',
          area: 'Market',
          latitude: 12.9716,
          longitude: 77.5946,
          verified: true,
        ),
      );
      expect(tester.takeException(), isNull);
      await show(tester, find.byKey(const Key('shop-copy-location')));
      expect(tester.takeException(), isNull);
      await show(tester, find.byType(CheckboxListTile));
      expect(find.byKey(const Key('save-shop')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'add and edit persist contact and PIN while Maps-only locations remain ready',
    (tester) async {
      await size(tester);
      await mount(tester);
      await type(tester, 'Shop name', 'National Pen Corner');
      await type(tester, 'Proprietor / contact person', 'Rajesh Sharma');
      await type(tester, 'Contact number', '+91 98765 43210');
      await type(tester, 'Address', '12 Market Road');
      await type(
        tester,
        'Google Maps link (optional)',
        'https://maps.app.goo.gl/example',
      );
      await type(tester, 'PIN code', '560001');
      await save(tester);
      final shop = c.shops.single;
      expect(shop.contactName, 'Rajesh Sharma');
      expect(shop.phone, '+919876543210');
      expect(shop.postalCode, '560001');
      expect(shop.hasCoordinates, isFalse);
      expect(shop.readyForDelivery, isTrue);
      await mount(tester, shop: shop);
      expect(
        tester
            .widget<TextField>(field('Proprietor / contact person'))
            .controller!
            .text,
        'Rajesh Sharma',
      );
      await type(tester, 'Proprietor / contact person', 'New contact');
      await save(tester);
      expect(c.shops.single.id, shop.id);
      expect(c.shops.single.contactName, 'New contact');
      expect(c.shops.single.mapsUrl, shop.mapsUrl);
      expect(c.shops.single.postalCode, '560001');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'real capture flow fills empty address, requires confirmation, saves coordinates and copy link',
    (tester) async {
      await size(tester);
      await mount(tester, gps: TestShopLocation());
      await type(tester, 'Shop name', 'Unlisted Shop');
      await type(tester, 'Proprietor / contact person', 'Rajesh');
      await type(tester, 'Contact number', '9876543210');
      final capture = find.byKey(const Key('shop-capture-gps'));
      await show(tester, capture);
      await tester.runAsync(() => tester.tap(capture));
      await tester.pumpAndSettle();
      expect(find.text('Live GPS · accuracy about 7 m'), findsOneWidget);
      await show(tester, field('Address'));
      expect(
        tester.widget<TextField>(field('Address')).controller!.text,
        '12 Market Road, Bengaluru',
      );
      await show(tester, find.byKey(const Key('shop-copy-location')));
      await tester.tap(find.byKey(const Key('shop-copy-location')));
      await tester.pumpAndSettle();
      final confirm = find.byType(CheckboxListTile);
      await show(tester, confirm);
      expect(tester.widget<CheckboxListTile>(confirm).value, isFalse);
      await tester.tap(confirm);
      await tester.pump();
      await save(tester);
      expect(c.shops.single.verified, isTrue);
      expect(c.shops.single.latitude, 12.9716);
      expect(c.shops.single.mapsUrl, isEmpty);
      expect(c.shops.single.postalCode, '560001');
      expect(c.shops.single.readyForDelivery, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'lookup failure keeps captured pin and manual address; denied GPS never claims capture',
    (tester) async {
      await size(tester);
      final gps = TestShopLocation()..unavailable = true;
      const shop = Shop(
        id: 'shop',
        name: 'Existing',
        area: 'East',
        address: 'Owner address',
        contactName: 'Rajesh',
        phone: '+919876543210',
        postalCode: '560002',
      );
      await tester.runAsync(() => c.saveShop(shop));
      await mount(tester, shop: shop, gps: gps);
      final capture = find.byKey(const Key('shop-capture-gps'));
      await show(tester, capture);
      await tester.runAsync(() => tester.tap(capture));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Address lookup unavailable; your GPS pin is kept'),
        findsOneWidget,
      );
      await show(tester, field('Address'));
      expect(
        tester.widget<TextField>(field('Address')).controller!.text,
        'Owner address',
      );
      await save(tester);
      expect(c.shops.single.latitude, 12.9716);
      expect(c.shops.single.verified, isFalse);
      expect(c.shops.single.postalCode, '560002');
      gps.failure = const ShopLocationException(
        'Allow location access in the phone’s app settings.',
        settingsNeeded: true,
      );
      await mount(
        tester,
        shop: const Shop(id: 'denied', name: 'Denied', area: 'East'),
        gps: gps,
      );
      await show(tester, capture);
      await tester.runAsync(() => tester.tap(capture));
      await tester.pumpAndSettle();
      expect(find.text('Open app settings'), findsOneWidget);
      expect(find.textContaining('Live GPS · accuracy'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'a manual address entered during lookup is retained and malformed PIN is rejected',
    (tester) async {
      await size(tester);
      final gps = TestShopLocation()..addressGate = Completer<ShopAddress?>();
      await mount(tester, gps: gps);
      await type(tester, 'Shop name', 'Manual address shop');
      await type(tester, 'Proprietor / contact person', 'Rajesh');
      await type(tester, 'Contact number', '9876543210');
      final capture = find.byKey(const Key('shop-capture-gps'));
      await show(tester, capture);
      await tester.runAsync(() => tester.tap(capture));
      await tester.pump();
      await type(tester, 'Address', 'Owner-entered exact doorway');
      gps.addressGate!.complete(
        const ShopAddress(
          address: 'Approximate road',
          area: 'Market',
          postalCode: '560001',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Address')).controller!.text,
        'Owner-entered exact doorway',
      );
      await type(tester, 'PIN code', '000000');
      await save(tester);
      expect(c.shops, isEmpty);
      expect(find.text('Enter a valid 6-digit PIN.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

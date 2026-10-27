import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/presentation/driver_shop_search.dart';
import 'package:gm_delivery/presentation/shop_directory.dart';

void main() {
  const shops = [
    Shop(
      id: 'alpha',
      name: 'Alpha Stationery',
      area: 'East',
      contactName: 'Rajesh Sharma',
      phone: '+919876543210',
      address: '14 Market Road',
      landmark: 'Central Bank',
      mapsUrl: 'https://maps.app.goo.gl/alpha',
    ),
    Shop(
      id: 'beta',
      name: 'Beta Pen House',
      area: 'West',
      contactName: 'Meena Chawla',
      address: '22 Station Road',
      latitude: 12.3,
      longitude: 77.5,
      verified: true,
    ),
    Shop(
      id: 'gamma',
      name: 'Gamma Supplies',
      area: 'West',
      address: 'Old Bazaar',
      contactName: 'Harish Varma',
    ),
  ];
  late TextEditingController search;
  setUp(() => search = TextEditingController());
  tearDown(() => search.dispose());
  Future<void> mount(
    WidgetTester tester, {
    List<Shop> records = shops,
    double scale = 1,
    Size size = const Size(390, 844),
    ValueChanged<Shop>? onNavigate,
    ValueChanged<Shop>? onCall,
    ValueChanged<Shop>? onOpen,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var query = '';
    await tester.pumpWidget(
      MaterialApp(
        theme: DirectoryDesign.theme(ThemeData()),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => DriverShopSearch(
              shops: records,
              todayShopIds: const {'alpha', 'gamma'},
              searchController: search,
              search: query,
              onSearch: (value) => update(() => query = value),
              onRefresh: () async {},
              onOpen: onOpen ?? (_) {},
              onCall: onCall ?? (_) {},
              onMap: (shop) => showDriverShopLocation(
                context,
                shop,
                onNavigate: onNavigate ?? (_) {},
                onCall: onCall ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('driver-shop-results')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(tester.element(finder), alignment: .4);
    await tester.pumpAndSettle();
  }

  Future<void> query(WidgetTester tester, String value) async {
    await tester.enterText(find.byKey(const Key('driver-shop-search')), value);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'search matches actual names, contacts, addresses, landmarks and formatted phone numbers',
    (tester) async {
      Shop? opened, called;
      await mount(
        tester,
        onOpen: (shop) => opened = shop,
        onCall: (shop) => called = shop,
      );
      for (final term in [
        'RAJESH',
        '14 market',
        'central BANK',
        '98765-43210',
        'alpha East',
      ]) {
        await query(tester, term);
        expect(find.text('1 shop shown'), findsOneWidget);
        await reveal(
          tester,
          find.byKey(const ValueKey('driver-search-shop-alpha')),
        );
        expect(
          find.byKey(const ValueKey('driver-search-shop-gamma')),
          findsNothing,
        );
      }
      await tester.tap(find.text('Alpha Stationery'));
      expect(opened?.id, 'alpha');
      await reveal(
        tester,
        find.byKey(const ValueKey('driver-search-call-alpha')),
      );
      await tester.tap(find.byKey(const ValueKey('driver-search-call-alpha')));
      expect(called?.phone, '+919876543210');
      await tester.tap(find.byTooltip('Clear shop search'));
      await tester.pumpAndSettle();
      expect(find.text('3 shops shown'), findsOneWidget);
      expect(find.textContaining('Cartons'), findsNothing);
      expect(find.text('GPS Calibrated'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'today, real location and area filters combine and no-results reset restores the directory',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('driver-shop-filter-today')));
      await tester.pumpAndSettle();
      expect(find.text('2 shops shown'), findsOneWidget);
      await tester.tap(find.byKey(const Key('driver-shop-area')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'West'),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 shop shown'), findsOneWidget);
      await query(tester, 'Rajesh');
      await reveal(tester, find.text('No matching shops'));
      await tester.tap(find.text('Reset search'));
      await tester.pumpAndSettle();
      expect(find.text('3 shops shown'), findsOneWidget);
      final ready = find.byKey(const ValueKey('driver-shop-filter-ready'));
      await tester.ensureVisible(ready);
      await tester.tap(ready);
      await tester.pumpAndSettle();
      expect(
        find.text('2 shops shown'),
        findsOneWidget,
        reason: 'A Maps share link needs no coordinate extraction',
      );
      await reveal(
        tester,
        find.byKey(const ValueKey('driver-search-call-beta')),
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('driver-search-call-beta')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('driver-shop-sort')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('driver-shop-sort')))
            .tooltip,
        'Sort A to Z',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'location sheet uses the chosen saved shop and handles missing location without a fake map',
    (tester) async {
      Shop? navigated;
      await mount(tester, onNavigate: (shop) => navigated = shop);
      await query(tester, 'alpha');
      await reveal(
        tester,
        find.byKey(const ValueKey('driver-search-map-alpha')),
      );
      await tester.tap(find.byKey(const ValueKey('driver-search-map-alpha')));
      await tester.pumpAndSettle();
      expect(find.text('Google Maps location saved'), findsOneWidget);
      expect(find.text('Landmark: Central Bank'), findsOneWidget);
      await tester.tap(find.byKey(const Key('driver-search-open-maps')));
      expect(navigationUri(navigated!).toString(), shops.first.mapsUrl);
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      await query(tester, 'gamma');
      await reveal(
        tester,
        find.byKey(const ValueKey('driver-search-map-gamma')),
      );
      await tester.tap(find.byKey(const ValueKey('driver-search-map-gamma')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('driver-search-open-maps')),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Ask the owner'), findsOneWidget);
      await tester.tap(find.byTooltip('Close shop location'));
      await tester.pumpAndSettle();
      expect(find.text('Open in Google Maps'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'hundreds of records stay lazy and a narrow keyboard viewport supports enlarged text',
    (tester) async {
      final many = List.generate(
        606,
        (i) => Shop(
          id: 'shop-$i',
          name: 'Shop ${i.toString().padLeft(3, '0')}',
          area: 'Market',
          mapsUrl: 'https://maps.app.goo.gl/example',
        ),
      );
      await mount(
        tester,
        records: many,
        scale: 1.4,
        size: const Size(320, 740),
      );
      expect(find.text('606 shops shown'), findsOneWidget);
      expect(
        find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith(
                    'driver-search-shop-',
                  ),
            )
            .evaluate()
            .length,
        lessThan(12),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 360);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('driver-shop-search')));
      await query(tester, 'Shop 605');
      expect(find.text('1 shop shown'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      final lastShop = find.byKey(
        const ValueKey('driver-search-shop-shop-605'),
      );
      await reveal(tester, lastShop);
      expect(
        find.descendant(of: lastShop, matching: find.text('Shop 605')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

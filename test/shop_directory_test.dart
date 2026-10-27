import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/presentation/shop_directory.dart';

void main() {
  const shops = [
    Shop(id: 'z', name: 'Zed Pens', area: 'West', address: '7 Palace Road'),
    Shop(
      id: 'a',
      name: 'Apex Stationery',
      area: 'East',
      contactName: 'Rajesh Sharma',
      phone: '+919876543210',
      address: '14 Market Road',
      mapsUrl: 'https://maps.app.goo.gl/example',
    ),
    Shop(
      id: 'b',
      name: 'Balaji Pens',
      area: 'West',
      address: '44 Industrial Area',
    ),
    Shop(id: 'e', name: 'Elite Books', area: 'East'),
    Shop(id: 'num', name: '123 Stores', area: 'East'),
    Shop(id: 'unicode', name: 'ಅಂಗಡಿ', area: 'East'),
  ];
  late TextEditingController search;
  setUp(() => search = TextEditingController());
  tearDown(() => search.dispose());

  Future<void> mount(
    WidgetTester tester, {
    List<Shop> records = shops,
    bool owner = true,
    Size size = const Size(390, 844),
    double scale = 1,
    ValueChanged<Shop>? onOpen,
    ValueChanged<Shop>? onCall,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var query = '', location = 'All locations';
    search.clear();
    String? area;
    await tester.pumpWidget(
      MaterialApp(
        theme: DirectoryDesign.theme(ThemeData(useMaterial3: true)),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => ShopDirectory(
              shops: records,
              search: query,
              searchController: search,
              onSearch: (value) => update(() => query = value),
              area: area,
              onArea: (value) => update(() => area = value),
              locationFilter: location,
              onLocationFilter: (value) => update(() => location = value),
              isOwner: owner,
              busy: false,
              onImport: () {},
              onAdd: () {},
              onOpen: onOpen ?? (_) {},
              onCall: onCall ?? (_) {},
              onRefresh: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> visible(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('shop-directory-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'letter groups filter real records, search and clear combine with the range, sorting reverses',
    (tester) async {
      await mount(tester);
      expect(find.text('All (6)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('directory-range-A–D')));
      await tester.pumpAndSettle();
      expect(find.text('2 shops shown'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('directory-search')),
        'RAJESH',
      );
      await tester.pumpAndSettle();
      expect(find.text('1 shop shown'), findsOneWidget);
      await visible(tester, find.text('Apex Stationery'));
      expect(find.text('Balaji Pens'), findsNothing);
      await visible(tester, find.byKey(const Key('directory-search')));
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('2 shops shown'), findsOneWidget);
      await tester.tap(find.byKey(const Key('directory-sort')));
      await tester.pumpAndSettle();
      await visible(tester, find.byKey(const ValueKey('directory-group-B')));
      await visible(tester, find.byKey(const ValueKey('directory-shop-a')));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('directory-shop-b'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('directory-shop-a'))).dy,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'location and area filters combine, map links count as ready, empty search resets',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const Key('directory-location-filter')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'Ready for delivery'),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 shop shown'), findsOneWidget);
      await tester.tap(find.byKey(const Key('directory-area-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'West'));
      await tester.pumpAndSettle();
      await visible(tester, find.text('No matching shops'));
      await tester.tap(find.text('Reset filters'));
      await tester.pumpAndSettle();
      expect(find.text('6 shops shown'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('directory-search')),
        '14 Market Road',
      );
      await tester.pumpAndSettle();
      expect(find.text('1 shop shown'), findsOneWidget);
      await visible(tester, find.text('Apex Stationery'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'contact actions use the selected saved shop and card opens its details',
    (tester) async {
      Shop? opened, called;
      await mount(
        tester,
        records: [shops[1]],
        onOpen: (shop) => opened = shop,
        onCall: (shop) => called = shop,
      );
      await visible(tester, find.byKey(const ValueKey('directory-call-a')));
      await tester.tap(find.byKey(const ValueKey('directory-call-a')));
      expect(called?.phone, '+919876543210');
      expect(opened, isNull);
      await tester.tap(find.text('Apex Stationery'));
      expect(opened?.id, 'a');
      expect(find.text('Rajesh Sharma'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester, records: [shops.first], owner: false);
      await visible(tester, find.byKey(const ValueKey('directory-call-z')));
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('directory-call-z')))
            .onPressed,
        isNull,
      );
      expect(find.text('Import Excel'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '600 shops and non-Latin names stay grouped; compact enlarged text has no overflow',
    (tester) async {
      final large = [
        ...shops,
        for (var i = 0; i < 600; i++)
          Shop(
            id: 'bulk-$i',
            name: 'Market ${i.toString().padLeft(3, '0')}',
            area: 'East',
          ),
      ];
      await mount(
        tester,
        records: large,
        size: const Size(320, 740),
        scale: 1.4,
      );
      expect(find.text('All (606)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('directory-shop-bulk-599')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const Key('directory-search')),
        'Market 599',
      );
      await tester.pumpAndSettle();
      await visible(
        tester,
        find.byKey(const ValueKey('directory-shop-bulk-599')),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester, records: [shops[4], shops[5]]);
      await visible(tester, find.byKey(const ValueKey('directory-group-#')));
      expect(find.text('2 Retailers'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

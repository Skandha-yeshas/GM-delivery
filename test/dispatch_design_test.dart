import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/presentation/dispatch_design.dart';
import 'package:gm_delivery/presentation/shop_directory.dart';

void main() {
  testWidgets(
    'dispatch board uses real status counts and exposes scan, manual list and date actions at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var scans = 0, manual = 0, dates = 0;
      const stops = [
        DeliveryStop(
          id: 'one',
          shopId: 'shop-one',
          date: '2026-10-22',
          driverId: 'driver',
          order: 1,
        ),
        DeliveryStop(
          id: 'two',
          shopId: 'shop-two',
          date: '2026-10-22',
          driverId: 'driver',
          order: 2,
          status: VisitStatus.delivered,
        ),
        DeliveryStop(
          id: 'three',
          shopId: 'shop-three',
          date: '2026-10-22',
          driverId: 'driver',
          order: 3,
          status: VisitStatus.failed,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: DirectoryDesign.theme(ThemeData()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: OwnerDispatchBoard(
              stops: stops,
              date: DateTime(2026, 10, 22),
              onScan: () => scans++,
              onAddStops: () => manual++,
              onChooseDate: () => dates++,
              onRefresh: () async {},
              stopBuilder: (stop, index) => Text(stop.shopId),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan whole bill'));
      expect(scans, 1);
      await tester.ensureVisible(find.text('Add stops'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add stops'));
      await tester.tap(find.text('22 Oct 2026'));
      expect(manual, 1);
      expect(dates, 1);
      await tester.ensureVisible(find.text('1 awaiting delivery'));
      await tester.pumpAndSettle();
      expect(find.text('1 delivered'), findsOneWidget);
      expect(find.textContaining('Cartons'), findsNothing);
      expect(find.text('Auto-Geocoded'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

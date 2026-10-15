import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gm_delivery/application/delivery_controller.dart';
import 'package:gm_delivery/data/local_store.dart';
import 'package:gm_delivery/domain/models.dart';

void main() {
  late LocalStore store;
  late Directory photos;
  const shop = Shop(
    id: 'shop-1',
    name: 'Test shop',
    area: 'Test area',
    latitude: 12.34,
    longitude: 77.56,
    verified: true,
  );
  const stop = DeliveryStop(
    id: 'stop-1',
    shopId: 'shop-1',
    date: '2026-10-13',
    driverId: 'driver-1',
    order: 1,
    version: 1,
  );

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    store = LocalStore(
      await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) => LocalStore.createSchema(db),
        ),
      ),
    );
    photos = await Directory.systemTemp.createTemp('gm_delivery_test_');
  });
  tearDown(() async {
    await store.close();
    await photos.delete(recursive: true);
  });

  test('editing a shop preserves its related deliveries', () async {
    await store.saveShop(shop);
    await store.saveStop(stop);
    await store.saveShop(
      const Shop(id: 'shop-1', name: 'Updated name', area: 'Test area'),
    );
    expect((await store.stops()).single.id, 'stop-1');
    expect((await store.shops()).single.name, 'Updated name');
  });

  test('one shop cannot be assigned twice on the same day', () async {
    await store.saveShop(shop);
    await store.saveStop(stop);
    expect(
      () => store.saveStop(
        const DeliveryStop(
          id: 'duplicate',
          shopId: 'shop-1',
          date: '2026-10-13',
          driverId: 'driver-1',
          order: 2,
        ),
      ),
      throwsA(isA<DatabaseException>()),
    );
    await store.saveStop(
      const DeliveryStop(
        id: 'next-day',
        shopId: 'shop-1',
        date: '2026-10-14',
        driverId: 'driver-1',
        order: 1,
      ),
    );
    expect(await store.stops(), hasLength(2));
  });

  test(
    'refresh cannot erase an offline delivery result or its durable operation ID',
    () async {
      await store.saveShop(shop);
      await store.saveStop(stop);
      const pending = PendingVisit(
        operationId: 'operation-1',
        stopId: 'stop-1',
        status: VisitStatus.delivered,
        reason: '',
        expectedVersion: 1,
      );
      await store.queueVisit(
        stop.withStatus(VisitStatus.delivered, ''),
        pending,
      );
      await store.replaceSnapshot([shop], [stop]);
      expect((await store.stops()).single.status, VisitStatus.delivered);
      expect((await store.pendingVisits()).single.operationId, 'operation-1');
      expect(() => store.queueVisit(stop, pending), throwsStateError);
      const acknowledged = DeliveryStop(
        id: 'stop-1',
        shopId: 'shop-1',
        date: '2026-10-13',
        driverId: 'driver-1',
        order: 1,
        status: VisitStatus.delivered,
        version: 2,
      );
      await store.acknowledgeVisit(pending, acknowledged);
      expect(await store.pendingVisits(), isEmpty);
      expect((await store.stops()).single.version, 2);
    },
  );

  test(
    'revoked shops disappear on refresh but pending results remain reviewable',
    () async {
      await store.saveShop(shop);
      await store.saveStop(stop);
      await store.replaceSnapshot([], []);
      expect(await store.shops(), isEmpty);
      expect(await store.stops(), isEmpty);
      await store.saveShop(shop);
      await store.saveStop(stop);
      await store.queueVisit(
        stop.withStatus(VisitStatus.failed, 'Closed'),
        const PendingVisit(
          operationId: 'operation-2',
          stopId: 'stop-1',
          status: VisitStatus.failed,
          reason: 'Closed',
          expectedVersion: 1,
        ),
      );
      await store.replaceSnapshot([], []);
      expect((await store.stops()).single.reason, 'Closed');
      expect((await store.shops()).single.id, 'shop-1');
    },
  );

  test(
    'controller refuses unverified coordinates and duplicate day assignments',
    () async {
      final controller = DeliveryController(
        store: store,
        photoDirectory: photos,
        accountId: 'local',
      );
      await controller.initialize();
      await controller.saveShop(
        const Shop(
          id: 'shop-1',
          name: 'Unverified',
          area: 'Test area',
          latitude: 12.34,
          longitude: 77.56,
        ),
      );
      expect(
        () => controller.addStop(
          controller.shops.single,
          DateTime(2026, 10, 13),
          'local-driver',
        ),
        throwsStateError,
      );
      await controller.saveShop(shop);
      await controller.addStop(shop, DateTime(2026, 10, 13), 'local-driver');
      expect(
        () => controller.addStop(shop, DateTime(2026, 10, 13), 'local-driver'),
        throwsStateError,
      );
      expect(
        () =>
            controller.recordVisit(controller.stops.single, VisitStatus.failed),
        throwsArgumentError,
      );
      controller.profile = const AppProfile(
        id: 'local-driver',
        name: 'Driver',
        role: UserRole.driver,
      );
      expect(() => controller.saveShop(shop), throwsStateError);
      controller.dispose();
    },
  );

  test(
    'Maps links persist and allow delivery without coordinates or verification',
    () async {
      final controller = DeliveryController(
        store: store,
        photoDirectory: photos,
        accountId: 'local',
      );
      await controller.initialize();
      const linked = Shop(
        id: 'link-shop',
        name: 'Maps Only Shop',
        area: 'Market',
        mapsUrl: 'https://maps.app.goo.gl/example',
      );
      await controller.saveShop(linked);
      final saved = (await store.shops()).single;
      expect(saved.hasCoordinates, isFalse);
      expect(saved.verified, isFalse);
      expect(saved.hasLocation, isTrue);
      expect(saved.readyForDelivery, isTrue);
      expect(saved.locationStatus, 'Ready for delivery');
      expect(saved.locationDescription, 'Google Maps location saved');
      expect(navigationUri(saved).toString(), linked.mapsUrl);
      expect(locationPreviewUri(saved).toString(), linked.mapsUrl);
      await controller.addStop(saved, DateTime(2026, 10, 15), 'local-driver');
      expect((await store.stops()).single.shopId, 'link-shop');
      controller.dispose();
    },
  );

  test(
    'untrusted links are not locations and do not mask invalid coordinates',
    () async {
      for (final link in [
        '',
        'some address',
        'https://evil.test/maps',
        'https://google.com.evil.test/maps',
        'https://www.google.com/search?q=shop',
      ]) {
        final invalid = Shop(
          id: 'invalid',
          name: 'Shop',
          area: 'Market',
          mapsUrl: link,
        );
        expect(invalid.hasLocation, isFalse);
        expect(invalid.readyForDelivery, isFalse);
        expect(() => navigationUri(invalid), throwsStateError);
      }
      final controller = DeliveryController(
        store: store,
        photoDirectory: photos,
        accountId: 'local',
      );
      await controller.initialize();
      expect(
        () => controller.saveShop(
          const Shop(
            id: 'invalid',
            name: 'Shop',
            area: 'Market',
            latitude: 91,
            longitude: 77,
            mapsUrl: 'https://maps.app.goo.gl/example',
          ),
        ),
        throwsArgumentError,
      );
      controller.dispose();
    },
  );

  test('navigation refuses missing, invalid and unverified coordinates', () {
    expect(validCoordinates(double.nan, 70), isFalse);
    expect(validCoordinates(91, 70), isFalse);
    expect(validCoordinates(12, double.infinity), isFalse);
    expect(
      () => navigationUri(const Shop(id: 'x', name: 'Shop', area: 'Area')),
      throwsStateError,
    );
    expect(
      () => navigationUri(
        const Shop(
          id: 'x',
          name: 'Shop',
          area: 'Area',
          latitude: 12,
          longitude: 70,
        ),
      ),
      throwsStateError,
    );
    final uri = navigationUri(shop);
    expect(uri.queryParameters['destination'], '12.34,77.56');
    expect(uri.queryParameters['dir_action'], 'navigate');
    expect(uri.queryParameters.containsKey('key'), isFalse);
  });
}

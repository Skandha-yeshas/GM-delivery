import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gm_delivery/application/delivery_controller.dart';
import 'package:gm_delivery/data/local_store.dart';
import 'package:gm_delivery/domain/maps_location.dart';
import 'package:gm_delivery/domain/models.dart';
import 'package:gm_delivery/domain/shop_import.dart';

Uint8List workbook(List<List<CellValue?>> rows) {
  final excel = Excel.createExcel();
  for (final row in rows) {
    excel[excel.getDefaultSheet()!].appendRow(row);
  }
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('Maps parsing uses a shop pin rather than the camera centre', () {
    final uri = googleMapsUri(
      'https://www.google.com/maps/place/Shop/@13.5,78.8,12z/data=!3d12.345!4d77.456',
    );
    final pin = pinFromMapsUri(uri)!;
    expect(pin.latitude, 12.345);
    expect(pin.longitude, 77.456);
    expect(
      pinFromMapsUri(
        googleMapsUri('https://www.google.com/maps/@13.5,78.8,12z'),
      ),
      isNull,
    );
    expect(
      pinFromMapsUri(googleMapsUri('https://maps.app.goo.gl/example')),
      isNull,
    );
    expect(
      pinFromMapsUri(
        googleMapsUri(
          'https://www.google.com/maps/search/?api=1&query=-12.3%2C77.5',
        ),
      )!.latitude,
      -12.3,
    );
    expect(
      pinFromMapsUri(googleMapsUri('https://maps.google.com/?q=91,77')),
      isNull,
    );
    for (final bad in [
      'https://google.com.evil.test/maps?q=12,77',
      'http://www.google.com/maps?q=12,77',
      'https://user:pass@www.google.com/maps?q=12,77',
      'https://www.google.com/search?q=12,77',
      'https://goo.gl/unrelated',
      'https://127.0.0.1/maps?q=12,77',
    ]) {
      expect(() => googleMapsUri(bad), throwsFormatException);
    }
  });

  test(
    'two-column Excel accepts blank, address, full and short Maps locations',
    () {
      final bytes = workbook([
        [TextCellValue('Name'), TextCellValue('Location')],
        [TextCellValue('Alpha')],
        [TextCellValue('Beta'), TextCellValue('Near City Market')],
        [
          TextCellValue('Gamma'),
          TextCellValue('https://maps.google.com/?q=12.3,77.5'),
        ],
        [
          TextCellValue('Delta'),
          TextCellValue('https://maps.app.goo.gl/example'),
        ],
        [null, TextCellValue('No name')],
      ]);
      final rows = parseShopWorkbook(bytes).single.rows;
      expect(rows, hasLength(5));
      expect(rows[0].shop!.area, 'Area not set');
      expect(rows[0].shop!.locationStatus, 'Needs location');
      expect(rows[1].shop!.address, 'Near City Market');
      expect(rows[2].shop!.locationStatus, 'Ready for delivery');
      expect(rows[2].shop!.readyForDelivery, isTrue);
      expect(rows[3].shop!.mapsUrl, contains('maps.app.goo.gl'));
      expect(rows[3].shop!.hasLocation, isTrue);
      expect(rows[3].shop!.hasCoordinates, isFalse);
      expect(rows[3].shop!.readyForDelivery, isTrue);
      expect(rows[4].error, contains('name is missing'));
      expect(rows[4].number, 6);
      expect(
        parseShopWorkbook(bytes).single.rows[0].shop!.id,
        rows[0].shop!.id,
      );
    },
  );

  test('invalid coordinates and formulas are reported per row', () {
    final rows = parseShopWorkbook(
      workbook([
        [
          TextCellValue('Shop Name'),
          TextCellValue('Latitude'),
          TextCellValue('Longitude'),
          TextCellValue('Phone'),
        ],
        [TextCellValue('Bad pin'), IntCellValue(95), IntCellValue(77)],
        [TextCellValue('Missing longitude'), DoubleCellValue(12.3)],
        [
          TextCellValue('Formula phone'),
          null,
          null,
          FormulaCellValue('123+456'),
        ],
        [TextCellValue('Good shop'), null, null, IntCellValue(9876543210)],
      ]),
    ).single.rows;
    expect(rows.take(3).every((r) => r.error != null), isTrue);
    expect(rows.last.shop!.phone, '9876543210');
    final duplicateHeader = parseShopWorkbook(
      workbook([
        [
          TextCellValue('Name'),
          TextCellValue('Location'),
          TextCellValue('Maps URL'),
        ],
      ]),
    ).single;
    expect(duplicateHeader.error, contains('More than one column'));
    expect(parseShopWorkbook(createShopImportTemplate()).single.rows, isEmpty);
    expect(
      () => parseShopWorkbook(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });

  test(
    '600-shop import preserves existing records and retries without duplicates',
    () async {
      final store = LocalStore(
        await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            onCreate: (db, _) => LocalStore.createSchema(db),
            version: 2,
          ),
        ),
      );
      final photos = await Directory.systemTemp.createTemp('gm_import_');
      final controller = DeliveryController(
        store: store,
        photoDirectory: photos,
        accountId: 'local',
      );
      try {
        await controller.initialize();
        await controller.saveShop(
          const Shop(
            id: 'existing',
            name: 'Shop 0',
            area: 'Area not set',
            notes: 'Keep owner notes',
          ),
        );
        final excel = workbook([
          [TextCellValue('Name'), TextCellValue('Location')],
          for (var i = 0; i < 600; i++) [TextCellValue('Shop $i')],
          [TextCellValue(' shop 1 ')],
        ]);
        final rows = parseShopWorkbook(excel).single.rows;
        final result = await controller.importShops(rows);
        expect(result.saved, 599);
        expect(result.skipped, 2);
        expect(result.failures, isEmpty);
        expect(controller.shops, hasLength(600));
        expect(controller.shopFor('existing')!.notes, 'Keep owner notes');
        final retried = await controller.importShops(rows);
        expect(retried.saved, 0);
        expect(retried.skipped, 601);
        expect(controller.shops.every((s) => !s.readyForDelivery), isTrue);
        controller.profile = const AppProfile(
          id: 'driver',
          name: 'Driver',
          role: UserRole.driver,
        );
        await expectLater(controller.importShops(rows), throwsStateError);
      } finally {
        controller.dispose();
        await store.close();
        await photos.delete(recursive: true);
      }
    },
  );

  test(
    'local database upgrade preserves old shops and stores Maps links',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      try {
        await db.execute(
          'CREATE TABLE shops (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
        );
        await db.insert('shops', {'id': 'old', 'name': 'Existing shop'});
        await LocalStore.upgradeSchema(db, 1, 2);
        expect((await db.query('shops')).single['maps_url'], '');
        await db.update('shops', {
          'maps_url': 'https://maps.google.com/?q=12,77',
        });
        expect((await db.query('shops')).single['name'], 'Existing shop');
        expect(
          (await db.query('shops')).single['maps_url'],
          contains('q=12,77'),
        );
      } finally {
        await db.close();
      }
    },
  );
}

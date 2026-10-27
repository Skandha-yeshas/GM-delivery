import 'dart:typed_data';
import 'dart:convert';
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';
import 'maps_location.dart';
import 'models.dart';
import 'ledger.dart';

String shopImportKey(Shop shop) {
  String normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return jsonEncode(
    [shop.name, shop.area, shop.address].map(normalize).toList(),
  );
}

class ShopImportRow {
  const ShopImportRow(
    this.number,
    this.name, {
    this.shop,
    this.error,
    this.openingBalancePaise,
  });
  final int number;
  final String name;
  final Shop? shop;
  final String? error;
  final int? openingBalancePaise;
}

class ShopImportSheet {
  const ShopImportSheet(this.name, this.rows, {this.error});
  final String name;
  final List<ShopImportRow> rows;
  final String? error;
}

const _headerAliases = {
  'name': 'name',
  'shopname': 'name',
  'shop': 'name',
  'location': 'location',
  'mapsurl': 'location',
  'googlemapslink': 'location',
  'googlemapsurl': 'location',
  'maplink': 'location',
  'mapslink': 'location',
  'area': 'area',
  'locality': 'area',
  'address': 'address',
  'shopaddress': 'address',
  'phone': 'phone',
  'contact': 'phone',
  'contactnumber': 'phone',
  'mobile': 'phone',
  'contactperson': 'contact_name',
  'proprietor': 'contact_name',
  'contactname': 'contact_name',
  'pincode': 'postal_code',
  'postalcode': 'postal_code',
  'landmark': 'landmark',
  'notes': 'notes',
  'deliveryinstructions': 'notes',
  'latitude': 'latitude',
  'lat': 'latitude',
  'longitude': 'longitude',
  'lng': 'longitude',
  'openingbalance': 'opening',
};

String _cell(Data? cell) => switch (cell?.value) {
  null => '',
  TextCellValue value => value.value.toString().trim(),
  IntCellValue value => value.value.toString(),
  DoubleCellValue value =>
    value.value == value.value.roundToDouble()
        ? value.value.toInt().toString()
        : value.value.toString(),
  FormulaCellValue() => throw const FormatException(
    'Use plain values instead of formulas.',
  ),
  _ => throw const FormatException(
    'Use text or numbers instead of date/boolean cells.',
  ),
};

/// Runs in a worker isolate. Import is append-only: no existing shop is edited.
List<ShopImportSheet> parseShopWorkbook(Uint8List bytes) {
  if (bytes.length > 5 * 1024 * 1024) {
    throw const FormatException('Choose an .xlsx file smaller than 5 MB.');
  }
  final Excel workbook;
  try {
    workbook = Excel.decodeBytes(bytes);
  } catch (_) {
    throw const FormatException(
      'Could not read this workbook. Save it as an unencrypted .xlsx file.',
    );
  }
  final sheets = <ShopImportSheet>[];
  for (final table in workbook.tables.values) {
    final allRows = table.rows;
    final headerIndex = allRows.indexWhere(
      (r) => r.any((c) => c?.value != null),
    );
    if (headerIndex < 0) continue;
    final columns = <String, int>{};
    try {
      for (var i = 0; i < allRows[headerIndex].length; i++) {
        final header = _cell(
          allRows[headerIndex][i],
        ).toLowerCase().replaceAll(RegExp('[^a-z]'), '');
        final key = _headerAliases[header];
        if (key == null) continue;
        if (columns.containsKey(key)) {
          throw FormatException(
            'More than one column maps to $key. Rename the extra column.',
          );
        }
        columns[key] = i;
      }
      if (!columns.containsKey('name')) {
        throw const FormatException(
          'The first nonempty row must contain a Name column.',
        );
      }
    } on FormatException catch (error) {
      sheets.add(
        ShopImportSheet(table.sheetName, const [], error: error.message),
      );
      continue;
    }
    final result = <ShopImportRow>[];
    for (var i = headerIndex + 1; i < allRows.length; i++) {
      final cells = allRows[i];
      if (!cells.any(
        (c) => c?.value != null && c!.value.toString().trim().isNotEmpty,
      )) {
        continue;
      }
      if (result.length == 5000) {
        throw const FormatException(
          'Import at most 5,000 nonempty rows per worksheet.',
        );
      }
      var name = '';
      try {
        String read(String key) {
          final column = columns[key];
          return column == null || column >= cells.length
              ? ''
              : _cell(cells[column]);
        }

        name = read('name');
        if (name.isEmpty) throw const FormatException('Shop name is missing.');
        final area = read('area').isEmpty ? 'Area not set' : read('area');
        var address = read('address');
        var mapsUrl = '';
        MapPin? pin;
        final location = read('location');
        if (location.isNotEmpty) {
          if (RegExp(
            r'^(https?://|www\.|maps\.)',
            caseSensitive: false,
          ).hasMatch(location)) {
            final uri = googleMapsUri(location);
            mapsUrl = uri.toString();
            pin = pinFromMapsUri(uri);
          } else if (address.isEmpty) {
            address = location;
          } else if (location != address) {
            throw const FormatException(
              'Location must be a Maps link when Address is also filled.',
            );
          }
        }
        final lat = read('latitude'), lng = read('longitude');
        if (lat.isNotEmpty || lng.isNotEmpty) {
          final latitude = double.tryParse(lat),
              longitude = double.tryParse(lng);
          if (!validCoordinates(latitude, longitude)) {
            throw const FormatException(
              'Latitude and longitude must both be valid numbers.',
            );
          }
          if (pin != null &&
              ((pin.latitude - latitude!).abs() > 0.00001 ||
                  (pin.longitude - longitude!).abs() > 0.00001)) {
            throw const FormatException(
              'Coordinates disagree with the Maps pin. Review this row.',
            );
          }
          pin = MapPin(latitude!, longitude!);
        }
        final phone = read('phone'),
            landmark = read('landmark'),
            notes = read('notes');
        final opening = read('opening');
        final contactName = read('contact_name'),
            postalCode = read('postal_code');
        if (postalCode.isNotEmpty &&
            !RegExp(r'^[1-9][0-9]{5}$').hasMatch(postalCode)) {
          throw const FormatException(
            'PIN code must contain six digits and start with 1–9.',
          );
        }
        final openingPaise = opening.isEmpty ? null : parsePaise(opening);
        for (final field in [
          (name, 200, 'Name'),
          (area, 200, 'Area'),
          (address, 1000, 'Address'),
          (phone, 30, 'Phone'),
          (contactName, 200, 'Contact person'),
          (landmark, 500, 'Landmark'),
          (notes, 1000, 'Delivery instructions'),
        ]) {
          if (field.$1.length > field.$2) {
            throw FormatException(
              '${field.$3} exceeds ${field.$2} characters.',
            );
          }
        }
        final draft = Shop(id: '', name: name, area: area, address: address);
        // Stable IDs make retries and imports on two owner phones non-destructive.
        final id = const Uuid().v5(
          '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
          'gm-enterprises-import:${shopImportKey(draft)}',
        );
        result.add(
          ShopImportRow(
            i + 1,
            name,
            openingBalancePaise: openingPaise,
            shop: Shop(
              id: id,
              name: name,
              area: area,
              address: address,
              phone: phone,
              contactName: contactName,
              postalCode: postalCode,
              landmark: landmark,
              notes: notes,
              mapsUrl: mapsUrl,
              latitude: pin?.latitude,
              longitude: pin?.longitude,
            ),
          ),
        );
      } on FormatException catch (error) {
        result.add(ShopImportRow(i + 1, name, error: error.message));
      }
    }
    sheets.add(ShopImportSheet(table.sheetName, result));
  }
  if (sheets.isEmpty) {
    throw const FormatException(
      'This workbook has no data. Add Name and Location headers.',
    );
  }
  return sheets;
}

Uint8List createShopImportTemplate() {
  final workbook = Excel.createExcel();
  final sheet = workbook[workbook.getDefaultSheet()!];
  sheet.appendRow([TextCellValue('Name'), TextCellValue('Location')]);
  sheet.setColumnWidth(0, 32);
  sheet.setColumnWidth(1, 80);
  return Uint8List.fromList(workbook.encode()!);
}

class ShopImportResult {
  const ShopImportResult(this.saved, this.skipped, this.failures);
  final int saved, skipped;
  final Map<int, String> failures;
}

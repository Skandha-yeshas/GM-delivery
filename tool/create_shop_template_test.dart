import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gm_delivery/domain/shop_import.dart';

void main() {
  test('generate the owner Excel template', () {
    final file = File('docs/templates/GM_Shops_Template.xlsx');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(createShopImportTemplate());
    expect(parseShopWorkbook(file.readAsBytesSync()).single.rows, isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:gm_delivery/domain/bill_shop_matcher.dart';
import 'package:gm_delivery/domain/models.dart';

void main() {
  test('a whole bill returns only its customer shop name', () {
    const text =
        'G.M. ENTERPRISES\nTAX INVOICE\nGSTIN: 29ABCDE1234F1Z5\n'
        'Buyer (Bill to): Omega Paper House\n18 Main Road\nCity Market\n'
        'Description Qty Rate\nBall Pen 10 50\nGrand Total 500';
    expect(extractShopNames(text), ['Omega Paper House']);
  });

  test('customer label on its own supports a wrapped name', () {
    expect(
      extractShopNames(
        'G.M. Enterprises\nBill To:\nPrakash\nStationery\n12 Main Road\nTotal 700',
      ),
      ['Prakash Stationery'],
    );
    expect(extractShopNames('ALPHA STATIONERY'), ['ALPHA STATIONERY']);
    expect(
      extractShopNames('Tax Invoice\nGSTIN: 29ABCDE1234F1Z5\nGrand Total: 800'),
      isEmpty,
    );
  });
  const alpha = Shop(
    id: 'a',
    name: 'Alpha Stationery',
    area: 'City Market',
    address: '18 Mango Street',
    latitude: 12.3,
    longitude: 77.5,
    verified: true,
  );
  const beta = Shop(id: 'b', name: 'Beta Stores', area: 'North');
  const own = Shop(id: 'supplier', name: 'G.M. Enterprises', area: 'South');

  test(
    'reads a buyer section and returns the directory GPS without guessing',
    () {
      final matches = matchBillShops(
        'G.M. ENTERPRISES\nTax invoice 2345\nBill To:\nALPHA STATIONERY\nCity Market\n18 Mango Street\nQty Pen Total',
        [own, beta, alpha],
      );
      expect(matches.first.shop.id, 'a');
      expect(matches.first.recipient, isTrue);
      expect(matches.first.addressMatch, isTrue);
      expect(matches.first.shop.latitude, 12.3);
      expect(matches.any((m) => m.shop.id == 'supplier'), isFalse);
    },
  );

  test('OCR typo and split shop name still suggest a saved shop', () {
    const shop = Shop(id: 'p', name: 'Prakash Stationery', area: 'West');
    final matches = matchBillShops(
      'Billed To\nPraksh\nStationery\nInvoice No 10',
      [shop],
    );
    expect(matches.single.shop.id, 'p');
    expect(matches.single.shop.hasLocation, isFalse);
  });

  test('generic item words do not identify a customer', () {
    const shop = Shop(id: 'generic', name: 'General Stationery', area: 'West');
    expect(
      matchBillShops('Tax invoice\nGeneral stationery\nPen 20\nTotal 500', [
        shop,
      ]),
      isEmpty,
    );
    expect(matchBillShops('', [alpha, beta]), isEmpty);
    expect(
      matchBillShops('An unrelated unknown customer', [alpha, beta]),
      isEmpty,
    );
  });

  test('same-name branches remain separate choices with address evidence', () {
    const other = Shop(
      id: 'other',
      name: 'Alpha Stationery',
      area: 'North Town',
      address: 'West Arcade',
    );
    final matches = matchBillShops(
      'Bill To: Alpha Stationery\nCity Market\n18 Mango Street',
      [other, alpha],
    );
    expect(matches, hasLength(2));
    expect(matches.first.shop.id, 'a');
    expect(matches.last.shop.id, 'other');
  });

  test('600-shop directory ranks the intended shop without losing its ID', () {
    final shops = [
      for (var i = 0; i < 600; i++)
        Shop(id: '$i', name: 'Merchant $i Stationery', area: 'West'),
    ];
    final matches = matchBillShops(
      'Bill To\nMerchant 567 Stationery\nInvoice 2026',
      shops,
    );
    expect(matches.first.shop.id, '567');
    expect(matches.length, lessThanOrEqualTo(12));
  });
}

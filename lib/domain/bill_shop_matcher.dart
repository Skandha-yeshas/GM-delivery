import 'dart:math' as math;
import 'models.dart';

class BillShopMatch {
  const BillShopMatch(this.shop, this.score, this.recipient, this.addressMatch);
  final Shop shop;
  final double score;
  final bool recipient, addressMatch;
  String get reason => [
    recipient ? 'Shop name near customer details' : 'Shop name in bill text',
    if (addressMatch) 'area or address also matches',
  ].join(' • ');
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll('&', ' and ')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

String normalizeShopName(String value) =>
    _normalize(value).replaceFirst(RegExp(r'^(?:m s|ms)\s+'), '');

/// Reads a customer-name field, not a full invoice summary. Keep the original
/// spelling for owner review; never substitute an existing shop's fuzzy name.
List<String> extractShopNames(String text) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .take(200)
      .toList();
  final label = RegExp(
    r'^(?:(?:buyer|customer|party|consignee)(?:\s*\([^)]*\))?(?:\s+name)?|bill(?:ed)?\s*to|ship\s*to|sold\s*to)\s*[:\-]?\s*(.*)$',
    caseSensitive: false,
  );
  final business = RegExp(
    r'\b(stationery|stationers|stores?|books?|bookshop|house|enterprises|traders|mart|agencies|agency|shop|corner)\b',
    caseSensitive: false,
  );
  String clean(String value) => value
      .replaceFirst(RegExp(r'^m\s*/?\s*s\.?\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  bool valid(String value) {
    final name = normalizeShopName(value);
    if (value.length > 200 ||
        name.replaceAll(RegExp('[^a-z]'), '').length < 3) {
      return false;
    }
    if (RegExp(r'^(?:g m|gm) enterprises\b').hasMatch(name)) return false;
    if (RegExp(
      r'^(?:tax invoice|invoice|retail invoice|bill no|bill number|gst|gstin|date|phone|mobile|tel|contact|email|www|https|description|item|qty|quantity|rate|amount|total|grand total|bank|account|ifsc|cash|credit|delivery|customer|bill to|buyer)\b',
    ).hasMatch(name)) {
      return false;
    }
    if (RegExp(
      r'^(?:no\b|near\b|opp\b|opposite\b|address\b|\d+[ /,\-])',
    ).hasMatch(name)) {
      return false;
    }
    if (!business.hasMatch(value) &&
        RegExp(
          r'\b(?:road|street|nagar|layout|pincode|pin code|cross|avenue)\b',
        ).hasMatch(name)) {
      return false;
    }
    if (RegExp(r'\d{5,}|[@₹$=]').hasMatch(value)) return false;
    return !(name.split(' ').length == 1 && _generic.contains(name));
  }

  String at(int i) {
    var value = clean(lines[i]);
    if (i + 1 < lines.length &&
        !business.hasMatch(value) &&
        RegExp(
          r'^(?:stationery|stationers|stores?|book house|enterprises|traders|mart|agencies|agency|shop)$',
          caseSensitive: false,
        ).hasMatch(lines[i + 1])) {
      value = '$value ${lines[i + 1]}';
    }
    return value;
  }

  final names = <String>[];
  void add(String name) {
    if (valid(name) &&
        !names.any((n) => normalizeShopName(n) == normalizeShopName(name))) {
      names.add(name);
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final match = label.firstMatch(lines[i]);
    if (match == null) continue;
    final inline = clean(match[1] ?? '');
    if (valid(inline)) {
      add(inline);
      continue;
    }
    for (var j = i + 1; j < lines.length && j <= i + 3; j++) {
      final candidate = at(j);
      if (valid(candidate)) {
        add(candidate);
        break;
      }
    }
  }
  if (names.isNotEmpty) return names.take(4).toList();
  final candidates = [
    for (var i = 0; i < lines.length; i++) at(i),
  ].where(valid).toList();
  for (final candidate in candidates.where(business.hasMatch)) {
    add(candidate);
  }
  if (names.isEmpty && candidates.isNotEmpty) add(candidates.first);
  return names.take(4).toList();
}

const _generic = {
  'the',
  'and',
  'm',
  's',
  'ms',
  'shop',
  'shops',
  'store',
  'stores',
  'general',
  'stationery',
  'stationary',
  'stationers',
  'enterprises',
  'traders',
  'limited',
  'ltd',
  'pvt',
  'proprietor',
};

double _similarity(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  if ((a.length - b.length).abs() > math.max(a.length, b.length) * .4) return 0;
  var previous = List.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      current[j] = math.min(
        math.min(current[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      );
    }
    previous = current;
  }
  return 1 - previous.last / math.max(a.length, b.length);
}

/// Deterministic suggestions, never an automatic customer selection. Recipient
/// labels outrank a supplier header; generic invoice words alone are insufficient.
List<BillShopMatch> matchBillShops(String text, List<Shop> shops) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map(_normalize)
      .where((line) => line.isNotEmpty)
      .take(250)
      .toList();
  final segments = <({String text, List<String> words, bool recipient})>[];
  var recipientUntil = -1;
  for (var i = 0; i < lines.length; i++) {
    if (RegExp(
      r'\b(bill to|billed to|ship to|sold to|customer|party|consignee|buyer)\b',
    ).hasMatch(lines[i])) {
      recipientUntil = i + 4;
    }
    for (var width = 1; width <= 2 && i + width <= lines.length; width++) {
      final segment = lines.sublist(i, i + width).join(' ');
      if (segment.length <= 220) {
        segments.add((
          text: segment,
          words: segment.split(' '),
          recipient: i <= recipientUntil,
        ));
      }
    }
  }
  final allText = ' ${lines.join(' ')} ';
  final matches = <BillShopMatch>[];
  for (final shop in shops) {
    final name = _normalize(shop.name);
    if (name.isEmpty || name == 'g m enterprises' || name == 'gm enterprises') {
      continue;
    }
    final tokens = name.split(' ').where((t) => t.length > 1).toSet();
    final distinctive = tokens.where((t) => !_generic.contains(t)).toList();
    double best = 0;
    var recipient = false;
    for (final segment in segments) {
      final words = segment.words;
      final exact = ' ${segment.text} '.contains(' $name ');
      var score = 0.0;
      if (exact) {
        score = .86;
      } else if (distinctive.isNotEmpty) {
        var matched = 0.0;
        for (final token in distinctive) {
          var closest = 0.0;
          for (final word in words) {
            final similarity = _similarity(token, word);
            if (similarity > closest) closest = similarity;
          }
          matched += closest >= .75 ? closest : 0;
        }
        final coverage = matched / distinctive.length;
        if (coverage >= .7) score = .68 * coverage;
      }
      // A name made only of generic words is credible only in a buyer section.
      if (distinctive.isEmpty && !segment.recipient) score = 0;
      if (score > 0 && segment.recipient) score += .12;
      if (score > best) {
        best = score;
        recipient = segment.recipient;
      }
    }
    if (best < .5) continue;
    final area = _normalize(shop.area);
    final addressTokens = _normalize(shop.address)
        .split(' ')
        .where((t) => t.length >= 4 && !{'road', 'main', 'near'}.contains(t))
        .toSet();
    final addressMatch =
        (area.length >= 3 &&
            area != 'area not set' &&
            allText.contains(' $area ')) ||
        (addressTokens.length >= 2 &&
            addressTokens.where((t) => allText.contains(' $t ')).length >= 2);
    if (addressMatch) best += .05;
    matches.add(BillShopMatch(shop, best.clamp(0, 1), recipient, addressMatch));
  }
  matches.sort((a, b) {
    final score = b.score.compareTo(a.score);
    return score != 0
        ? score
        : '${a.shop.name} ${a.shop.area}'.compareTo(
            '${b.shop.name} ${b.shop.area}',
          );
  });
  return matches.take(12).toList();
}

List<BillShopMatch> matchBillShopRequest((String, List<Shop>) input) =>
    matchBillShops(input.$1, input.$2);

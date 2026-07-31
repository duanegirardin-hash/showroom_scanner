import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/pricing_math.dart';

/// Import-path checks: CSV text → parse → Product.price semantics (no round).
double _parsePriceLikeApp(String value) {
  final cleaned = value.replaceAll('\$', '').replaceAll(',', '').trim();
  return double.tryParse(cleaned) ?? 0.0;
}

List<String> _parseCsvLine(String line) {
  final cols = <String>[];
  final sb = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
      continue;
    }
    if (ch == ',' && !inQuotes) {
      cols.add(sb.toString());
      sb.clear();
      continue;
    }
    sb.write(ch);
  }
  cols.add(sb.toString());
  return cols;
}

/// Minimal CSV field extract for a known item (avoids typed numeric item keys).
String? _priceCellForItem(String rawCsv, String itemNumber) {
  for (final line in rawCsv.split(RegExp(r'\r?\n'))) {
    if (line.startsWith('$itemNumber,') || line.startsWith('"$itemNumber",')) {
      final cols = _parseCsvLine(line);
      if (cols.length > 4) return cols[4];
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parser retains 0.585 from CSV cell', () {
    expect(_parsePriceLikeApp('\$0.585'), 0.585);
    expect(_parsePriceLikeApp('0.585'), 0.585);
    expect(_parsePriceLikeApp('\$0.585') == 0.59, isFalse);
  });

  test('bundled products.csv preserves high-precision 46314', () async {
    final raw = await rootBundle.loadString('assets/data/products.csv');
    final priceRaw = _priceCellForItem(raw, '46314');
    expect(priceRaw, isNotNull);
    expect(_parsePriceLikeApp(priceRaw!), 0.585);

    var highCount = 0;
    for (final line in raw.split(RegExp(r'\r?\n')).skip(1)) {
      if (line.trim().isEmpty) continue;
      final cols = _parseCsvLine(line);
      if (cols.length <= 4) continue;
      final price = _parsePriceLikeApp(cols[4]);
      final t = price
          .toStringAsFixed(12)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
      final mp = t.contains('.') ? t.split('.')[1].length : 0;
      if (mp > 2) highCount++;
    }
    expect(highCount, greaterThanOrEqualTo(850));
  });

  test('01514 remains 1.62 in assets and Method A total 31.20', () async {
    final raw = await rootBundle.loadString('assets/data/products.csv');
    final priceRaw = _priceCellForItem(raw, '01514');
    expect(priceRaw, isNotNull, reason: '01514 must exist in assets catalog');
    expect(_parsePriceLikeApp(priceRaw!), 1.62);
    expect(
      lineTotalForPay(shelfPrice: 1.62, discountPercent: 20, qty: 24),
      31.20,
    );
  });

  test('production main.dart remains connected to precision-safe pay math', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains("import 'pricing_math.dart' as pricing;"));
    expect(
      RegExp(r'_lineTotalFromRoundedUnitPrice\(').allMatches(source).length,
      0,
      reason:
          'Production pay/total paths must not use the old rounded-unit helper.',
    );
    expect(
      source,
      contains(
        'double _getRegularLineTotal(OrderLine line) => _lineTotalForPay(',
      ),
    );
    expect(
      source,
      contains(
        'double _getDiscountedLineTotal(OrderLine line) => _lineTotalForPay(',
      ),
    );
    expect(
      RegExp(r'sum \+= _lineTotalForPay\(').allMatches(source).length,
      1,
      reason:
          'Persisted/archive quote totals must use Emun-aligned pay math.',
    );
    expect(
      RegExp(r'lineTotal: _lineTotalForPay\(').allMatches(source).length,
      1,
      reason: 'CSV/XLSX/email attachment totals must use Emun-aligned math.',
    );
    expect(
      RegExp(r'final linePay = _lineTotalForPay\(').allMatches(source).length,
      1,
      reason: 'Text quote totals must use Emun-aligned math.',
    );

    // Protect the c92a912 workflows from accidental replacement while pricing
    // wiring is edited.
    expect(source, contains("_sectionHeader('Recently Deleted')"));
    expect(source, contains('persistCsvCopies: true'));
    expect(source, contains('archiveActiveQuotesAfterShare: true'));
    expect(source, contains('Email Current Quote Only\\n(moves to Archive)'));
  });
}

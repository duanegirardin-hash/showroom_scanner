import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/pricing_math.dart';

void main() {
  group('pricing_math — display', () {
    test('46314 displays as 0.59', () {
      expect(roundedUnitPrice(0.585), 0.59);
    });

    test('two-decimal shelf unchanged when displayed', () {
      expect(roundedUnitPrice(5.00), 5.00);
      expect(roundedUnitPrice(0.90), 0.90);
    });
  });

  group('pricing_math — direct price (PS/NET/shelf)', () {
    test('1.125 × 8 uses full unit precision and totals 9.00', () {
      expect(
        lineTotalForPay(shelfPrice: 1.125, discountPercent: 0, qty: 8),
        9.00,
      );
      expect(lineTotalRoundUnitThenQty(rawUnitPrice: 1.125, qty: 8), 9.04);
    });

    test('1.125 × 3 retains raw 3.375 before final cent rounding', () {
      const unit = 1.125;
      const qty = 3;
      expect(unit * qty, 3.375);
      expect(
        lineTotalForPay(shelfPrice: unit, discountPercent: 0, qty: qty),
        3.38,
      );
    });

    test('4.6875 × 16 totals 75.00 without unit rounding', () {
      expect(
        lineTotalForPay(shelfPrice: 4.6875, discountPercent: 0, qty: 16),
        75.00,
      );
      expect(lineTotalRoundUnitThenQty(rawUnitPrice: 4.6875, qty: 16), 75.04);
    });

    test('0.833333 retains fractional precision across quantity', () {
      const unit = 0.833333;
      const qty = 6;
      expect(unit * qty, closeTo(4.999998, 1e-12));
      expect(
        lineTotalForPay(shelfPrice: unit, discountPercent: 0, qty: qty),
        5.00,
      );
    });

    test('46314 qty 12 → 7.02 (not 7.08)', () {
      final total = lineTotalForPay(
        shelfPrice: 0.585,
        discountPercent: 0,
        qty: 12,
      );
      expect(total, 7.02);
      // Old wrong path (unit-round first):
      expect(lineTotalRoundUnitThenQty(rawUnitPrice: 0.585, qty: 12), 7.08);
      // Delta old→new is exactly $0.06 (matches reported Scanner−EMUN gap)
      expect(
        lineTotalRoundUnitThenQty(rawUnitPrice: 0.585, qty: 12) - total,
        closeTo(0.06, 1e-9),
      );
    });

    test('11406 qty 12 → round¢(0.992×12)=11.90', () {
      expect(
        lineTotalForPay(shelfPrice: 0.992, discountPercent: 0, qty: 12),
        11.90,
      );
      expect(roundedUnitPrice(0.992), 0.99);
    });

    test('S612CA-CD qty 12 → 37.50', () {
      expect(
        lineTotalForPay(shelfPrice: 3.125, discountPercent: 0, qty: 12),
        37.50,
      );
      expect(roundedUnitPrice(3.125), 3.13);
    });

    test('two-decimal PS unchanged vs Method A', () {
      const price = 5.00;
      const qty = 12;
      final direct = lineTotalForPay(
        shelfPrice: price,
        discountPercent: 0,
        qty: qty,
      );
      final methodA = lineTotalRoundUnitThenQty(rawUnitPrice: price, qty: qty);
      expect(direct, methodA);
      expect(direct, 60.00);
    });

    test('two-decimal NET unchanged vs Method A', () {
      const price = 0.90;
      const qty = 24;
      final direct = lineTotalForPay(
        shelfPrice: price,
        discountPercent: 0,
        qty: qty,
      );
      final methodA = lineTotalRoundUnitThenQty(rawUnitPrice: price, qty: qty);
      expect(direct, methodA);
      expect(direct, 21.60);
    });

    test('three-decimal PS uses full precision', () {
      expect(
        lineTotalForPay(shelfPrice: 0.585, discountPercent: 0, qty: 12),
        isNot(lineTotalRoundUnitThenQty(rawUnitPrice: 0.585, qty: 12)),
      );
    });

    test('three-decimal NET uses full precision', () {
      // Synthetic NET-style shelf price (analysis: 2 NET high-precision SKUs).
      const price = 1.255;
      const qty = 8;
      expect(
        lineTotalForPay(shelfPrice: price, discountPercent: 0, qty: qty),
        roundMoney(price * qty),
      );
      expect(
        lineTotalForPay(shelfPrice: price, discountPercent: 0, qty: qty),
        isNot(lineTotalRoundUnitThenQty(rawUnitPrice: price, qty: qty)),
      );
    });

    test('four-decimal direct uses full precision', () {
      const price = 3.8528;
      const qty = 12;
      expect(
        lineTotalForPay(shelfPrice: price, discountPercent: 0, qty: qty),
        roundMoney(price * qty),
      );
      expect(roundedUnitPrice(price), 3.85);
    });
  });

  group('pricing_math — percentage discount Method A', () {
    test('01514 @ 20% qty 24 → unit 1.30 line 31.20', () {
      const shelf = 1.62;
      const pct = 20.0;
      const qty = 24;
      final raw = shelf * (1 - pct / 100.0);
      expect(raw, closeTo(1.296, 1e-9));
      expect(roundedUnitPrice(raw), 1.30);
      expect(
        lineTotalForPay(shelfPrice: shelf, discountPercent: pct, qty: qty),
        31.20,
      );
      // Must NOT use full-precision extend of raw 1.296×24 (=31.104→31.10)
      expect(roundMoney(raw * qty), 31.10);
    });

    test('discount-eligible with 0% uses direct full-unit path', () {
      expect(
        lineTotalForPay(shelfPrice: 0.585, discountPercent: 0, qty: 12),
        7.02,
      );
    });
  });

  group('pricing_math — normal 2dp products unchanged', () {
    test('2dp discount line identical to historical Method A', () {
      const shelf = 2.35;
      const pct = 20.0;
      const qty = 12;
      final raw = shelf * (1 - pct / 100.0);
      expect(
        lineTotalForPay(shelfPrice: shelf, discountPercent: pct, qty: qty),
        lineTotalRoundUnitThenQty(rawUnitPrice: raw, qty: qty),
      );
    });

    test('2dp direct identical to historical Method A', () {
      const shelf = 3.05;
      const qty = 36;
      expect(
        lineTotalForPay(shelfPrice: shelf, discountPercent: 0, qty: qty),
        lineTotalRoundUnitThenQty(rawUnitPrice: shelf, qty: qty),
      );
    });
  });

  group('pricing_math — persistence and quantity regression', () {
    test('JSON round-trip retains a high-precision saved price', () {
      final encoded = jsonEncode({
        'lines': [
          {'price': 4.6875, 'quantity': 16, 'scans': 3},
        ],
      });
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final line = (decoded['lines'] as List).single as Map<String, dynamic>;
      final price = (line['price'] as num).toDouble();
      final quantity = (line['quantity'] as num).toInt();

      expect(price, 4.6875);
      expect(
        lineTotalForPay(shelfPrice: price, discountPercent: 0, qty: quantity),
        75.00,
      );
    });

    test('quantity increase and decrease never alter stored unit price', () {
      const price = 1.125;
      expect(
        lineTotalForPay(shelfPrice: price, discountPercent: 0, qty: 7),
        7.88,
      );
      expect(
        lineTotalForPay(shelfPrice: price, discountPercent: 0, qty: 8),
        9.00,
      );
      expect(
        lineTotalForPay(shelfPrice: price, discountPercent: 0, qty: 7),
        7.88,
      );
      expect(price, 1.125);
    });

    test('mixed subtotal sums full-precision and ordinary line totals', () {
      final highPrecision = lineTotalForPay(
        shelfPrice: 1.125,
        discountPercent: 0,
        qty: 8,
      );
      final ordinary = lineTotalForPay(
        shelfPrice: 2.35,
        discountPercent: 0,
        qty: 4,
      );

      expect(roundMoney(highPrecision + ordinary), 18.40);
    });
  });

  group(r'paired-quote $0.06 gap class', () {
    test('46314×12 alone explains Scanner 12421.92 vs EMUN 12421.86', () {
      const previousScanner = 12421.92;
      const emun = 12421.86;
      final oldLine = lineTotalRoundUnitThenQty(rawUnitPrice: 0.585, qty: 12);
      final newLine = lineTotalForPay(
        shelfPrice: 0.585,
        discountPercent: 0,
        qty: 12,
      );
      expect(oldLine - newLine, closeTo(previousScanner - emun, 1e-9));
      expect(previousScanner - (oldLine - newLine), closeTo(emun, 1e-9));
    });
  });
}

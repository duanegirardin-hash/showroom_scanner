import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/pricing_math.dart';

void main() {
  group('pricing_math — display', () {
    test('46314 displays as 0.59', () {
      expect(roundedUnitPrice(0.585), 0.59);
    });

    test('S612CA-CD displays as 3.13', () {
      expect(roundedUnitPrice(3.125), 3.13);
    });

    test('two-decimal shelf unchanged when displayed', () {
      expect(roundedUnitPrice(5.00), 5.00);
      expect(roundedUnitPrice(0.90), 0.90);
    });
  });

  group('pricing_math — direct / 0% discount (EMUN unit-round first)', () {
    test('S612CA-CD 3.125 × 36 = 112.68', () {
      expect(roundedUnitPrice(3.125), 3.13);
      expect(
        lineTotalForPay(shelfPrice: 3.125, discountPercent: 0, qty: 36),
        112.68,
      );
      // Old incorrect full-precision path:
      expect(lineTotalFullUnitThenRound(unitPrice: 3.125, qty: 36), 112.50);
    });

    test('GC473517 0.625 × 96 = 60.48', () {
      expect(
        lineTotalForPay(shelfPrice: 0.625, discountPercent: 0, qty: 96),
        60.48,
      );
    });

    test('GC477311 0.375 × 72 = 27.36', () {
      expect(
        lineTotalForPay(shelfPrice: 0.375, discountPercent: 0, qty: 72),
        27.36,
      );
    });

    test('59521 0.864 × 72 = 61.92', () {
      expect(
        lineTotalForPay(shelfPrice: 0.864, discountPercent: 0, qty: 72),
        61.92,
      );
    });

    test('1.125 × 8 totals 9.04 (unit-round then × qty)', () {
      expect(roundedUnitPrice(1.125), 1.13);
      expect(
        lineTotalForPay(shelfPrice: 1.125, discountPercent: 0, qty: 8),
        9.04,
      );
      expect(lineTotalFullUnitThenRound(unitPrice: 1.125, qty: 8), 9.00);
    });

    test('46314 qty 12 → 7.08 (not full-precision 7.02)', () {
      final total = lineTotalForPay(
        shelfPrice: 0.585,
        discountPercent: 0,
        qty: 12,
      );
      expect(total, 7.08);
      expect(lineTotalFullUnitThenRound(unitPrice: 0.585, qty: 12), 7.02);
    });

    test('11406 qty 12 → 0.99×12 = 11.88', () {
      expect(roundedUnitPrice(0.992), 0.99);
      expect(
        lineTotalForPay(shelfPrice: 0.992, discountPercent: 0, qty: 12),
        11.88,
      );
    });

    test('S612CA-CD qty 12 → 3.13×12 = 37.56', () {
      expect(
        lineTotalForPay(shelfPrice: 3.125, discountPercent: 0, qty: 12),
        37.56,
      );
    });

    test('two-decimal PS unchanged vs Method A unit path', () {
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

    test('two-decimal NET unchanged vs Method A unit path', () {
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

    test('three-decimal PS uses display-rounded unit', () {
      expect(
        lineTotalForPay(shelfPrice: 0.585, discountPercent: 0, qty: 12),
        lineTotalRoundUnitThenQty(rawUnitPrice: 0.585, qty: 12),
      );
    });

    test('three-decimal NET uses display-rounded unit', () {
      const price = 1.255;
      const qty = 8;
      expect(
        lineTotalForPay(shelfPrice: price, discountPercent: 0, qty: qty),
        lineTotalRoundUnitThenQty(rawUnitPrice: price, qty: qty),
      );
    });

    test('four-decimal direct uses display-rounded unit', () {
      const price = 3.8528;
      const qty = 12;
      expect(roundedUnitPrice(price), 3.85);
      expect(
        lineTotalForPay(shelfPrice: price, discountPercent: 0, qty: qty),
        lineTotalRoundUnitThenQty(rawUnitPrice: price, qty: qty),
      );
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

    test('discount-eligible with 0% uses unit-round-then-qty (same as direct)', () {
      expect(
        lineTotalForPay(shelfPrice: 3.125, discountPercent: 0, qty: 36),
        112.68,
      );
      expect(
        lineTotalForPay(shelfPrice: 0.585, discountPercent: 0, qty: 12),
        7.08,
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
          {'price': 3.125, 'quantity': 36, 'scans': 1},
        ],
      });
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final line = (decoded['lines'] as List).single as Map<String, dynamic>;
      final price = (line['price'] as num).toDouble();
      final quantity = (line['quantity'] as num).toInt();

      expect(price, 3.125);
      expect(
        lineTotalForPay(shelfPrice: price, discountPercent: 0, qty: quantity),
        112.68,
      );
    });

    test('quantity increase and decrease never alter stored unit price', () {
      const price = 3.125;
      expect(
        lineTotalForPay(shelfPrice: price, discountPercent: 0, qty: 35),
        roundMoney(roundedUnitPrice(price) * 35),
      );
      expect(
        lineTotalForPay(shelfPrice: price, discountPercent: 0, qty: 36),
        112.68,
      );
      expect(
        lineTotalForPay(shelfPrice: price, discountPercent: 0, qty: 35),
        roundMoney(roundedUnitPrice(price) * 35),
      );
      expect(price, 3.125);
    });

    test('mixed subtotal uses unit-rounded line totals', () {
      final highPrecision = lineTotalForPay(
        shelfPrice: 3.125,
        discountPercent: 0,
        qty: 36,
      );
      final ordinary = lineTotalForPay(
        shelfPrice: 2.35,
        discountPercent: 0,
        qty: 4,
      );

      expect(highPrecision, 112.68);
      expect(ordinary, 9.40);
      expect(roundMoney(highPrecision + ordinary), 122.08);
    });
  });

  group(r'comparison quote — Emun $7,742.08', () {
    test('S612CA-CD correction lifts previous Scanner 7741.90 to 7742.08', () {
      const previousIncorrectScannerTotal = 7741.90;
      const expectedEmunTotal = 7742.08;
      final incorrectLine = lineTotalFullUnitThenRound(
        unitPrice: 3.125,
        qty: 36,
      );
      final correctedLine = lineTotalForPay(
        shelfPrice: 3.125,
        discountPercent: 0,
        qty: 36,
      );

      expect(incorrectLine, 112.50);
      expect(correctedLine, 112.68);
      expect(correctedLine - incorrectLine, closeTo(0.18, 1e-9));
      expect(
        roundMoney(
          previousIncorrectScannerTotal - incorrectLine + correctedLine,
        ),
        expectedEmunTotal,
      );
    });
  });
}

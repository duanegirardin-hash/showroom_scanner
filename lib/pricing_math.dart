/// Centralized EMUN-aligned quote line money math.
///
/// Display helpers ([roundedUnitPrice]) are for UI only.
/// Pay / extend totals must use [lineTotalForPay].
library;

/// Cent-round (half away from zero on scaled value), matching historical app behavior.
double roundMoney(num value) {
  return (value * 100).roundToDouble() / 100.0;
}

/// Display / customer unit — round shelf or discounted raw unit to cents.
double roundedUnitPrice(double rawUnitPrice) => roundMoney(rawUnitPrice);

/// EMUN: round unit to cents, then × qty, then round line.
double lineTotalRoundUnitThenQty({
  required double rawUnitPrice,
  required num qty,
}) {
  final unit = roundedUnitPrice(rawUnitPrice);
  return roundMoney(unit * qty);
}

/// Full stored unit × qty, then cent-round (PS path).
double lineTotalFullUnitThenRound({
  required double unitPrice,
  required num qty,
}) {
  return roundMoney(unitPrice * qty);
}

/// Pricing class for pay-line branching (mirrors app PS→NET→DISCOUNT→direct).
enum PayPricingClass {
  /// Full stored precision × qty, then round¢.
  ps,

  /// Round unit to cents, then × qty, then round¢.
  net,

  /// Percentage-discount eligible; Method A when [discountPercent] > 0,
  /// otherwise same as [regular] (unproven at 0% — unit-round).
  discountEligible,

  /// Direct / regular shelf (unproven high-precision) — unit-round.
  regular,
}

/// Branch name selected by [lineTotalForPay] (for diagnostics).
String payLineBranchName({
  required double discountPercent,
  required PayPricingClass pricingClass,
}) {
  if (discountPercent > 0) return 'methodA';
  if (pricingClass == PayPricingClass.ps) return 'fullStoredThenRound';
  return 'roundUnitThenQty';
}

/// Class-aware pay-line rule (EMUN-aligned).
///
/// When [discountPercent] > 0 (percentage-discount Method A):
///   customerUnit = round¢(shelfPrice × (1 − discountPercent/100))
///   lineTotal = round¢(customerUnit × qty)
///
/// When [pricingClass] is [PayPricingClass.ps] and disc% == 0:
///   lineTotal = round¢(shelfPrice × qty)  // full stored precision
///
/// Otherwise (NET, discount@0%, regular):
///   lineTotal = round¢(round¢(shelfPrice) × qty)
double lineTotalForPay({
  required double shelfPrice,
  required double discountPercent,
  required num qty,
  PayPricingClass pricingClass = PayPricingClass.regular,
}) {
  if (discountPercent > 0) {
    final raw = shelfPrice * (1 - discountPercent / 100.0);
    return lineTotalRoundUnitThenQty(rawUnitPrice: raw, qty: qty);
  }
  if (pricingClass == PayPricingClass.ps) {
    return lineTotalFullUnitThenRound(unitPrice: shelfPrice, qty: qty);
  }
  return lineTotalRoundUnitThenQty(rawUnitPrice: shelfPrice, qty: qty);
}

/// Regular (pre-discount) shelf extend — class-aware like [lineTotalForPay] at 0%.
double lineTotalRegularFromShelf({
  required double shelfPrice,
  required num qty,
  PayPricingClass pricingClass = PayPricingClass.regular,
}) {
  return lineTotalForPay(
    shelfPrice: shelfPrice,
    discountPercent: 0,
    qty: qty,
    pricingClass: pricingClass,
  );
}

/// Centralized EMUN-aligned quote line money math.
///
/// Display helpers ([roundedUnitPrice]) are for UI only.
/// Pay / extend totals must use [lineTotalForPay].
library;

/// Cent-round (half away from zero on scaled value), matching historical app behavior.
double roundMoney(num value) {
  return (value * 100).roundToDouble() / 100.0;
}

/// Display / Method-A customer unit — round shelf or discounted raw unit to cents.
double roundedUnitPrice(double rawUnitPrice) => roundMoney(rawUnitPrice);

/// EMUN Method A: round unit to cents, then × qty, then round line.
double lineTotalRoundUnitThenQty({
  required double rawUnitPrice,
  required num qty,
}) {
  final unit = roundedUnitPrice(rawUnitPrice);
  return roundMoney(unit * qty);
}

/// Direct customer price (PS / NET / shelf): full unit × qty, then round line.
double lineTotalFullUnitThenRound({
  required double unitPrice,
  required num qty,
}) {
  return roundMoney(unitPrice * qty);
}

/// Single pay-line rule.
///
/// When [discountPercent] > 0 (percentage-discount path only):
///   customerUnit = round¢(shelfPrice × (1 − discountPercent/100))
///   lineTotal = round¢(customerUnit × qty)
///
/// Otherwise (PS, NET, regular, or discount-eligible with 0%):
///   lineTotal = round¢(shelfPrice × qty)  // full stored precision
double lineTotalForPay({
  required double shelfPrice,
  required double discountPercent,
  required num qty,
}) {
  if (discountPercent > 0) {
    final raw = shelfPrice * (1 - discountPercent / 100.0);
    return lineTotalRoundUnitThenQty(rawUnitPrice: raw, qty: qty);
  }
  return lineTotalFullUnitThenRound(unitPrice: shelfPrice, qty: qty);
}

/// Regular (pre-discount) line extend from catalog shelf price — always full-unit path.
double lineTotalRegularFromShelf({
  required double shelfPrice,
  required num qty,
}) {
  return lineTotalFullUnitThenRound(unitPrice: shelfPrice, qty: qty);
}

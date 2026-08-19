/// Compact EMUN-ready CSV used by quote export and SEND TO PC.
/// Must stay identical to the non-rich path of [_formatQuoteAsCsv] in main.dart.
library;

int quoteQuantityFromJson(dynamic v) {
  if (v == null) return 1;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 1;
  return 1;
}

String csvEscapeCell(String value) {
  if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}

/// Header is always `Item,Quantity`. No prices, names, or QuoteID in the file.
String formatQuoteAsEmunCsv(
  Map<String, dynamic> data, {
  bool sortByItemNumberAsc = false,
  int Function(String a, String b)? compareItemNumber,
}) {
  const header = 'Item,Quantity';
  final lines =
      data['lines'] as List<dynamic>? ?? data['items'] as List<dynamic>? ?? [];
  final csvLines = <({String itemNumber, int qty})>[];

  for (final lineJson in lines) {
    final map = Map<String, dynamic>.from(lineJson as Map);
    final itemNumber = (map['itemNumber'] as String?) ?? '';
    final qty = quoteQuantityFromJson(map['quantity']);
    csvLines.add((itemNumber: itemNumber, qty: qty));
  }

  final ordered = List<({String itemNumber, int qty})>.from(csvLines);
  if (sortByItemNumberAsc) {
    final cmp = compareItemNumber ?? _defaultItemNumberCompare;
    ordered.sort((a, b) => cmp(a.itemNumber, b.itemNumber));
  }

  final rows = <String>[header];
  for (final line in ordered) {
    rows.add('${csvEscapeCell(line.itemNumber)},${line.qty}');
  }
  return rows.join('\n');
}

int _defaultItemNumberCompare(String a, String b) {
  return a.trim().compareTo(b.trim());
}

({String quoteId, String customerId, String customerName})
quoteTransferMetadata(Map<String, dynamic> data, {String fallbackCustomerId = '', String fallbackCustomerName = ''}) {
  final quoteId = (data['id'] as String?)?.trim() ?? '';
  var customerId = fallbackCustomerId.trim();
  var customerName = fallbackCustomerName.trim();
  final customerMap = data['customer'];
  if (customerMap is Map) {
    final map = Map<String, dynamic>.from(customerMap);
    final id = (map['id'] as String?)?.trim() ?? '';
    final company = (map['companyName'] as String?)?.trim() ?? '';
    if (id.isNotEmpty) customerId = id;
    if (company.isNotEmpty) customerName = company;
  }
  return (
    quoteId: quoteId,
    customerId: customerId,
    customerName: customerName,
  );
}

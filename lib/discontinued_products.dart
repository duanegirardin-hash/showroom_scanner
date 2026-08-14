/// Separate discontinued / L-item (EMUN Inactive) catalog helpers.
///
/// Active product maps must never be merged with these collections.
library;

import 'package:csv/csv.dart';

class DiscontinuedProduct {
  const DiscontinuedProduct({
    required this.itemNumber,
    required this.description,
    required this.upc,
    required this.emunStatus,
    required this.sellable,
    required this.whse1Qty,
    required this.whse2Qty,
    required this.totalQty,
    required this.isNewRelease,
    required this.category,
    required this.subCategory,
  });

  final String itemNumber;
  final String description;
  final String upc;
  final String emunStatus;
  final String sellable;
  final int? whse1Qty;
  final int? whse2Qty;
  final int? totalQty;
  final bool isNewRelease;
  final String category;
  final String subCategory;
}

class DiscontinuedCatalog {
  const DiscontinuedCatalog({
    required this.byUpc,
    required this.byItemNumber,
    required this.count,
  });

  final Map<String, DiscontinuedProduct> byUpc;
  final Map<String, DiscontinuedProduct> byItemNumber;
  final int count;

  static const empty = DiscontinuedCatalog(
    byUpc: {},
    byItemNumber: {},
    count: 0,
  );
}

String discontinuedNormalizeItemNumber(String value) =>
    value.trim().toUpperCase();

String discontinuedDigitsOnly(String value) {
  return value.replaceAll(RegExp(r'[^0-9]'), '').trim();
}

/// Same UPC lookup key rules as Showroom Scanner active products.
String discontinuedNormalizeUpcLookupKey(String value) {
  final trimmed = value.trim();
  final digits = discontinuedDigitsOnly(trimmed);
  return digits.isNotEmpty ? digits : trimmed.toUpperCase();
}

String _normalizedHeaderKey(String s) {
  return s.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '');
}

Map<String, int> _headerIndexMap(List<String> header) {
  final map = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    final nk = _normalizedHeaderKey(header[i]);
    if (nk.isEmpty) continue;
    map.putIfAbsent(nk, () => i);
  }
  return map;
}

int _requireColumn(
  Map<String, int> byNorm,
  String logicalName,
  List<String> keys,
  List<String> header,
) {
  for (final nk in keys) {
    final i = byNorm[nk];
    if (i != null) return i;
  }
  throw FormatException(
    'Discontinued CSV missing required column "$logicalName". '
    'Headers: ${header.join(', ')}',
  );
}

int? _optionalColumn(Map<String, int> byNorm, List<String> keys) {
  for (final nk in keys) {
    final i = byNorm[nk];
    if (i != null) return i;
  }
  return null;
}

String _cell(List<dynamic> row, int col) {
  if (col < 0 || col >= row.length) return '';
  return row[col].toString();
}

int? _parseInt(String value) {
  final cleaned = value.replaceAll(',', '').trim();
  if (cleaned.isEmpty) return null;
  return int.tryParse(cleaned) ?? double.tryParse(cleaned)?.round();
}

bool _parseYes(String value) {
  final v = value.trim().toUpperCase();
  return v == 'YES' || v == 'Y' || v == 'TRUE' || v == '1';
}

/// Parse discontinued CSV into separate UPC / item-number maps.
///
/// Blank UPCs are omitted from the UPC map.
/// Duplicate UPC rows: later row wins (deterministic CSV order).
DiscontinuedCatalog parseDiscontinuedCsv(String rawCsv) {
  final rows = const CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\n',
  ).convert(rawCsv.replaceFirst('\uFEFF', '').replaceAll('\r\n', '\n'));
  if (rows.isEmpty) {
    return DiscontinuedCatalog.empty;
  }
  // Skip leading blank rows (common with multiline test fixtures / BOM files).
  var headerRowIndex = 0;
  while (headerRowIndex < rows.length &&
      (rows[headerRowIndex].isEmpty ||
          rows[headerRowIndex].every((e) => e.toString().trim().isEmpty))) {
    headerRowIndex++;
  }
  if (headerRowIndex >= rows.length) {
    return DiscontinuedCatalog.empty;
  }
  final header = rows[headerRowIndex].map((e) => e.toString()).toList();
  final byNorm = _headerIndexMap(header);
  final idxItem = _requireColumn(byNorm, 'Item Number', const [
    'itemnumber',
  ], header);
  final idxDesc = _requireColumn(byNorm, 'Description', const [
    'description',
  ], header);
  final idxUpc = _requireColumn(byNorm, 'UPC', const ['upc'], header);
  final idxStatus = _optionalColumn(byNorm, const [
    'emunstatus',
    'status',
  ]);
  final idxSellable = _optionalColumn(byNorm, const ['sellable']);
  final idxW1 = _optionalColumn(byNorm, const [
    'whse1qtyavailable',
    'whse1',
  ]);
  final idxW2 = _optionalColumn(byNorm, const [
    'whse2qtyavailable',
    'whse2',
  ]);
  final idxTotal = _optionalColumn(byNorm, const [
    'totalqtyavailable',
    'totalqty',
  ]);
  final idxNew = _optionalColumn(byNorm, const [
    'newrelease',
    'new',
  ]);
  final idxCat = _optionalColumn(byNorm, const ['category']);
  final idxSub = _optionalColumn(byNorm, const [
    'subcategory',
  ]);

  final byUpc = <String, DiscontinuedProduct>{};
  final byItem = <String, DiscontinuedProduct>{};

  for (var i = headerRowIndex + 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.isEmpty || row.every((e) => e.toString().trim().isEmpty)) {
      continue;
    }
    final itemNumber = discontinuedNormalizeItemNumber(_cell(row, idxItem));
    if (itemNumber.isEmpty) continue;
    final upc = _cell(row, idxUpc).trim();
    final upcKey = discontinuedNormalizeUpcLookupKey(upc);
    final product = DiscontinuedProduct(
      itemNumber: itemNumber,
      description: _cell(row, idxDesc).trim(),
      upc: upc,
      emunStatus: idxStatus == null
          ? 'Inactive'
          : _cell(row, idxStatus).trim(),
      sellable: idxSellable == null ? 'NO' : _cell(row, idxSellable).trim(),
      whse1Qty: idxW1 == null ? null : _parseInt(_cell(row, idxW1)),
      whse2Qty: idxW2 == null ? null : _parseInt(_cell(row, idxW2)),
      totalQty: idxTotal == null ? null : _parseInt(_cell(row, idxTotal)),
      isNewRelease: idxNew == null ? false : _parseYes(_cell(row, idxNew)),
      category: idxCat == null ? '' : _cell(row, idxCat).trim(),
      subCategory: idxSub == null ? '' : _cell(row, idxSub).trim(),
    );
    byItem[itemNumber] = product;
    if (upcKey.isNotEmpty) {
      byUpc[upcKey] = product;
    }
  }

  return DiscontinuedCatalog(
    byUpc: byUpc,
    byItemNumber: byItem,
    count: byItem.length,
  );
}

/// Active-first lookup. Returns discontinued only when Active maps miss.
DiscontinuedProduct? findDiscontinuedProduct({
  required String input,
  required Map<String, dynamic> activeByUpc,
  required Map<String, dynamic> activeByItemNumber,
  required DiscontinuedCatalog discontinued,
  String Function(String input)? normalizeItemNumber,
}) {
  final upc = discontinuedNormalizeUpcLookupKey(input);
  final itemNorm =
      (normalizeItemNumber ?? discontinuedNormalizeItemNumber)(input);

  // Active always wins — never consult discontinued if Active matches.
  dynamic active = activeByUpc[upc];
  active ??= activeByItemNumber[itemNorm];
  if (active == null && upc.length == 12 && upc.startsWith('0')) {
    active = activeByUpc[upc.substring(1)];
  }
  if (active == null && upc.length == 11) {
    active = activeByUpc['0$upc'];
  }
  if (active != null) {
    return null;
  }

  DiscontinuedProduct? disc = discontinued.byUpc[upc];
  disc ??= discontinued.byItemNumber[itemNorm];
  if (disc == null && upc.length == 12 && upc.startsWith('0')) {
    disc = discontinued.byUpc[upc.substring(1)];
  }
  if (disc == null && upc.length == 11) {
    disc = discontinued.byUpc['0$upc'];
  }
  return disc;
}

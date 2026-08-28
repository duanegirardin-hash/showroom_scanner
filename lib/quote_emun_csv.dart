/// Compact EMUN-ready CSV used by quote export and SEND TO PC.
/// Must stay identical to the non-rich path of [_formatQuoteAsCsv] in main.dart.
library;

/// True when a parsed export quote-type segment begins with a barcode-like run
/// (8+ consecutive digits), e.g. `062823532588_GENERAL_QUOTE`.
bool quoteExportTypeLooksBarcodeCorrupted(String quoteType) {
  final trimmed = quoteType.trim();
  if (trimmed.isEmpty) return false;
  return RegExp(r'^\d{8,}').hasMatch(trimmed);
}

/// Chooses the export/SEND TO PC quote-type segment from parsed name + bucket.
String resolveQuoteExportTypeCandidate({
  required String parsedQuoteType,
  String? quoteBucketLabel,
  String? quoteBucketKey,
}) {
  final parsed = parsedQuoteType.trim();
  if (parsed.isNotEmpty && !quoteExportTypeLooksBarcodeCorrupted(parsed)) {
    return parsed;
  }

  final bucketLabel = (quoteBucketLabel ?? '').trim();
  if (bucketLabel.isNotEmpty) {
    final upper = bucketLabel.toUpperCase();
    return upper.endsWith(' QUOTE') ? bucketLabel.trim() : '$bucketLabel QUOTE';
  }

  final bucketKey = (quoteBucketKey ?? '').trim();
  if (bucketKey.isNotEmpty) {
    final fromKey = bucketKey.replaceAll('_', ' ').trim().toUpperCase();
    return fromKey.endsWith(' QUOTE') ? fromKey : '$fromKey QUOTE';
  }

  if (parsed.isNotEmpty) return parsed;
  return 'QUOTE';
}

/// When focus is in the quote-name field, returns a newly inserted 8+ digit barcode
/// scan to route into the normal scanner flow, or null if none detected.
String? newlyInsertedBarcodeInQuoteName(String currentText, String savedText) {
  final current = currentText.trim();
  if (current.isEmpty) return null;

  if (RegExp(r'^\d{8,}$').hasMatch(current)) {
    return current;
  }

  final savedRuns = RegExp(r'\d{8,}')
      .allMatches(savedText.trim())
      .map((m) => m.group(0)!)
      .toSet();

  for (final match in RegExp(r'\d{8,}').allMatches(current)) {
    final run = match.group(0)!;
    if (!savedRuns.contains(run)) {
      return run;
    }
  }

  return null;
}

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

/// Wrap the quote-type segment of an export basename for PC transfer only.
/// Example: `EVERYDAY_QUOTE_2026_08_27_001_...` → `[EVERYDAY_QUOTE]_2026_08_27_001_...`
String wrapQuoteTypeForPcTransferBasename(String exportBasenameWithoutExtension) {
  final base = exportBasenameWithoutExtension.trim();
  if (base.isEmpty) return base;
  if (base.startsWith('[')) return base;

  final match = RegExp(r'^(.+)_(\d{4})_(\d{2})_(\d{2})_(\d{3})_(.+)$').firstMatch(base);
  if (match == null) return base;

  final quoteType = match.group(1)!.trim();
  if (quoteType.isEmpty) return base;

  return '[${quoteType}]_${match.group(2)}_${match.group(3)}_${match.group(4)}_'
      '${match.group(5)}_${match.group(6)}';
}

/// PC transfer filename stem: `{quoteId}_{exportBasename}` (PC transfer naming).
String buildPcTransferQuoteFilenameStem({
  required String quoteId,
  required String exportBasenameWithoutExtension,
}) {
  final base = wrapQuoteTypeForPcTransferBasename(exportBasenameWithoutExtension);
  final id = quoteId.trim();
  if (base.isEmpty) return id;
  if (id.isEmpty) return base;
  return '${id}_$base';
}

/// Resolve the quote name sent to the PC receiver (metadata only, not CSV).
String resolvePcTransferQuoteName(
  Map<String, dynamic> data, {
  String Function(Map<String, dynamic> data)? buildTransferFilename,
  String fallbackCustomerId = '',
  String fallbackCustomerName = '',
  String fallbackQuoteName = '',
}) {
  final built = buildTransferFilename?.call(data).trim() ?? '';
  if (built.isNotEmpty) return built;
  return quoteTransferMetadata(
    data,
    fallbackCustomerId: fallbackCustomerId,
    fallbackCustomerName: fallbackCustomerName,
    fallbackQuoteName: fallbackQuoteName,
  ).quoteName;
}

({String quoteId, String customerId, String customerName, String quoteName})
quoteTransferMetadata(
  Map<String, dynamic> data, {
  String fallbackCustomerId = '',
  String fallbackCustomerName = '',
  String fallbackQuoteName = '',
}) {
  final quoteId = (data['id'] as String?)?.trim() ?? '';
  var customerId = fallbackCustomerId.trim();
  var customerName = fallbackCustomerName.trim();
  var quoteName = (data['name'] as String?)?.trim() ?? '';
  if (quoteName.isEmpty) {
    quoteName = fallbackQuoteName.trim();
  }
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
    quoteName: quoteName,
  );
}

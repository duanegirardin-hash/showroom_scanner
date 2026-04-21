// Isolated spreadsheet workflow: Build Updated Master Products Sheet.
// Does not depend on app catalog, quote state, or order lines.

import 'dart:convert';
import 'dart:io';

import 'package:diacritic/diacritic.dart';
import 'package:excel/excel.dart' as xlsx;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:unorm_dart/unorm_dart.dart';

const String _kLogPrefix = '[MasterBuildDiag]';

void _mbLog(String message) {
  debugPrint('$_kLogPrefix $message');
}

void _whseLog(String message) {
  debugPrint('[WhseDiag] $message');
}

String _normHeader(String s) {
  return s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_]+'), '');
}

/// Result of [runUpdatedMasterProductsBuild].
class MasterProductsBuildReport {
  MasterProductsBuildReport({
    required this.success,
    required this.errorMessage,
    required this.bytes,
    required this.startingQuoteDataRows,
    required this.removedRows,
    required this.listPriceUpdated,
    required this.psYesRows,
    required this.newReleaseYesRows,
    required this.addedFromNewRelease,
    required this.unmatchedNewReleaseNotInProducts,
    required this.unmatchedPsNotInProductsOrQuote,
    required this.finalDataRowCount,
    required this.exceptionRowCount,
  });

  final bool success;
  final String? errorMessage;
  final List<int>? bytes;

  final int startingQuoteDataRows;
  final int removedRows;
  final int listPriceUpdated;
  final int psYesRows;
  final int newReleaseYesRows;
  final int addedFromNewRelease;
  final int unmatchedNewReleaseNotInProducts;
  /// PS items missing from Products, plus PS items in Products but not in Quote and not added via New Release.
  final int unmatchedPsNotInProductsOrQuote;
  final int finalDataRowCount;
  final int exceptionRowCount;
}

class _ProductsRow {
  _ProductsRow({
    required this.sourceRowIndex1Based,
    required this.itemKey,
    required this.itemDisplay,
    required this.listPriceText,
    required this.hasListPriceValue,
    required this.listPriceNumeric,
    required this.description,
    required this.upc,
    required this.priceText,
    required this.priceNumeric,
    required this.productType,
    required this.category,
    required this.subCategory,
    required this.minOrderQtyText,
    required this.caseQtyText,
  });

  final int sourceRowIndex1Based;
  final String itemKey;
  final String itemDisplay;
  final String listPriceText;
  final bool hasListPriceValue;
  final double? listPriceNumeric;
  final String description;
  final String upc;
  final String priceText;
  final double? priceNumeric;
  final String productType;
  final String category;
  final String subCategory;
  final String minOrderQtyText;
  final String caseQtyText;
}

String _plainFromData(xlsx.Data? d) {
  if (d == null) return '';
  return _plainFromValue(d.value);
}

String _plainFromValue(xlsx.CellValue? v) {
  if (v == null) return '';
  if (v is xlsx.TextCellValue) {
    return v.value.toString();
  }
  if (v is xlsx.IntCellValue) return v.value.toString();
  if (v is xlsx.DoubleCellValue) {
    final x = v.value;
    if (x.isNaN || x.isInfinite) return '';
    if (x == x.roundToDouble() && x.abs() < 1e15) {
      return x.toInt().toString();
    }
    return _formatDoublePlain(x);
  }
  if (v is xlsx.BoolCellValue) return v.value ? 'TRUE' : 'FALSE';
  if (v is xlsx.DateCellValue) {
    return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
  }
  if (v is xlsx.FormulaCellValue) return v.formula;
  return v.toString();
}

/// Item Number identity: always read as text (never [int]/[double] parsing).
/// Trims surrounding whitespace. Leading zeros are preserved when the cell is stored as text in Excel;
/// if Excel stored the value as a numeric cell, leading zeros cannot be recovered.
String _itemNumberPlainFromValue(xlsx.CellValue? v) {
  if (v == null) return '';
  if (v is xlsx.TextCellValue) {
    final ts = v.value;
    final direct = ts.text;
    if (direct != null) return direct;
    return ts.toString();
  }
  return _plainFromValue(v);
}

String _itemNumberPlainFromData(xlsx.Data? d) {
  if (d == null) return '';
  return _itemNumberPlainFromValue(d.value);
}

/// Match key for lookups: trimmed display, case-insensitive (does not strip leading zeros from text cells).
String _itemNumberMatchKey(String trimmedDisplay) => trimmedDisplay.toUpperCase();

String _formatDoublePlain(double x) {
  var s = x.toStringAsFixed(6);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// Repairs UTF-8 bytes that were misinterpreted as Latin-1/Windows-1252 (mojibake),
/// e.g. "DÃ©cor" → "Décor". Safe for already-correct text (typically no-ops or throws → original).
String _repairUtf8Mojibake(String text) {
  if (text.isEmpty) return text;
  var current = text;
  for (var round = 0; round < 3; round++) {
    try {
      final repaired = utf8.decode(latin1.encode(current));
      if (repaired == current) break;
      current = repaired;
    } catch (_) {
      break;
    }
  }
  return current;
}

/// Mojibake repair, Unicode NFD decomposition, diacritic stripping, then trim.
String _cleanMasterText(String input) {
  final repaired = _repairUtf8Mojibake(input);
  final normalized = nfd(repaired);
  final plain = removeDiacritics(normalized);
  return plain.trim();
}

/// Counts master text fields whose value changed after [_cleanMasterText].
final class _MasterTextCleanupTicker {
  int changedCells = 0;

  void recordIfChanged(String beforeRaw, String after) {
    if (beforeRaw.trim() != after) changedCells++;
  }
}

void _repairMasterTextColumnsInDst(
  List<xlsx.CellValue?> dst, {
  required int? idxDesc,
  required int? idxPt,
  required int? idxCat,
  required int? idxSub,
  _MasterTextCleanupTicker? cleanup,
}) {
  for (final idx in [idxDesc, idxPt, idxCat, idxSub]) {
    if (idx == null || idx < 0 || idx >= dst.length) continue;
    final v = dst[idx];
    if (v != null && v is! xlsx.TextCellValue) continue;
    final plain = _plainFromValue(v);
    if (plain.isEmpty) continue;
    final cleaned = _cleanMasterText(plain);
    cleanup?.recordIfChanged(plain, cleaned);
    dst[idx] = _textCv(cleaned);
  }
}

xlsx.CellValue? _cloneCellValue(xlsx.CellValue? v) {
  if (v == null) return null;
  if (v is xlsx.TextCellValue) {
    return xlsx.TextCellValue(_plainFromValue(v));
  }
  if (v is xlsx.IntCellValue) return xlsx.IntCellValue(v.value);
  if (v is xlsx.DoubleCellValue) return xlsx.DoubleCellValue(v.value);
  if (v is xlsx.BoolCellValue) return xlsx.BoolCellValue(v.value);
  if (v is xlsx.DateCellValue) {
    return xlsx.DateCellValue(year: v.year, month: v.month, day: v.day);
  }
  if (v is xlsx.FormulaCellValue) return xlsx.FormulaCellValue(v.formula);
  return xlsx.TextCellValue(_plainFromValue(v));
}

xlsx.CellValue _textCv(String s) => xlsx.TextCellValue(s);

bool _isBlankRow(List<xlsx.Data?> row, int maxCol) {
  for (var c = 0; c < maxCol && c < row.length; c++) {
    if (_plainFromData(row[c]).trim().isNotEmpty) return false;
  }
  return true;
}

int? _matchHeaderIndex(List<String> headerNorm, Set<String> aliases) {
  for (var i = 0; i < headerNorm.length; i++) {
    final h = headerNorm[i];
    if (aliases.contains(h)) return i;
  }
  return null;
}

/// First output column whose normalized header is in [aliases] (quote sheet may use any alias).
int? _matchOutputColumn(Map<String, int> hIndex, Set<String> aliases) {
  for (final a in aliases) {
    final i = hIndex[a];
    if (i != null) return i;
  }
  return null;
}

final Set<String> _aliasesItemNumber = {
  'itemnumber',
  'itemno',
  'item#',
  'item',
};

final Set<String> _aliasesListPrice = {'listprice'};
final Set<String> _aliasesPs = {'ps'};
final Set<String> _aliasesNewRelease = {'newrelease'};
final Set<String> _aliasesDescription = {'description', 'desc', 'itemdescription'};
final Set<String> _aliasesUpc = {'upc', 'barcode'};
final Set<String> _aliasesPrice = {'price', 'unitprice'};
final Set<String> _aliasesProductType = {'producttype', 'type'};
final Set<String> _aliasesCategory = {'category'};
final Set<String> _aliasesSubCategory = {'subcategory'};
final Set<String> _aliasesMoq = {
  'minimumorderquantity',
  'minorderqty',
  'moq',
  'minqty',
};
final Set<String> _aliasesCaseQty = {
  'casequantity',
  'caseqty',
  'case',
};

/// Output column labels (exact spelling for the master workbook).
const String _kOutWhse1InStock = 'Whse 1 In Stock';
const String _kOutWhse2InStock = 'Whse 2 In Stock';
const String _kOutWhse1OutOfStock = 'Whse 1 Out of Stock';
const String _kOutWhse2OutOfStock = 'Whse 2 Out of Stock';
const String _kOutWhse1ComingSoon = 'Whse 1 Coming Soon';
const String _kOutWhse2ComingSoon = 'Whse 2 Coming Soon';

final Set<String> _aliasesWhse1InStock = {_normHeader(_kOutWhse1InStock)};
final Set<String> _aliasesWhse2InStock = {_normHeader(_kOutWhse2InStock)};
final Set<String> _aliasesWhse1OutOfStock = {_normHeader(_kOutWhse1OutOfStock)};
final Set<String> _aliasesWhse2OutOfStock = {_normHeader(_kOutWhse2OutOfStock)};
final Set<String> _aliasesWhse1ComingSoon = {_normHeader(_kOutWhse1ComingSoon)};
final Set<String> _aliasesWhse2ComingSoon = {_normHeader(_kOutWhse2ComingSoon)};

double? _tryParseDouble(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  return double.tryParse(t.replaceAll(RegExp(r'[,$]'), ''));
}

bool _truthyYes(String s) {
  final u = s.trim().toUpperCase();
  return u == 'Y' || u == 'YES' || u == 'TRUE' || u == '1';
}

xlsx.Sheet? _resolveSheetForRole(
  xlsx.Excel excel,
  List<String> preferredNames,
  String roleLabel,
) {
  for (final name in preferredNames) {
    final want = name.trim().toLowerCase();
    for (final key in excel.tables.keys) {
      if (key.trim().toLowerCase() == want) {
        return excel[key];
      }
    }
  }
  if (excel.tables.length == 1) {
    _mbLog(
      'Sheet role "$roleLabel": single sheet fallback "${excel.tables.keys.first}"',
    );
    return excel[excel.tables.keys.first];
  }
  return null;
}

List<String> _readHeaderStrings(List<xlsx.Data?> row) {
  final out = <String>[];
  for (final c in row) {
    out.add(_plainFromData(c).trim());
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out;
}

({Map<String, _ProductsRow> map, Map<String, List<int>> dupRows})
_parseProductsSheet(
  xlsx.Sheet sheet, [
  _MasterTextCleanupTicker? cleanup,
]) {
  final rows = sheet.rows;
  if (rows.isEmpty) {
    return (map: <String, _ProductsRow>{}, dupRows: <String, List<int>>{});
  }
  final headerRow = rows.first;
  final headerLabels = _readHeaderStrings(headerRow);
  final headerNorm = headerLabels.map(_normHeader).toList();

  final itemCol = _matchHeaderIndex(headerNorm, _aliasesItemNumber);
  if (itemCol == null) {
    throw StateError('Products sheet: could not find an Item Number column.');
  }
  final lpCol = _matchHeaderIndex(headerNorm, _aliasesListPrice);
  final descCol = _matchHeaderIndex(headerNorm, _aliasesDescription);
  final upcCol = _matchHeaderIndex(headerNorm, _aliasesUpc);
  final priceCol = _matchHeaderIndex(headerNorm, _aliasesPrice);
  final ptCol = _matchHeaderIndex(headerNorm, _aliasesProductType);
  final catCol = _matchHeaderIndex(headerNorm, _aliasesCategory);
  final subCol = _matchHeaderIndex(headerNorm, _aliasesSubCategory);
  final moqCol = _matchHeaderIndex(headerNorm, _aliasesMoq);
  final caseCol = _matchHeaderIndex(headerNorm, _aliasesCaseQty);

  final map = <String, _ProductsRow>{};
  final dupRows = <String, List<int>>{};
  final maxCol = headerNorm.length;

  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    if (row.isEmpty || _isBlankRow(row, maxCol)) continue;
    final itemCell = itemCol < row.length ? row[itemCol] : null;
    final itemDisplay = _itemNumberPlainFromData(itemCell).trim();
    if (itemDisplay.isEmpty) continue;
    final itemKey = _itemNumberMatchKey(itemDisplay);
    final rowIndex1 = r + 1;

    final lpStr = lpCol != null && lpCol < row.length
        ? _plainFromData(row[lpCol]).trim()
        : '';
    final lpNum = _tryParseDouble(lpStr);
    final hasLp = lpStr.isNotEmpty && lpNum != null;

    String descOut = '';
    if (descCol != null && descCol < row.length) {
      final raw = _plainFromData(row[descCol]);
      descOut = _cleanMasterText(raw);
      cleanup?.recordIfChanged(raw, descOut);
    }
    String ptOut = '';
    if (ptCol != null && ptCol < row.length) {
      final raw = _plainFromData(row[ptCol]);
      ptOut = _cleanMasterText(raw);
      cleanup?.recordIfChanged(raw, ptOut);
    }
    String catOut = '';
    if (catCol != null && catCol < row.length) {
      final raw = _plainFromData(row[catCol]);
      catOut = _cleanMasterText(raw);
      cleanup?.recordIfChanged(raw, catOut);
    }
    String subOut = '';
    if (subCol != null && subCol < row.length) {
      final raw = _plainFromData(row[subCol]);
      subOut = _cleanMasterText(raw);
      cleanup?.recordIfChanged(raw, subOut);
    }

    final pr = _ProductsRow(
      sourceRowIndex1Based: rowIndex1,
      itemKey: itemKey,
      itemDisplay: itemDisplay,
      listPriceText: lpStr,
      hasListPriceValue: hasLp,
      listPriceNumeric: lpNum,
      description: descOut,
      upc: upcCol != null && upcCol < row.length
          ? _plainFromData(row[upcCol]).trim()
          : '',
      priceText: priceCol != null && priceCol < row.length
          ? _plainFromData(row[priceCol]).trim()
          : '',
      priceNumeric: priceCol != null && priceCol < row.length
          ? _tryParseDouble(_plainFromData(row[priceCol]))
          : null,
      productType: ptOut,
      category: catOut,
      subCategory: subOut,
      minOrderQtyText: moqCol != null && moqCol < row.length
          ? _plainFromData(row[moqCol]).trim()
          : '',
      caseQtyText: caseCol != null && caseCol < row.length
          ? _plainFromData(row[caseCol]).trim()
          : '',
    );

    dupRows.putIfAbsent(itemKey, () => []).add(rowIndex1);
    map.putIfAbsent(itemKey, () => pr);
  }

  return (map: map, dupRows: dupRows);
}

/// Ordered item keys from PS or New Release helper sheets.
({List<String> orderedKeys, Set<String> keySet}) _parseFlagSheet(
  xlsx.Sheet sheet,
  String label,
) {
  final rows = sheet.rows;
  final ordered = <String>[];
  final seen = <String>{};
  if (rows.isEmpty) return (orderedKeys: ordered, keySet: seen);

  final headerRow = rows.first;
  final headerLabels = _readHeaderStrings(headerRow);
  final headerNorm = headerLabels.map(_normHeader).toList();
  var itemCol = _matchHeaderIndex(headerNorm, _aliasesItemNumber);
  itemCol ??= 0;

  int? psFlagCol;
  int? nrFlagCol;
  for (var i = 0; i < headerNorm.length; i++) {
    final h = headerNorm[i];
    if (_aliasesPs.contains(h)) psFlagCol = i;
    if (_aliasesNewRelease.contains(h)) nrFlagCol = i;
  }

  final maxScanCol = rows.isEmpty
      ? 0
      : rows.map((e) => e.length).reduce((a, b) => a > b ? a : b);

  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    if (row.isEmpty || _isBlankRow(row, maxScanCol)) continue;

    final itemRaw = itemCol < row.length
        ? _itemNumberPlainFromData(row[itemCol]).trim()
        : '';
    if (itemRaw.isEmpty) continue;

    var include = true;
    if (label == 'PS' && psFlagCol != null && psFlagCol < row.length) {
      final flag = _plainFromData(row[psFlagCol]).trim();
      if (flag.isNotEmpty && !_truthyYes(flag)) include = false;
    }
    if (label == 'NewRelease' && nrFlagCol != null && nrFlagCol < row.length) {
      final flag = _plainFromData(row[nrFlagCol]).trim();
      if (flag.isNotEmpty && !_truthyYes(flag)) include = false;
    }

    if (!include) continue;

    final k = _itemNumberMatchKey(itemRaw);
    if (seen.add(k)) ordered.add(k);
  }

  return (orderedKeys: ordered, keySet: seen);
}

xlsx.CellValue _listPriceCell(_ProductsRow pr) {
  if (pr.hasListPriceValue && pr.listPriceNumeric != null) {
    return xlsx.DoubleCellValue(pr.listPriceNumeric!);
  }
  if (pr.listPriceText.isNotEmpty) {
    return _textCv(pr.listPriceText);
  }
  return _textCv('');
}

xlsx.CellValue? _priceCellForNewRow(_ProductsRow pr) {
  if (pr.priceNumeric != null) {
    return xlsx.DoubleCellValue(pr.priceNumeric!);
  }
  if (pr.priceText.isNotEmpty) return _textCv(pr.priceText);
  return null;
}

Map<String, int> _headerIndexMap(List<String> headers) {
  final m = <String, int>{};
  for (var i = 0; i < headers.length; i++) {
    m[_normHeader(headers[i])] = i;
  }
  return m;
}

void _copyQuoteSourceRow(
  List<xlsx.Data?> srcRow,
  List<String> quoteHeaderLabels,
  Map<String, int> hIndex,
  List<xlsx.CellValue?> dst,
) {
  for (var oc = 0; oc < quoteHeaderLabels.length; oc++) {
    final norm = _normHeader(quoteHeaderLabels[oc]);
    final di = hIndex[norm];
    if (di != null && oc < srcRow.length) {
      dst[di] = _cloneCellValue(srcRow[oc]?.value);
    }
  }
}

int _countYesInColumn(
  List<List<xlsx.CellValue?>> rows,
  int? col,
) {
  if (col == null || col < 0) return 0;
  var n = 0;
  for (final row in rows) {
    if (col >= row.length) continue;
    if (_truthyYes(_plainFromValue(row[col]))) n++;
  }
  return n;
}

List<xlsx.CellValue> _filledRow(List<xlsx.CellValue?> row) {
  return [for (final v in row) v ?? _textCv('')];
}

xlsx.Sheet? _resolveWarehouseInputSheet(xlsx.Excel excel, String diagLabel) {
  final named = _resolveSheetForRole(
    excel,
    const ['Sheet1', 'Data', 'Inventory', 'In Stock'],
    diagLabel,
  );
  if (named != null) return named;
  if (excel.tables.length == 1) {
    return excel[excel.tables.keys.first];
  }
  if (excel.tables.isNotEmpty) {
    final k = excel.tables.keys.first;
    _whseLog(
      '$diagLabel: using first workbook sheet "$k" (${excel.tables.length} total)',
    );
    return excel[k];
  }
  return null;
}

/// Reads Item Number column into a set (trimmed, case-insensitive key); duplicates ignored.
({Set<String> itemKeys, int rowsWithItem, int duplicateSkips})
_parseWarehouseItemNumberSet(xlsx.Sheet sheet, String diagLabel) {
  final rows = sheet.rows;
  if (rows.isEmpty) {
    _whseLog('$diagLabel: sheet has no rows');
    return (itemKeys: <String>{}, rowsWithItem: 0, duplicateSkips: 0);
  }
  final headerRow = rows.first;
  final headerLabels = _readHeaderStrings(headerRow);
  final headerNorm = headerLabels.map(_normHeader).toList();
  var itemCol = _matchHeaderIndex(headerNorm, _aliasesItemNumber);
  itemCol ??= 0;

  final maxScanCol = rows.isEmpty
      ? 0
      : rows.map((e) => e.length).reduce((a, b) => a > b ? a : b);

  final keys = <String>{};
  var rowsWithItem = 0;
  var duplicateSkips = 0;

  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    if (row.isEmpty || _isBlankRow(row, maxScanCol)) continue;

    final itemRaw = itemCol < row.length
        ? _itemNumberPlainFromData(row[itemCol]).trim()
        : '';
    if (itemRaw.isEmpty) continue;

    rowsWithItem++;
    final k = _itemNumberMatchKey(itemRaw);
    if (!keys.add(k)) duplicateSkips++;
  }

  _whseLog(
    '$diagLabel: unique item keys=${keys.length} rowsWithItem=$rowsWithItem '
    'duplicateSkips=$duplicateSkips',
  );
  return (itemKeys: keys, rowsWithItem: rowsWithItem, duplicateSkips: duplicateSkips);
}

/// Validates inputs and builds the output workbook bytes.
Future<MasterProductsBuildReport> runUpdatedMasterProductsBuild({
  required String quoteFilePath,
  required String productsFilePath,
  required String psFilePath,
  required String newReleaseFilePath,
  required String whse1InStockFilePath,
  required String whse2InStockFilePath,
  required String whse1OutOfStockFilePath,
  required String whse2OutOfStockFilePath,
  required String whse1ComingSoonFilePath,
  required String whse2ComingSoonFilePath,
}) async {
  _mbLog('start');
  try {
    final qBytes = await File(quoteFilePath).readAsBytes();
    final pBytes = await File(productsFilePath).readAsBytes();
    final sBytes = await File(psFilePath).readAsBytes();
    final nBytes = await File(newReleaseFilePath).readAsBytes();
    final whse1InBytes = await File(whse1InStockFilePath).readAsBytes();
    final whse2InBytes = await File(whse2InStockFilePath).readAsBytes();
    final whse1OutBytes = await File(whse1OutOfStockFilePath).readAsBytes();
    final whse2OutBytes = await File(whse2OutOfStockFilePath).readAsBytes();
    final whse1SoonBytes = await File(whse1ComingSoonFilePath).readAsBytes();
    final whse2SoonBytes = await File(whse2ComingSoonFilePath).readAsBytes();

    _mbLog(
      'source byte lengths quote=${qBytes.length} products=${pBytes.length} '
      'ps=${sBytes.length} newRelease=${nBytes.length}',
    );
    _whseLog(
      'warehouse byte lengths w1In=${whse1InBytes.length} w2In=${whse2InBytes.length} '
      'w1Out=${whse1OutBytes.length} w2Out=${whse2OutBytes.length} '
      'w1Soon=${whse1SoonBytes.length} w2Soon=${whse2SoonBytes.length}',
    );

    final quoteBook = xlsx.Excel.decodeBytes(qBytes);
    final productsBook = xlsx.Excel.decodeBytes(pBytes);
    final psBook = xlsx.Excel.decodeBytes(sBytes);
    final newBook = xlsx.Excel.decodeBytes(nBytes);
    final whse1InBook = xlsx.Excel.decodeBytes(whse1InBytes);
    final whse2InBook = xlsx.Excel.decodeBytes(whse2InBytes);
    final whse1OutBook = xlsx.Excel.decodeBytes(whse1OutBytes);
    final whse2OutBook = xlsx.Excel.decodeBytes(whse2OutBytes);
    final whse1SoonBook = xlsx.Excel.decodeBytes(whse1SoonBytes);
    final whse2SoonBook = xlsx.Excel.decodeBytes(whse2SoonBytes);

    _whseLog('parsed 6 warehouse workbooks from disk');

    final quoteSheet = _resolveSheetForRole(quoteBook, const ['Quote'], 'Quote');
    final productsSheet = _resolveSheetForRole(
      productsBook,
      const ['Products', 'Product'],
      'Products',
    );
    final psSheet = _resolveSheetForRole(psBook, const ['PS', 'Ps'], 'PS');
    final nrSheet = _resolveSheetForRole(
      newBook,
      const ['New Release', 'NewRelease'],
      'New Release',
    );

    if (quoteSheet == null) {
      return MasterProductsBuildReport(
        success: false,
        errorMessage: 'Quote workbook: no sheet named Quote (or single sheet).',
        bytes: null,
        startingQuoteDataRows: 0,
        removedRows: 0,
        listPriceUpdated: 0,
        psYesRows: 0,
        newReleaseYesRows: 0,
        addedFromNewRelease: 0,
        unmatchedNewReleaseNotInProducts: 0,
        unmatchedPsNotInProductsOrQuote: 0,
        finalDataRowCount: 0,
        exceptionRowCount: 0,
      );
    }
    if (productsSheet == null) {
      return MasterProductsBuildReport(
        success: false,
        errorMessage:
            'Products workbook: no sheet named Products (or single sheet).',
        bytes: null,
        startingQuoteDataRows: 0,
        removedRows: 0,
        listPriceUpdated: 0,
        psYesRows: 0,
        newReleaseYesRows: 0,
        addedFromNewRelease: 0,
        unmatchedNewReleaseNotInProducts: 0,
        unmatchedPsNotInProductsOrQuote: 0,
        finalDataRowCount: 0,
        exceptionRowCount: 0,
      );
    }
    if (psSheet == null) {
      return MasterProductsBuildReport(
        success: false,
        errorMessage: 'PS workbook: no sheet named PS (or single sheet).',
        bytes: null,
        startingQuoteDataRows: 0,
        removedRows: 0,
        listPriceUpdated: 0,
        psYesRows: 0,
        newReleaseYesRows: 0,
        addedFromNewRelease: 0,
        unmatchedNewReleaseNotInProducts: 0,
        unmatchedPsNotInProductsOrQuote: 0,
        finalDataRowCount: 0,
        exceptionRowCount: 0,
      );
    }
    if (nrSheet == null) {
      return MasterProductsBuildReport(
        success: false,
        errorMessage:
            'New Release workbook: no sheet named "New Release" (or single sheet).',
        bytes: null,
        startingQuoteDataRows: 0,
        removedRows: 0,
        listPriceUpdated: 0,
        psYesRows: 0,
        newReleaseYesRows: 0,
        addedFromNewRelease: 0,
        unmatchedNewReleaseNotInProducts: 0,
        unmatchedPsNotInProductsOrQuote: 0,
        finalDataRowCount: 0,
        exceptionRowCount: 0,
      );
    }

    final whse1InSheet =
        _resolveWarehouseInputSheet(whse1InBook, 'Whse 1 In Stock');
    final whse2InSheet =
        _resolveWarehouseInputSheet(whse2InBook, 'Whse 2 In Stock');
    final whse1OutSheet =
        _resolveWarehouseInputSheet(whse1OutBook, 'Whse 1 Out of Stock');
    final whse2OutSheet =
        _resolveWarehouseInputSheet(whse2OutBook, 'Whse 2 Out of Stock');
    final whse1SoonSheet =
        _resolveWarehouseInputSheet(whse1SoonBook, 'Whse 1 Coming Soon');
    final whse2SoonSheet =
        _resolveWarehouseInputSheet(whse2SoonBook, 'Whse 2 Coming Soon');

    if (whse1InSheet == null) {
      return MasterProductsBuildReport(
        success: false,
        errorMessage:
            'Whse 1 In Stock workbook: could not resolve a data sheet.',
        bytes: null,
        startingQuoteDataRows: 0,
        removedRows: 0,
        listPriceUpdated: 0,
        psYesRows: 0,
        newReleaseYesRows: 0,
        addedFromNewRelease: 0,
        unmatchedNewReleaseNotInProducts: 0,
        unmatchedPsNotInProductsOrQuote: 0,
        finalDataRowCount: 0,
        exceptionRowCount: 0,
      );
    }
    if (whse2InSheet == null) {
      return MasterProductsBuildReport(
        success: false,
        errorMessage:
            'Whse 2 In Stock workbook: could not resolve a data sheet.',
        bytes: null,
        startingQuoteDataRows: 0,
        removedRows: 0,
        listPriceUpdated: 0,
        psYesRows: 0,
        newReleaseYesRows: 0,
        addedFromNewRelease: 0,
        unmatchedNewReleaseNotInProducts: 0,
        unmatchedPsNotInProductsOrQuote: 0,
        finalDataRowCount: 0,
        exceptionRowCount: 0,
      );
    }
    if (whse1OutSheet == null) {
      return MasterProductsBuildReport(
        success: false,
        errorMessage:
            'Whse 1 Out of Stock workbook: could not resolve a data sheet.',
        bytes: null,
        startingQuoteDataRows: 0,
        removedRows: 0,
        listPriceUpdated: 0,
        psYesRows: 0,
        newReleaseYesRows: 0,
        addedFromNewRelease: 0,
        unmatchedNewReleaseNotInProducts: 0,
        unmatchedPsNotInProductsOrQuote: 0,
        finalDataRowCount: 0,
        exceptionRowCount: 0,
      );
    }
    if (whse2OutSheet == null) {
      return MasterProductsBuildReport(
        success: false,
        errorMessage:
            'Whse 2 Out of Stock workbook: could not resolve a data sheet.',
        bytes: null,
        startingQuoteDataRows: 0,
        removedRows: 0,
        listPriceUpdated: 0,
        psYesRows: 0,
        newReleaseYesRows: 0,
        addedFromNewRelease: 0,
        unmatchedNewReleaseNotInProducts: 0,
        unmatchedPsNotInProductsOrQuote: 0,
        finalDataRowCount: 0,
        exceptionRowCount: 0,
      );
    }
    if (whse1SoonSheet == null) {
      return MasterProductsBuildReport(
        success: false,
        errorMessage:
            'Whse 1 Coming Soon workbook: could not resolve a data sheet.',
        bytes: null,
        startingQuoteDataRows: 0,
        removedRows: 0,
        listPriceUpdated: 0,
        psYesRows: 0,
        newReleaseYesRows: 0,
        addedFromNewRelease: 0,
        unmatchedNewReleaseNotInProducts: 0,
        unmatchedPsNotInProductsOrQuote: 0,
        finalDataRowCount: 0,
        exceptionRowCount: 0,
      );
    }
    if (whse2SoonSheet == null) {
      return MasterProductsBuildReport(
        success: false,
        errorMessage:
            'Whse 2 Coming Soon workbook: could not resolve a data sheet.',
        bytes: null,
        startingQuoteDataRows: 0,
        removedRows: 0,
        listPriceUpdated: 0,
        psYesRows: 0,
        newReleaseYesRows: 0,
        addedFromNewRelease: 0,
        unmatchedNewReleaseNotInProducts: 0,
        unmatchedPsNotInProductsOrQuote: 0,
        finalDataRowCount: 0,
        exceptionRowCount: 0,
      );
    }

    final whse1InKeys =
        _parseWarehouseItemNumberSet(whse1InSheet, 'Whse 1 In Stock').itemKeys;
    final whse2InKeys =
        _parseWarehouseItemNumberSet(whse2InSheet, 'Whse 2 In Stock').itemKeys;
    final whse1OutKeys = _parseWarehouseItemNumberSet(
      whse1OutSheet,
      'Whse 1 Out of Stock',
    ).itemKeys;
    final whse2OutKeys = _parseWarehouseItemNumberSet(
      whse2OutSheet,
      'Whse 2 Out of Stock',
    ).itemKeys;
    final whse1SoonKeys = _parseWarehouseItemNumberSet(
      whse1SoonSheet,
      'Whse 1 Coming Soon',
    ).itemKeys;
    final whse2SoonKeys = _parseWarehouseItemNumberSet(
      whse2SoonSheet,
      'Whse 2 Coming Soon',
    ).itemKeys;

    final masterTextCleanup = _MasterTextCleanupTicker();
    final productsParse = _parseProductsSheet(productsSheet, masterTextCleanup);
    final productsMap = productsParse.map;
    final productsDup = productsParse.dupRows;

    final quoteRows = quoteSheet.rows;
    if (quoteRows.isEmpty) {
      return MasterProductsBuildReport(
        success: false,
        errorMessage: 'Quote sheet is empty.',
        bytes: null,
        startingQuoteDataRows: 0,
        removedRows: 0,
        listPriceUpdated: 0,
        psYesRows: 0,
        newReleaseYesRows: 0,
        addedFromNewRelease: 0,
        unmatchedNewReleaseNotInProducts: 0,
        unmatchedPsNotInProductsOrQuote: 0,
        finalDataRowCount: 0,
        exceptionRowCount: 0,
      );
    }

    final quoteHeaderLabels = _readHeaderStrings(quoteRows.first);
    final quoteHeaderNorm = quoteHeaderLabels.map(_normHeader).toList();
    final itemColQ = _matchHeaderIndex(quoteHeaderNorm, _aliasesItemNumber);

    if (itemColQ == null) {
      return MasterProductsBuildReport(
        success: false,
        errorMessage: 'Quote sheet: missing Item Number column.',
        bytes: null,
        startingQuoteDataRows: 0,
        removedRows: 0,
        listPriceUpdated: 0,
        psYesRows: 0,
        newReleaseYesRows: 0,
        addedFromNewRelease: 0,
        unmatchedNewReleaseNotInProducts: 0,
        unmatchedPsNotInProductsOrQuote: 0,
        finalDataRowCount: 0,
        exceptionRowCount: 0,
      );
    }

    final psParse = _parseFlagSheet(psSheet, 'PS');
    final psKeys = psParse.keySet;
    final nrParse = _parseFlagSheet(nrSheet, 'NewRelease');
    final nrOrdered = nrParse.orderedKeys;
    final nrKeys = nrParse.keySet;

    _mbLog(
      'source row counts quoteRows=${quoteRows.length} '
      'products=${productsMap.length} psFlags=${psKeys.length} '
      'newRelease=${nrKeys.length}',
    );

    final quoteDupTracker = <String, List<int>>{};
    var startingDataRows = 0;
    for (var r = 1; r < quoteRows.length; r++) {
      final row = quoteRows[r];
      if (row.isEmpty) continue;
      final itemRaw = itemColQ < row.length
          ? _itemNumberPlainFromData(row[itemColQ]).trim()
          : '';
      if (itemRaw.isEmpty) continue;
      startingDataRows++;
      final k = _itemNumberMatchKey(itemRaw);
      quoteDupTracker.putIfAbsent(k, () => []).add(r + 1);
    }

    final quoteDupKeys =
        quoteDupTracker.entries.where((e) => e.value.length > 1).toList();

    final productDupKeys =
        productsDup.entries.where((e) => e.value.length > 1).toList();

    final exceptions = <List<String>>[];

    for (final e in quoteDupKeys) {
      exceptions.add([
        'Duplicate Item Number in Quote',
        e.key,
        e.value.join(', '),
      ]);
    }
    for (final e in productDupKeys) {
      exceptions.add([
        'Duplicate Item Number in Products',
        e.key,
        e.value.join(', '),
      ]);
    }

    var nrMissingProducts = 0;
    for (final k in nrKeys) {
      if (!productsMap.containsKey(k)) {
        nrMissingProducts++;
        exceptions.add(['New Release item not in Products', k, '']);
      }
    }

    var psMissingProducts = 0;
    for (final k in psKeys) {
      if (!productsMap.containsKey(k)) {
        psMissingProducts++;
        exceptions.add(['PS item not in Products', k, '']);
      }
    }

    final originalQuoteKeys = <String>{};
    for (var r = 1; r < quoteRows.length; r++) {
      final srcRow = quoteRows[r];
      if (srcRow.isEmpty) continue;
      final itemRaw = itemColQ < srcRow.length
          ? _itemNumberPlainFromData(srcRow[itemColQ]).trim()
          : '';
      if (itemRaw.isEmpty) continue;
      originalQuoteKeys.add(_itemNumberMatchKey(itemRaw));
    }

    for (var r = 1; r < quoteRows.length; r++) {
      final row = quoteRows[r];
      if (row.isEmpty) continue;
      final itemRaw = itemColQ < row.length
          ? _itemNumberPlainFromData(row[itemColQ]).trim()
          : '';
      if (itemRaw.isEmpty) continue;
      final k = _itemNumberMatchKey(itemRaw);
      final pr = productsMap[k];
      if (pr != null && !pr.hasListPriceValue) {
        exceptions.add([
          'Missing List Price in Products (matched Quote item)',
          k,
          'Quote row ${r + 1}',
        ]);
      }
    }

    var psNotInQuoteNoNr = 0;
    for (final k in psKeys) {
      if (!productsMap.containsKey(k)) continue;
      if (originalQuoteKeys.contains(k)) continue;
      if (nrKeys.contains(k)) continue;
      psNotInQuoteNoNr++;
    }

    _mbLog(
      'validation counts quoteDup=${quoteDupKeys.length} '
      'productsDup=${productDupKeys.length} nrNotInProducts=$nrMissingProducts '
      'psNotInProducts=$psMissingProducts psNotMappedToQuote=$psNotInQuoteNoNr',
    );

    final outHeaders = List<String>.from(quoteHeaderLabels);
    if (!_headerIndexMap(outHeaders).containsKey('listprice')) {
      outHeaders.add('List Price');
    }
    if (!_headerIndexMap(outHeaders).containsKey('ps')) {
      outHeaders.add('PS');
    }
    if (!_headerIndexMap(outHeaders).containsKey('newrelease')) {
      outHeaders.add('New Release');
    }

    for (final label in [
      _kOutWhse1InStock,
      _kOutWhse2InStock,
      _kOutWhse1OutOfStock,
      _kOutWhse2OutOfStock,
      _kOutWhse1ComingSoon,
      _kOutWhse2ComingSoon,
    ]) {
      final nk = _normHeader(label);
      final cur = _headerIndexMap(outHeaders);
      if (!cur.containsKey(nk)) {
        outHeaders.add(label);
        _mbLog('appended output column: $label');
      } else {
        _mbLog('output column already present (warehouse): $label');
      }
    }

    final hIndex = _headerIndexMap(outHeaders);
    final idxListPrice = _matchOutputColumn(hIndex, _aliasesListPrice);
    final idxPs = _matchOutputColumn(hIndex, _aliasesPs);
    final idxNr = _matchOutputColumn(hIndex, _aliasesNewRelease);
    final idxDiscount = _matchOutputColumn(hIndex, const {'discount'});
    final idxNet = _matchOutputColumn(hIndex, const {'net'});
    final idxDesc = _matchOutputColumn(hIndex, _aliasesDescription);
    final idxUpc = _matchOutputColumn(hIndex, _aliasesUpc);
    final idxPrice = _matchOutputColumn(hIndex, _aliasesPrice);
    final idxPt = _matchOutputColumn(hIndex, _aliasesProductType);
    final idxCat = _matchOutputColumn(hIndex, _aliasesCategory);
    final idxSub = _matchOutputColumn(hIndex, _aliasesSubCategory);
    final idxMoq = _matchOutputColumn(hIndex, _aliasesMoq);
    final idxCase = _matchOutputColumn(hIndex, _aliasesCaseQty);
    final idxItemNumber = _matchOutputColumn(hIndex, _aliasesItemNumber);
    final idxWhse1In = _matchOutputColumn(hIndex, _aliasesWhse1InStock);
    final idxWhse2In = _matchOutputColumn(hIndex, _aliasesWhse2InStock);
    final idxWhse1Out = _matchOutputColumn(hIndex, _aliasesWhse1OutOfStock);
    final idxWhse2Out = _matchOutputColumn(hIndex, _aliasesWhse2OutOfStock);
    final idxWhse1Soon = _matchOutputColumn(hIndex, _aliasesWhse1ComingSoon);
    final idxWhse2Soon = _matchOutputColumn(hIndex, _aliasesWhse2ComingSoon);
    _mbLog(
      'warehouse column indices: '
      'W1In=$idxWhse1In W2In=$idxWhse2In W1Out=$idxWhse1Out W2Out=$idxWhse2Out '
      'W1Soon=$idxWhse1Soon W2Soon=$idxWhse2Soon',
    );

    final outRows = <List<xlsx.CellValue?>>[];

    var removed = 0;
    var listUpdated = 0;

    for (var r = 1; r < quoteRows.length; r++) {
      final srcRow = quoteRows[r];
      if (srcRow.isEmpty) continue;

      final nCols = outHeaders.length;
      final dst = List<xlsx.CellValue?>.filled(nCols, null);

      final itemRaw = itemColQ < srcRow.length
          ? _itemNumberPlainFromData(srcRow[itemColQ]).trim()
          : '';
      if (itemRaw.isEmpty) {
        _copyQuoteSourceRow(srcRow, quoteHeaderLabels, hIndex, dst);
        _repairMasterTextColumnsInDst(
          dst,
          idxDesc: idxDesc,
          idxPt: idxPt,
          idxCat: idxCat,
          idxSub: idxSub,
          cleanup: masterTextCleanup,
        );
        outRows.add(dst);
        continue;
      }

      final itemKey = _itemNumberMatchKey(itemRaw);
      final pr = productsMap[itemKey];
      if (pr == null) {
        removed++;
        continue;
      }

      _copyQuoteSourceRow(srcRow, quoteHeaderLabels, hIndex, dst);
      _repairMasterTextColumnsInDst(
        dst,
        idxDesc: idxDesc,
        idxPt: idxPt,
        idxCat: idxCat,
        idxSub: idxSub,
        cleanup: masterTextCleanup,
      );

      if (idxListPrice != null) {
        dst[idxListPrice] = _listPriceCell(pr);
        if (pr.hasListPriceValue) listUpdated++;
      }

      if (idxPs != null && psKeys.contains(itemKey)) {
        dst[idxPs] = _textCv('YES');
      }

      if (idxNr != null && nrKeys.contains(itemKey)) {
        dst[idxNr] = _textCv('YES');
      }

      if (idxWhse1In != null && whse1InKeys.contains(itemKey)) {
        dst[idxWhse1In] = _textCv('YES');
      }
      if (idxWhse2In != null && whse2InKeys.contains(itemKey)) {
        dst[idxWhse2In] = _textCv('YES');
      }
      if (idxWhse1Out != null && whse1OutKeys.contains(itemKey)) {
        dst[idxWhse1Out] = _textCv('YES');
      }
      if (idxWhse2Out != null && whse2OutKeys.contains(itemKey)) {
        dst[idxWhse2Out] = _textCv('YES');
      }
      if (idxWhse1Soon != null && whse1SoonKeys.contains(itemKey)) {
        dst[idxWhse1Soon] = _textCv('YES');
      }
      if (idxWhse2Soon != null && whse2SoonKeys.contains(itemKey)) {
        dst[idxWhse2Soon] = _textCv('YES');
      }

      outRows.add(dst);
    }

    var addedNr = 0;
    for (final k in nrOrdered) {
      if (originalQuoteKeys.contains(k)) continue;
      final pr = productsMap[k];
      if (pr == null) continue;

      final nCols = outHeaders.length;
      final dst = List<xlsx.CellValue?>.filled(nCols, null);

      if (idxItemNumber != null) {
        dst[idxItemNumber] = _textCv(pr.itemDisplay);
      }
      if (idxDesc != null && pr.description.isNotEmpty) {
        dst[idxDesc] = _textCv(pr.description);
      }
      if (idxUpc != null && pr.upc.isNotEmpty) {
        dst[idxUpc] = _textCv(pr.upc);
      }
      if (idxListPrice != null) {
        dst[idxListPrice] = _listPriceCell(pr);
        if (pr.hasListPriceValue) listUpdated++;
      }
      if (idxDiscount != null) dst[idxDiscount] = _textCv('');
      if (idxNet != null) dst[idxNet] = _textCv('');
      if (idxPs != null) {
        dst[idxPs] = psKeys.contains(k) ? _textCv('YES') : _textCv('');
      }
      if (idxNr != null) dst[idxNr] = _textCv('YES');
      if (idxPrice != null) {
        final pc = _priceCellForNewRow(pr);
        if (pc != null) dst[idxPrice] = pc;
      }
      if (idxPt != null && pr.productType.isNotEmpty) {
        dst[idxPt] = _textCv(pr.productType);
      }
      if (idxCat != null && pr.category.isNotEmpty) {
        dst[idxCat] = _textCv(pr.category);
      }
      if (idxSub != null && pr.subCategory.isNotEmpty) {
        dst[idxSub] = _textCv(pr.subCategory);
      }
      if (idxMoq != null && pr.minOrderQtyText.isNotEmpty) {
        dst[idxMoq] = _textCv(pr.minOrderQtyText);
      }
      if (idxCase != null && pr.caseQtyText.isNotEmpty) {
        dst[idxCase] = _textCv(pr.caseQtyText);
      }

      if (idxWhse1In != null && whse1InKeys.contains(k)) {
        dst[idxWhse1In] = _textCv('YES');
      }
      if (idxWhse2In != null && whse2InKeys.contains(k)) {
        dst[idxWhse2In] = _textCv('YES');
      }
      if (idxWhse1Out != null && whse1OutKeys.contains(k)) {
        dst[idxWhse1Out] = _textCv('YES');
      }
      if (idxWhse2Out != null && whse2OutKeys.contains(k)) {
        dst[idxWhse2Out] = _textCv('YES');
      }
      if (idxWhse1Soon != null && whse1SoonKeys.contains(k)) {
        dst[idxWhse1Soon] = _textCv('YES');
      }
      if (idxWhse2Soon != null && whse2SoonKeys.contains(k)) {
        dst[idxWhse2Soon] = _textCv('YES');
      }

      outRows.add(dst);
      addedNr++;
    }

    final psYes = _countYesInColumn(outRows, idxPs);
    final nrYes = _countYesInColumn(outRows, idxNr);
    final finalCount = outRows.length;

    final unmatchedPs =
        psMissingProducts + psNotInQuoteNoNr;

    _mbLog(
      'removed rows=$removed list price updates=$listUpdated '
      'PS YES rows=$psYes New Release YES rows=$nrYes '
      'added NR rows=$addedNr final data rows=$finalCount',
    );
    _mbLog(
      'master text cells cleaned (mojibake/diacritics/trim): '
      '${masterTextCleanup.changedCells}',
    );

    final excel = xlsx.Excel.createExcel();
    final defName = excel.getDefaultSheet() ?? excel.tables.keys.first;
    excel.rename(defName, 'Quote');
    final qOut = excel['Quote'];

    qOut.appendRow([for (final h in outHeaders) _textCv(h)]);
    for (final line in outRows) {
      qOut.appendRow(_filledRow(line));
    }

    final sum = excel['Summary'];
    sum.appendRow([_textCv('Metric'), _textCv('Value')]);
    void sumRow(String a, String b) {
      sum.appendRow([_textCv(a), _textCv(b)]);
    }

    sumRow('Starting Quote row count', startingDataRows.toString());
    sumRow('Removed rows count', removed.toString());
    sumRow('List Price updated count', listUpdated.toString());
    sumRow('PS YES count', psYes.toString());
    sumRow('New Release YES count', nrYes.toString());
    sumRow('New rows added from New Release count', addedNr.toString());
    sumRow(
      'Duplicate Item Number keys in Quote',
      quoteDupKeys.length.toString(),
    );
    sumRow(
      'Duplicate Item Number keys in Products',
      productDupKeys.length.toString(),
    );
    sumRow(
      'When Products has duplicate Item Numbers',
      'first row wins (lowest sheet row index); see Exceptions for row numbers',
    );
    sumRow(
      'Unmatched New Release items not found in Products count',
      nrMissingProducts.toString(),
    );
    sumRow(
      'Unmatched PS items not found in Products/Quote count',
      unmatchedPs.toString(),
    );

    final ex = excel['Exceptions'];
    ex.appendRow([
      _textCv('Exception type'),
      _textCv('Item or key'),
      _textCv('Detail'),
    ]);
    for (final row in exceptions) {
      ex.appendRow([
        _textCv(row[0]),
        _textCv(row[1]),
        _textCv(row.length > 2 ? row[2] : ''),
      ]);
    }

    _mbLog('excel.encode() start');
    final bytes = excel.encode();
    final ok = bytes != null && bytes.isNotEmpty;
    _mbLog('excel.encode() done ok=$ok bytes=${bytes?.length ?? 0}');

    if (!ok) {
      return MasterProductsBuildReport(
        success: false,
        errorMessage: 'Excel encode returned no data.',
        bytes: null,
        startingQuoteDataRows: startingDataRows,
        removedRows: removed,
        listPriceUpdated: listUpdated,
        psYesRows: psYes,
        newReleaseYesRows: nrYes,
        addedFromNewRelease: addedNr,
        unmatchedNewReleaseNotInProducts: nrMissingProducts,
        unmatchedPsNotInProductsOrQuote: unmatchedPs,
        finalDataRowCount: finalCount,
        exceptionRowCount: exceptions.length,
      );
    }

    return MasterProductsBuildReport(
      success: true,
      errorMessage: null,
      bytes: bytes,
      startingQuoteDataRows: startingDataRows,
      removedRows: removed,
      listPriceUpdated: listUpdated,
      psYesRows: psYes,
      newReleaseYesRows: nrYes,
      addedFromNewRelease: addedNr,
      unmatchedNewReleaseNotInProducts: nrMissingProducts,
      unmatchedPsNotInProductsOrQuote: unmatchedPs,
      finalDataRowCount: finalCount,
      exceptionRowCount: exceptions.length,
    );
  } catch (e, st) {
    _mbLog('error $e\n$st');
    return MasterProductsBuildReport(
      success: false,
      errorMessage: e.toString(),
      bytes: null,
      startingQuoteDataRows: 0,
      removedRows: 0,
      listPriceUpdated: 0,
      psYesRows: 0,
      newReleaseYesRows: 0,
      addedFromNewRelease: 0,
      unmatchedNewReleaseNotInProducts: 0,
      unmatchedPsNotInProductsOrQuote: 0,
      finalDataRowCount: 0,
      exceptionRowCount: 0,
    );
  }
}

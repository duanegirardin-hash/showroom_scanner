// Showroom Scanner - sound paths: use sounds/... with prefix assets/ to avoid double assets/ (2025-03-11)
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Master switch for temporary scan-tab profiling (Steps 3–5).
/// When `true` (debug builds only): `REBUILD_INSTRUMENT`, `SETSTATE_TRACE[...]`, and
/// `SCAN_PATH[...]` logs are printed. When `false`, all of that code stays in place but is silent.
const bool _kScanRebuildInstrumentationEnabled = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const ShowroomScannerApp());
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

// --- Phase 1: theme tokens (visual only; no app logic) ---
const Color _kDeepTeal = Color(0xFF006D77);
const Color _kWarmCoral = Color(0xFFFF7F50);
const Color _kSuccessGreen = Color(0xFF2E7D32);
const Color _kScaffoldBackground = Color(0xFFF8F6F3);
const Color _kSurfaceCard = Color(0xFFFFFFFF);
const Color _kHeadingText = Color(0xFF1F2529);
const Color _kSecondaryText = Color(0xFF5F6368);
const Color _kDividerWarm = Color(0xFFC9C5C0);
const Color _kDividerWarmSoft = Color(0xFFE5E2DE);

class ShowroomScannerApp extends StatelessWidget {
  const ShowroomScannerApp({super.key});

  static ThemeData get _showroomTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _kDeepTeal,
      brightness: Brightness.light,
    ).copyWith(
      primary: _kDeepTeal,
      onPrimary: Colors.white,
      secondary: _kWarmCoral,
      onSecondary: Colors.white,
      tertiary: _kSuccessGreen,
      onTertiary: Colors.white,
      surface: _kSurfaceCard,
      onSurface: _kHeadingText,
      onSurfaceVariant: _kSecondaryText,
      outline: _kDividerWarm,
      outlineVariant: _kDividerWarmSoft,
    );

    final filledShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
    );

    final textTheme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    ).textTheme.apply(
      bodyColor: _kHeadingText,
      displayColor: _kHeadingText,
    ).copyWith(
      headlineLarge: const TextStyle(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: _kHeadingText,
      ),
      headlineMedium: const TextStyle(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.25,
        color: _kHeadingText,
      ),
      headlineSmall: const TextStyle(
        fontWeight: FontWeight.w600,
        color: _kHeadingText,
      ),
      titleLarge: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 22,
        height: 1.25,
        letterSpacing: -0.2,
        color: _kHeadingText,
      ),
      titleMedium: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 16,
        height: 1.3,
        color: _kHeadingText,
      ),
      titleSmall: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        height: 1.3,
        color: _kHeadingText,
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        height: 1.45,
        color: _kHeadingText,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        height: 1.4,
        color: _kSecondaryText,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.35,
        color: _kSecondaryText.withValues(alpha: 0.95),
      ),
      labelLarge: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        letterSpacing: 0.15,
        color: _kHeadingText,
      ),
      labelMedium: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 12,
        color: _kSecondaryText,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _kScaffoldBackground,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: _kSurfaceCard,
        elevation: 1,
        shadowColor: const Color(0x331F2529),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: filledShape,
          elevation: 0,
          foregroundColor: colorScheme.onPrimary,
          backgroundColor: colorScheme.primary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: filledShape,
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outline, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: inputBorder,
        enabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600);
          }
          return TextStyle(color: colorScheme.onSurfaceVariant);
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
        dividerColor: colorScheme.outlineVariant,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: textTheme.titleSmall,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Showroom Scanner',
      debugShowCheckedModeBanner: false,
      theme: _showroomTheme,
      home: const ScannerHomePage(),
    );
  }
}

class Product {
  final String itemNumber;
  final String description;
  final String upc;
  final double price;
  final String productType;
  final String discountRaw;
  final bool discountEligible;
  final String category;
  final String subCategory;
  final int minOrderQty;
  final int caseQty;

  Product({
    required this.itemNumber,
    required this.description,
    required this.upc,
    required this.price,
    required this.productType,
    required this.discountRaw,
    required this.discountEligible,
    required this.category,
    required this.subCategory,
    required this.minOrderQty,
    required this.caseQty,
  });
}

class QuoteBucketDefinition {
  final String bucketKey;
  final String displayLabel;

  const QuoteBucketDefinition({
    required this.bucketKey,
    required this.displayLabel,
  });
}

class OrderLine {
  final Product product;
  int quantity;
  int scans;

  OrderLine({
    required this.product,
    required this.quantity,
    required this.scans,
  });
}

/// Single path segment for export filenames (Windows / cross-platform safe).
String _sanitizeOrderExportCustomerSegment(String name) {
  final t = name.trim();
  if (t.isEmpty) return 'Unknown';
  var s = t.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return 'Unknown';
  return s.length > 120 ? s.substring(0, 120) : s;
}

/// `Order_{customerName}_{yyyy-MM-dd}.csv`
String orderExportFilename({
  required String customerDisplayName,
  required DateTime exportedOn,
}) {
  final seg = _sanitizeOrderExportCustomerSegment(customerDisplayName);
  final d = exportedOn;
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return 'Order_${seg}_$y-$m-$day.csv';
}

/// Data rows only (no header). Caller builds header `Item,Quantity` via [orderExportCsvRows].
List<List<String>> orderExportAggregatedItemRows({
  required List<OrderLine> orderLines,
  required String Function(Product) exportItemLabel,
  required String Function(Product) exportAggregationKey,
}) {
  final totals = <String, int>{};
  final keyToLabel = <String, String>{};
  for (final line in orderLines) {
    final key = exportAggregationKey(line.product);
    totals[key] = (totals[key] ?? 0) + line.quantity;
    keyToLabel.putIfAbsent(key, () => exportItemLabel(line.product));
  }
  final sortedKeys = keyToLabel.keys.toList()..sort();
  return [
    for (final k in sortedKeys) [keyToLabel[k]!, totals[k]!.toString()],
  ];
}

/// Full CSV matrix: header row is exactly `Item` / `Quantity`.
List<List<String>> orderExportCsvRows({
  required List<OrderLine> orderLines,
  required String Function(Product) exportItemLabel,
  required String Function(Product) exportAggregationKey,
}) {
  return [
    const ['Item', 'Quantity'],
    ...orderExportAggregatedItemRows(
      orderLines: orderLines,
      exportItemLabel: exportItemLabel,
      exportAggregationKey: exportAggregationKey,
    ),
  ];
}

// --- Order import from CSV (Item,Quantity; header row ignored) ---

/// Single usable data row after CSV parsing (header excluded).
class OrderImportCsvRow {
  final String item;
  final int quantity;

  const OrderImportCsvRow({
    required this.item,
    required this.quantity,
  });
}

/// Represents one row that could not be imported and why.
class OrderImportSkippedRow {
  final String item;
  final String quantity;
  final String reason;

  const OrderImportSkippedRow({
    required this.item,
    required this.quantity,
    required this.reason,
  });
}

/// Result of scanning CSV text for import rows (malformed rows counted separately).
class OrderImportCsvParseOutcome {
  final List<OrderImportCsvRow> rows;
  final List<OrderImportSkippedRow> skippedRows;

  const OrderImportCsvParseOutcome({
    required this.rows,
    required this.skippedRows,
  });
}

class OrderImportApplyOutcome {
  final int importedRows;
  final int moqAdjustedRows;
  final Map<String, int> importedQuantityByBucket;
  final List<OrderImportSkippedRow> skippedRows;

  const OrderImportApplyOutcome({
    required this.importedRows,
    required this.moqAdjustedRows,
    required this.importedQuantityByBucket,
    required this.skippedRows,
  });
}

String _orderImportNormalizeItemKey(String value) => value.trim().toUpperCase();

String _orderImportNormalizeUpcLookupKey(String value) {
  final trimmed = value.trim();
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '').trim();
  return digits.isNotEmpty ? digits : trimmed.toUpperCase();
}

/// Reads [rawCsv], skips the first row (header), trims fields, skips empty rows.
/// Throws [FormatException] when the file is empty, unparseable, or has no data rows after the header.
OrderImportCsvParseOutcome parseOrderImportCsv(String rawCsv) {
  final trimmed = rawCsv.trim();
  if (trimmed.isEmpty) {
    throw FormatException('CSV file is empty.');
  }
  final List<List<dynamic>> rows;
  try {
    rows = const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(rawCsv);
  } catch (e) {
    throw FormatException('Invalid CSV: $e');
  }
  if (rows.isEmpty) {
    throw FormatException('CSV has no rows.');
  }
  if (rows.length < 2) {
    throw FormatException('CSV has no data rows (only a header).');
  }

  final list = <OrderImportCsvRow>[];
  final skippedRows = <OrderImportSkippedRow>[];

  for (int i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.isEmpty) {
      skippedRows.add(
        const OrderImportSkippedRow(
          item: '',
          quantity: '',
          reason: 'Malformed row: empty row.',
        ),
      );
      continue;
    }
    if (row.every((c) => c.toString().trim().isEmpty)) {
      skippedRows.add(
        const OrderImportSkippedRow(
          item: '',
          quantity: '',
          reason: 'Malformed row: all fields empty.',
        ),
      );
      continue;
    }
    if (row.length < 2) {
      final itemOnly = row[0].toString().trim();
      skippedRows.add(
        OrderImportSkippedRow(
          item: itemOnly,
          quantity: '',
          reason: 'Malformed row: missing Quantity column.',
        ),
      );
      continue;
    }
    final item = row[0].toString().trim();
    final qtyStr = row[1].toString().trim();
    if (item.isEmpty) {
      skippedRows.add(
        OrderImportSkippedRow(
          item: '',
          quantity: qtyStr,
          reason: 'Empty item.',
        ),
      );
      continue;
    }
    final qty = int.tryParse(qtyStr);
    if (qty == null || qty < 1) {
      skippedRows.add(
        OrderImportSkippedRow(
          item: item,
          quantity: qtyStr,
          reason: 'Invalid quantity.',
        ),
      );
      continue;
    }
    list.add(OrderImportCsvRow(item: item, quantity: qty));
  }

  if (list.isEmpty) {
    throw FormatException(
      'No valid data rows with Item and a positive Quantity.',
    );
  }

  return OrderImportCsvParseOutcome(
    rows: list,
    skippedRows: skippedRows,
  );
}

/// Match import label to catalog: [Product.itemNumber] first, then [Product.upc].
Product? matchOrderImportProduct(
  String itemLabel,
  Map<String, Product> productsByItemNumber,
  Map<String, Product> productsByUpc,
) {
  final itemKey = _orderImportNormalizeItemKey(itemLabel);
  if (itemKey.isEmpty) return null;

  final byItem = productsByItemNumber[itemKey];
  if (byItem != null) return byItem;

  final upc = _orderImportNormalizeUpcLookupKey(itemLabel);
  if (upc.isEmpty) return null;

  Product? product = productsByUpc[upc];
  if (product == null && upc.length == 12 && upc.startsWith('0')) {
    product = productsByUpc[upc.substring(1)];
  }
  if (product == null && upc.length == 11) {
    product = productsByUpc['0$upc'];
  }
  return product;
}

Future<File> saveOrderExportCsv({
  required String directoryPath,
  required String filename,
  required String csvText,
}) async {
  final fullPath = p.join(directoryPath, filename);
  final file = File(fullPath);
  await file.writeAsString(csvText);
  return file;
}

/// If [filename] already exists in [directoryPath], appends `_2`, `_3`, … before `.csv`.
Future<String> uniqueCsvFilenameInDirectory(
  String directoryPath,
  String filename,
) async {
  const ext = '.csv';
  if (!filename.toLowerCase().endsWith(ext)) return filename;
  final stem = filename.substring(0, filename.length - ext.length);
  var candidate = filename;
  var n = 2;
  while (await File(p.join(directoryPath, candidate)).exists()) {
    candidate = '${stem}_$n$ext';
    n++;
  }
  return candidate;
}

/// Fixed root under the platform "Documents" area: `Documents/Showroom_Exports/...` on Android
/// (public Documents); app documents directory on other platforms.
const String kShowroomExportsRootFolderName = 'Showroom_Exports';

/// Fallback folder name when the customer name is blank after trimming.
const String kNoCustomerExportFolderName = 'No_Customer';

/// Single path segment for a customer subfolder under the designated export base.
/// Trims edges, replaces invalid filename characters with `_`, uses [kNoCustomerExportFolderName] when empty.
String sanitizeCustomerExportFolderName(String name) {
  final t = name.trim();
  if (t.isEmpty) return kNoCustomerExportFolderName;
  var s = t.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
  s = s.trim();
  if (s.isEmpty) return kNoCustomerExportFolderName;
  if (s.length > 120) s = s.substring(0, 120);
  return s;
}

/// Ensures `[exportBasePath]/[sanitized customer folder]/` exists and returns it.
Future<Directory> ensureOrderExportCustomerDirectory({
  required String exportBasePath,
  required String customerDisplayName,
}) async {
  final folderName = sanitizeCustomerExportFolderName(customerDisplayName);
  final fullPath = p.join(exportBasePath, folderName);
  final dir = Directory(fullPath);
  await dir.create(recursive: true);
  return dir;
}

/// Resolves the directory and writes the CSV there (same format as [saveOrderExportCsv]).
Future<File> writeOrderExportCsvUnderDesignatedBase({
  required String exportBasePath,
  required String customerDisplayName,
  required String filename,
  required String csvText,
}) async {
  final customerDir = await ensureOrderExportCustomerDirectory(
    exportBasePath: exportBasePath,
    customerDisplayName: customerDisplayName,
  );
  final uniqueName = await uniqueCsvFilenameInDirectory(
    customerDir.path,
    filename,
  );
  return saveOrderExportCsv(
    directoryPath: customerDir.path,
    filename: uniqueName,
    csvText: csvText,
  );
}

const _androidPublicDocumentsChannel = MethodChannel(
  'com.example.showroom_scanner/documents',
);

/// Android: `Documents/Showroom_Exports/[customerFolder]/[filename]` via platform channel.
/// [sanitizedCustomerFolderName] must be a single path segment (from [sanitizeCustomerExportFolderName]).
Future<File> saveOrderExportCsvToAndroidPublicShowroomExports({
  required String sanitizedCustomerFolderName,
  required String filename,
  required String csvText,
}) async {
  if (!Platform.isAndroid) {
    throw UnsupportedError(
      'saveOrderExportCsvToAndroidPublicShowroomExports is Android-only',
    );
  }
  final path = await _androidPublicDocumentsChannel.invokeMethod<String>(
    'savePublicCsvInShowroomExports',
    <String, dynamic>{
      'customerFolder': sanitizedCustomerFolderName,
      'filename': filename,
      'content': csvText,
    },
  );
  if (path == null || path.isEmpty) {
    throw StateError('savePublicCsvInShowroomExports returned no path');
  }
  return File(path);
}

/// Ensures `[getApplicationDocumentsDirectory]/Showroom_Exports` exists (non-Android export root).
Future<Directory> ensureLocalShowroomExportsRootDirectory() async {
  final base = await getApplicationDocumentsDirectory();
  final root = Directory(p.join(base.path, kShowroomExportsRootFolderName));
  await root.create(recursive: true);
  return root;
}

/// Writes order CSV to `Showroom_Exports/<customer>/` under the platform documents area.
Future<File> exportOrderCsvToShowroomExportsLayout({
  required String customerDisplayName,
  required String filename,
  required String csvText,
}) async {
  if (Platform.isAndroid) {
    final folder = sanitizeCustomerExportFolderName(customerDisplayName);
    return saveOrderExportCsvToAndroidPublicShowroomExports(
      sanitizedCustomerFolderName: folder,
      filename: filename,
      csvText: csvText,
    );
  }
  final root = await ensureLocalShowroomExportsRootDirectory();
  return writeOrderExportCsvUnderDesignatedBase(
    exportBasePath: root.path,
    customerDisplayName: customerDisplayName,
    filename: filename,
    csvText: csvText,
  );
}

enum ScanFeedbackType {
  none,
  successNewItem,
  successExistingItem,
  notFound,
}

/// Lifecycle for saved quotes (active workspace vs archive).
enum QuoteLifecycleStatus {
  active,
  archived,
  confirmed,
}

List<String> _stringListFromJsonField(dynamic v) {
  if (v is! List) return [];
  final out = <String>[];
  for (final e in v) {
    if (e == null) continue;
    final s = e.toString();
    if (s.isNotEmpty) out.add(s);
  }
  return out;
}

String _quoteIdFromJsonField(dynamic raw) {
  if (raw == null) return '';
  if (raw is String) return raw.trim();
  return raw.toString();
}

QuoteLifecycleStatus quoteLifecycleStatusFromJson(dynamic raw) {
  if (raw == null) return QuoteLifecycleStatus.active;
  if (raw is! String) return QuoteLifecycleStatus.active;
  switch (raw.toLowerCase().trim()) {
    case 'archived':
      return QuoteLifecycleStatus.archived;
    case 'confirmed':
      return QuoteLifecycleStatus.confirmed;
    case 'active':
    default:
      return QuoteLifecycleStatus.active;
  }
}

String quoteLifecycleStatusToJson(QuoteLifecycleStatus s) {
  switch (s) {
    case QuoteLifecycleStatus.active:
      return 'active';
    case QuoteLifecycleStatus.archived:
      return 'archived';
    case QuoteLifecycleStatus.confirmed:
      return 'confirmed';
  }
}

enum _ArchiveDeleteConfirmKind {
  singleArchived,
  singleConfirmed,
  purgeArchived,
  purgeConfirmed,
}

/// Saved quote entry in the index (for Load Quote list).
class SavedQuoteInfo {
  final String id;
  final String name;
  final String customerName;
  final String customerId;
  final String quoteBucketKey;
  final String quoteBucketLabel;
  final DateTime updatedAt;
  final QuoteLifecycleStatus status;
  final DateTime? exportedAt;
  final DateTime? confirmedAt;
  final List<String> exportedFilePaths;
  final List<String> exportedFileNames;

  SavedQuoteInfo({
    required this.id,
    required this.name,
    required this.customerName,
    required this.customerId,
    required this.quoteBucketKey,
    required this.quoteBucketLabel,
    required this.updatedAt,
    this.status = QuoteLifecycleStatus.active,
    this.exportedAt,
    this.confirmedAt,
    this.exportedFilePaths = const [],
    this.exportedFileNames = const [],
  });

  factory SavedQuoteInfo.fromJson(Map<String, dynamic> json) {
    final statusRaw = json['quoteStatus'] ?? json['status'];
    return SavedQuoteInfo(
      id: _quoteIdFromJsonField(json['id']),
      name: (json['name'] as String?)?.trim() ?? '',
      customerName: (json['customerName'] as String?)?.trim() ?? '',
      customerId: (json['customerId'] as String?)?.trim() ?? '',
      quoteBucketKey: (json['quoteBucketKey'] as String?)?.trim() ?? '',
      quoteBucketLabel: (json['quoteBucketLabel'] as String?)?.trim() ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      status: quoteLifecycleStatusFromJson(statusRaw),
      exportedAt: DateTime.tryParse(json['exportedAt'] as String? ?? ''),
      confirmedAt: DateTime.tryParse(json['confirmedAt'] as String? ?? ''),
      exportedFilePaths: _stringListFromJsonField(json['exportedFilePaths']),
      exportedFileNames: _stringListFromJsonField(json['exportedFileNames']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'customerName': customerName,
    'customerId': customerId,
    'quoteBucketKey': quoteBucketKey,
    'quoteBucketLabel': quoteBucketLabel,
    'updatedAt': updatedAt.toIso8601String(),
    'quoteStatus': quoteLifecycleStatusToJson(status),
    'exportedAt': exportedAt?.toIso8601String(),
    'confirmedAt': confirmedAt?.toIso8601String(),
    'exportedFilePaths': exportedFilePaths,
    'exportedFileNames': exportedFileNames,
  };
}

/// True when two index rows refer to the same logical customer: ids match when both
/// are present; otherwise fall back to matching display names. Handles legacy active
/// rows with empty [customerId] next to rows that have the same customer id and name
/// (so export/archive can remove every duplicate for that bucket).
bool _sameLogicalCustomerQuoteRows({
  required String customerIdA,
  required String customerNameA,
  required String customerIdB,
  required String customerNameB,
}) {
  final idA = customerIdA.trim();
  final idB = customerIdB.trim();
  final nameA = customerNameA.trim().toLowerCase();
  final nameB = customerNameB.trim().toLowerCase();
  if (idA.isNotEmpty && idB.isNotEmpty) {
    return idA.toLowerCase() == idB.toLowerCase();
  }
  if (idA.isNotEmpty && idB.isEmpty) {
    return nameB.isNotEmpty && nameB == nameA;
  }
  if (idA.isEmpty && idB.isNotEmpty) {
    return nameA.isNotEmpty && nameA == nameB;
  }
  return nameA.isNotEmpty && nameA == nameB;
}

/// Aggregates for archive / read-only quote display (from persisted JSON).
(int lineCount, int unitCount, double orderTotal) quoteDataLineStatsAndTotal(
  Map<String, dynamic> data,
) {
  final lines =
      data['lines'] as List<dynamic>? ?? data['items'] as List<dynamic>? ?? [];
  var units = 0;
  for (final lineJson in lines) {
    final map = Map<String, dynamic>.from(lineJson as Map);
    units += (map['quantity'] as int?) ?? 1;
  }
  final total = _orderTotalFromQuoteDataMap(data);
  return (lines.length, units, total);
}

/// True when persisted quote JSON has no line items or all line quantities sum to 0.
bool persistedQuoteDataIsEmptyForReuse(Map<String, dynamic> data) {
  final (lineCount, unitCount, _) = quoteDataLineStatsAndTotal(data);
  return lineCount == 0 || unitCount <= 0;
}

double _orderTotalFromQuoteDataMap(Map<String, dynamic> data) {
  final lines =
      data['lines'] as List<dynamic>? ?? data['items'] as List<dynamic>? ?? [];
  final customerMap = data['customer'];
  var customerDiscPct = 0.0;
  if (customerMap is Map<String, dynamic>) {
    customerDiscPct =
        Customer.fromJson(Map<String, dynamic>.from(customerMap))
            .discountPercent;
  }

  bool lineDiscountEligible(Map<String, dynamic> map) {
    final b = map['discountEligible'];
    if (b is bool) return b;
    final raw = (map['discountRaw'] as String?) ?? '';
    return raw.trim().toUpperCase() == 'YES';
  }

  double discountedUnit(Map<String, dynamic> map, double regularUnit) {
    if (!lineDiscountEligible(map) || customerDiscPct <= 0) {
      return regularUnit;
    }
    return regularUnit * (1 - customerDiscPct / 100.0);
  }

  var sum = 0.0;
  for (final lineJson in lines) {
    final map = Map<String, dynamic>.from(lineJson as Map);
    final qty = (map['quantity'] as int?) ?? 1;
    final price = (map['price'] as num?)?.toDouble() ?? 0.0;
    sum += discountedUnit(map, price) * qty;
  }
  return sum;
}

/// Customer from customers.csv (headers: Id, CompanyName, Address, ...).
class Customer {
  final String id;
  final String companyName;
  final String address;
  final String address2;
  final String city;
  final String state;
  final String zip;
  final String phone;
  final String fax;
  final String email;
  final String contact;
  final String salesRepName;
  final String priceList;
  final String discount;
  final double discountPercent;
  final String paymentTerms;

  Customer({
    required this.id,
    required this.companyName,
    required this.address,
    required this.address2,
    required this.city,
    required this.state,
    required this.zip,
    required this.phone,
    required this.fax,
    required this.email,
    required this.contact,
    required this.salesRepName,
    required this.priceList,
    required this.discount,
    required this.discountPercent,
    required this.paymentTerms,
  });

  /// Parses customers.csv `discount` cell: blank/invalid → 0; clamped to [0, 100].
  static double parseDiscountPercentFromRaw(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 0.0;
    final v = double.tryParse(t.replaceAll(',', ''));
    if (v == null || v.isNaN) return 0.0;
    if (v < 0) return 0.0;
    if (v > 100) return 100.0;
    return v;
  }

  String get displayName =>
      companyName.trim().isNotEmpty ? companyName : id;

  /// Stable lookup key (CSV `Id` when present; otherwise derived from row).
  String get idOrKey => id;

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyName': companyName,
        'address': address,
        'address2': address2,
        'city': city,
        'state': state,
        'zip': zip,
        'phone': phone,
        'fax': fax,
        'email': email,
        'contact': contact,
        'salesRepName': salesRepName,
        'priceList': priceList,
        'discount': discount,
        'discountPercent': discountPercent,
        'paymentTerms': paymentTerms,
      };

  static Customer fromJson(Map<String, dynamic> json) {
    String s(String key) => (json[key] as String?)?.trim() ?? '';
    final discStr = s('discount');
    final embedded = json['discountPercent'];
    final double pct;
    if (embedded is num) {
      final d = embedded.toDouble();
      if (d.isNaN) {
        pct = parseDiscountPercentFromRaw(discStr);
      } else if (d < 0) {
        pct = 0.0;
      } else if (d > 100) {
        pct = 100.0;
      } else {
        pct = d;
      }
    } else {
      pct = parseDiscountPercentFromRaw(discStr);
    }
    return Customer(
      id: s('id'),
      companyName: s('companyName'),
      address: s('address'),
      address2: s('address2'),
      city: s('city'),
      state: s('state'),
      zip: s('zip'),
      phone: s('phone'),
      fax: s('fax'),
      email: s('email'),
      contact: s('contact'),
      salesRepName: s('salesRepName'),
      priceList: s('priceList'),
      discount: discStr,
      discountPercent: pct,
      paymentTerms: s('paymentTerms'),
    );
  }
}

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({super.key});

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

/// Load Quote dialog content. Owns the search TextEditingController and disposes it
/// when the dialog is closed, avoiding "used after being disposed" when deleting the last quote.
class _LoadQuoteDialogContent extends StatefulWidget {
  const _LoadQuoteDialogContent({
    required this.allQuotes,
    required this.formatDate,
    required this.dialogContext,
    required this.onRemoveQuote,
    required this.onShareQuote,
    required this.searchQuotesFocusNode,
  });

  final List<SavedQuoteInfo> allQuotes;
  final String Function(DateTime) formatDate;
  final BuildContext dialogContext;
  final Future<void> Function(String id) onRemoveQuote;
  final void Function(String id, String name) onShareQuote;
  final FocusNode searchQuotesFocusNode;

  @override
  State<_LoadQuoteDialogContent> createState() => _LoadQuoteDialogContentState();
}

class _LoadQuoteDialogContentState extends State<_LoadQuoteDialogContent> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() => setState(() {}));

    // `autofocus: true` is not fully reliable on some Android devices when
    // another TextField (the hidden scanner input) has focus.
    // Request focus explicitly right after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.searchQuotesFocusNode.hasFocus) {
        FocusScope.of(context).requestFocus(widget.searchQuotesFocusNode);
      }
    });

    // A second attempt helps on devices where the initial focus request is
    // dropped due to timing.
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      if (!widget.searchQuotesFocusNode.hasFocus) {
        FocusScope.of(context).requestFocus(widget.searchQuotesFocusNode);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchController.text.trim().toLowerCase();
    final filtered = widget.allQuotes.where((info) {
      // Use raw fields for searching so user can type either
      // quote name, customer name, date text, or even pieces
      // of the combined "Customer: X – Quote: Y" label.
      final name = (info.name).toLowerCase();
      final customer = (info.customerName).toLowerCase();
      final bucketLabel = (info.quoteBucketLabel).toLowerCase();
      final dateText = widget.formatDate(info.updatedAt).toLowerCase();
      final displayCustomer =
          customer.isEmpty ? 'no customer' : customer; // matches visible label
      final displayQuote = name.isEmpty ? 'unnamed quote' : name;
      final combined =
          'customer: $displayCustomer – quote: $displayQuote'.toLowerCase();

      if (q.isEmpty) return true;

      return name.contains(q) ||
          customer.contains(q) ||
          bucketLabel.contains(q) ||
          dateText.contains(q) ||
          combined.contains(q);
    }).toList();

    final media = MediaQuery.of(context);
    // Keep dialog comfortably within view in both orientations and when the
    // on-screen keyboard is visible by respecting viewInsets (e.g. keyboard).
    final availableHeight =
        media.size.height - media.viewInsets.vertical - 32; // safety margin
    final double maxHeight = availableHeight > 0
        ? availableHeight * 0.75
        : media.size.height * 0.6;

    return SizedBox(
      width: double.maxFinite,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          // Allow the content to shrink for few items but never overflow screen.
          maxHeight: maxHeight,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tap a quote to load it. Email to share; remove only after emailing or saving elsewhere.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _searchController,
                focusNode: widget.searchQuotesFocusNode,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Search quotes',
                  hintText: 'Type quote name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 4),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Text(
                      'No matching quotes',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final info = filtered[i];
                    final String customerName = info.customerName.trim().isEmpty
                        ? 'No customer'
                        : info.customerName.trim();
                    final String quoteName =
                        info.name.isEmpty ? 'Unnamed quote' : info.name;
                    final rawBucketKey = info.quoteBucketKey.trim().toLowerCase();
                    final rawBucketLabel = info.quoteBucketLabel.trim();
                    final String bucketLabel = rawBucketLabel.isEmpty
                        ? 'EVERYDAY'
                        : (rawBucketKey == 'every_day'
                            ? 'EVERYDAY'
                            : rawBucketLabel);
                    return ListTile(
                      title: Text(
                        'Customer: $customerName – Quote: $quoteName',
                      ),
                      subtitle: Text(
                        '$bucketLabel • ${widget.formatDate(info.updatedAt)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.email_outlined),
                            tooltip: 'Email / Share quote',
                            onPressed: () =>
                                widget.onShareQuote(info.id, info.name),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip:
                                'Remove from list (after emailing or saving)',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Remove quote?'),
                                  content: const Text(
                                    'Remove this quote from the list? The file will be deleted.\n\n'
                                    'Only do this after you have emailed or saved the quote elsewhere. This cannot be undone.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(c, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(c, true),
                                      child: const Text('Remove'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true && mounted) {
                                await widget.onRemoveQuote(info.id);
                                widget.allQuotes
                                    .removeWhere((e) => e.id == info.id);
                                if (mounted) {
                                  Navigator.of(widget.dialogContext)
                                      .pop('removed:${info.id}');
                                }
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () =>
                          Navigator.of(widget.dialogContext).pop(info.id),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerHomePageState extends State<ScannerHomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const bool _scanPerfDebug = true;

  /// Temporary: quote routing / bucket reuse (set false to silence).
  static const bool _quoteRoutingDebug = true;

  /// Temporary: Graduation-only routing trace (set false to silence).
  static const bool _graduationRoutingDebug = true;

  /// Temporary: KSP-only routing trace (set false to silence).
  static const bool _kspRoutingDebug = true;

  /// Temporary: quote export / archive index diagnostics (set false to silence).
  static const bool _quoteLifecycleExportDebug = true;

  /// Temporary: log active/archive index rows for a customer during import/export audits.
  static const bool _quoteIndexAuditDebug = true;

  /// Temporary: starter quote + import reuse + export-empty skips (set false to silence).
  static const bool _quoteImportExportEmptyDebug = true;

  final FocusNode _scannerFocusNode = FocusNode();
  final TextEditingController _scannerController = TextEditingController();

  final FocusNode _searchQuotesFocusNode = FocusNode();
  final FocusNode _searchCustomersFocusNode = FocusNode();

  final FocusNode _quickEntryFocusNode = FocusNode();
  final TextEditingController _quickEntryController = TextEditingController();
  /// Keeps the manual Item # / UPC [TextField] instance when it moves into the keyboard bar.
  final GlobalKey _quickEntryTextFieldKey = GlobalKey();

  /// While the OS keyboard inset is closing after quick entry dismiss, keep the placeholder +
  /// floating bar layout so the full [_ScanTabItemSearchBlock] is not placed in the shrunken
  /// main column (avoids a one-frame [Column] overflow before insets reach zero).
  bool _quickEntryHoldFloatingLayoutForKeyboard = false;

  final FocusNode _quoteNameFocusNode = FocusNode();
  final TextEditingController _quoteNameController = TextEditingController(
    text: 'NEW QUOTE',
  );

  final ScrollController _orderListScrollController = ScrollController();
  final ScrollController _orderListTabScrollController = ScrollController();
  /// Scroll controller for the Scan tab middle (order list + details + search hits).
  final ScrollController _scanPanelScrollController = ScrollController();

  final GlobalKey<_ArchiveQuotesTabState> _archiveQuotesTabKey =
      GlobalKey<_ArchiveQuotesTabState>();

  /// Debug-only: trace focus transitions around quick/manual entry.
  /// This is intentionally limited to the bug reproduction path.
  bool _manualEntryFocusTraceActive = false;
  Timer? _manualEntryFocusTraceTimeout;

  final Map<String, Product> _productsByUpc = {};
  final Map<String, Product> _productsByItemNumber = {};
  final Map<String, QuoteBucketDefinition> _quoteBucketsByRawType = {};
  final Map<String, QuoteBucketDefinition> _quoteBucketsByBucketKey = {};
  final Set<String> _configuredRawQuoteBucketKeys = {};

  List<Product> get _allProducts =>
      _productsByItemNumber.values.toList(growable: false);

  final List<OrderLine> _orderLines = [];
  /// Order lines keyed by a strict identity based on full item number (preferred) or UPC.
  /// This ensures similar-looking item numbers (e.g. 87001 vs 87002) are never merged.
  final Map<String, OrderLine> _orderLineByKey = {};

  Timer? _scanDebounceTimer;
  Timer? _refocusTimer;
  Timer? _scanFeedbackTimer;
  /// Cancels stale tail-cutoff pauses so rapid error scans are not clipped by an older timer.
  Timer? _errorBuzzTailPauseTimer;
  Timer? _quoteNameBarcodeDebounce;
  /// Clears [_scanTabHighlightLineKey] after a brief post-scan flash (Scan tab order list only).
  Timer? _scanTabHighlightClearTimer;

  TextEditingController _searchController = TextEditingController();
  List<Product> _searchResults = [];
  Timer? _searchDebounce;

  late final AudioPlayer _goodScanPlayer;
  late final AudioPlayer _goodScanPlayer2;
  late final AudioPlayer _errorScanPlayer;

  /// After a successful [AudioPlayer.setSource], replay with seek+resume only (good-scan latency).
  bool _goodScanPlayer1SourceReady = false;
  bool _goodScanPlayer2SourceReady = false;
  bool _errorScanPlayerSourceReady = false;
  bool _errorScanPlayerVolumeRateSet = false;

  /// Windows: asset playback uses a temp path passed as [Uri.path] (`/C:/...`) without a
  /// `file://` scheme; Media Foundation rejects it. In-memory sources avoid that.
  Uint8List? _windowsGoodScanBytes;
  Uint8List? _windowsGoodScan2Bytes;
  Uint8List? _windowsErrorScanBytes;

  // Still updated by scan/quote flows; hidden from live panel (UI cleanup).
  // ignore: unused_field
  String _lastScan = '-';
  // ignore: unused_field
  String _lastItem = '-';
  // ignore: unused_field
  String _status = 'Loading products...';
  String _quickEntryStatus = '-';
  String _catalogSource = 'Built-in catalog';

  int _itemsScanned = 0;
  int _totalUnits = 0;
  double _regularOrderTotal = 0.0;
  double _orderDiscountAmount = 0.0;
  double _orderTotal = 0.0;
  int _qtyAdded = 0;
  int _catalogCount = 0;
  String? _lastAddedUpc;

  // ignore: unused_field
  bool _readyToScan = false;
  bool _loadingProducts = true;
  bool _editDialogOpen = false;
  /// Prevents overlapping order-CSV imports (second tap while apply/write still runs → duplicate ITEMS_NOT_IMPORTED writes).
  bool _orderCsvImportInProgress = false;

  /// When non-null, [_ensureRoutingForProduct] logs each bucket once per CSV import session.
  String? _quoteImportDebugSession;
  final Set<String> _quoteImportLoggedBucketKeys = <String>{};

  /// Quote name to restore when a barcode was mistakenly entered in the quote name field
  String _savedQuoteNameBeforeEdit = 'NEW QUOTE';

  /// Incremented when loading a quote so the order list widget is recreated and items display
  int _orderListVersion = 0;

  OrderLine? _selectedLine;
  ScanFeedbackType _scanFeedbackType = ScanFeedbackType.none;

  /// Order line key ([_orderLineKeyForProduct]) to flash-highlight on the Scan tab list after a successful scan.
  String? _scanTabHighlightLineKey;

  /// [GlobalKey]s for Scan tab order rows — used with [Scrollable.ensureVisible] after a scan (UI only).
  final Map<String, GlobalKey> _scanTabOrderRowKeys = <String, GlobalKey>{};

  /// Prevent accidental duplicate scans: ignore same barcode if processed within this window (ms).
  static const int _scanDedupeMs = 80;
  // 12ms proved too aggressive on some scanners and can split a single
  // physical scan into partial fragments ("2", "73", "730", ...).
  // Idle debounce only when no newline/submit/editing-complete arrives (see [_onScannerChanged]).
  static const int _scanInputDebounceMs = 28;
  static const int _scannerRefocusDelayMs = 35;
  static const int _tabReturnRefocusDelayMs = 120;
  String? _lastProcessedScanUpc;
  DateTime? _lastProcessedScanTime;

  /// Serialize rapid-fire scans so they are processed one at a time in order.
  bool _isProcessingScan = false;
  final Queue<String> _pendingScans = Queue<String>();

  List<Customer> _customers = [];
  final Map<String, Customer> _customersByKey = {};
  Customer? _selectedCustomer;
  /// Updated when customer CSV loads; no longer shown in Scan panel.
  // ignore: unused_field
  String _customersLoadDebugLine = 'Customers Loaded: loading…';
  /// Updated when product catalog loads; no longer shown in Scan panel.
  // ignore: unused_field
  String _productsLoadDebugLine = 'Products Loaded: loading…';
  /// When non-null, Save Quote updates this quote instead of creating a new one.
  String? _currentQuoteId;
  String _activeQuoteBucketKey = _defaultQuoteBucketKey;
  String _activeQuoteBucketLabel = 'EVERYDAY';
  bool _quoteNameUserEdited = false;

  late final TabController _tabController;
  bool _scanTabActive = true;
  int _activeTabIndex = 0;

  int _scanPerfSeq = 0;
  final Map<int, Stopwatch> _scanPerfWatches = {};
  final Map<int, String> _scanPerfRawBySeq = {};
  int _scanTabBuildCount = 0;
  int _orderListTabBuildCount = 0;
  int _orderListBuildCount = 0;
  final Map<int, int> _scanStartScanTabBuildCount = {};
  final Map<int, int> _scanStartOrderListTabBuildCount = {};
  final Map<int, int> _scanStartOrderListBuildCount = {};
  int _currentScanSampleId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_handleGlobalFocusChange);

    _goodScanPlayer = AudioPlayer();
    _goodScanPlayer2 = AudioPlayer();
    _errorScanPlayer = AudioPlayer();

    _loadProductsFromAssets();
    _loadCustomersFromAssets();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _requestScannerFocus();
      try {
        final beforeId = _currentQuoteId;
        await _pruneSupersededEmptyDuplicateQuotesForAllActiveIndexCustomers();
        if (kDebugMode && _quoteImportExportEmptyDebug) {
          final idx = await _loadQuoteIndex();
          _debugLogQuoteImportExport(
            '[Startup] prune-all done currentId before=$beforeId after=$_currentQuoteId '
            'activeIndexIds=${idx.map((e) => e.id).join(',')}',
          );
        }
      } catch (e, st) {
        debugPrint('[Startup] prune-all failed: $e\n$st');
      }
    });

    // Keep startup focus recovery reliable, but avoid a long chain of delayed
    // pulses. `_requestScannerFocus()` already performs internal retry pulses.
    for (final ms in [90, 320]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (!mounted || _editDialogOpen) return;
        if (!_scannerFocusNode.hasFocus) _requestScannerFocus();
      });
    }

    _scannerFocusNode.addListener(() {
      if (!_scannerFocusNode.hasFocus &&
          !_quickEntryFocusNode.hasFocus &&
          !_quoteNameFocusNode.hasFocus &&
          !_searchQuotesFocusNode.hasFocus &&
          !_searchCustomersFocusNode.hasFocus &&
          !_editDialogOpen) {
        _scheduleScannerRefocus();
      }
    });

    void showKeyboardIfNeeded() {
      // On some Android devices, a previously hidden keyboard does not
      // reliably re-open just from focus changes. Explicitly showing it
      // when the user focuses an input field makes behavior consistent.
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }

    _quickEntryFocusNode.addListener(() {
      if (_quickEntryFocusNode.hasFocus) {
        debugPrint('[ManualEntry][Focus] quickEntryFocusNode got focus');
        showKeyboardIfNeeded();
      }
      // Rebuild so Scan tab can swap inline vs floating quick-entry layout.
      if (mounted) setState(() {});
    });

    _quoteNameFocusNode.addListener(() {
      if (_quoteNameFocusNode.hasFocus) {
        showKeyboardIfNeeded();
        _savedQuoteNameBeforeEdit = _quoteNameController.text.trim().isEmpty
            ? 'NEW QUOTE'
            : _quoteNameController.text.trim().toUpperCase();
      }
    });

    _searchQuotesFocusNode.addListener(() {
      if (_searchQuotesFocusNode.hasFocus) {
        showKeyboardIfNeeded();
      }
    });

    _searchCustomersFocusNode.addListener(() {
      if (_searchCustomersFocusNode.hasFocus) {
        showKeyboardIfNeeded();
      }
    });

    _quoteNameController.addListener(_onQuoteNameChanged);

    _tabController = TabController(length: 4, vsync: this);
    _activeTabIndex = _tabController.index;
    _scanTabActive = _tabController.index == 0;
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (!mounted) return;
      final previousIndex = _activeTabIndex;
      final nextIndex = _tabController.index;
      _setStateDebug('tab_active_index', () {
        _activeTabIndex = nextIndex;
        _scanTabActive = nextIndex == 0;
      });
      _recoverScannerFocusAfterTabChange(
        previousIndex: previousIndex,
        nextIndex: nextIndex,
      );
    });
  }

  void _perfLog(String message) {
    if (!_scanPerfDebug) return;
    debugPrint('[ScanPerf] $message');
  }

  /// Debug-only: labels which `setState` ran (gated by [_kScanRebuildInstrumentationEnabled]).
  void _setStateDebug(String label, VoidCallback fn) {
    if (kDebugMode && _kScanRebuildInstrumentationEnabled) {
      debugPrint('SETSTATE_TRACE[$label]');
    }
    setState(fn);
  }

  int _startScanPerfSample(String raw) {
    final seq = ++_scanPerfSeq;
    _scanPerfRawBySeq[seq] = raw;
    _scanPerfWatches[seq] = Stopwatch()..start();
    _scanStartScanTabBuildCount[seq] = _scanTabBuildCount;
    _scanStartOrderListTabBuildCount[seq] = _orderListTabBuildCount;
    _scanStartOrderListBuildCount[seq] = _orderListBuildCount;
    _perfLog(
      '#$seq barcode complete raw="$raw" (scanTabBuild=$_scanTabBuildCount orderListTabBuild=$_orderListTabBuildCount orderListBuild=$_orderListBuildCount)',
    );
    return seq;
  }

  void _logScanPerfStep(int seq, String step) {
    final sw = _scanPerfWatches[seq];
    if (sw == null) return;
    _perfLog('#$seq +${sw.elapsedMilliseconds}ms $step');
  }

  void _finishScanPerfSample(int seq, {required String outcome}) {
    final sw = _scanPerfWatches.remove(seq);
    if (sw == null) return;
    sw.stop();
    final raw = _scanPerfRawBySeq.remove(seq) ?? '';
    final scanTabBuildDelta =
        _scanTabBuildCount - (_scanStartScanTabBuildCount.remove(seq) ?? 0);
    final orderListTabBuildDelta = _orderListTabBuildCount -
        (_scanStartOrderListTabBuildCount.remove(seq) ?? 0);
    final orderListBuildDelta =
        _orderListBuildCount - (_scanStartOrderListBuildCount.remove(seq) ?? 0);
    _perfLog(
      '#$seq total=${sw.elapsedMilliseconds}ms outcome=$outcome raw="$raw" buildDeltas(scanTab=$scanTabBuildDelta orderListTab=$orderListTabBuildDelta orderList=$orderListBuildDelta)',
    );
  }

  void _onQuoteNameChanged() {
    if (!_quoteNameFocusNode.hasFocus) return;
    _quoteNameUserEdited = true;

    _quoteNameBarcodeDebounce?.cancel();

    final text = _quoteNameController.text.trim();
    final digits = digitsOnly(text);

    if (digits.length >= 8 && digits == text) {
      _quoteNameBarcodeDebounce = Timer(const Duration(milliseconds: 80), () {
        if (!mounted) return;

        final t = _quoteNameController.text.trim();
        final d = digitsOnly(t);

        if (d.length >= 8 && d == t) {
          _quoteNameController.text = _savedQuoteNameBeforeEdit;
          _quoteNameController.selection = TextSelection.collapsed(
            offset: _savedQuoteNameBeforeEdit.length,
          );
          _enqueueScan(t);
          _requestScannerFocus();
        }

        _quoteNameBarcodeDebounce = null;
      });
    }
  }

  Future<void> _initAudio() async {
    try {
      final ctx = AudioContext(
        android: AudioContextAndroid(
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      );

      await AudioPlayer.global.setAudioContext(ctx);

      final scanAudioCache = AudioCache(prefix: '');
      _goodScanPlayer.audioCache = scanAudioCache;
      _goodScanPlayer2.audioCache = scanAudioCache;
      _errorScanPlayer.audioCache = scanAudioCache;

      await _goodScanPlayer.setReleaseMode(ReleaseMode.stop);
      await _goodScanPlayer2.setReleaseMode(ReleaseMode.stop);
      await _errorScanPlayer.setReleaseMode(ReleaseMode.stop);

      // Short UI sounds: lowLatency is faster on many devices, but some Android OEM
      // builds fail silently with SoundPool; mediaPlayer is slower but reliable.
      final goodMode = Platform.isAndroid
          ? PlayerMode.mediaPlayer
          : PlayerMode.lowLatency;
      await _goodScanPlayer.setPlayerMode(goodMode);
      await _goodScanPlayer2.setPlayerMode(goodMode);

      // Slightly reduce good scan volume to avoid audible clipping/distortion.
      await _goodScanPlayer.setVolume(0.75);
      await _goodScanPlayer2.setVolume(0.75);

      // Do not pre-load or prepare players in init: on Android, early prepare + stop/pause
      // can break first/double beep. Sources are set on first play and then reused via seek+resume.

      if (Platform.isWindows) {
        _windowsGoodScanBytes =
            (await rootBundle.load(_goodScanAsset)).buffer.asUint8List();
        _windowsGoodScan2Bytes =
            (await rootBundle.load(_goodScan2Asset)).buffer.asUint8List();
        _windowsErrorScanBytes =
            (await rootBundle.load(_errorScanAsset)).buffer.asUint8List();
      }

      debugPrint('[Audio] initialized OK');
    } catch (e) {
      debugPrint('[Audio] init error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_handleGlobalFocusChange);
    _scanDebounceTimer?.cancel();
    _refocusTimer?.cancel();
    _scanFeedbackTimer?.cancel();
    _errorBuzzTailPauseTimer?.cancel();
    _quoteNameBarcodeDebounce?.cancel();
    _searchDebounce?.cancel();
    _manualEntryFocusTraceTimeout?.cancel();
    _quoteNameController.removeListener(_onQuoteNameChanged);

    _goodScanPlayer.dispose();
    _goodScanPlayer2.dispose();
    _errorScanPlayer.dispose();

    _scannerFocusNode.dispose();
    _scannerController.dispose();

    _searchQuotesFocusNode.dispose();
    _searchCustomersFocusNode.dispose();

    _quickEntryFocusNode.dispose();
    _quickEntryController.dispose();

    _quoteNameFocusNode.dispose();
    _quoteNameController.dispose();

    _searchController.dispose();

    _orderListScrollController.dispose();
    _orderListTabScrollController.dispose();
    _scanPanelScrollController.dispose();
    _scanTabHighlightClearTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      _scheduleScannerRefocus();
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final keyboardClosed =
        _quickEntryHoldFloatingLayoutForKeyboard &&
            MediaQuery.viewInsetsOf(context).bottom == 0;
    if (keyboardClosed) {
      setState(() {
        _quickEntryHoldFloatingLayoutForKeyboard = false;
      });
    } else if (_quickEntryFocusNode.hasFocus) {
      setState(() {});
    }
    _scheduleScannerRefocus();
  }

  void _handleGlobalFocusChange() {
    if (!mounted || _editDialogOpen || !_scanTabActive) return;
    if (_scannerFocusNode.hasFocus) return;
    _scheduleScannerRefocus();
  }

  void _scheduleScannerRefocus() {
    final startedAt = DateTime.now();
    _refocusTimer?.cancel();
    _refocusTimer = Timer(const Duration(milliseconds: _scannerRefocusDelayMs), () {
      if (!mounted) return;
      if (!_shouldReclaimScannerFocus()) return;
      if (kDebugMode && _kScanRebuildInstrumentationEnabled) {
        debugPrint('SCAN_PATH[focus_refocus_timer_fired]');
      }
      _perfLog(
        'focus restore timer fired after ${DateTime.now().difference(startedAt).inMilliseconds}ms',
      );
      _requestScannerFocus();
    });
  }

  void _recoverScannerFocusAfterTabChange({
    required int previousIndex,
    required int nextIndex,
  }) {
    if (!mounted) return;
    if (previousIndex == nextIndex) return;
    if (nextIndex != 0) return; // Only when returning to Scan tab.
    if (!_scanTabActive) return;

    // The Scan tab subtree (including the hidden scanner TextField) is not built
    // while another tab is active (`_buildScanTab` returns shrink). Focus must
    // be requested after the frame where that field is mounted again.
    void tryRestore() {
      if (!mounted || !_scanTabActive || _editDialogOpen) return;
      if (_scannerFocusNode.hasFocus) return;
      if (kDebugMode && _kScanRebuildInstrumentationEnabled) {
        debugPrint('SCAN_PATH[tab_return_post_frame_request_scanner_focus]');
      }
      _requestScannerFocus();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      tryRestore();
    });
    _scheduleScannerRefocus();
    Future.delayed(
      const Duration(milliseconds: _tabReturnRefocusDelayMs),
      _scheduleScannerRefocus,
    );
  }

  bool _shouldReclaimScannerFocus() {
    if (!mounted) return false;
    if (_editDialogOpen) return false;
    if (!_scanTabActive) return false;

    // Never steal focus while the user is typing in one of our known input
    // fields.
    if (_quickEntryFocusNode.hasFocus ||
        _quoteNameFocusNode.hasFocus ||
        _searchQuotesFocusNode.hasFocus ||
        _searchCustomersFocusNode.hasFocus) {
      return false;
    }

    // If something else editable (TextField/TextFormField) is focused (often
    // inside a dialog), do not reclaim focus.
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return true; // no one focused -> safe to reclaim
    if (primary != _scannerFocusNode) {
      final ctx = primary.context;
      // During initial startup/tab mount, Flutter can report a transient
      // primary focus with no context. Treat that as safe to reclaim so the
      // hidden scanner field can become ready without manual tap/refocus.
      if (ctx == null) return true;

      // In practice `primary.context.widget` may not be the EditableText
      // itself, so check the focused widget and its ancestry.
      final widget = ctx.widget;
      if (widget is EditableText ||
          widget is TextField ||
          widget is TextFormField) {
        return false;
      }

      if (ctx.findAncestorWidgetOfExactType<EditableText>() != null ||
          ctx.findAncestorWidgetOfExactType<TextField>() != null ||
          ctx.findAncestorWidgetOfExactType<TextFormField>() != null) {
        return false;
      }
    }

    // Scanner already focused, or focus is on a non-editable widget.
    return true;
  }

  void _requestScannerFocus() {
    final primary = FocusManager.instance.primaryFocus;
    final scannerAlreadyFocused = _scannerFocusNode.hasFocus;
    if (scannerAlreadyFocused && !_editDialogOpen && _scanTabActive) {
      _perfLog('focus restore skipped (scanner already focused)');
      return;
    }

    final shouldReclaim = _shouldReclaimScannerFocus();
    if (!shouldReclaim) {
      if (_manualEntryFocusTraceActive) {
        debugPrint(
          '[ScannerFocus][Blocked] editDialogOpen=$_editDialogOpen scanTabActive=$_scanTabActive '
          'quickEntryHasFocus=${_quickEntryFocusNode.hasFocus} quoteNameHasFocus=${_quoteNameFocusNode.hasFocus} '
          'searchQuotesHasFocus=${_searchQuotesFocusNode.hasFocus} searchCustomersHasFocus=${_searchCustomersFocusNode.hasFocus} '
          'scannerHasFocus=${_scannerFocusNode.hasFocus} primaryFocusType=${primary?.runtimeType} '
          'primaryFocusMatchesScanner=${primary == _scannerFocusNode}',
        );
      }
      return;
    }

    if (_manualEntryFocusTraceActive) {
      debugPrint(
        '[ScannerFocus][Request] calling requestFocus(scanner). '
        'scannerHasFocus=${_scannerFocusNode.hasFocus} primaryFocusMatchesScanner=${primary == _scannerFocusNode}',
      );
    }

    FocusScope.of(context).requestFocus(_scannerFocusNode);

    // Only schedule retry pulses when we are actively recovering lost focus.
    // This avoids repeated delayed focus work during normal scan flow.
    if (!scannerAlreadyFocused) {
      const delays = [30, 120];
      for (final ms in delays) {
        Future.delayed(Duration(milliseconds: ms), () {
          if (!_shouldReclaimScannerFocus()) return;
          if (!_scannerFocusNode.hasFocus) {
            FocusScope.of(context).requestFocus(_scannerFocusNode);
          }
        });
      }
    }

    // Hide the keyboard after focusing the hidden scanner input.
    // Delay slightly to avoid racing with the user's attempt to focus another
    // text field (which can leave the keyboard suppressed).
    Future.delayed(const Duration(milliseconds: 60), () {
      if (!mounted || _editDialogOpen) return;
      if (!_scannerFocusNode.hasFocus) return;

      final primary = FocusManager.instance.primaryFocus;
      if (primary != _scannerFocusNode) return;

      // If the app already moved focus into a normal entry field, don't hide
      // the keyboard.
      if (_quickEntryFocusNode.hasFocus || _quoteNameFocusNode.hasFocus) {
        return;
      }

      SystemChannels.textInput.invokeMethod('TextInput.hide');
    });
  }

  Future<void> _stopAllSounds() async {
    // Do NOT stop good scan players to avoid Android playback issues.
    // Pause (not stop) on the error player so the asset source stays prepared
    // for faster repeated error feedback; see [_playErrorBuzz].
    _errorBuzzTailPauseTimer?.cancel();
    _errorBuzzTailPauseTimer = null;
    try {
      await _errorScanPlayer.pause();
    } catch (_) {}
  }

  Future<void> _deliverScanFeedbackSounds(
    ScanFeedbackType type,
    int sampleId,
  ) async {
    await _stopAllSounds();
    if (!mounted) return;
    if (type == ScanFeedbackType.successNewItem ||
        type == ScanFeedbackType.successExistingItem) {
      final bool isSingle = type == ScanFeedbackType.successNewItem;
      await _playGoodScanBeep(isSingle: isSingle);
      if (sampleId > 0) {
        _logScanPerfStep(sampleId, 'beep triggered (good)');
      }
      HapticFeedback.selectionClick();
    } else if (type == ScanFeedbackType.notFound) {
      await _playErrorBuzz();
      if (sampleId > 0) {
        _logScanPerfStep(sampleId, 'beep triggered (error)');
      }
      HapticFeedback.vibrate();
    }
  }

  void _triggerScanFeedback(ScanFeedbackType type) {
    final int sampleId = _currentScanSampleId;
    _scanFeedbackTimer?.cancel();

    if (_scanFeedbackType != type) {
      _setStateDebug('scan_feedback_apply', () {
        _scanFeedbackType = type;
      });
    }

    // Ensure only one sound plays per scan / entry: finish pause on the error
    // player before seek/resume, or pause races with replay on the same native player.
    unawaited(_deliverScanFeedbackSounds(type, sampleId));

    if (kDebugMode && _kScanRebuildInstrumentationEnabled) {
      debugPrint(
        'SCAN_PATH[scan_feedback_after_beep type=${type.name} clear_timer_scheduled_200ms]',
      );
    }

    _scanFeedbackTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      if (_scanFeedbackType == ScanFeedbackType.none) return;
      _setStateDebug('scan_feedback_clear_timer', () {
        _scanFeedbackType = ScanFeedbackType.none;
      });
    });
  }

  static const String _goodScanAsset = 'assets/sounds/good_scan.mp3';
  static const String _goodScan2Asset = 'assets/sounds/good_scan2.mp3';
  static const String _errorScanAsset = 'assets/sounds/error_scan.mp3';

  static final AssetSource _goodScanAssetSource = AssetSource(_goodScanAsset);
  static final AssetSource _goodScan2AssetSource = AssetSource(_goodScan2Asset);
  static final AssetSource _errorScanAssetSource = AssetSource(_errorScanAsset);

  Future<void> _playGoodScanBeep({required bool isSingle}) async {
    try {
      if (kDebugMode) {
        debugPrint('Playing ${isSingle ? 'single' : 'double'} beep');
        if (!isSingle) {
          debugPrint(
            '[Audio] double beep: asset=$_goodScan2Asset '
            'p2SourceReady=$_goodScanPlayer2SourceReady '
            'winBytes=${_windowsGoodScan2Bytes?.length}',
          );
        }
      }

      if (!mounted) return;

      if (Platform.isWindows) {
        final bytes =
            isSingle ? _windowsGoodScanBytes : _windowsGoodScan2Bytes;
        if (bytes == null) {
          debugPrint(
            '[Audio] Windows scan sound bytes missing '
            '(single=$isSingle)',
          );
          return;
        }
        final player = isSingle ? _goodScanPlayer : _goodScanPlayer2;
        if (isSingle) {
          if (!_goodScanPlayer1SourceReady) {
            await player.setSourceBytes(bytes, mimeType: 'audio/mpeg');
            if (!mounted) return;
            _goodScanPlayer1SourceReady = true;
          }
        } else {
          if (!_goodScanPlayer2SourceReady) {
            await player.setSourceBytes(bytes, mimeType: 'audio/mpeg');
            if (!mounted) return;
            await Future.delayed(const Duration(milliseconds: 40));
            if (!mounted) return;
            _goodScanPlayer2SourceReady = true;
          }
        }
        await player.seek(Duration.zero);
        await player.resume();
        if (kDebugMode) {
          debugPrint('Play attempt (Windows bytes)');
        }
        return;
      }

      // Use separate players so we never swap source on the same player (avoids second-play silent on Android).
      if (isSingle) {
        if (!_goodScanPlayer1SourceReady) {
          await _goodScanPlayer.setSource(_goodScanAssetSource);
          if (!mounted) return;
          _goodScanPlayer1SourceReady = true;
        }
        await _goodScanPlayer.seek(Duration.zero);
        await _goodScanPlayer.resume();
      } else {
        if (!_goodScanPlayer2SourceReady) {
          if (kDebugMode) {
            debugPrint('[Audio] player2 setSource($_goodScan2Asset)');
          }
          await _goodScanPlayer2.setSource(_goodScan2AssetSource);
          if (!mounted) return;
          // Brief yield so the second player finishes preparing (first load only;
          // lowLatency mode usually needs less time than legacy media player).
          await Future.delayed(const Duration(milliseconds: 40));
          if (!mounted) return;
          _goodScanPlayer2SourceReady = true;
          if (kDebugMode) {
            debugPrint('[Audio] player2 source prepared');
          }
        }
        await _goodScanPlayer2.seek(Duration.zero);
        await _goodScanPlayer2.resume();
      }
      if (kDebugMode) {
        debugPrint('Play attempt');
      }
    } catch (e, st) {
      debugPrint(
        '[Audio] good beep error (single=$isSingle): $e',
      );
      if (kDebugMode && !isSingle) {
        debugPrint('[Audio] good beep p2: $st');
      }
      if (isSingle) {
        _goodScanPlayer1SourceReady = false;
      } else {
        _goodScanPlayer2SourceReady = false;
      }
    }
  }

  Future<void> _playErrorBuzz() async {
    bool soundPlayed = false;
    try {
      // Avoid stop() before play: on some Android devices it puts MediaPlayer in error state (-38)
      if (!_errorScanPlayerVolumeRateSet) {
        await _errorScanPlayer.setVolume(1.0);
        await _errorScanPlayer.setPlaybackRate(1.0);
        _errorScanPlayerVolumeRateSet = true;
      }
      if (Platform.isWindows) {
        final bytes = _windowsErrorScanBytes;
        if (bytes != null) {
          if (!_errorScanPlayerSourceReady) {
            await _errorScanPlayer.setSourceBytes(bytes, mimeType: 'audio/mpeg');
            if (!mounted) return;
            _errorScanPlayerSourceReady = true;
          } else {
            await _errorScanPlayer.seek(Duration.zero);
          }
          await _errorScanPlayer.resume();
          soundPlayed = true;
        }
      } else {
        if (!_errorScanPlayerSourceReady) {
          await _errorScanPlayer.setSource(_errorScanAssetSource);
          if (!mounted) return;
          _errorScanPlayerSourceReady = true;
        } else {
          await _errorScanPlayer.seek(Duration.zero);
        }
        await _errorScanPlayer.resume();
        soundPlayed = true;
      }
      if (soundPlayed) {
        // Same 500ms cutoff as before (avoid long tails); pause keeps source prepared
        // for the next bad scan instead of stop()+clearing [_errorScanPlayerSourceReady].
        _errorBuzzTailPauseTimer?.cancel();
        _errorBuzzTailPauseTimer =
            Timer(const Duration(milliseconds: 500), () async {
          _errorBuzzTailPauseTimer = null;
          if (!mounted) return;
          try {
            await _errorScanPlayer.pause();
          } catch (_) {}
        });
      }
    } catch (e) {
      debugPrint('[Audio] error buzz error: $e');
      _errorScanPlayerSourceReady = false;
    }
    // If asset sound never played, use system alert so user always hears something on bad scan
    if (!soundPlayed && mounted) {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  String digitsOnly(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '').trim();
  }

  String normalizeItemNumber(String value) {
    return value.trim().toUpperCase();
  }

  String _normalizeUpcLookupKey(String value) {
    final trimmed = value.trim();
    final digits = digitsOnly(trimmed);
    return digits.isNotEmpty ? digits : trimmed.toUpperCase();
  }

  String _normalizeBucketLookup(String value) {
    var normalized = value.trim().toLowerCase();
    normalized = normalized.replaceAll(RegExp(r"[`´’']"), "'");
    normalized = normalized.replaceAll('&', ' and ');
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  /// Single canonical bucket key for routing, index matching, export grouping, and import reuse.
  /// Blank/legacy keys normalize to the default Everyday bucket (see [_defaultQuoteBucketKey]).
  String _logicalQuoteBucketKey(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.isEmpty) {
      return _defaultQuoteBucketKey;
    }

    if (t == _defaultQuoteBucketKey ||
        t == 'everyday' ||
        t == 'every day' ||
        t.replaceAll('_', ' ').trim() == 'every day' ||
        t == 'everyday_quote' ||
        t == 'every day quote') {
      return _defaultQuoteBucketKey;
    }

    if (t == 'christmas' ||
        t == 'xmas' ||
        t == 'christmas_quote' ||
        t == 'christmas quote') {
      return 'christmas';
    }

    if (t == 'fall_winter' ||
        t == 'fall/winter' ||
        t == 'fall winter' ||
        t == 'fall-winter') {
      return 'fall_winter';
    }

    if (t == 'halloween' ||
        t == 'halloween_quote' ||
        t == 'halloween quote') {
      return 'halloween';
    }

    return t
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
  }

  void _debugLogQuoteRouting(String message) {
    if (!kDebugMode || !_quoteRoutingDebug) return;
    debugPrint(message);
  }

  /// products.csv `Discount` column: only YES (trimmed, case-insensitive) is eligible.
  bool _parseDiscountEligibility(String value) {
    return value.trim().toUpperCase() == 'YES';
  }

  static const String _defaultQuoteBucketKey = 'every_day';

  QuoteBucketDefinition get _defaultQuoteBucketDefinition {
    final fromConfig = _quoteBucketsByBucketKey[_defaultQuoteBucketKey];
    if (fromConfig != null) return fromConfig;
    return const QuoteBucketDefinition(
      bucketKey: _defaultQuoteBucketKey,
      displayLabel: 'EVERYDAY',
    );
  }

  bool _containsPrideToken(String value) {
    final normalized = _normalizeBucketLookup(value);
    if (normalized.isEmpty) return false;
    return normalized == 'pride' ||
        normalized.startsWith('pride ') ||
        normalized.endsWith(' pride') ||
        normalized.contains(' pride ');
  }

  /// True when CSV Product Type or Category indicates Graduation (for targeted debug logs).
  bool _isGraduationRoutingProductSignal(Product product) {
    if (!_isAbsentProductType(product.productType)) {
      if (_normalizeBucketLookup(product.productType.trim()) == 'graduation') {
        return true;
      }
    }
    final cat = product.category.trim();
    if (cat.isNotEmpty && _normalizeBucketLookup(cat) == 'graduation') {
      return true;
    }
    return false;
  }

  void _debugLogGraduationRouting(String message) {
    if (!kDebugMode || !_graduationRoutingDebug) return;
    debugPrint(message);
  }

  /// True when CSV Product Type or Category indicates KSP (for targeted debug logs).
  bool _isKspRoutingProductSignal(Product product) {
    if (!_isAbsentProductType(product.productType)) {
      if (_normalizeBucketLookup(product.productType.trim()) == 'ksp') {
        return true;
      }
    }
    final cat = product.category.trim();
    if (cat.isNotEmpty && _normalizeBucketLookup(cat) == 'ksp') {
      return true;
    }
    return false;
  }

  void _debugLogKspRouting(String message) {
    if (!kDebugMode || !_kspRoutingDebug) return;
    debugPrint(message);
  }

  void _traceBucketRouteLine({
    required bool kspTrace,
    required bool graduationTrace,
    required String message,
  }) {
    if (kspTrace) {
      _debugLogKspRouting(message);
    } else if (graduationTrace) {
      _debugLogGraduationRouting(message);
    } else {
      _debugLogQuoteRouting(message);
    }
  }

  /// True when CSV Product Type is absent or explicitly "no type" — not bucket-routed
  /// via category/Pride; only the default quote bucket applies.
  bool _isAbsentProductType(String value) {
    final t = value.trim();
    if (t.isEmpty) return true;
    if (t == '0') return true;
    return false;
  }

  QuoteBucketDefinition _resolveQuoteBucketForProduct(Product product) {
    final fromProductType = product.productType.trim();
    if (_isAbsentProductType(product.productType)) {
      return _defaultQuoteBucketDefinition;
    }
    if (fromProductType.isNotEmpty) {
      final resolved = _quoteBucketsByRawType[_normalizeBucketLookup(
        fromProductType,
      )];
      if (resolved != null) return resolved;
    }

    final fromCategory = product.category.trim();
    if (fromCategory.isNotEmpty) {
      final resolved = _quoteBucketsByRawType[_normalizeBucketLookup(
        fromCategory,
      )];
      if (resolved != null) return resolved;
    }

    // Pride should always route to the PRIDE quote, even when product type
    // values include additional words not listed as explicit mappings.
    if (_containsPrideToken(fromProductType) || _containsPrideToken(fromCategory)) {
      final prideBucket = _quoteBucketsByBucketKey['pride'];
      if (prideBucket != null) return prideBucket;
    }

    return _defaultQuoteBucketDefinition;
  }

  /// Stable prefix for route keys when [Customer.id] is blank (name-scoped fallback).
  String _logicalCustomerRoutePrefix(Customer customer) {
    final id = customer.id.trim();
    if (id.isNotEmpty) return id.toLowerCase();
    return 'name:${customer.displayName.trim().toLowerCase()}';
  }

  bool _savedQuoteInfoMatchesCustomer(SavedQuoteInfo info, Customer customer) {
    return _sameLogicalCustomerQuoteRows(
      customerIdA: customer.id,
      customerNameA: customer.displayName,
      customerIdB: info.customerId,
      customerNameB: info.customerName,
    );
  }

  void _debugLogQuoteImportExport(String message) {
    if (!kDebugMode || !_quoteImportExportEmptyDebug) return;
    debugPrint(message);
  }

  String _routeKeyForCustomerBucket(Customer customer, String bucketKey) {
    final cid = _logicalCustomerRoutePrefix(customer);
    final bid = _logicalQuoteBucketKey(bucketKey);
    return '$cid::$bid';
  }

  /// True when [info] belongs to [soughtLogical] — index [SavedQuoteInfo.quoteBucketKey]
  /// first, otherwise quote JSON root `quoteBucketKey` (stale/blank index rows).
  Future<bool> _quoteIndexEntryMatchesLogicalBucket(
    SavedQuoteInfo info,
    Directory dir,
    String soughtLogical,
  ) async {
    if (_logicalQuoteBucketKey(info.quoteBucketKey) == soughtLogical) {
      return true;
    }
    final f = File('${dir.path}/quote_${info.id}.json');
    if (!await f.exists()) return false;
    try {
      final data = Map<String, dynamic>.from(
        jsonDecode(await f.readAsString()) as Map,
      );
      final diskKey = (data['quoteBucketKey'] as String?)?.trim() ?? '';
      return _logicalQuoteBucketKey(diskKey) == soughtLogical;
    } catch (_) {
      return false;
    }
  }

  /// Any persisted quote row for this customer + logical bucket with line data.
  /// Prefers non-empty on-disk quotes (newest-first index order) so routing never
  /// picks an empty starter while a real order exists.
  Future<String?> _findExistingQuoteIdForCustomerBucket({
    required Customer customer,
    required String bucketKey,
  }) async {
    final sought = _logicalQuoteBucketKey(bucketKey);
    final infos = await _loadQuoteIndex();
    final dir = await _getQuotesDirectory();
    final matches = <SavedQuoteInfo>[];
    for (final info in infos) {
      if (!_savedQuoteInfoMatchesCustomer(info, customer)) continue;
      if (!await _quoteIndexEntryMatchesLogicalBucket(info, dir, sought)) {
        continue;
      }
      matches.add(info);
    }
    if (matches.isEmpty) return null;
    for (final info in matches) {
      final f = File('${dir.path}/quote_${info.id}.json');
      if (!await f.exists()) continue;
      try {
        final data = Map<String, dynamic>.from(
          jsonDecode(await f.readAsString()) as Map,
        );
        if (!persistedQuoteDataIsEmptyForReuse(data)) {
          return info.id;
        }
      } catch (_) {}
    }
    for (final info in matches) {
      final f = File('${dir.path}/quote_${info.id}.json');
      if (!await f.exists()) continue;
      try {
        final data = Map<String, dynamic>.from(
          jsonDecode(await f.readAsString()) as Map,
        );
        if (persistedQuoteDataIsEmptyForReuse(data)) {
          return info.id;
        }
      } catch (_) {}
    }
    return matches.first.id;
  }

  /// Empty starter / placeholder file for this customer + bucket (import reuse).
  Future<String?> _findEmptyPersistedQuoteIdForCustomerBucket({
    required Customer customer,
    required String bucketKey,
  }) async {
    final sought = _logicalQuoteBucketKey(bucketKey);
    final infos = await _loadQuoteIndex();
    final dir = await _getQuotesDirectory();
    for (final info in infos) {
      if (!_savedQuoteInfoMatchesCustomer(info, customer)) continue;
      if (!await _quoteIndexEntryMatchesLogicalBucket(info, dir, sought)) {
        continue;
      }
      final f = File('${dir.path}/quote_${info.id}.json');
      if (!await f.exists()) continue;
      try {
        final data = Map<String, dynamic>.from(
          jsonDecode(await f.readAsString()) as Map,
        );
        if (persistedQuoteDataIsEmptyForReuse(data)) {
          return info.id;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Minimal [Customer] for index-only operations (logical identity matches
  /// [_savedQuoteInfoMatchesCustomer] / [_logicalCustomerRoutePrefix]).
  Customer _customerStubForSavedQuoteInfo(SavedQuoteInfo info) {
    return Customer(
      id: info.customerId,
      companyName: info.customerName,
      address: '',
      address2: '',
      city: '',
      state: '',
      zip: '',
      phone: '',
      fax: '',
      email: '',
      contact: '',
      salesRepName: '',
      priceList: '',
      discount: '',
      discountPercent: 0,
      paymentTerms: '',
    );
  }

  /// Prunes superseded empty duplicates for every logical customer present in the
  /// active index (so Load Quote reflects [quotes_active.json] after cleanup).
  Future<void> _pruneSupersededEmptyDuplicateQuotesForAllActiveIndexCustomers() async {
    final snapshot = await _loadQuoteIndex();
    final seenRoute = <String>{};
    for (final info in snapshot) {
      final stub = _customerStubForSavedQuoteInfo(info);
      final key = _logicalCustomerRoutePrefix(stub);
      if (!seenRoute.add(key)) continue;
      await _pruneSupersededEmptyDuplicateQuotesForCustomer(stub);
    }
  }

  /// Removes extra active index rows / files for the same logical customer + bucket when only
  /// empty starter duplicates remain (import/export integrity).
  Future<void> _pruneSupersededEmptyDuplicateQuotesForCustomer(
    Customer customer,
  ) async {
    try {
      final dir = await _getQuotesDirectory();
      final indexFile = await _activeQuoteIndexFileForReadWrite(dir);
      if (!await indexFile.exists()) return;

      final archiveIds =
          (await _loadArchiveQuoteIndex()).map((e) => e.id).toSet();
      final content = await indexFile.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! List) return;

      final list = List<Map<String, dynamic>>.from(
        decoded.map((e) => Map<String, dynamic>.from(e as Map)),
      );

      final candidates = <SavedQuoteInfo>[];
      for (final m in list) {
        try {
          final info = SavedQuoteInfo.fromJson(m);
          if (info.id.isEmpty) continue;
          if (archiveIds.contains(info.id)) continue;
          if (info.status != QuoteLifecycleStatus.active) continue;
          if (!_savedQuoteInfoMatchesCustomer(info, customer)) continue;
          candidates.add(info);
        } catch (_) {}
      }

      final byBucket = <String, List<SavedQuoteInfo>>{};
      for (final info in candidates) {
        final k = _logicalQuoteBucketKey(info.quoteBucketKey);
        byBucket.putIfAbsent(k, () => []).add(info);
      }

      final idsToRemove = <String>{};
      String? replacementIdIfCurrentRemoved;
      for (final group in byBucket.values) {
        if (group.length <= 1) continue;
        group.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        final nonEmptyIds = <String>[];
        final emptyIds = <String>[];
        for (final info in group) {
          final f = File('${dir.path}/quote_${info.id}.json');
          if (!await f.exists()) {
            emptyIds.add(info.id);
            continue;
          }
          try {
            final data = Map<String, dynamic>.from(
              jsonDecode(await f.readAsString()) as Map,
            );
            if (persistedQuoteDataIsEmptyForReuse(data)) {
              emptyIds.add(info.id);
            } else {
              nonEmptyIds.add(info.id);
            }
          } catch (_) {
            emptyIds.add(info.id);
          }
        }

        if (nonEmptyIds.isNotEmpty) {
          for (final id in emptyIds) {
            idsToRemove.add(id);
          }
          final cur = _currentQuoteId;
          if (cur != null &&
              emptyIds.contains(cur) &&
              nonEmptyIds.isNotEmpty) {
            // Prefer newest non-empty quote when dropping the empty starter that
            // is still the current id (never skip removal just because it is current).
            replacementIdIfCurrentRemoved ??= nonEmptyIds.first;
          }
        } else {
          var keepId = group.first.id;
          final cur = _currentQuoteId;
          if (cur != null && group.any((info) => info.id == cur)) {
            keepId = cur;
          }
          for (final info in group) {
            if (info.id != keepId) {
              idsToRemove.add(info.id);
            }
          }
        }
      }

      if (idsToRemove.isEmpty) return;

      _debugLogQuoteImportExport(
        '[QuoteImport] pruneEmptyDupes customer="${customer.displayName}" '
        'removeIds=${idsToRemove.join(',')}'
        '${replacementIdIfCurrentRemoved != null ? ' repointCurrent->$replacementIdIfCurrentRemoved' : ''}',
      );

      for (final id in idsToRemove) {
        list.removeWhere((e) => e['id']?.toString() == id);
        final qf = File('${dir.path}/quote_$id.json');
        try {
          if (await qf.exists()) {
            await qf.delete();
            _debugLogQuoteImportExport(
              '[QuoteImport] prune deleted quote_$id.json ok',
            );
          } else {
            _debugLogQuoteImportExport(
              '[QuoteImport] prune quote_$id.json already absent',
            );
          }
        } catch (e) {
          _debugLogQuoteImportExport(
            '[QuoteImport] prune delete quote_$id.json failed: $e',
          );
        }
      }

      await indexFile.writeAsString(jsonEncode(list), flush: true);

      final removedCurrent =
          _currentQuoteId != null && idsToRemove.contains(_currentQuoteId);
      final rep = replacementIdIfCurrentRemoved;
      if (removedCurrent && rep != null && rep.isNotEmpty) {
        _debugLogQuoteImportExport(
          '[QuoteImport] prune repoint current '
          'from=$_currentQuoteId to=$rep mounted=$mounted',
        );
        // Always sync workspace when the current id was pruned so [_saveQuote]
        // cannot resurrect a removed row/file. [syncWorkspaceIfUnmounted] applies
        // in-memory state without setState when the widget is between frames.
        await _loadQuoteById(rep, syncWorkspaceIfUnmounted: true);
      }
    } catch (e) {
      debugPrint('[QuoteImport] pruneEmptyDupes failed: $e');
    }
  }

  bool _shouldAutoPrefixQuoteName() {
    if (_orderLines.isNotEmpty) return false;
    if (_quoteNameUserEdited) return false;
    if (_quoteNameFocusNode.hasFocus) return false;
    final text = _quoteNameController.text.trim();
    if (text.isEmpty) return true;
    final upper = text.toUpperCase();
    if (upper == 'NEW QUOTE') return true;
    return RegExp(r'^QUOTE_\d{4}_\d{2}_\d{2}_\d{3}$', caseSensitive: false)
        .hasMatch(text);
  }

  Future<void> _ensureRoutingForProduct(Product product) async {
    final customer = _selectedCustomer;
    final bucket = _resolveQuoteBucketForProduct(product);
    final rawType = product.productType;
    final normType = _isAbsentProductType(product.productType)
        ? '(absent/blank/0)'
        : _normalizeBucketLookup(product.productType.trim());
    final activeId = _logicalQuoteBucketKey(_activeQuoteBucketKey);
    final targetId = _logicalQuoteBucketKey(bucket.bucketKey);
    final kspTrace = _isKspRoutingProductSignal(product);
    final graduationTrace =
        !kspTrace && _isGraduationRoutingProductSignal(product);
    final bucketTrace = kspTrace || graduationTrace;
    final tracePrefix = kspTrace
        ? '[KSP Routing]'
        : graduationTrace
            ? '[Graduation Routing]'
            : '[Routing]';

    _traceBucketRouteLine(
      kspTrace: kspTrace,
      graduationTrace: graduationTrace,
      message:
          '$tracePrefix Item ${product.itemNumber}\n'
          '$tracePrefix Raw Product Type: "$rawType"\n'
          '$tracePrefix Normalized Product Type: "$normType"\n'
          '$tracePrefix Resolved bucket key: "${bucket.bucketKey}"\n'
          '$tracePrefix Canonical bucket identity: "$targetId"\n'
          '$tracePrefix Resolved display label: "${bucket.displayLabel}"\n'
          '$tracePrefix Active quote bucket identity: "$activeId"',
    );

    if (customer == null) {
      if (bucketTrace) {
        _traceBucketRouteLine(
          kspTrace: kspTrace,
          graduationTrace: graduationTrace,
          message:
              '$tracePrefix No customer selected — routing skipped\n'
              '$tracePrefix Existing quote found: n/a\n'
              '$tracePrefix New quote created: n/a\n'
              '$tracePrefix Final target quote: n/a (no switch)',
        );
      } else {
        _debugLogQuoteRouting(
          '[Routing] No customer selected — routing/switch skipped (item still added to current quote)',
        );
      }
      return;
    }

    final alreadyOnTargetBucket = activeId == targetId;
    if (!bucketTrace) {
      _debugLogQuoteRouting(
        '[Routing] Already on target bucket: ${alreadyOnTargetBucket ? 'yes' : 'no'}',
      );
    }
    if (alreadyOnTargetBucket) {
      // Import / scan: user is already on this bucket but never adopted a saved id
      // (e.g. [_currentQuoteId] still null). Reuse an empty on-disk starter for this
      // customer + bucket so [_saveQuote] updates that file instead of minting a new id.
      // After CSV import, reuse the persisted quote for this bucket (non–import runs only)
      // so scanning appends instead of saving under the wrong id.
      if (_currentQuoteId == null) {
        if (!_orderCsvImportInProgress) {
          final existingId = await _findExistingQuoteIdForCustomerBucket(
            customer: customer,
            bucketKey: _activeQuoteBucketKey,
          );
          if (existingId != null) {
            await _loadQuoteById(existingId);
            if (!mounted) return;
          }
        }
        if (_currentQuoteId == null) {
          final emptyReuseId = await _findEmptyPersistedQuoteIdForCustomerBucket(
            customer: customer,
            bucketKey: _activeQuoteBucketKey,
          );
          if (emptyReuseId != null) {
            if (_orderLines.isEmpty) {
              await _loadQuoteById(emptyReuseId);
              if (!mounted) return;
            } else {
              _currentQuoteId = emptyReuseId;
            }
          }
        }
      }
      if (bucketTrace) {
        _traceBucketRouteLine(
          kspTrace: kspTrace,
          graduationTrace: graduationTrace,
          message:
              '$tracePrefix Already on target bucket: yes\n'
              '$tracePrefix Existing quote found: yes (already on bucket)\n'
              '$tracePrefix New quote created: no\n'
              '$tracePrefix Final target quote: "${_quoteNameController.text.trim()}"',
        );
      }
      return;
    }

    final currentRouteKey = _routeKeyForCustomerBucket(
      customer,
      _activeQuoteBucketKey,
    );
    final targetRouteKey = _routeKeyForCustomerBucket(customer, bucket.bucketKey);
    if (!bucketTrace) {
      _debugLogQuoteRouting(
        '[Routing] Route key current: "$currentRouteKey"  target: "$targetRouteKey"',
      );
    }
    if (currentRouteKey == targetRouteKey) {
      if (bucketTrace) {
        _traceBucketRouteLine(
          kspTrace: kspTrace,
          graduationTrace: graduationTrace,
          message:
              '$tracePrefix Route key current == target — no switch\n'
              '$tracePrefix Existing quote found: n/a\n'
              '$tracePrefix New quote created: no\n'
              '$tracePrefix Final target quote: "${_quoteNameController.text.trim()}"',
        );
      }
      return;
    }

    if (_orderLines.isNotEmpty) {
      await _saveQuote();
    }

    final existingQuoteId = await _findExistingQuoteIdForCustomerBucket(
      customer: customer,
      bucketKey: bucket.bucketKey,
    );
    if (_quoteImportDebugSession != null &&
        kDebugMode &&
        _quoteImportExportEmptyDebug &&
        _quoteImportLoggedBucketKeys.add(targetId)) {
      _debugLogQuoteImportExport(
        '[QuoteImport] session=$_quoteImportDebugSession bucket=$targetId '
        'item=${product.itemNumber} '
        '${existingQuoteId != null ? 'reuse id=$existingQuoteId' : 'no match -> startNew'}',
      );
    }
    if (existingQuoteId != null) {
      if (bucketTrace) {
        _traceBucketRouteLine(
          kspTrace: kspTrace,
          graduationTrace: graduationTrace,
          message: '$tracePrefix Existing quote found: yes (id=$existingQuoteId)',
        );
      } else {
        _debugLogQuoteRouting(
          '[Routing] Existing quote found: yes (id=$existingQuoteId)',
        );
      }
      await _loadQuoteById(existingQuoteId);
      if (!mounted) return;
      if (bucketTrace) {
        _traceBucketRouteLine(
          kspTrace: kspTrace,
          graduationTrace: graduationTrace,
          message:
              '$tracePrefix New quote created: no\n'
              '$tracePrefix Final target quote: "${_quoteNameController.text.trim()}"',
        );
      } else {
        _debugLogQuoteRouting(
          '[Routing] Target quote name: "${_quoteNameController.text.trim()}"',
        );
      }
      _setStateDebug('routing_after_load_bucket_quote', () {
        _status = 'Switched to ${bucket.displayLabel} quote';
      });
      return;
    }

    if (bucketTrace) {
      _traceBucketRouteLine(
        kspTrace: kspTrace,
        graduationTrace: graduationTrace,
        message: '$tracePrefix Existing quote found: no',
      );
    } else {
      _debugLogQuoteRouting(
        '[Routing] Existing quote found: no\n'
        '[Routing] Creating new routed quote for bucket: "$targetId"',
      );
    }
    await _startNewQuote(customer, initialBucket: bucket);
    if (mounted) {
      if (bucketTrace) {
        _traceBucketRouteLine(
          kspTrace: kspTrace,
          graduationTrace: graduationTrace,
          message:
              '$tracePrefix New quote created: yes\n'
              '$tracePrefix Final target quote: "${_quoteNameController.text.trim()}"',
        );
      } else {
        _debugLogQuoteRouting(
          '[Routing] New quote created; name: "${_quoteNameController.text.trim()}"',
        );
      }
    }
  }

  void _debugLogMissingProductTypeMappings() {
    assert(() {
      if (_productsByItemNumber.isEmpty) return true;

      final missingRawTypes = <String>{};
      for (final product in _productsByItemNumber.values) {
        final rawProductType = product.productType.trim();
        if (_isAbsentProductType(product.productType)) continue;
        final normalized = _normalizeBucketLookup(rawProductType);
        if (!_configuredRawQuoteBucketKeys.contains(normalized)) {
          missingRawTypes.add(rawProductType);
        }
      }

      if (missingRawTypes.isEmpty) {
        debugPrint(
          '[Products] Product Type mapping check: all Product Type values are mapped.',
        );
        return true;
      }

      final sorted = missingRawTypes.toList()..sort();
      debugPrint(
        '[Products] Product Type mapping check: missing mappings for '
        '${sorted.length} raw value(s): ${sorted.join(', ')}',
      );
      return true;
    }());
  }

  Future<void> _loadQuoteBucketConfig() async {
    _quoteBucketsByRawType.clear();
    _quoteBucketsByBucketKey.clear();
    _configuredRawQuoteBucketKeys.clear();
    try {
      final raw = await rootBundle.loadString(
        'assets/data/product_type_buckets.json',
      );
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      final mappings = decoded['mappings'];
      if (mappings is! Map<String, dynamic>) return;

      for (final entry in mappings.entries) {
        final rawKey = entry.key.trim();
        final rawValue = entry.value;
        if (rawKey.isEmpty || rawValue is! Map<String, dynamic>) continue;

        final bucketKey = (rawValue['bucketKey'] as String?)?.trim() ?? '';
        final displayLabel = (rawValue['displayLabel'] as String?)?.trim() ?? '';
        if (bucketKey.isEmpty || displayLabel.isEmpty) continue;

        final definition = QuoteBucketDefinition(
          bucketKey: bucketKey,
          displayLabel: displayLabel,
        );
        final normalizedRawKey = _normalizeBucketLookup(rawKey);
        _quoteBucketsByRawType[normalizedRawKey] = definition;
        _configuredRawQuoteBucketKeys.add(normalizedRawKey);
        _quoteBucketsByBucketKey[bucketKey] = definition;
      }
    } catch (_) {
      // Optional config; default fallback behavior applies if missing/invalid.
    }
  }

  /// Build a strict identity key for an order line: prefer full item number, fall back to UPC.
  /// No partial or fuzzy matching is used here.
  String _orderLineKeyForProduct(Product product) {
    final item = normalizeItemNumber(product.itemNumber);
    if (item.isNotEmpty) {
      return 'ITEM:$item';
    }
    final upc = _normalizeUpcLookupKey(product.upc);
    return 'UPC:$upc';
  }

  String _sanitizeOrderExportFileSegment(
    String value, {
    String ifEmpty = 'Quote',
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return ifEmpty;
    var s = trimmed.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    s = s.replaceAll(RegExp(r'\s+'), '_').trim();
    if (s.isEmpty) return ifEmpty;
    if (s.length > 120) s = s.substring(0, 120);
    return s;
  }

  /// Export CSV basename: `{QuoteName}_{CustomerName}_{yyyyMMdd_HHmmss_mmm}.csv` (clipped to 180 chars).
  static const int _kMaxExportCsvFilenameLength = 180;

  String _formatExportTimestamp(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final mo = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    final s = d.second.toString().padLeft(2, '0');
    final ms = d.millisecond.toString().padLeft(3, '0');
    return '${y}${mo}${day}_${h}${mi}${s}_$ms';
  }

  String _clipExportCsvFilename(String filename) {
    if (filename.length <= _kMaxExportCsvFilenameLength) return filename;
    const ext = '.csv';
    final maxStem = _kMaxExportCsvFilenameLength - ext.length;
    return '${filename.substring(0, maxStem)}$ext';
  }

  String _buildExportOrderCsvFilename({
    required String quoteName,
    required String customerName,
    required DateTime exportedOn,
  }) {
    final quoteSeg = _sanitizeOrderExportFileSegment(
      quoteName.trim().isEmpty ? 'Quote' : quoteName.trim(),
    );
    final customerSeg = _sanitizeOrderExportFileSegment(
      customerName,
      ifEmpty: 'Unknown_Customer',
    );
    final stamp = _formatExportTimestamp(exportedOn);
    return _clipExportCsvFilename('${quoteSeg}_${customerSeg}_$stamp.csv');
  }

  String _userFacingExportErrorMessage(Object error) {
    final t = error.toString().trim();
    if (t.isEmpty) return 'Export failed.';
    return t;
  }

  Future<void> _showExportSuccessDialog({
    required String customerName,
    required int quotesExported,
    required List<String> fileBasenames,
    required String folderPath,
    String? noteAfterQuotes,
    String? shareButtonLabel,
    Future<void> Function()? onSharePressed,
  }) async {
    final filesText = fileBasenames.isEmpty
        ? '(none)'
        : fileBasenames.map((n) => '• $n').join('\n');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Export Complete'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Customer: $customerName'),
                const SizedBox(height: 8),
                Text('Quotes exported: $quotesExported'),
                if (noteAfterQuotes != null && noteAfterQuotes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(noteAfterQuotes),
                ],
                const SizedBox(height: 12),
                const Text('Saved to:'),
                const SizedBox(height: 4),
                SelectableText(folderPath),
                const SizedBox(height: 12),
                const Text('Files:'),
                const SizedBox(height: 4),
                SelectableText(filesText),
              ],
            ),
          ),
          actions: [
            if (shareButtonLabel != null && onSharePressed != null)
              TextButton(
                onPressed: () async {
                  try {
                    await onSharePressed();
                  } catch (_) {}
                },
                child: Text(shareButtonLabel),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showExportErrorDialog(String message) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Export failed'),
          content: SingleChildScrollView(
            child: SelectableText(message),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _shareSingleExportedCsv(File file) async {
    try {
      if (!await file.exists()) {
        throw StateError('Exported file not found.');
      }
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to share file')),
      );
    }
  }

  Future<void> _shareMultipleExportedCsvs(List<File> files) async {
    try {
      final existing = <XFile>[];
      for (final file in files) {
        if (await file.exists()) {
          existing.add(XFile(file.path, mimeType: 'text/csv'));
        }
      }
      if (existing.isEmpty) {
        throw StateError('No exported files found.');
      }
      await Share.shareXFiles(existing);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to share files')),
      );
    }
  }

  String _buildItemsNotImportedFilename(
    String customerDisplayName,
    DateTime stampedOn,
  ) {
    final customerSegment = _sanitizeOrderExportFileSegment(customerDisplayName);
    final stamp = _formatExportTimestamp(stampedOn);
    return 'ITEMS_NOT_IMPORTED_${customerSegment}_$stamp.csv';
  }

  String _csvEscape(String value) {
    if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }

  String _formatNotImportedRowsCsv(List<OrderImportSkippedRow> rows) {
    final out = <String>['Item,Quantity,Reason'];
    for (final r in rows) {
      out.add(
        '${_csvEscape(r.item)},${_csvEscape(r.quantity)},${_csvEscape(r.reason)}',
      );
    }
    return out.join('\n');
  }

  Future<File> _writeItemsNotImportedCsv({
    required String customerDisplayName,
    required List<OrderImportSkippedRow> skippedRows,
  }) async {
    final filename = _buildItemsNotImportedFilename(
      customerDisplayName,
      DateTime.now(),
    );
    final csvText = _formatNotImportedRowsCsv(skippedRows);
    return exportOrderCsvToShowroomExportsLayout(
      customerDisplayName: customerDisplayName,
      filename: filename,
      csvText: csvText,
    );
  }

  void _debugLogQuoteLifecycleExport(String message) {
    if (!kDebugMode || !_quoteLifecycleExportDebug) return;
    debugPrint('[QuoteLifecycleExport] $message');
  }

  Future<void> _debugLogActiveIndexSnapshot(String label) async {
    if (!kDebugMode || !_quoteLifecycleExportDebug) return;
    try {
      final idx = await _loadQuoteIndex();
      final parts = idx
          .map(
            (i) =>
                '${i.id}:${i.quoteBucketKey}[${_logicalQuoteBucketKey(i.quoteBucketKey)}]',
          )
          .join(', ');
      _debugLogQuoteLifecycleExport(
        '$label activeIndex=[$parts] currentId=$_currentQuoteId '
        'activeBucket=$_activeQuoteBucketKey',
      );
    } catch (e) {
      _debugLogQuoteLifecycleExport('$label snapshot failed: $e');
    }
  }

  /// Debug: log all index rows for [_selectedCustomer] from both JSON files (raw rows,
  /// not filtered by quote file existence). Use for import/export bucket audits.
  Future<void> _debugLogQuoteIndexAuditForCustomer(String phase) async {
    if (!kDebugMode || !_quoteIndexAuditDebug) return;
    final customer = _selectedCustomer;
    if (customer == null) return;

    void auditLine(String fileLabel, String line) {
      debugPrint('[QuoteIndexAudit] $phase $fileLabel $line');
    }

    Future<void> dumpFile(String fileLabel, String path) async {
      final file = File(path);
      if (!await file.exists()) {
        auditLine(fileLabel, '(file missing)');
        return;
      }
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! List) {
          auditLine(fileLabel, '(not a JSON array)');
          return;
        }
        var n = 0;
        for (final e in decoded) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final rowCid = (m['customerId'] as String?)?.trim() ?? '';
          final rowName = (m['customerName'] as String?)?.trim() ?? '';
          final primId = customer.id.trim();
          final primName = customer.displayName.trim();
          final match = _sameLogicalCustomerQuoteRows(
            customerIdA: primId,
            customerNameA: primName,
            customerIdB: rowCid,
            customerNameB: rowName,
          );
          if (!match) continue;
          n++;
          final id = m['id']?.toString() ?? '';
          final qName = (m['name'] as String?)?.trim() ?? '';
          final qbk = (m['quoteBucketKey'] as String?)?.trim() ?? '';
          final qbl = (m['quoteBucketLabel'] as String?)?.trim() ?? '';
          final statusRaw = m['quoteStatus'] ?? m['status'];
          final qStatus = statusRaw?.toString() ?? '';
          auditLine(
            fileLabel,
            'row#$n id=$id customerName=$rowName quoteName=$qName '
            'quoteBucketKey=$qbk quoteBucketLabel=$qbl quoteStatus=$qStatus',
          );
        }
        if (n == 0) {
          auditLine(fileLabel, '(no rows for this customer)');
        }
      } catch (e) {
        auditLine(fileLabel, 'read failed: $e');
      }
    }

    final activePath = await _getQuoteActiveIndexPath();
    final archivePath = await _getQuoteArchiveIndexPath();
    await dumpFile('quotes_active.json', activePath);
    await dumpFile('quotes_archive.json', archivePath);
  }

  Future<void> _exportAllQuotesToCsv() async {
    final customer = _selectedCustomer;
    if (customer == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a customer before exporting.')),
      );
      return;
    }
    if (_orderLines.isEmpty && _currentQuoteId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items in order to export.')),
      );
      return;
    }

    final customerName = customer.displayName.trim();
    try {
      // Persist the in-memory quote so export reads all routed quotes consistently.
      await _saveQuote(notifyOnArchiveSideSave: false);

      final index = await _loadQuoteIndex();
      await _debugLogActiveIndexSnapshot('ExportAll after save+loadIndex');
      await _debugLogQuoteIndexAuditForCustomer('before Export All');
      final archivedIds = (await _loadArchiveQuoteIndex())
          .map((e) => e.id)
          .toSet();
      final matchingByBucket = <String, SavedQuoteInfo>{};
      for (final info in index) {
        if (!_sameLogicalCustomerQuoteRows(
          customerIdA: customer.id,
          customerNameA: customer.displayName,
          customerIdB: info.customerId,
          customerNameB: info.customerName,
        )) {
          continue;
        }
        if (archivedIds.contains(info.id)) {
          _debugLogQuoteLifecycleExport(
            'ExportAll skip id=${info.id} (still listed in active but also in archive — stale row)',
          );
          continue;
        }
        final bucketIdentity = _logicalQuoteBucketKey(info.quoteBucketKey);
        // Keep the most recent quote per bucket (index is newest-first).
        matchingByBucket.putIfAbsent(bucketIdentity, () => info);
      }
      _debugLogQuoteLifecycleExport(
        'ExportAll matchingByBucket keys=${matchingByBucket.keys.join('|')} '
        'ids=${matchingByBucket.values.map((e) => e.id).join(',')}',
      );

      if (matchingByBucket.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No routed quotes found to export.')),
        );
        return;
      }

      final quotesDir = await _getQuotesDirectory();
      final exportedFiles = <File>[];
      final skippedMissingOnDisk = <String>[];
      final exportedQuoteIds = <String>{};
      var movedToArchiveCount = 0;
      var exportFailureCount = 0;

      if (kDebugMode && _quoteImportExportEmptyDebug) {
        final parts = <String>[];
        for (final info in matchingByBucket.values) {
          final qf = File('${quotesDir.path}/quote_${info.id}.json');
          if (!await qf.exists()) {
            parts.add('id=${info.id}:missing');
            continue;
          }
          try {
            final raw = await qf.readAsString();
            final qd = Map<String, dynamic>.from(jsonDecode(raw) as Map);
            final empty = persistedQuoteDataIsEmptyForReuse(qd);
            parts.add(
              'id=${info.id} b=${_logicalQuoteBucketKey(info.quoteBucketKey)} '
              '${empty ? 'SKIP-empty' : 'ok'}',
            );
          } catch (_) {
            parts.add('id=${info.id}:err');
          }
        }
        _debugLogQuoteImportExport('[ExportAll] candidates: ${parts.join('; ')}');
      }

      for (final info in matchingByBucket.values) {
        if (!exportedQuoteIds.add(info.id)) {
          continue;
        }
        if (!await _quoteIdHasActiveEligibleRowInActiveIndexStorage(info.id)) {
          _debugLogQuoteLifecycleExport(
            'ExportAll skip id=${info.id} (no active eligible row at export time)',
          );
          continue;
        }
        final quoteFile = File('${quotesDir.path}/quote_${info.id}.json');
        if (!await quoteFile.exists()) {
          skippedMissingOnDisk.add(info.id);
          continue;
        }
        try {
          final quoteRaw = await quoteFile.readAsString();
          final quoteData = Map<String, dynamic>.from(
            jsonDecode(quoteRaw) as Map,
          );
          if (persistedQuoteDataIsEmptyForReuse(quoteData)) {
            _debugLogQuoteImportExport(
              '[ExportAll] skip-empty id=${info.id} '
              'bucket=${_logicalQuoteBucketKey(info.quoteBucketKey)}',
            );
            continue;
          }
          final csvText = _formatQuoteAsCsv(quoteData);
          final exportedOn = DateTime.now();
          final filename = _buildExportOrderCsvFilename(
            quoteName: info.name,
            customerName: customerName,
            exportedOn: exportedOn,
          );
          final file = await exportOrderCsvToShowroomExportsLayout(
            customerDisplayName: customerName,
            filename: filename,
            csvText: csvText,
          );
          exportedFiles.add(file);
          final moved = await _moveActiveQuoteToArchiveAfterSuccessfulExport(
            quoteId: info.id,
            exportedAt: exportedOn,
            exportedFile: file,
          );
          if (moved) {
            movedToArchiveCount++;
          } else {
            debugPrint(
              '[OrderExportAll] archive index move failed after export for id=${info.id}',
            );
          }
        } catch (e, st) {
          exportFailureCount++;
          debugPrint('[OrderExportAll] quote id=${info.id} failed: $e\n$st');
        }
      }

      if (mounted && movedToArchiveCount > 0) {
        setState(() {});
      }

      if (exportedFiles.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No CSV files were exported.')),
        );
        return;
      }

      if (!mounted) return;
      final basenames = exportedFiles.map((f) => p.basename(f.path)).toList();
      final noteParts = <String>[
        'Export complete. $movedToArchiveCount quote(s) moved to Archive.',
        if (exportFailureCount > 0) 'Failed exports: $exportFailureCount.',
        if (skippedMissingOnDisk.isNotEmpty)
          '(${skippedMissingOnDisk.length} saved quote(s) missing on disk were skipped.)',
      ];
      await _showExportSuccessDialog(
        customerName: customer.displayName.trim(),
        quotesExported: exportedFiles.length,
        fileBasenames: basenames,
        folderPath: exportedFiles.first.parent.path,
        noteAfterQuotes: noteParts.join(' '),
        shareButtonLabel: 'Share Files',
        onSharePressed: () => _shareMultipleExportedCsvs(exportedFiles),
      );
    } catch (e, st) {
      debugPrint('[OrderExportAll] failed: $e\n$st');
      if (!mounted) return;
      await _showExportErrorDialog(_userFacingExportErrorMessage(e));
    }
  }

  Future<void> _exportCurrentQuoteOnlyToCsv() async {
    final customer = _selectedCustomer;
    if (customer == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a customer before exporting.')),
      );
      return;
    }
    if (_orderLines.isEmpty && _currentQuoteId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items in current quote to export.')),
      );
      return;
    }

    try {
      await _saveQuote(notifyOnArchiveSideSave: false);
      final currentId = _currentQuoteId;
      if (currentId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Current quote is not available to export.')),
        );
        return;
      }

      _debugLogQuoteLifecycleExport(
        'ExportCurrent quoteId=$currentId activeBucket=$_activeQuoteBucketKey',
      );
      await _debugLogActiveIndexSnapshot('ExportCurrent after save');

      // Only quotes with an active index row may be exported from this path.
      if (!await _quoteIdHasActiveEligibleRowInActiveIndexStorage(currentId)) {
        if (await _isQuoteIdInArchiveButNotActive(currentId)) {
          if (!mounted) return;
          await _startNewQuote(customer);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'That quote was already exported and is in Archive. Started a new quote.',
              ),
            ),
          );
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Current quote is not in active saved quotes and cannot be exported.',
            ),
          ),
        );
        return;
      }

      final quotesDir = await _getQuotesDirectory();
      final quoteFile = File('${quotesDir.path}/quote_$currentId.json');
      if (!await quoteFile.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Current quote file not found.')),
        );
        return;
      }

      final quoteRaw = await quoteFile.readAsString();
      final quoteData = Map<String, dynamic>.from(jsonDecode(quoteRaw) as Map);
      if (persistedQuoteDataIsEmptyForReuse(quoteData)) {
        _debugLogQuoteImportExport(
          '[ExportCurrent] skip-empty quoteId=$currentId',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Current quote has no items to export.'),
          ),
        );
        return;
      }
      final csvText = _formatQuoteAsCsv(quoteData);
      final quoteName = (quoteData['name'] as String?)?.trim() ?? '';
      final exportedOn = DateTime.now();
      final filename = _buildExportOrderCsvFilename(
        quoteName: quoteName,
        customerName: customer.displayName.trim(),
        exportedOn: exportedOn,
      );
      final file = await exportOrderCsvToShowroomExportsLayout(
        customerDisplayName: customer.displayName.trim(),
        filename: filename,
        csvText: csvText,
      );

      final moved = await _moveActiveQuoteToArchiveAfterSuccessfulExport(
        quoteId: currentId,
        exportedAt: exportedOn,
        exportedFile: file,
      );
      if (moved) {
        await _debugLogActiveIndexSnapshot(
          'ExportCurrent after archive move (before startNewQuote)',
        );
        await _debugLogQuoteIndexAuditForCustomer(
          'after Export Current (archive move)',
        );
      }
      if (!moved) {
        debugPrint(
          '[OrderExportCurrent] archive index move failed after export for id=$currentId',
        );
      } else {
        // Exported quote must leave the editable workspace so Export Current cannot
        // re-read quote_$id.json and export the same archived quote again.
        if (!mounted) return;
        await _startNewQuote(customer);
      }

      if (!mounted) return;
      if (await file.exists()) {
        await _shareSingleExportedCsv(file);
      }
      if (!mounted) return;
      await _showExportSuccessDialog(
        customerName: customer.displayName.trim(),
        quotesExported: 1,
        fileBasenames: [p.basename(file.path)],
        folderPath: file.parent.path,
        noteAfterQuotes: moved
            ? 'Export complete. Quote moved to Archive.'
            : 'Export complete. (Could not move quote to Archive in the index; your CSV was saved.)',
        shareButtonLabel: 'Share File',
        onSharePressed: () => _shareSingleExportedCsv(file),
      );
    } catch (e, st) {
      debugPrint('[OrderExportCurrent] failed: $e\n$st');
      if (!mounted) return;
      await _showExportErrorDialog(_userFacingExportErrorMessage(e));
    }
  }

  Future<OrderImportApplyOutcome> _applyOrderImportRows(
    List<OrderImportCsvRow> rows,
  ) async {
    var importedRows = 0;
    var moqAdjustedRows = 0;
    final importedQuantityByBucket = <String, int>{};
    final skippedRows = <OrderImportSkippedRow>[];
    final groupedQuantityByItemKey = <String, int>{};
    final displayItemByItemKey = <String, String>{};
    for (final r in rows) {
      final key = _orderImportNormalizeItemKey(r.item);
      groupedQuantityByItemKey.update(
        key,
        (value) => value + r.quantity,
        ifAbsent: () => r.quantity,
      );
      displayItemByItemKey.putIfAbsent(key, () => r.item);
    }

    for (final entry in groupedQuantityByItemKey.entries) {
      final item = displayItemByItemKey[entry.key] ?? entry.key;
      final combinedQuantity = entry.value;
      try {
        final product = matchOrderImportProduct(
          item,
          _productsByItemNumber,
          _productsByUpc,
        );
        if (product == null) {
          skippedRows.add(
            OrderImportSkippedRow(
              item: item,
              quantity: combinedQuantity.toString(),
              reason: 'Item not found',
            ),
          );
          continue;
        }
        final importedQty = _nearestValidMoqMultiple(
          requestedQty: combinedQuantity,
          minOrderQty: product.minOrderQty,
        );
        if (importedQty != combinedQuantity) {
          moqAdjustedRows++;
        }
        await _ensureRoutingForProduct(product);
        _mergeImportedProductIntoOrder(product, importedQty);
        importedRows++;
        final bucket = _resolveQuoteBucketForProduct(product);
        final label = bucket.displayLabel.trim().isEmpty
            ? 'EVERYDAY'
            : bucket.displayLabel.trim().toUpperCase();
        importedQuantityByBucket.update(
          label,
          (value) => value + importedQty,
          ifAbsent: () => importedQty,
        );
      } catch (e) {
        skippedRows.add(
          OrderImportSkippedRow(
            item: item,
            quantity: combinedQuantity.toString(),
            reason: 'Import failure: $e',
          ),
        );
      }
    }
    return OrderImportApplyOutcome(
      importedRows: importedRows,
      moqAdjustedRows: moqAdjustedRows,
      importedQuantityByBucket: importedQuantityByBucket,
      skippedRows: skippedRows,
    );
  }

  int _nearestValidMoqMultiple({
    required int requestedQty,
    required int minOrderQty,
  }) {
    if (requestedQty < 1) return 1;
    final moq = minOrderQty < 1 ? 1 : minOrderQty;
    if (requestedQty <= moq) return moq;
    final remainder = requestedQty % moq;
    if (remainder == 0) return requestedQty;
    final lower = requestedQty - remainder;
    final upper = lower + moq;
    final downDistance = requestedQty - lower;
    final upDistance = upper - requestedQty;
    // If equally distant between two valid MOQ multiples, round up.
    return upDistance <= downDistance ? upper : lower;
  }

  Future<void> _showImportSummaryDialog({
    required Map<String, int> importedByBucket,
    required int importedLineCount,
    required int moqAdjustedRowCount,
    required int skippedRowCount,
    required String sourceFileName,
    String? itemsNotImportedPath,
  }) async {
    var totalUnitsAdded = 0;
    for (final v in importedByBucket.values) {
      totalUnitsAdded += v;
    }
    final bucketLines = importedByBucket.entries.map((entry) {
      return '• ${entry.key}: ${entry.value}';
    }).join('\n');
    final bucketText = bucketLines.isEmpty ? 'None' : bucketLines;

    final buffer = StringBuffer()
      ..writeln('File: $sourceFileName')
      ..writeln()
      ..writeln('Rows imported: $importedLineCount')
      ..writeln('Rows adjusted to MOQ: $moqAdjustedRowCount')
      ..writeln('Rows skipped: $skippedRowCount')
      ..writeln('Total units added: $totalUnitsAdded')
      ..writeln()
      ..writeln('Quantity by bucket:')
      ..writeln(bucketText);
    if (itemsNotImportedPath != null) {
      buffer
        ..writeln()
        ..writeln('Items not imported report:')
        ..writeln(itemsNotImportedPath);
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Import Complete'),
          content: SingleChildScrollView(
            child: SelectableText(buffer.toString()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _mergeImportedProductIntoOrder(Product product, int addQty) {
    final key = _orderLineKeyForProduct(product);
    late final OrderLine line;
    final bool isExistingLine = _orderLineByKey.containsKey(key);
    if (isExistingLine) {
      line = _orderLineByKey[key]!;
      line.quantity += addQty;
      line.scans += 1;
      _orderLines.remove(line);
      _orderLines.insert(0, line);
    } else {
      line = OrderLine(
        product: product,
        quantity: addQty,
        scans: 1,
      );
      _orderLines.insert(0, line);
      _orderLineByKey[key] = line;
    }
  }

  void _syncItemsScannedFromOrderLines() {
    var sum = 0;
    for (final l in _orderLines) {
      sum += l.scans;
    }
    _itemsScanned = sum;
  }

  Future<void> _pickAndImportOrderCsv() async {
    if (_loadingProducts) return;
    if (_orderCsvImportInProgress) return;
    _orderCsvImportInProgress = true;
    try {
      _editDialogOpen = true;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      _editDialogOpen = false;

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      String? raw;
      if (file.bytes != null) {
        raw = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        raw = await File(file.path!).readAsString();
      }

      if (raw == null || raw.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected file is empty.')),
        );
        return;
      }

      late final OrderImportCsvParseOutcome outcome;
      try {
        outcome = parseOrderImportCsv(raw);
      } on FormatException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        return;
      }

      if (_productsByItemNumber.isEmpty && _productsByUpc.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Load products first before importing an order.'),
          ),
        );
        return;
      }
      if (_selectedCustomer == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select a customer before importing an order.'),
          ),
        );
        return;
      }

      _quoteImportDebugSession =
          kDebugMode ? 'imp_${DateTime.now().millisecondsSinceEpoch}' : null;
      _quoteImportLoggedBucketKeys.clear();
      final applyOutcome = await _applyOrderImportRows(outcome.rows);
      await _saveQuote();
      await _pruneSupersededEmptyDuplicateQuotesForCustomer(_selectedCustomer!);
      await _debugLogQuoteIndexAuditForCustomer('after import (persisted)');
      final skippedRows = <OrderImportSkippedRow>[
        ...outcome.skippedRows,
        ...applyOutcome.skippedRows,
      ];
      File? skippedCsvFile;
      if (skippedRows.isNotEmpty) {
        skippedCsvFile = await _writeItemsNotImportedCsv(
          customerDisplayName: _selectedCustomer!.displayName,
          skippedRows: skippedRows,
        );
      }

      if (!mounted) return;
      setState(() {
        _syncItemsScannedFromOrderLines();
        _recalculateTotals();
        _orderListVersion += 1;
        if (_orderLines.isNotEmpty) {
          _selectedLine = _orderLines.first;
          _lastAddedUpc = _orderLines.first.product.upc;
        }
        _status = 'Imported order from ${file.name}';
      });

      if (!mounted) return;
      await _showImportSummaryDialog(
        importedByBucket: SplayTreeMap<String, int>.from(
          applyOutcome.importedQuantityByBucket,
        ),
        importedLineCount: applyOutcome.importedRows,
        moqAdjustedRowCount: applyOutcome.moqAdjustedRows,
        skippedRowCount: skippedRows.length,
        sourceFileName: file.name,
        itemsNotImportedPath: skippedCsvFile?.path,
      );
    } catch (e, st) {
      _editDialogOpen = false;
      debugPrint('[OrderImport] failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    } finally {
      _quoteImportDebugSession = null;
      _quoteImportLoggedBucketKeys.clear();
      _orderCsvImportInProgress = false;
    }
  }

  double _parsePrice(String value) {
    final cleaned = value.replaceAll('\$', '').replaceAll(',', '').trim();
    return double.tryParse(cleaned) ?? 0.0;
  }

  int _parseInt(String value) {
    return int.tryParse(value.trim()) ?? 0;
  }

  /// Normalizes CSV header labels for case-insensitive, spacing/hyphen-tolerant matching.
  String _normalizedProductHeaderKey(String s) {
    return s.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '');
  }

  /// Builds column index map: first occurrence wins for duplicate header names.
  Map<String, int> _productHeaderIndexMap(List<String> header) {
    final Map<String, int> map = {};
    for (int i = 0; i < header.length; i++) {
      final nk = _normalizedProductHeaderKey(header[i]);
      if (nk.isEmpty) continue;
      map.putIfAbsent(nk, () => i);
    }
    return map;
  }

  int _requireProductColumnIndex(
    Map<String, int> byNorm,
    String logicalName,
    List<String> normalizedKeys,
    List<String> headerForError,
  ) {
    for (final nk in normalizedKeys) {
      final i = byNorm[nk];
      if (i != null) return i;
    }
    throw FormatException(
      'Products CSV missing required column "$logicalName" '
      '(tried normalized keys: $normalizedKeys). '
      'Headers: ${headerForError.join(', ')}',
    );
  }

  String _productCell(List<dynamic> row, int col) {
    if (col < 0 || col >= row.length) return '';
    return row[col].toString();
  }

  void _parseAndStoreProducts(String rawCsv, {required String sourceLabel}) {
    void setProductsDebugLine(String line) {
      if (mounted) {
        setState(() => _productsLoadDebugLine = line);
      } else {
        _productsLoadDebugLine = line;
      }
    }

    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(rawCsv);

    if (rows.isEmpty) {
      debugPrint(
        '[Products] CSV appears empty after parsing – no header/rows found.',
      );
      _productsByUpc.clear();
      _productsByItemNumber.clear();
      _catalogCount = 0;
      _catalogSource = '$sourceLabel (empty)';
      setProductsDebugLine('Products Loaded: 0 (empty file)');
      debugPrint('----- PRODUCT LOAD REPORT -----');
      debugPrint('Total rows read: 0');
      debugPrint('Products loaded: 0');
      debugPrint('Discount-eligible products: 0');
      debugPrint('Skipped rows: 0');
      debugPrint('Duplicate UPC rows: 0');
      debugPrint('Duplicate item number rows: 0');
      return;
    }

    final header =
        rows.first.map((e) => e.toString().trim()).toList(growable: false);
    debugPrint(
      '[Products] Headers found (${header.length} cols): ${header.join(', ')}',
    );

    final byNorm = _productHeaderIndexMap(header);
    debugPrint(
      '[Products] Normalized header keys: ${byNorm.keys.toList()..sort()}',
    );

    final idxItemNumber = _requireProductColumnIndex(
      byNorm,
      'Item Number',
      const ['itemnumber'],
      header,
    );
    final idxDescription = _requireProductColumnIndex(
      byNorm,
      'Description',
      const ['description'],
      header,
    );
    final idxUpc = _requireProductColumnIndex(byNorm, 'UPC', const ['upc'], header);
    final idxPrice = _requireProductColumnIndex(
      byNorm,
      'Price',
      const ['price'],
      header,
    );
    final idxDiscount = _requireProductColumnIndex(
      byNorm,
      'DISCOUNT',
      const ['discount'],
      header,
    );
    final idxProductType = _requireProductColumnIndex(
      byNorm,
      'Product Type',
      const ['producttype'],
      header,
    );
    final idxCategory = _requireProductColumnIndex(
      byNorm,
      'Category',
      const ['category'],
      header,
    );
    final idxSubCategory = _requireProductColumnIndex(
      byNorm,
      'Sub-Category',
      const ['subcategory'],
      header,
    );
    final idxMinOrderQty = _requireProductColumnIndex(
      byNorm,
      'MinOrder Qty',
      const ['minorderqty'],
      header,
    );
    final idxCaseQty = _requireProductColumnIndex(
      byNorm,
      'Case Qty',
      const ['caseqty'],
      header,
    );

    final maxColIndex = [
      idxItemNumber,
      idxDescription,
      idxUpc,
      idxPrice,
      idxDiscount,
      idxProductType,
      idxCategory,
      idxSubCategory,
      idxMinOrderQty,
      idxCaseQty,
    ].reduce((a, b) => a > b ? a : b);

    debugPrint(
      '[Products] Column indices — Item:$idxItemNumber Desc:$idxDescription '
      'UPC:$idxUpc Price:$idxPrice DISCOUNT:$idxDiscount Type:$idxProductType '
      'Cat:$idxCategory Sub:${idxSubCategory} Min:${idxMinOrderQty} '
      'Case:$idxCaseQty (max:$maxColIndex)',
    );

    final Map<String, Product> newProductsByUpc = {};
    final Map<String, Product> newProductsByItemNumber = {};

    final int totalDataRows = rows.length - 1;
    int processedRows = 0;
    int skippedMissingKeyRows = 0;
    int skippedParseErrorRows = 0;
    int duplicateUpcCount = 0;
    int duplicateItemNumberCount = 0;
    int discountEligibleCount = 0;
    String? firstErrorMessage;

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty ||
          row.every((e) => e.toString().trim().isEmpty)) {
        skippedParseErrorRows++;
        continue;
      }

      try {
        final itemNumber = normalizeItemNumber(
          _productCell(row, idxItemNumber),
        );
        final description = _productCell(row, idxDescription).trim();
        final upc = _productCell(row, idxUpc).trim();
        final upcLookup = _normalizeUpcLookupKey(upc);
        final price = _parsePrice(_productCell(row, idxPrice));
        final discountRaw = _productCell(row, idxDiscount).trim();
        final discountEligible = _parseDiscountEligibility(discountRaw);
        if (discountEligible) discountEligibleCount++;
        final productType = _productCell(row, idxProductType).trim();
        final category = _productCell(row, idxCategory).trim();
        final subCategory = _productCell(row, idxSubCategory).trim();
        final minOrderQty = _parseInt(_productCell(row, idxMinOrderQty));
        final caseQty = _parseInt(_productCell(row, idxCaseQty));

        if (itemNumber.isEmpty || upcLookup.isEmpty) {
          skippedMissingKeyRows++;
          continue;
        }

        final product = Product(
          itemNumber: itemNumber,
          description: description,
          upc: upc,
          price: price,
          productType: productType,
          discountRaw: discountRaw,
          discountEligible: discountEligible,
          category: category,
          subCategory: subCategory,
          minOrderQty: minOrderQty == 0 ? 1 : minOrderQty,
          caseQty: caseQty,
        );

        if (newProductsByUpc.containsKey(upcLookup)) {
          duplicateUpcCount++;
        }
        if (newProductsByItemNumber.containsKey(itemNumber)) {
          duplicateItemNumberCount++;
        }

        newProductsByUpc[upcLookup] = product;
        newProductsByItemNumber[itemNumber] = product;
        processedRows++;
      } catch (e) {
        skippedParseErrorRows++;
        if (firstErrorMessage == null) {
          firstErrorMessage =
              'Row ${i + 1} parse error: $e (raw: ${row.map((c) => c.toString()).toList()})';
        }
      }
    }

    _productsByUpc
      ..clear()
      ..addAll(newProductsByUpc);

    _productsByItemNumber
      ..clear()
      ..addAll(newProductsByItemNumber);

    _catalogCount = _productsByUpc.length;
    _catalogSource = sourceLabel;

    final int skippedRows =
        skippedMissingKeyRows + skippedParseErrorRows;

    setProductsDebugLine('Products Loaded: $_catalogCount');

    debugPrint('----- PRODUCT LOAD REPORT -----');
    debugPrint('Total rows read: $totalDataRows');
    debugPrint('Products loaded: $_catalogCount');
    debugPrint('Discount-eligible products: $discountEligibleCount');
    debugPrint('Skipped rows: $skippedRows');
    debugPrint('Duplicate UPC rows: $duplicateUpcCount');
    debugPrint('Duplicate item number rows: $duplicateItemNumberCount');

    debugPrint(
      '[Products] Parsed $processedRows of $totalDataRows data rows from '
      '$sourceLabel. Loaded $_catalogCount products. '
      'Skipped missing key rows: $skippedMissingKeyRows, '
      'skipped other: $skippedParseErrorRows, '
      'duplicate UPCs: $duplicateUpcCount, '
      'duplicate item numbers: $duplicateItemNumberCount.',
    );
    if (firstErrorMessage != null) {
      debugPrint('[Products] First row parse error: $firstErrorMessage');
    }

    _debugLogMissingProductTypeMappings();
  }

  Future<void> _loadProductsFromAssets() async {
    debugPrint('[Products] _loadProductsFromAssets called');
    try {
      await _initAudio();
      await _loadQuoteBucketConfig();
      debugPrint('[Products] Attempting to load assets/data/products.csv');
      final rawCsv = await rootBundle.loadString('assets/data/products.csv');
      debugPrint(
        '[Products] products.csv loaded successfully '
        '(${rawCsv.length} characters)',
      );
      debugPrint('[Products] parse started');
      _parseAndStoreProducts(rawCsv, sourceLabel: 'Built-in catalog');
      debugPrint('[Products] parse completed');

      setState(() {
        _loadingProducts = false;
        _readyToScan = true;
        _status = 'Ready to scan';
      });

      _requestScannerFocus();
    } catch (e, st) {
      debugPrint('[Products] Error loading built-in products.csv: $e');
      debugPrint('[Products] Stack: $st');
      if (mounted) {
        setState(() {
          _loadingProducts = false;
          _readyToScan = false;
          _status = 'Error loading built-in catalog';
          _catalogCount = 0;
          _productsLoadDebugLine =
              'Products Loaded: FAILED (see debug log for $e)';
        });
      } else {
        _catalogCount = 0;
        _productsLoadDebugLine =
            'Products Loaded: FAILED (see debug log for $e)';
      }
    }
  }

  /// Load customers from assets/data/customers.csv (non-fatal if missing/bad).
  /// Called from [initState] so it always runs even if built-in product loading fails.
  Future<void> _loadCustomersFromAssets() async {
    debugPrint('[Customers] _loadCustomersFromAssets called');
    try {
      debugPrint('[Customers] Attempting to load assets/data/customers.csv');
      final rawCsv =
          await rootBundle.loadString('assets/data/customers.csv');
      debugPrint(
        '[Customers] customers.csv loaded successfully '
        '(${rawCsv.length} characters)',
      );
      _parseAndStoreCustomers(rawCsv);
      debugPrint('[Customers] parse completed');
    } catch (e, st) {
      debugPrint(
        '[Customers] Failed to load assets/data/customers.csv: $e',
      );
      debugPrint('[Customers] Stack: $st');
      if (mounted) {
        setState(() {
          _customers = [];
          _customersByKey.clear();
          _selectedCustomer = null;
          _customersLoadDebugLine =
              'Customers Loaded: FAILED (see debug log for $e)';
        });
      } else {
        _customers = [];
        _customersByKey.clear();
        _selectedCustomer = null;
      }
    }
  }

  Future<void> _loadCsvFromPhone() async {
    try {
      _editDialogOpen = true;

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      _editDialogOpen = false;

      if (result == null || result.files.isEmpty) {
        setState(() {
          _status = 'CSV load cancelled';
        });
        _requestScannerFocus();
        return;
      }

      final file = result.files.single;
      String? rawCsv;

      if (file.bytes != null) {
        rawCsv = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        rawCsv = await File(file.path!).readAsString();
      }

      if (rawCsv == null || rawCsv.trim().isEmpty) {
        setState(() {
          _status = 'Selected CSV was empty';
        });
        _requestScannerFocus();
        return;
      }

      debugPrint('[Products] parse started (phone CSV)');
      _parseAndStoreProducts(rawCsv, sourceLabel: file.name);
      debugPrint('[Products] parse completed (phone CSV)');
      debugPrint(
        '[Products] Loaded CSV from phone "${file.name}" '
        '(${rawCsv.length} characters). Catalog now has $_catalogCount '
        'products from source "$_catalogSource".',
      );

      setState(() {
        _readyToScan = true;
        _loadingProducts = false;
        _status = 'Loaded CSV: ${file.name}';
      });
    } catch (e, st) {
      _editDialogOpen = false;
      setState(() {
        _status = 'Error loading CSV from phone';
        _productsLoadDebugLine =
            'Products Loaded: FAILED (see debug log for $e)';
      });
      debugPrint('[Products] Error loading CSV from phone: $e');
      debugPrint('[Products] Stack: $st');
    }

    _requestScannerFocus();
  }

  /// Customers.csv headers: Id, CompanyName, Address, Address2, City, State, Zip, Phone, Fax, Email, Contact, SalesRepName, PriceList, Discount, PaymentTerms.
  void _parseAndStoreCustomers(String rawCsv) {
    debugPrint('[Customers] parse started');

    void setCustomersDebugLine(String line) {
      if (mounted) {
        setState(() => _customersLoadDebugLine = line);
      } else {
        _customersLoadDebugLine = line;
      }
    }

    void printCustomerLoadReport({
      required int totalRowsRead,
      required int customersLoaded,
      required int customersWithDiscount,
      required int skippedRows,
      required int duplicateKeyRows,
    }) {
      debugPrint('----- CUSTOMER LOAD REPORT -----');
      debugPrint('Total rows read: $totalRowsRead');
      debugPrint('Customers loaded: $customersLoaded');
      debugPrint('Customers with discount > 0: $customersWithDiscount');
      debugPrint('Skipped rows: $skippedRows');
      if (duplicateKeyRows > 0) {
        debugPrint(
          'Duplicate key rows skipped: $duplicateKeyRows '
          '(first occurrence kept; key is CSV Id, or CompanyName if Id empty)',
        );
      } else {
        debugPrint('Duplicate key rows skipped: 0');
      }
      if (customersLoaded == 0) {
        debugPrint(
          '[Customers] Zero customers in memory: check CSV content, headers, '
          'required columns (Id and/or CompanyName), empty data rows, or '
          'parse errors above.',
        );
      }
      setCustomersDebugLine('Customers Loaded: $customersLoaded');
    }

    void applyEmpty() {
      if (mounted) {
        setState(() {
          _customers = [];
          _customersByKey.clear();
          _selectedCustomer = null;
        });
      } else {
        _customers = [];
        _customersByKey.clear();
      }
    }

    final trimmed = rawCsv.trim();
    if (trimmed.isEmpty) {
      debugPrint('[Customers] CSV text is empty after trim.');
      printCustomerLoadReport(
        totalRowsRead: 0,
        customersLoaded: 0,
        customersWithDiscount: 0,
        skippedRows: 0,
        duplicateKeyRows: 0,
      );
      applyEmpty();
      return;
    }

    final firstLine = rawCsv.split('\n').first;
    final useTab =
        firstLine.split('\t').length > firstLine.split(',').length;
    List<List<dynamic>> rows;
    try {
      rows = CsvToListConverter(
        shouldParseNumbers: false,
        fieldDelimiter: useTab ? '\t' : ',',
      ).convert(rawCsv);
    } catch (e) {
      debugPrint('[Customers] CSV parse failed: $e');
      printCustomerLoadReport(
        totalRowsRead: 0,
        customersLoaded: 0,
        customersWithDiscount: 0,
        skippedRows: 0,
        duplicateKeyRows: 0,
      );
      applyEmpty();
      return;
    }

    if (rows.isEmpty) {
      debugPrint('[Customers] CSV parse produced no rows.');
      printCustomerLoadReport(
        totalRowsRead: 0,
        customersLoaded: 0,
        customersWithDiscount: 0,
        skippedRows: 0,
        duplicateKeyRows: 0,
      );
      applyEmpty();
      return;
    }

    final headerRow = rows[0].map((e) => e.toString().trim()).toList();
    debugPrint('[Customers] Headers found: ${headerRow.join(', ')}');
    int col(String name) {
      final i = headerRow.indexOf(name);
      return i >= 0 ? i : -1;
    }

    int colIgnoreCase(String name) {
      final lower = name.toLowerCase();
      for (int i = 0; i < headerRow.length; i++) {
        if (headerRow[i].toLowerCase() == lower) return i;
      }
      return -1;
    }

    final idxId = col('Id');
    final idxCompanyName = col('CompanyName');
    final idxAddress = col('Address');
    final idxAddress2 = col('Address2');
    final idxCity = col('City');
    final idxState = col('State');
    final idxZip = col('Zip');
    final idxPhone = col('Phone');
    final idxFax = col('Fax');
    final idxEmail = col('Email');
    final idxContact = col('Contact');
    final idxSalesRepName = col('SalesRepName');
    final idxPriceList = col('PriceList');
    final idxDiscount = colIgnoreCase('discount');
    final idxPaymentTerms = col('PaymentTerms');
    if (idxId < 0 && idxCompanyName < 0) {
      debugPrint(
        '[Customers] Missing required columns: need Id and/or CompanyName.',
      );
      debugPrint(
        '[Customers] Column index: Id=$idxId, CompanyName=$idxCompanyName, '
        'Discount=$idxDiscount',
      );
      printCustomerLoadReport(
        totalRowsRead: rows.length > 1 ? rows.length - 1 : 0,
        customersLoaded: 0,
        customersWithDiscount: 0,
        skippedRows: rows.length > 1 ? rows.length - 1 : 0,
        duplicateKeyRows: 0,
      );
      applyEmpty();
      return;
    }

    final totalRowsRead = rows.length > 1 ? rows.length - 1 : 0;
    final list = <Customer>[];
    final byKey = <String, Customer>{};
    var skippedRows = 0;
    var duplicateKeyRows = 0;
    var discountNonZero = 0;
    var duplicateLogBudget = 5;

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      try {
        if (row.every((c) => c.toString().trim().isEmpty)) {
          skippedRows++;
          continue;
        }

        String get(int index) => index >= 0 && index < row.length
            ? row[index].toString().trim()
            : '';

        final idPart = idxId >= 0 ? get(idxId) : '';
        final company = get(idxCompanyName);
        final lookupKey = idPart.isNotEmpty ? idPart : company;
        if (lookupKey.isEmpty) {
          skippedRows++;
          continue;
        }
        if (byKey.containsKey(lookupKey)) {
          duplicateKeyRows++;
          skippedRows++;
          if (duplicateLogBudget > 0) {
            duplicateLogBudget--;
            debugPrint(
              '[Customers] Duplicate key "$lookupKey" at CSV row ${i + 1}: '
              'skipped (first row at key wins).',
            );
          }
          continue;
        }

        final idForModel = idPart.isNotEmpty ? idPart : company;
        final discountCell = idxDiscount >= 0 ? get(idxDiscount) : '';
        final pct = Customer.parseDiscountPercentFromRaw(discountCell);

        final customer = Customer(
          id: idForModel,
          companyName: company,
          address: get(idxAddress),
          address2: get(idxAddress2),
          city: get(idxCity),
          state: get(idxState),
          zip: get(idxZip),
          phone: get(idxPhone),
          fax: get(idxFax),
          email: get(idxEmail),
          contact: get(idxContact),
          salesRepName: get(idxSalesRepName),
          priceList: get(idxPriceList),
          discount: discountCell,
          discountPercent: pct,
          paymentTerms: get(idxPaymentTerms),
        );

        byKey[lookupKey] = customer;
        list.add(customer);
        if (pct > 0) discountNonZero++;
      } catch (e) {
        skippedRows++;
        debugPrint('[Customers] Skipping row ${i + 1}: $e');
      }
    }

    if (duplicateKeyRows > 5) {
      debugPrint(
        '[Customers] ... ${duplicateKeyRows - 5} more duplicate key row(s) '
        'not shown (see Duplicate key rows skipped count in report).',
      );
    }

    printCustomerLoadReport(
      totalRowsRead: totalRowsRead,
      customersLoaded: list.length,
      customersWithDiscount: discountNonZero,
      skippedRows: skippedRows,
      duplicateKeyRows: duplicateKeyRows,
    );

    if (mounted) {
      setState(() {
        _customers = list;
        _customersByKey
          ..clear()
          ..addAll(byKey);
        _selectedCustomer = null;
      });
    } else {
      _customers = list;
      _customersByKey
        ..clear()
        ..addAll(byKey);
    }
  }

  Future<void> _loadCustomersCsvFromPhone() async {
    try {
      _editDialogOpen = true;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      _editDialogOpen = false;
      if (result == null || result.files.isEmpty) {
        setState(() => _status = 'Customers CSV load cancelled');
        _requestScannerFocus();
        return;
      }
      final file = result.files.single;
      String? rawCsv;
      if (file.bytes != null) {
        rawCsv = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        rawCsv = await File(file.path!).readAsString();
      }
      if (rawCsv == null || rawCsv.trim().isEmpty) {
        setState(() => _status = 'Selected customers CSV was empty');
        _requestScannerFocus();
        return;
      }
      _parseAndStoreCustomers(rawCsv);
      setState(() => _status = 'Loaded customers from ${file.name}');
    } catch (e) {
      _editDialogOpen = false;
      setState(() => _status = 'Error loading customers CSV');
    }
    _requestScannerFocus();
  }

  Future<void> _showSelectCustomerDialog() async {
    if (_customers.isEmpty) return;
    _editDialogOpen = true;
    final searchController = TextEditingController();
    final filtered = <Customer>[];
    filtered.addAll(_customers);
    final picked = await showDialog<Customer>(
      context: context,
      builder: (ctx) {
        var didRequestFocus = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!didRequestFocus) {
              didRequestFocus = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (!_searchCustomersFocusNode.hasFocus) {
                  FocusScope.of(context).requestFocus(_searchCustomersFocusNode);
                }
              });
              Future.delayed(const Duration(milliseconds: 150), () {
                if (!mounted) return;
                if (!_searchCustomersFocusNode.hasFocus) {
                  FocusScope.of(context).requestFocus(_searchCustomersFocusNode);
                }
              });
            }

            void applyCustomerFilter(String query) {
              final q = query.trim().toLowerCase();
              filtered
                ..clear()
                ..addAll(_customers.where((c) {
                  if (q.isEmpty) return true;
                  return c.displayName.toLowerCase().contains(q) ||
                      c.contact.toLowerCase().contains(q) ||
                      c.email.toLowerCase().contains(q) ||
                      c.companyName.toLowerCase().contains(q) ||
                      c.city.toLowerCase().contains(q) ||
                      c.state.toLowerCase().contains(q);
                }));
              setDialogState(() {});
            }
            return AlertDialog(
              title: const Text('Select Customer'),
              content: SizedBox(
                width: 400,
                height: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      focusNode: _searchCustomersFocusNode,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Search customers',
                        hintText: 'Name, contact, email...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: applyCustomerFilter,
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(18),
                                child: Text('No matching customers'),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final c = filtered[i];
                                return ListTile(
                                  title: Text(c.displayName),
                                  subtitle: c.contact.isEmpty
                                      ? null
                                      : Text(c.contact),
                                  onTap: () => Navigator.pop(ctx, c),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Clear selection'),
                ),
              ],
            );
          },
        );
      },
    );
    _editDialogOpen = false;
    if (!mounted) return;
    setState(() {
      _selectedCustomer = picked;
      _status = picked == null
          ? 'Customer cleared'
          : 'Customer: ${picked.displayName}';
    });
    _requestScannerFocus();
  }

  Product? _findProduct(String input) {
    final upc = _normalizeUpcLookupKey(input);
    final item = normalizeItemNumber(input);

    Product? product = _productsByUpc[upc];
    product ??= _productsByItemNumber[item];

    if (product == null && upc.length == 12 && upc.startsWith('0')) {
      product = _productsByUpc[upc.substring(1)];
    }

    if (product == null && upc.length == 11) {
      product = _productsByUpc['0$upc'];
    }

    return product;
  }

  bool _productIsDiscountEligible(Product product) => product.discountEligible;

  double _getCustomerDiscountPercent() =>
      _selectedCustomer?.discountPercent ?? 0.0;

  double _getLineDiscountPercent(OrderLine line) {
    if (!_productIsDiscountEligible(line.product)) return 0.0;
    final p = _getCustomerDiscountPercent();
    return p > 0 ? p : 0.0;
  }

  double _getDiscountedUnitPrice(OrderLine line) {
    final d = _getLineDiscountPercent(line);
    return line.product.price * (1 - d / 100.0);
  }

  double _getRegularLineTotal(OrderLine line) =>
      line.product.price * line.quantity;

  double _getDiscountedLineTotal(OrderLine line) =>
      _getDiscountedUnitPrice(line) * line.quantity;

  double _getLineDiscountAmount(OrderLine line) =>
      _getRegularLineTotal(line) - _getDiscountedLineTotal(line);

  bool _lineHasDiscount(OrderLine line) =>
      _getLineDiscountAmount(line) > 0.005;

  bool _orderHasAnyDiscount() => _orderDiscountAmount > 0.005;

  double _getTotalDiscountAmount() => _orderDiscountAmount;

  double _getRegularOrderTotal() => _regularOrderTotal;

  void _recalculateTotals() {
    int units = 0;
    double regularSum = 0.0;
    double discountedSum = 0.0;

    for (final line in _orderLines) {
      units += line.quantity;
      regularSum += _getRegularLineTotal(line);
      discountedSum += _getDiscountedLineTotal(line);
    }

    _totalUnits = units;
    _regularOrderTotal = regularSum;
    _orderTotal = discountedSum;
    _orderDiscountAmount = regularSum - discountedSum;
  }

  /// Call when quote/list becomes empty so next scan or manual entry is "first time" (single beep).
  void _resetQuoteDisplayAndScanState() {
    _lastAddedUpc = null;
    _lastItem = '-';
    _lastScan = '-';
    _qtyAdded = 0;
    _itemsScanned = 0;
    _lastProcessedScanUpc = null;
    _lastProcessedScanTime = null;
  }

  void _scrollToTopSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scanPanelScrollController.hasClients) return;
      _scanPanelScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  GlobalKey _globalKeyForScanTabOrderRow(String lineKey) =>
      _scanTabOrderRowKeys.putIfAbsent(lineKey, GlobalKey.new);

  /// Scan tab only: scroll parent [ListView] so the row is visible and flash-highlight briefly.
  /// Does not alter order data or scan processing.
  void _revealScanTabOrderRowAfterScan(String lineKey) {
    _scanTabHighlightClearTimer?.cancel();
    setState(() => _scanTabHighlightLineKey = lineKey);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _scanTabOrderRowKeys[lineKey]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.12,
        );
      }
    });

    _scanTabHighlightClearTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _scanTabHighlightLineKey = null);
    });
  }

  void _addProduct(
    Product product,
    String source, {
    required QuoteBucketDefinition bucket,
    /// When true (scanner path only): reveal/highlight the row instead of [_scrollToTopSoon].
    bool scheduleScanTabOrderRowReveal = false,
  }) {
    OrderLine line;
    final String key = _orderLineKeyForProduct(product);
    final bool isExistingLine = _orderLineByKey.containsKey(key);
    final int addedQty = product.minOrderQty;

    if (isExistingLine) {
      line = _orderLineByKey[key]!;
      line.quantity += addedQty;
      line.scans += 1;

      _orderLines.remove(line);
      _orderLines.insert(0, line);
    } else {
      line = OrderLine(
        product: product,
        quantity: addedQty,
        scans: 1,
      );

      _orderLines.insert(0, line);
      _orderLineByKey[key] = line;
    }

    _itemsScanned += 1;
    _qtyAdded = addedQty;
    _lastAddedUpc = product.upc;

    final int sampleId = _currentScanSampleId;
    if (sampleId > 0) {
      _logScanPerfStep(sampleId, 'item added');
      _logScanPerfStep(sampleId, 'totals updated');
      _logScanPerfStep(sampleId, 'setState start (item add state)');
    }
    _setStateDebug('item_add', () {
      if (_shouldAutoPrefixQuoteName()) {
        final prefixed = '${bucket.displayLabel} QUOTE ';
        _quoteNameController.text = prefixed;
        _quoteNameController.selection = TextSelection.collapsed(
          offset: prefixed.length,
        );
        _savedQuoteNameBeforeEdit = prefixed;
      }
      _activeQuoteBucketKey = bucket.bucketKey;
      _activeQuoteBucketLabel = bucket.displayLabel;
      _selectedLine = line;
      _lastScan = source;
      _lastItem = product.description;
      _status = 'Added to ${bucket.displayLabel} quote';
      _quickEntryStatus = 'Added ${product.itemNumber}';
      _recalculateTotals();
    });
    if (sampleId > 0) {
      _logScanPerfStep(sampleId, 'setState complete (item add state updated)');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _logScanPerfStep(sampleId, 'setState frame complete');
        _logScanPerfStep(sampleId, 'UI refresh triggered');
      });
    }

    if (scheduleScanTabOrderRowReveal) {
      final lineKey = _orderLineKeyForProduct(product);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _revealScanTabOrderRowAfterScan(lineKey);
      });
    } else {
      _scrollToTopSoon();
    }

    _triggerScanFeedback(
      isExistingLine
          ? ScanFeedbackType.successExistingItem
          : ScanFeedbackType.successNewItem,
    );
  }

  Future<void> _processScan(String value) async {
    try {
      final int sampleId = _currentScanSampleId;
      if (sampleId > 0) {
        _logScanPerfStep(sampleId, 'scan processing started');
      }
      final raw = value.trim();
      final upc = digitsOnly(raw);

      if (raw.isEmpty || upc.isEmpty) {
        _requestScannerFocus();
        return;
      }

      // Prevent double beep: scanner or focus can deliver same barcode twice in quick succession.
      final now = DateTime.now();
      if (_lastProcessedScanUpc == upc &&
          _lastProcessedScanTime != null &&
          now.difference(_lastProcessedScanTime!).inMilliseconds <
              _scanDedupeMs) {
        if (sampleId > 0) {
          _logScanPerfStep(
            sampleId,
            'duplicate dropped (<${_scanDedupeMs}ms window)',
          );
          _finishScanPerfSample(sampleId, outcome: 'duplicate-dropped');
          _currentScanSampleId = 0;
        }
        _requestScannerFocus();
        return;
      }
      _lastProcessedScanUpc = upc;
      _lastProcessedScanTime = now;

      final product = _findProduct(raw);
      if (sampleId > 0) {
        _logScanPerfStep(sampleId, 'product lookup complete');
      }
      if (_quickEntryController.text.trim() == raw) {
        _quickEntryController.clear();
      }

      if (product == null) {
        if (sampleId > 0) {
          _logScanPerfStep(sampleId, 'setState start (not-found state)');
        }
        _setStateDebug('scan_not_found', () {
          _lastScan = raw;
          _lastItem = 'NOT FOUND';
          _status = 'UPC / ITEM NOT FOUND';
        });
        if (sampleId > 0) {
          _logScanPerfStep(sampleId, 'setState complete (not-found state updated)');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _logScanPerfStep(sampleId, 'setState frame complete');
            _logScanPerfStep(sampleId, 'UI refresh triggered');
          });
        }
        _triggerScanFeedback(ScanFeedbackType.notFound);
        _requestScannerFocus();
        if (sampleId > 0) {
          _logScanPerfStep(sampleId, 'app ready for next scan');
          _finishScanPerfSample(sampleId, outcome: 'not-found');
          _currentScanSampleId = 0;
        }
        return;
      }
      await _ensureRoutingForProduct(product);
      final bucket = _resolveQuoteBucketForProduct(product);
      _addProduct(
        product,
        raw,
        bucket: bucket,
        scheduleScanTabOrderRowReveal: true,
      );
      _requestScannerFocus();
      if (sampleId > 0) {
        _logScanPerfStep(sampleId, 'app ready for next scan');
        _finishScanPerfSample(sampleId, outcome: 'item-added');
        _currentScanSampleId = 0;
      }
    } catch (e) {
      final int sampleId = _currentScanSampleId;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No match — try again'),
        ),
      );
      _quickEntryController.clear();
      _requestScannerFocus();
      if (sampleId > 0) {
        _finishScanPerfSample(sampleId, outcome: 'exception');
      }
      _currentScanSampleId = 0;
    }
  }

  void _enqueueScan(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (_currentScanSampleId > 0) {
      _logScanPerfStep(_currentScanSampleId, 'scan received');
    }

    _pendingScans.addLast(trimmed);
    if (_isProcessingScan) {
      return;
    }
    unawaited(_drainScanQueue());
  }

  Future<void> _drainScanQueue() async {
    if (_isProcessingScan) return;
    _isProcessingScan = true;
    try {
      while (_pendingScans.isNotEmpty && mounted) {
        final next = _pendingScans.removeFirst();
        await _processScan(next);
      }
    } finally {
      _isProcessingScan = false;
    }
  }

  /// Scanner "terminator" paths commit immediately (no idle debounce):
  /// newline or carriage return in the change text, [TextField.onSubmitted], or
  /// [TextField.onEditingComplete] (some stacks fire completion there for
  /// [TextInputType.none] without a reliable `onSubmitted`).
  /// Otherwise [_scanInputDebounceMs] idle debounce coalesces keystrokes for
  /// scanners that do not send a suffix.
  void _onScannerChanged(String value) {
    if (_manualEntryFocusTraceActive) {
      debugPrint(
        '[ScannerInput] onChanged (trace active): value="$value" scannerHasFocus=${_scannerFocusNode.hasFocus} '
        'quickEntryHasFocus=${_quickEntryFocusNode.hasFocus}',
      );
      final trimmed = value.trim();
      if (trimmed.isNotEmpty || value.contains('\n') || value.contains('\r')) {
        _manualEntryFocusTraceActive = false;
        _manualEntryFocusTraceTimeout?.cancel();
        debugPrint(
          '[ManualEntry][Debug] ending focus trace: scanner input received. scannerHasFocus=${_scannerFocusNode.hasFocus}',
        );
      }
    }

    _scanDebounceTimer?.cancel();
    // If the scanner sends an Enter/newline terminator, treat that as a
    // completion signal and process the full buffer immediately to avoid
    // acting on partial intermediate values.
    if (value.contains('\n') || value.contains('\r')) {
      _commitScannerBuffer(
        trigger: 'newline terminator',
        rawOverride: value,
      );
      return;
    }
    // Post-commit [clear] notifies with ""; skip debounce (would only re-commit empty).
    if (value.isEmpty) {
      return;
    }
    _scanDebounceTimer = Timer(Duration(milliseconds: _scanInputDebounceMs), () {
      if (!mounted) return;
      _commitScannerBuffer(trigger: 'debounce ${_scanInputDebounceMs}ms');
    });
  }

  void _onScannerSubmitted(String value) {
    _scanDebounceTimer?.cancel();
    _commitScannerBuffer(trigger: 'submit action', rawOverride: value);
  }

  void _onScannerEditingComplete() {
    _scanDebounceTimer?.cancel();
    _commitScannerBuffer(
      trigger: 'editing complete',
      rawOverride: _scannerController.text,
    );
  }

  void _commitScannerBuffer({
    required String trigger,
    String? rawOverride,
  }) {
    final source = rawOverride ?? _scannerController.text;
    final cleaned = source.replaceAll('\n', '').replaceAll('\r', '').trim();
    if (cleaned.isEmpty) {
      _scannerController.clear();
      _requestScannerFocus();
      return;
    }
    // Capture-and-clear at commit time so queued processing cannot erase
    // in-flight input from the next physical scan.
    _scannerController.clear();
    final int sampleId = _startScanPerfSample(cleaned);
    _currentScanSampleId = sampleId;
    _logScanPerfStep(sampleId, 'barcode text fully received ($trigger)');
    _enqueueScan(cleaned);
  }

  /// When user scans while focus is in quote name field, barcode gets typed there.
  /// Detect barcode-like input and process as scan, then restore quote name.
  void _onQuoteNameSubmitted(String value) {
    final trimmed = value.trim();
    final digits = digitsOnly(trimmed);

    if (digits.length >= 8 && digits == trimmed) {
      _quoteNameController.text = _savedQuoteNameBeforeEdit;
      _quoteNameController.selection = TextSelection.collapsed(
        offset: _savedQuoteNameBeforeEdit.length,
      );
      _enqueueScan(trimmed);
      _requestScannerFocus();
      return;
    }

    _savedQuoteNameBeforeEdit = trimmed.isEmpty
        ? 'NEW QUOTE'
        : trimmed.toUpperCase();

    if (_quoteNameController.text.trim().isEmpty) {
      _quoteNameController.text = 'NEW QUOTE';
    }

    _requestScannerFocus();
  }

  Future<void> _addQuickEntry() async {
    try {
      final input = _quickEntryController.text.trim();
      if (input.isEmpty) {
        debugPrint(
          '[ManualEntry][Submit] start input is empty. '
          'quickEntryHasFocus=${_quickEntryFocusNode.hasFocus} scannerHasFocus=${_scannerFocusNode.hasFocus}',
        );
        _requestScannerFocusAfterManualEntry(debugLabel: 'quickEntryEmptySubmit');
        return;
      }

      debugPrint(
        '[ManualEntry][Submit] start '
        'input="$input" '
        'quickEntryHasFocus=${_quickEntryFocusNode.hasFocus} scannerHasFocus=${_scannerFocusNode.hasFocus}',
      );
      _manualEntryFocusTraceActive = true;
      _manualEntryFocusTraceTimeout?.cancel();
      _manualEntryFocusTraceTimeout = Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        debugPrint(
          '[ManualEntry][Debug] focus trace timed out (no scanner input received within 4s). '
          'scannerHasFocus=${_scannerFocusNode.hasFocus} quickEntryHasFocus=${_quickEntryFocusNode.hasFocus}',
        );
        _manualEntryFocusTraceActive = false;
      });

      _searchDebounce?.cancel();
      if (_searchResults.isNotEmpty) {
        _setStateDebug('quick_entry_pre_lookup_clear_search', () {
          _searchResults = [];
        });
      }

      final product = _findProduct(input);

      if (product == null) {
        _setStateDebug('quick_entry_not_found_status', () {
          _quickEntryStatus = 'Item not found';
          _status = 'Quick entry not found';
        });
        _quickEntryController.clear();
        _setStateDebug('quick_entry_not_found_clear_search', () {
          _searchResults = [];
        });
        _triggerScanFeedback(ScanFeedbackType.notFound);
        _requestScannerFocusAfterManualEntry(
          debugLabel: 'quickEntryNotFound',
        );
        return;
      }

      _quickEntryController.clear();
      await _ensureRoutingForProduct(product);
      final bucket = _resolveQuoteBucketForProduct(product);
      _addProduct(product, input, bucket: bucket);

      if (_searchResults.isNotEmpty) {
        _setStateDebug('quick_entry_clear_search_after_add', () {
          _searchResults = [];
        });
      }
      _requestScannerFocusAfterManualEntry(debugLabel: 'quickEntrySuccess');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No match — try again'),
        ),
      );
      _scannerController.clear();
      _quickEntryController.clear();
      _setStateDebug('quick_entry_clear_search_after_error', () {
        _searchResults = [];
      });
      _requestScannerFocusAfterManualEntry(debugLabel: 'quickEntryCatch');
    }
  }

  void _requestScannerFocusAfterManualEntry({required String debugLabel}) {
    final insetBottom = MediaQuery.viewInsetsOf(context).bottom;
    if (insetBottom > 0) {
      setState(() {
        _quickEntryHoldFloatingLayoutForKeyboard = true;
      });
    }
    debugPrint(
      '[ManualEntry][Submit] completed ($debugLabel). '
      'After submit: quickEntryHasFocus=${_quickEntryFocusNode.hasFocus} scannerHasFocus=${_scannerFocusNode.hasFocus} '
      'restoring scanner focus will run next frame.',
    );

    // Ensure any focus state updates (like `unfocus()`) are applied before the
    // scanner-focus guard runs. Without this, `_requestScannerFocus()` can be
    // blocked because quickEntry is still "effectively" focused.
    if (_quickEntryFocusNode.hasFocus) {
      _quickEntryFocusNode.unfocus();
    }
    FocusManager.instance.primaryFocus?.unfocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_editDialogOpen || !_scanTabActive) {
        debugPrint(
          '[ManualEntry][Submit] post-frame skip scanner restore '
          '(editDialogOpen=$_editDialogOpen, scanTabActive=$_scanTabActive).',
        );
        return;
      }
      debugPrint(
        '[ManualEntry][Submit] post-frame. '
        'quickEntryHasFocus=${_quickEntryFocusNode.hasFocus} scannerHasFocus=${_scannerFocusNode.hasFocus} '
        'scheduling scanner focus restore.',
      );
      _scheduleScannerRefocus();
      _scannerController.clear();
      debugPrint(
        '[ManualEntry][Submit] scanner focus recovery scheduled. '
        'scannerHasFocus=${_scannerFocusNode.hasFocus}',
      );

      // Mark trace "complete" for the next scanner keystroke; `_onScannerChanged`
      // will stop it as soon as scanner input is received.
      // (If scanner never receives input, the timeout above will end trace.)
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();

    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      final query = value.trim().toLowerCase();

      if (query.isEmpty) {
        _setStateDebug('search_debounce_clear_results', () {
          _searchResults = [];
        });
        return;
      }

      final results = _allProducts.where((p) {
        return p.itemNumber.toLowerCase().contains(query) ||
            p.description.toLowerCase().contains(query);
      }).take(10).toList();

      _setStateDebug('search_debounce_apply_results', () {
        _searchResults = results;
      });
    });
  }

  Future<void> _showEditQuantityDialog(OrderLine line) async {
    final controller = TextEditingController(text: line.quantity.toString());

    _editDialogOpen = true;

    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: AlertDialog(
              title: const Text('Edit Quantity'),
              content: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration:
                    InputDecoration(labelText: line.product.description),
                onSubmitted: (_) {
                  final qty = int.tryParse(controller.text.trim());
                  Navigator.pop(dialogContext, qty);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final qty = int.tryParse(controller.text.trim());
                    Navigator.pop(dialogContext, qty);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        );
      },
    );

    _editDialogOpen = false;

    if (result == null) {
      _requestScannerFocus();
      return;
    }

    if (result <= 0) {
      setState(() {
        _status = 'Quantity must be greater than 0';
      });
      _requestScannerFocus();
      return;
    }

    setState(() {
      _selectedLine = line;
      line.quantity = result;
      _recalculateTotals();
      _status = 'Quantity updated';
    });

    _requestScannerFocus();
  }

  Future<void> _confirmDeleteLine(OrderLine line) async {
    _editDialogOpen = true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Item'),
          content: Text('Remove ${line.product.description} from this order?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    _editDialogOpen = false;

    if (confirm == true) {
      setState(() {
        final wasSelected = identical(_selectedLine, line);

        _orderLines.remove(line);
        _orderLineByKey.remove(_orderLineKeyForProduct(line.product));
        _recalculateTotals();
        _status = 'Item deleted';

        if (_orderLines.isEmpty) {
          _resetQuoteDisplayAndScanState();
          _selectedLine = null;
        } else {
          if (_lastAddedUpc == line.product.upc) {
            final newLastLine = _orderLines.first;
            _lastAddedUpc = newLastLine.product.upc;
            _lastItem = newLastLine.product.description;
          }
          if (wasSelected) {
            _selectedLine = _orderLines.first;
          }
        }
      });
    }

    _requestScannerFocus();
  }

  Future<void> _confirmNewQuote() async {
    if (!mounted) return;

    final hasItems = _orderLines.isNotEmpty;

    final customerForNewQuote = await _ensureCustomerForNewQuote();
    if (customerForNewQuote == null || !mounted) return;

    // Only after a customer is assigned do we ask whether to proceed.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Create Quote'),
          content: Text(
            hasItems
                ? 'Your current order (${_orderLines.length} item${_orderLines.length == 1 ? '' : 's'}) will be saved first, then you can create a quote.'
                : 'Create a quote?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Create Quote'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    if (hasItems) await _saveQuote();
    if (!mounted) return;

    await _startNewQuote(customerForNewQuote);
  }

  Future<Customer?> _ensureCustomerForNewQuote() async {
    if (_selectedCustomer != null) return _selectedCustomer;

    final continueToSelect = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Select Customer'),
          content: const Text(
            'A customer is required before creating a quote.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (continueToSelect != true || !mounted) return null;

    await _showSelectCustomerDialog();
    if (!mounted) return null;
    if (_selectedCustomer == null) {
      setState(() => _status = 'Create quote canceled: customer required');
    }
    return _selectedCustomer;
  }

  Future<void> _startNewQuote(
    Customer customer, {
    QuoteBucketDefinition? initialBucket,
  }) async {
    final defaultName = await _generateDefaultQuoteName();
    final bucket = initialBucket ?? _defaultQuoteBucketDefinition;
    final isEverydayBucket =
        _logicalQuoteBucketKey(bucket.bucketKey) == _defaultQuoteBucketKey;
    final initialName = isEverydayBucket
        ? 'EVERYDAY $defaultName'
        : '${bucket.displayLabel} $defaultName';

    _setStateDebug('routing_start_new_quote', () {
      _orderLines.clear();
      _orderLineByKey.clear();
      _recalculateTotals();
      _resetQuoteDisplayAndScanState();
      _status = 'Create quote started';
      _quickEntryStatus = '-';
      _quoteNameController.text = initialName;
      _savedQuoteNameBeforeEdit = initialName;
      _quoteNameUserEdited = false;
      _selectedLine = null;
      _selectedCustomer = customer;
      _currentQuoteId = null;
      _activeQuoteBucketKey = bucket.bucketKey;
      _activeQuoteBucketLabel = bucket.displayLabel;
    });

    _requestScannerFocus();

    _debugLogQuoteImportExport(
      '[QuoteStarter] bucket=${bucket.bucketKey} '
      'logical=${_logicalQuoteBucketKey(bucket.bucketKey)} '
      'customer="${customer.displayName}"',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_quoteNameFocusNode.hasFocus && !_quickEntryFocusNode.hasFocus) {
        _scheduleScannerRefocus();
      }
    });
  }

  Future<Directory> _getQuotesDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final quotesDir = Directory('${appDir.path}/showroom_quotes');

    if (!await quotesDir.exists()) {
      await quotesDir.create(recursive: true);
    }

    return quotesDir;
  }

  /// Legacy single-file quote index (pre–split storage). Preserved on disk
  /// after one-time migration; not deleted automatically.
  Future<String> _getQuoteIndexPath() async {
    final dir = await _getQuotesDirectory();
    return '${dir.path}/quotes_index.json';
  }

  Future<String> _getQuoteActiveIndexPath() async {
    final dir = await _getQuotesDirectory();
    return '${dir.path}/quotes_active.json';
  }

  Future<String> _getQuoteArchiveIndexPath() async {
    final dir = await _getQuotesDirectory();
    return '${dir.path}/quotes_archive.json';
  }

  List<SavedQuoteInfo> _parseQuoteIndexEntriesDefensively(
    List<Map<String, dynamic>> rawList,
  ) {
    final out = <SavedQuoteInfo>[];
    for (final map in rawList) {
      try {
        final info = SavedQuoteInfo.fromJson(map);
        if (info.id.isEmpty) continue;
        out.add(info);
      } catch (_) {}
    }
    return out;
  }

  Future<List<SavedQuoteInfo>> _loadSavedQuotesFromIndexFile(
    File file,
    Directory quotesDir,
  ) async {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! List) {
      return [];
    }
    final rawList = decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final list = _parseQuoteIndexEntriesDefensively(rawList);
    final valid = <SavedQuoteInfo>[];
    for (final info in list) {
      final quoteFile = File('${quotesDir.path}/quote_${info.id}.json');
      if (await quoteFile.exists()) {
        valid.add(info);
      }
    }
    return valid;
  }

  /// If [quotes_index.json] exists and [quotes_active.json] does not, partition
  /// entries into active vs archive files. Legacy file is left unchanged.
  Future<void> _ensureLegacyQuoteIndexMigratedIfNeeded() async {
    final legacyFile = File(await _getQuoteIndexPath());
    final activeFile = File(await _getQuoteActiveIndexPath());
    if (!await legacyFile.exists() || await activeFile.exists()) {
      return;
    }

    try {
      final content = await legacyFile.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! List) {
        return;
      }
      final rawList = decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final parsed = _parseQuoteIndexEntriesDefensively(rawList);
      final activeInfos = <SavedQuoteInfo>[];
      final archiveInfos = <SavedQuoteInfo>[];
      for (final info in parsed) {
        if (info.status == QuoteLifecycleStatus.active) {
          activeInfos.add(info);
        } else {
          archiveInfos.add(info);
        }
      }
      await activeFile.writeAsString(
        jsonEncode(activeInfos.map((e) => e.toJson()).toList()),
        flush: true,
      );
      if (archiveInfos.isNotEmpty) {
        await _saveArchiveQuoteIndex(archiveInfos);
      }
    } catch (_) {
      // Keep legacy file; active file absent → callers fall back to legacy reads.
    }
  }

  /// Writable active index: [quotes_active.json] after migration or new data,
  /// otherwise legacy [quotes_index.json] if it still exists alone.
  Future<File> _activeQuoteIndexFileForReadWrite(Directory dir) async {
    await _ensureLegacyQuoteIndexMigratedIfNeeded();
    final activeFile = File(await _getQuoteActiveIndexPath());
    final legacyFile = File(await _getQuoteIndexPath());
    if (await activeFile.exists()) {
      return activeFile;
    }
    if (await legacyFile.exists()) {
      return legacyFile;
    }
    return activeFile;
  }

  /// Loads archived / confirmed quote index entries (for future archive UI).
  /// Does not remove or modify active storage.
  Future<List<SavedQuoteInfo>> _loadArchiveQuoteIndex() async {
    try {
      await _ensureLegacyQuoteIndexMigratedIfNeeded();
      final path = await _getQuoteArchiveIndexPath();
      final file = File(path);
      if (!await file.exists()) {
        return [];
      }
      final dir = await _getQuotesDirectory();
      return _loadSavedQuotesFromIndexFile(file, dir);
    } catch (_) {
      return [];
    }
  }

  /// Persists the archive index only; does not touch active quotes or legacy file.
  Future<void> _saveArchiveQuoteIndex(List<SavedQuoteInfo> entries) async {
    final path = await _getQuoteArchiveIndexPath();
    final file = File(path);
    await file.writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  /// When saving a working quote to the active index, drop the same id from archive
  /// so the same quote cannot exist in both places after a re-save.
  Future<void> _removeQuoteFromArchiveIndexIfPresent(String quoteId) async {
    try {
      final existing = await _loadArchiveQuoteIndex();
      if (existing.every((e) => e.id != quoteId)) return;
      await _saveArchiveQuoteIndex(
        existing.where((e) => e.id != quoteId).toList(),
      );
    } catch (e, st) {
      debugPrint(
        '[QuoteArchive] remove id=$quoteId from archive failed: $e\n$st',
      );
    }
  }

  /// IDs listed in the on-disk active index ([quotes_active.json] after migration).
  Future<Set<String>> _loadActiveIndexIds() async {
    try {
      final dir = await _getQuotesDirectory();
      await _ensureLegacyQuoteIndexMigratedIfNeeded();
      final indexFile = await _activeQuoteIndexFileForReadWrite(dir);
      if (!await indexFile.exists()) {
        return {};
      }
      final decoded = jsonDecode(await indexFile.readAsString());
      if (decoded is! List) {
        return {};
      }
      final ids = <String>{};
      for (final e in decoded) {
        if (e is! Map) continue;
        final id = e['id']?.toString();
        if (id != null && id.isNotEmpty) {
          ids.add(id);
        }
      }
      return ids;
    } catch (_) {
      return {};
    }
  }

  Future<bool> _isQuoteIdActive(String id) async {
    if (id.isEmpty) return false;
    return (await _loadActiveIndexIds()).contains(id);
  }

  void _refreshArchiveTabAfterIndexMutation() {
    _archiveQuotesTabKey.currentState?.reloadArchiveList();
    if (mounted) setState(() {});
  }

  /// Removes one row from [quotes_archive.json]; deletes [quote_<id>.json] only when
  /// [id] is not in the active index.
  Future<bool> _deleteArchivedQuoteById(String id) async {
    if (id.isEmpty) return false;
    try {
      final archiveEntries = await _loadArchiveQuoteIndex();
      if (!archiveEntries.any((e) => e.id == id)) {
        return false;
      }
      final newArchive = archiveEntries.where((e) => e.id != id).toList();
      await _saveArchiveQuoteIndex(newArchive);
      if (!await _isQuoteIdActive(id)) {
        final dir = await _getQuotesDirectory();
        final quoteFile = File('${dir.path}/quote_$id.json');
        if (await quoteFile.exists()) {
          await quoteFile.delete();
        }
      }
      _refreshArchiveTabAfterIndexMutation();
      return true;
    } catch (e, st) {
      debugPrint('[QuoteArchive] delete by id failed: $e\n$st');
      return false;
    }
  }

  /// [status] is `archived` or `confirmed`. Returns number of archive index rows removed.
  Future<int> _purgeArchivedQuotesByStatus(String status) async {
    final wantStatus = status.toLowerCase().trim() == 'confirmed'
        ? QuoteLifecycleStatus.confirmed
        : QuoteLifecycleStatus.archived;
    try {
      final archiveEntries = await _loadArchiveQuoteIndex();
      final toRemoveIds = archiveEntries
          .where((e) => e.status == wantStatus)
          .map((e) => e.id)
          .where((id) => id.isNotEmpty)
          .toList();
      if (toRemoveIds.isEmpty) {
        return 0;
      }
      final removeSet = toRemoveIds.toSet();
      final newArchive =
          archiveEntries.where((e) => !removeSet.contains(e.id)).toList();
      await _saveArchiveQuoteIndex(newArchive);
      final activeIds = await _loadActiveIndexIds();
      final dir = await _getQuotesDirectory();
      for (final qid in removeSet) {
        if (!activeIds.contains(qid)) {
          final f = File('${dir.path}/quote_$qid.json');
          if (await f.exists()) {
            await f.delete();
          }
        }
      }
      _refreshArchiveTabAfterIndexMutation();
      return toRemoveIds.length;
    } catch (e, st) {
      debugPrint('[QuoteArchive] purge by status failed: $e\n$st');
      return 0;
    }
  }

  /// Another quote already in the active workflow for the same logical customer + bucket.
  Future<SavedQuoteInfo?> _findActiveIndexRowConflictingWithRestore(
    SavedQuoteInfo archived,
  ) async {
    if (archived.id.isEmpty) return null;
    try {
      final dir = await _getQuotesDirectory();
      await _ensureLegacyQuoteIndexMigratedIfNeeded();
      final indexFile = await _activeQuoteIndexFileForReadWrite(dir);
      if (!await indexFile.exists()) return null;
      final decoded = jsonDecode(await indexFile.readAsString());
      if (decoded is! List) return null;
      final soughtBucket = _logicalQuoteBucketKey(archived.quoteBucketKey);
      for (final e in decoded) {
        if (e is! Map) continue;
        SavedQuoteInfo info;
        try {
          info = SavedQuoteInfo.fromJson(Map<String, dynamic>.from(e));
        } catch (_) {
          continue;
        }
        if (info.id.isEmpty || info.id == archived.id) continue;
        if (!_sameLogicalCustomerQuoteRows(
          customerIdA: archived.customerId,
          customerNameA: archived.customerName,
          customerIdB: info.customerId,
          customerNameB: info.customerName,
        )) {
          continue;
        }
        if (_logicalQuoteBucketKey(info.quoteBucketKey) != soughtBucket) {
          continue;
        }
        if (await _quoteIdHasActiveEligibleRowInActiveIndexStorage(info.id)) {
          return info;
        }
      }
    } catch (e, st) {
      debugPrint('[QuoteArchive] conflict check failed: $e\n$st');
    }
    return null;
  }

  /// Moves [archived] from [quotes_archive.json] to the active index as [active];
  /// does not load it into the in-memory workspace. Rolls back archive if active write fails.
  Future<bool> _restoreArchivedQuoteToActiveIndex(SavedQuoteInfo archived) async {
    if (archived.id.isEmpty) return false;
    try {
      final dir = await _getQuotesDirectory();
      final quoteFile = File('${dir.path}/quote_${archived.id}.json');
      if (!await quoteFile.exists()) return false;

      final archiveEntries = await _loadArchiveQuoteIndex();
      if (!archiveEntries.any((e) => e.id == archived.id)) return false;

      final previousArchive = List<SavedQuoteInfo>.from(archiveEntries);
      final newArchive =
          archiveEntries.where((e) => e.id != archived.id).toList();

      final now = DateTime.now();
      final restored = SavedQuoteInfo(
        id: archived.id,
        name: archived.name,
        customerName: archived.customerName,
        customerId: archived.customerId,
        quoteBucketKey: archived.quoteBucketKey,
        quoteBucketLabel: archived.quoteBucketLabel,
        updatedAt: now,
        status: QuoteLifecycleStatus.active,
        exportedAt: archived.exportedAt,
        confirmedAt: null,
        exportedFilePaths: archived.exportedFilePaths,
        exportedFileNames: archived.exportedFileNames,
      );

      await _saveArchiveQuoteIndex(newArchive);

      try {
        final activeFile = await _activeQuoteIndexFileForReadWrite(dir);
        List<Map<String, dynamic>> list = [];
        if (await activeFile.exists()) {
          final content = await activeFile.readAsString();
          final decoded = jsonDecode(content);
          if (decoded is List) {
            list = List<Map<String, dynamic>>.from(
              decoded.map((e) => Map<String, dynamic>.from(e as Map)),
            );
          }
        }
        list.removeWhere((e) => e['id']?.toString() == archived.id);
        list.insert(0, restored.toJson());
        await activeFile.writeAsString(jsonEncode(list), flush: true);
      } catch (e, st) {
        debugPrint(
          '[QuoteArchive] restore active index write failed; rolling back archive: $e\n$st',
        );
        await _saveArchiveQuoteIndex(previousArchive);
        return false;
      }
      return true;
    } catch (e, st) {
      debugPrint('[QuoteArchive] restore failed: $e\n$st');
      return false;
    }
  }

  Future<bool> _archiveMarkQuoteConfirmed(SavedQuoteInfo info) async {
    if (info.status != QuoteLifecycleStatus.archived) return false;
    if (info.id.isEmpty) return false;
    try {
      final list = await _loadArchiveQuoteIndex();
      final i = list.indexWhere((e) => e.id == info.id);
      if (i < 0) return false;
      final now = DateTime.now();
      final cur = list[i];
      list[i] = SavedQuoteInfo(
        id: cur.id,
        name: cur.name,
        customerName: cur.customerName,
        customerId: cur.customerId,
        quoteBucketKey: cur.quoteBucketKey,
        quoteBucketLabel: cur.quoteBucketLabel,
        updatedAt: cur.updatedAt,
        status: QuoteLifecycleStatus.confirmed,
        exportedAt: cur.exportedAt,
        confirmedAt: now,
        exportedFilePaths: cur.exportedFilePaths,
        exportedFileNames: cur.exportedFileNames,
      );
      await _saveArchiveQuoteIndex(list);
      return true;
    } catch (e, st) {
      debugPrint('[QuoteArchive] mark confirmed failed: $e\n$st');
      return false;
    }
  }

  String _customerDisplayNameForExportFromQuoteData(
    Map<String, dynamic> quoteData,
    SavedQuoteInfo indexFallback,
  ) {
    final customerMap = quoteData['customer'];
    if (customerMap is Map<String, dynamic>) {
      try {
        return Customer.fromJson(
          Map<String, dynamic>.from(customerMap),
        ).displayName.trim();
      } catch (_) {}
    }
    return indexFallback.customerName.trim();
  }

  /// Writes CSV from on-disk quote JSON only; updates archive index metadata, no active/workspace changes.
  Future<File?> _archiveReexportQuoteToCsv(SavedQuoteInfo info) async {
    if (info.id.isEmpty) return null;
    try {
      final dir = await _getQuotesDirectory();
      final quoteFile = File('${dir.path}/quote_${info.id}.json');
      if (!await quoteFile.exists()) return null;
      final quoteRaw = await quoteFile.readAsString();
      final quoteData = Map<String, dynamic>.from(jsonDecode(quoteRaw) as Map);
      if (persistedQuoteDataIsEmptyForReuse(quoteData)) {
        return null;
      }
      final csvText = _formatQuoteAsCsv(quoteData);
      final quoteName = (quoteData['name'] as String?)?.trim() ?? info.name;
      final customerName =
          _customerDisplayNameForExportFromQuoteData(quoteData, info);
      final exportedOn = DateTime.now();
      final filename = _buildExportOrderCsvFilename(
        quoteName: quoteName,
        customerName: customerName,
        exportedOn: exportedOn,
      );
      final outFile = await exportOrderCsvToShowroomExportsLayout(
        customerDisplayName: customerName,
        filename: filename,
        csvText: csvText,
      );

      final arch = await _loadArchiveQuoteIndex();
      final i = arch.indexWhere((e) => e.id == info.id);
      if (i >= 0) {
        final e = arch[i];
        final basePath = outFile.path;
        final baseName = p.basename(basePath);
        arch[i] = SavedQuoteInfo(
          id: e.id,
          name: e.name,
          customerName: e.customerName,
          customerId: e.customerId,
          quoteBucketKey: e.quoteBucketKey,
          quoteBucketLabel: e.quoteBucketLabel,
          updatedAt: e.updatedAt,
          status: e.status,
          exportedAt: exportedOn,
          confirmedAt: e.confirmedAt,
          exportedFilePaths: [...e.exportedFilePaths, basePath],
          exportedFileNames: [...e.exportedFileNames, baseName],
        );
        await _saveArchiveQuoteIndex(arch);
      }
      return outFile;
    } catch (e, st) {
      debugPrint('[QuoteArchive] re-export failed: $e\n$st');
      return null;
    }
  }

  Future<void> _showArchivedQuoteReadOnlyDialog(SavedQuoteInfo info) async {
    if (!mounted) return;
    final dir = await _getQuotesDirectory();
    final file = File('${dir.path}/quote_${info.id}.json');
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved quote file was not found.')),
      );
      return;
    }
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read quote file.')),
      );
      return;
    }
    if (!mounted) return;
    final stats = quoteDataLineStatsAndTotal(data);
    final lines =
        data['lines'] as List<dynamic>? ?? data['items'] as List<dynamic>? ?? [];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Quote details (read-only)'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    info.customerName.trim().isEmpty
                        ? '(No customer name)'
                        : info.customerName.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('Quote: ${info.name.trim().isEmpty ? '(unnamed)' : info.name.trim()}'),
                  Text(
                    'Bucket: ${info.quoteBucketLabel.trim().isNotEmpty ? info.quoteBucketLabel.trim() : info.quoteBucketKey}',
                  ),
                  if (info.exportedAt != null)
                    Text('Exported: ${info.exportedAt}'),
                  if (info.confirmedAt != null)
                    Text('Confirmed: ${info.confirmedAt}'),
                  const SizedBox(height: 8),
                  Text(
                    'Lines: ${stats.$1} · Units: ${stats.$2} · '
                    'Total: \$${stats.$3.toStringAsFixed(2)}',
                  ),
                  const Divider(height: 20),
                  const Text('Line items', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ...lines.map((lineJson) {
                    final map = Map<String, dynamic>.from(lineJson as Map);
                    final desc = (map['description'] as String?) ?? '';
                    final item = (map['itemNumber'] as String?) ?? '';
                    final qty = (map['quantity'] as int?) ?? 1;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${item.isNotEmpty ? item : desc} × $qty',
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmArchiveDelete({
    required BuildContext context,
    required _ArchiveDeleteConfirmKind kind,
  }) async {
    late final String title;
    late final String body;
    late final String confirmLabel;
    switch (kind) {
      case _ArchiveDeleteConfirmKind.singleArchived:
        title = 'Delete this archived quote?';
        body =
            'This will permanently remove it from Archive. Active quotes will not be affected.';
        confirmLabel = 'Delete';
        break;
      case _ArchiveDeleteConfirmKind.singleConfirmed:
        title = 'Delete this confirmed quote?';
        body =
            'This will permanently remove it from Archive. Active quotes will not be affected.';
        confirmLabel = 'Delete';
        break;
      case _ArchiveDeleteConfirmKind.purgeArchived:
        title = 'Purge all archived quotes?';
        body =
            'This will permanently delete all archived quotes in the Archive section. Confirmed and active quotes will not be affected.';
        confirmLabel = 'Purge';
        break;
      case _ArchiveDeleteConfirmKind.purgeConfirmed:
        title = 'Purge all confirmed quotes?';
        body =
            'This will permanently delete all confirmed quotes in the Archive section. Active quotes will not be affected.';
        confirmLabel = 'Purge';
        break;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _onArchiveRestorePressed(SavedQuoteInfo info) async {
    final conflict = await _findActiveIndexRowConflictingWithRestore(info);
    if (!mounted) return;
    if (conflict != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot restore because an active quote already exists for this customer and bucket.',
          ),
        ),
      );
      return;
    }
    final ok = await _restoreArchivedQuoteToActiveIndex(info);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quote restored to Active.')),
      );
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not restore quote.')),
      );
    }
  }

  Future<void> _onArchiveConfirmPressed(SavedQuoteInfo info) async {
    final ok = await _archiveMarkQuoteConfirmed(info);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quote marked Confirmed.')),
      );
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update quote.')),
      );
    }
  }

  Future<void> _onArchiveReexportPressed(SavedQuoteInfo info) async {
    final file = await _archiveReexportQuoteToCsv(info);
    if (!mounted) return;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to export (quote is empty or file missing).'),
        ),
      );
      return;
    }
    await _shareSingleExportedCsv(file);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Archived quote re-exported.')),
    );
    setState(() {});
  }

  Future<void> _onArchiveDeletePressed(SavedQuoteInfo info) async {
    if (!mounted) return;
    final kind = info.status == QuoteLifecycleStatus.confirmed
        ? _ArchiveDeleteConfirmKind.singleConfirmed
        : _ArchiveDeleteConfirmKind.singleArchived;
    if (!await _confirmArchiveDelete(context: context, kind: kind)) {
      return;
    }
    if (!mounted) return;
    final ok = await _deleteArchivedQuoteById(info.id);
    if (!mounted) return;
    if (ok) {
      final msg = info.status == QuoteLifecycleStatus.confirmed
          ? 'Confirmed quote deleted'
          : 'Archived quote deleted';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _onPurgeArchivedPressed() async {
    if (!mounted) return;
    if (!await _confirmArchiveDelete(
      context: context,
      kind: _ArchiveDeleteConfirmKind.purgeArchived,
    )) {
      return;
    }
    if (!mounted) return;
    final n = await _purgeArchivedQuotesByStatus('archived');
    if (!mounted) return;
    final archivedMsg = n == 1
        ? '1 archived quote deleted'
        : '$n archived quotes deleted';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(archivedMsg)),
    );
  }

  Future<void> _onPurgeConfirmedPressed() async {
    if (!mounted) return;
    if (!await _confirmArchiveDelete(
      context: context,
      kind: _ArchiveDeleteConfirmKind.purgeConfirmed,
    )) {
      return;
    }
    if (!mounted) return;
    final n = await _purgeArchivedQuotesByStatus('confirmed');
    if (!mounted) return;
    final confirmedMsg = n == 1
        ? '1 confirmed quote deleted'
        : '$n confirmed quotes deleted';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(confirmedMsg)),
    );
  }

  Widget _buildArchiveTab() {
    if (_activeTabIndex != 2) {
      return const SizedBox.shrink();
    }
    return _ArchiveQuotesTab(
      key: _archiveQuotesTabKey,
      onView: _showArchivedQuoteReadOnlyDialog,
      onRestore: _onArchiveRestorePressed,
      onConfirm: _onArchiveConfirmPressed,
      onReexport: _onArchiveReexportPressed,
      onDelete: _onArchiveDeletePressed,
      onPurgeArchived: _onPurgeArchivedPressed,
      onPurgeConfirmed: _onPurgeConfirmedPressed,
      loadArchive: _loadArchiveQuoteIndex,
    );
  }

  /// After a successful CSV export: removes [quoteId] from the active index and
  /// adds it to [quotes_archive.json]. Saves archive before mutating active;
  /// restores the previous archive snapshot if updating active fails.
  /// Also removes every other active index row for the same customer and logical
  /// export bucket (see [_logicalQuoteBucketKey] identity) so duplicate Everyday rows
  /// (e.g. legacy empty [quoteBucketKey] vs [every_day]) cannot survive export.
  /// Does not delete `quote_<id>.json` files or any CSV on disk.
  Future<bool> _moveActiveQuoteToArchiveAfterSuccessfulExport({
    required String quoteId,
    required DateTime exportedAt,
    required File exportedFile,
  }) async {
    try {
      final dir = await _getQuotesDirectory();
      final activeFile = await _activeQuoteIndexFileForReadWrite(dir);
      if (!await activeFile.exists()) {
        return false;
      }
      final content = await activeFile.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! List) {
        return false;
      }
      final list = List<Map<String, dynamic>>.from(
        decoded.map((e) => Map<String, dynamic>.from(e as Map)),
      );
      final matchingRows = list
          .where((e) => e['id']?.toString() == quoteId)
          .toList();
      if (matchingRows.isEmpty) {
        return false;
      }
      final map = Map<String, dynamic>.from(matchingRows.first);
      final SavedQuoteInfo primaryInfo;
      try {
        primaryInfo = SavedQuoteInfo.fromJson(map);
      } catch (e, st) {
        debugPrint('[MoveQuoteArchive] parse entry failed: $e\n$st');
        return false;
      }

      final exportPath = exportedFile.path;
      final exportBasename = p.basename(exportPath);
      final bucketExportKey =
          _logicalQuoteBucketKey(primaryInfo.quoteBucketKey);

      final idsToMove = <String>{};
      for (final e in list) {
        SavedQuoteInfo info;
        try {
          info = SavedQuoteInfo.fromJson(Map<String, dynamic>.from(e));
        } catch (_) {
          continue;
        }
        if (!_sameLogicalCustomerQuoteRows(
          customerIdA: primaryInfo.customerId,
          customerNameA: primaryInfo.customerName,
          customerIdB: info.customerId,
          customerNameB: info.customerName,
        )) {
          continue;
        }
        if (_logicalQuoteBucketKey(info.quoteBucketKey) !=
            bucketExportKey) {
          continue;
        }
        final id = info.id;
        if (id.isNotEmpty) {
          idsToMove.add(id);
        }
      }
      idsToMove.add(quoteId);

      if (idsToMove.length > 1 && kDebugMode) {
        debugPrint(
          '[MoveQuoteArchive] archiving ${idsToMove.length} active row(s) for '
          'customer+bucket export key=$bucketExportKey ids=${idsToMove.join(',')}',
        );
      }

      SavedQuoteInfo archivedCopy(SavedQuoteInfo info) {
        return SavedQuoteInfo(
          id: info.id,
          name: info.name,
          customerName: info.customerName,
          customerId: info.customerId,
          quoteBucketKey: info.quoteBucketKey,
          quoteBucketLabel: info.quoteBucketLabel,
          updatedAt: info.updatedAt,
          status: QuoteLifecycleStatus.archived,
          exportedAt: exportedAt,
          confirmedAt: null,
          exportedFilePaths: [...info.exportedFilePaths, exportPath],
          exportedFileNames: [...info.exportedFileNames, exportBasename],
        );
      }

      final previousArchive = await _loadArchiveQuoteIndex();
      final newArchive = List<SavedQuoteInfo>.from(previousArchive)
        ..removeWhere((e) => idsToMove.contains(e.id));

      for (final id in idsToMove) {
        final rowsForId = list.where((e) => e['id']?.toString() == id).toList();
        if (rowsForId.isEmpty) continue;
        SavedQuoteInfo info;
        try {
          info = SavedQuoteInfo.fromJson(
            Map<String, dynamic>.from(rowsForId.first),
          );
        } catch (_) {
          continue;
        }
        newArchive.insert(0, archivedCopy(info));
      }

      await _saveArchiveQuoteIndex(newArchive);

      try {
        list.removeWhere((e) => idsToMove.contains(e['id']?.toString()));
        if (matchingRows.length > 1 && kDebugMode) {
          debugPrint(
            '[MoveQuoteArchive] removed ${matchingRows.length} duplicate index '
            'row(s) for id=$quoteId',
          );
        }
        await activeFile.writeAsString(jsonEncode(list), flush: true);
      } catch (e, st) {
        debugPrint(
          '[MoveQuoteArchive] active index update failed; rolling back archive: $e\n$st',
        );
        await _saveArchiveQuoteIndex(previousArchive);
        return false;
      }
      return true;
    } catch (e, st) {
      debugPrint('[MoveQuoteArchive] failed: $e\n$st');
      return false;
    }
  }

  /// Max numeric suffix for QUOTE_<datePart>_### / EVERYDAY QUOTE_<datePart>_### names.
  int _maxQuoteSequenceForDatePart(dynamic decoded, String datePart) {
    var maxSequence = 0;
    if (decoded is! List) {
      return maxSequence;
    }
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final rawName = (map['name'] as String?) ?? '';
      final upperName = rawName.trim().toUpperCase();
      final matchesLegacyPrefix = upperName.startsWith('QUOTE_${datePart}_');
      final matchesEverydayPrefix =
          upperName.startsWith('EVERYDAY QUOTE_${datePart}_');
      if (!matchesLegacyPrefix && !matchesEverydayPrefix) continue;
      final prefix = matchesEverydayPrefix
          ? 'EVERYDAY QUOTE_${datePart}_'
          : 'QUOTE_${datePart}_';
      final suffix = upperName.substring(prefix.length);
      if (!RegExp(r'^\d{3}$').hasMatch(suffix)) continue;
      final value = int.tryParse(suffix);
      if (value != null && value > maxSequence) {
        maxSequence = value;
      }
    }
    return maxSequence;
  }

  Future<String> _generateDefaultQuoteName() async {
    final now = DateTime.now();
    final datePart =
        '${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}';

    int maxSequence = 0;

    try {
      final indexPaths = <String>{
        await _getQuoteActiveIndexPath(),
        await _getQuoteIndexPath(),
        await _getQuoteArchiveIndexPath(),
      };
      for (final indexPath in indexPaths) {
        final indexFile = File(indexPath);
        if (!await indexFile.exists()) continue;
        final content = await indexFile.readAsString();
        final decoded = jsonDecode(content);
        final m = _maxQuoteSequenceForDatePart(decoded, datePart);
        if (m > maxSequence) {
          maxSequence = m;
        }
      }
    } catch (_) {
      // If anything goes wrong, fall back to _001 for today.
    }

    final next = maxSequence + 1;
    final seq = next.toString().padLeft(3, '0');
    return 'QUOTE_${datePart}_$seq';
  }

  /// True when [quoteId] appears in [quotes_archive.json] (exported / archived workflow).
  Future<bool> _archiveIndexContainsQuoteId(String quoteId) async {
    if (quoteId.isEmpty) return false;
    try {
      final archived = await _loadArchiveQuoteIndex();
      return archived.any((q) => q.id == quoteId);
    } catch (_) {
      return false;
    }
  }

  /// True when [quoteId] may participate in the active Scan / Orders workflow:
  /// a row in the on-disk active index ([_activeQuoteIndexFileForReadWrite])
  /// with [QuoteLifecycleStatus.active], and the same id is **not** still listed
  /// in the archive index (avoids stale duplicate rows after export).
  /// Export removes the id from the active list; [_saveQuote] must not re-insert it if
  /// the id is only archived in-app.
  Future<bool> _quoteIdHasActiveEligibleRowInActiveIndexStorage(
    String quoteId,
  ) async {
    if (quoteId.isEmpty) return false;
    try {
      final dir = await _getQuotesDirectory();
      await _ensureLegacyQuoteIndexMigratedIfNeeded();
      final indexFile = await _activeQuoteIndexFileForReadWrite(dir);
      if (!await indexFile.exists()) return false;
      final decoded = jsonDecode(await indexFile.readAsString());
      if (decoded is! List) return false;
      for (final e in decoded) {
        if (e is! Map) continue;
        if (e['id']?.toString() != quoteId) continue;
        try {
          final info = SavedQuoteInfo.fromJson(
            Map<String, dynamic>.from(e),
          );
          if (info.status != QuoteLifecycleStatus.active) return false;
          if (await _archiveIndexContainsQuoteId(quoteId)) return false;
          return true;
        } catch (_) {
          if (await _archiveIndexContainsQuoteId(quoteId)) return false;
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// True when this id is archived on disk but is not eligible as an active
  /// workspace quote (no active-status row in the active index file).
  /// Used to avoid "resurrecting" a quote into the active workspace after export
  /// and to gate load/export/share for archive-only quotes.
  Future<bool> _isQuoteIdInArchiveButNotActive(String quoteId) async {
    if (quoteId.isEmpty) return false;
    if (await _quoteIdHasActiveEligibleRowInActiveIndexStorage(quoteId)) {
      return false;
    }
    final archived = await _loadArchiveQuoteIndex();
    return archived.any((q) => q.id == quoteId);
  }

  Future<void> _saveQuote({
    bool notifyOnArchiveSideSave = true,
    bool rebindWorkspaceIfArchiveSideSave = false,
  }) async {
    final name = _quoteNameController.text.trim().isEmpty
        ? 'NEW QUOTE'
        : _quoteNameController.text.trim().toUpperCase();
    final customerName = _selectedCustomer?.displayName.trim() ?? '';
    final customerId = _selectedCustomer?.id.trim() ?? '';

    final now = DateTime.now();

    final linesJson = _orderLines.map((line) {
      final bucket = _resolveQuoteBucketForProduct(line.product);
      return {
        'upc': line.product.upc,
        'itemNumber': line.product.itemNumber,
        'description': line.product.description,
        'price': line.product.price,
        'productType': line.product.productType,
        'discountRaw': line.product.discountRaw,
        'discountEligible': line.product.discountEligible,
        'category': line.product.category,
        'subCategory': line.product.subCategory,
        'quoteBucketKey': bucket.bucketKey,
        'quoteBucketLabel': bucket.displayLabel,
        'quantity': line.quantity,
        'scans': line.scans,
      };
    }).toList();

    final persistedBucketKey = _logicalQuoteBucketKey(_activeQuoteBucketKey);
    final rootBucketKey = persistedBucketKey.isNotEmpty
        ? persistedBucketKey
        : _defaultQuoteBucketDefinition.bucketKey;

    try {
      final dir = await _getQuotesDirectory();

      var workspaceId = _currentQuoteId;
      if (workspaceId != null) {
        final eligible =
            await _quoteIdHasActiveEligibleRowInActiveIndexStorage(workspaceId);
        final diskProbe = File('${dir.path}/quote_$workspaceId.json');
        if (!eligible && !await diskProbe.exists()) {
          _debugLogQuoteImportExport(
            '[SaveQuote] drop stale workspace id=$workspaceId '
            '(no active index row and no quote file — pruned or corrupt)',
          );
          workspaceId = null;
          _currentQuoteId = null;
        }
      }

      final id = workspaceId ?? now.millisecondsSinceEpoch.toString();

      final quoteJson = {
        'id': id,
        'name': name,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'quoteBucketKey': rootBucketKey,
        'quoteBucketLabel': _activeQuoteBucketLabel,
        'lines': linesJson,
        if (_selectedCustomer != null) 'customer': _selectedCustomer!.toJson(),
      };

      final file = File('${dir.path}/quote_$id.json');

      // Export moves this id to archive only; the session may still hold the same
      // id. A full save would re-insert into the active index and strip archive —
      // undoing export. Persist payload only until the user restores or switches.
      if (_currentQuoteId != null &&
          await _isQuoteIdInArchiveButNotActive(_currentQuoteId!)) {
        var payload = Map<String, dynamic>.from(quoteJson);
        try {
          if (await file.exists()) {
            final prior = jsonDecode(await file.readAsString());
            if (prior is Map) {
              final created = prior['createdAt'] as String?;
              if (created != null && created.isNotEmpty) {
                payload['createdAt'] = created;
              }
            }
          }
        } catch (_) {}
        payload['updatedAt'] = now.toIso8601String();
        await file.writeAsString(jsonEncode(payload), flush: true);
        if (!mounted) return;
        if (rebindWorkspaceIfArchiveSideSave) {
          final c = _selectedCustomer;
          if (c != null) {
            await _startNewQuote(c);
          } else {
            setState(() {
              _currentQuoteId = null;
              _activeQuoteBucketKey = _defaultQuoteBucketDefinition.bucketKey;
              _activeQuoteBucketLabel = _defaultQuoteBucketDefinition.displayLabel;
              _orderLines.clear();
              _orderLineByKey.clear();
              _orderListVersion += 1;
              _recalculateTotals();
              _quoteNameController.text = 'NEW QUOTE';
              _savedQuoteNameBeforeEdit = 'NEW QUOTE';
              _quoteNameUserEdited = false;
              _selectedLine = null;
              _resetQuoteDisplayAndScanState();
            });
          }
        } else if (notifyOnArchiveSideSave) {
          setState(() {
            _status =
                'Quote file updated (exported quote stays in Archive until restored).';
          });
        }
        _requestScannerFocus();
        return;
      }

      await file.writeAsString(jsonEncode(quoteJson), flush: true);

      final indexFile = await _activeQuoteIndexFileForReadWrite(dir);
      List<Map<String, dynamic>> list = [];

      if (await indexFile.exists()) {
        final content = await indexFile.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          list = List<Map<String, dynamic>>.from(
            decoded.map((e) => Map<String, dynamic>.from(e as Map)),
          );
        }
      }

      final priorIdx = list.indexWhere((e) => e['id']?.toString() == id);
      final priorEntry = priorIdx >= 0
          ? Map<String, dynamic>.from(list[priorIdx])
          : <String, dynamic>{};

      list.removeWhere((e) => e['id']?.toString() == id);

      final row = <String, dynamic>{
        ...priorEntry,
        'id': id,
        'name': name,
        'customerName': customerName,
        'customerId': customerId,
        'quoteBucketKey': rootBucketKey,
        'quoteBucketLabel': _activeQuoteBucketLabel,
        'updatedAt': now.toIso8601String(),
      };
      row['quoteStatus'] =
          row['quoteStatus'] ??
          quoteLifecycleStatusToJson(QuoteLifecycleStatus.active);

      list.insert(0, row);

      await indexFile.writeAsString(jsonEncode(list), flush: true);
      await _removeQuoteFromArchiveIndexIfPresent(id);

      if (!mounted) return;
      setState(() {
        _currentQuoteId = id;
        _activeQuoteBucketKey = rootBucketKey;
        _status = 'Quote saved: $name';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Error saving quote: $e';
      });
    }

    _requestScannerFocus();
  }

  /// Active (working) quotes for Load Quote and daily use — same eligibility as
  /// [_quoteIdHasActiveEligibleRowInActiveIndexStorage] (active index row, not in archive).
  Future<List<SavedQuoteInfo>> _loadQuoteIndex() async {
    try {
      await _ensureLegacyQuoteIndexMigratedIfNeeded();
      final dir = await _getQuotesDirectory();
      final archiveIds =
          (await _loadArchiveQuoteIndex()).map((e) => e.id).toSet();
      final activeFile = File(await _getQuoteActiveIndexPath());
      if (await activeFile.exists()) {
        final loaded = await _loadSavedQuotesFromIndexFile(activeFile, dir);
        return loaded
            .where(
              (q) =>
                  q.status == QuoteLifecycleStatus.active &&
                  !archiveIds.contains(q.id),
            )
            .toList();
      }
      final legacyFile = File(await _getQuoteIndexPath());
      if (await legacyFile.exists()) {
        final all = await _loadSavedQuotesFromIndexFile(legacyFile, dir);
        return all
            .where(
              (q) =>
                  q.status == QuoteLifecycleStatus.active &&
                  !archiveIds.contains(q.id),
            )
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Remove quote from index and delete its file. Call after user confirms.
  Future<void> _removeQuoteFromIndex(String id) async {
    try {
      final dir = await _getQuotesDirectory();
      final quoteFile = File('${dir.path}/quote_$id.json');
      if (await quoteFile.exists()) await quoteFile.delete();

      final indexFile = await _activeQuoteIndexFileForReadWrite(dir);
      if (!await indexFile.exists()) return;

      final content = await indexFile.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! List) return;

      final list = List<Map<String, dynamic>>.from(
        decoded.map((e) => Map<String, dynamic>.from(e as Map)),
      );

      list.removeWhere((e) => e['id']?.toString() == id);
      await indexFile.writeAsString(jsonEncode(list), flush: true);
    } catch (_) {}
  }

  /// Build CSV with Item Number and Quantity for website upload.
  String _formatQuoteAsCsv(Map<String, dynamic> data) {
    const header = 'Item,Quantity';
    final lines =
        data['lines'] as List<dynamic>? ?? data['items'] as List<dynamic>? ?? [];
    final rows = <String>[header];

    for (final lineJson in lines) {
      final map = Map<String, dynamic>.from(lineJson as Map);
      final itemNumber = (map['itemNumber'] as String?) ?? '';
      final qty = (map['quantity'] as int?) ?? 1;
      final itemEscaped = itemNumber.contains(',') ? '"$itemNumber"' : itemNumber;
      rows.add('$itemEscaped,$qty');
    }

    return rows.join('\n');
  }

  /// Build shareable text for a quote from its JSON data.
  String _formatQuoteAsText(Map<String, dynamic> data) {
    final name = data['name'] as String? ?? 'Quote';
    final lines =
        data['lines'] as List<dynamic>? ?? data['items'] as List<dynamic>? ?? [];
    final buffer = StringBuffer('Quote: $name\n');
    final customerMap = data['customer'];
    var customerDiscPct = 0.0;
    if (customerMap is Map<String, dynamic>) {
      final c = Customer.fromJson(Map<String, dynamic>.from(customerMap));
      customerDiscPct = c.discountPercent;
      buffer.writeln('Customer: ${c.displayName}');
      if (c.contact.isNotEmpty) buffer.writeln('Contact: ${c.contact}');
      if (c.email.isNotEmpty) buffer.writeln('Email: ${c.email}');
      if (c.phone.isNotEmpty) buffer.writeln('Phone: ${c.phone}');
      buffer.writeln('');
    }

    bool lineDiscountEligible(Map<String, dynamic> map) {
      final b = map['discountEligible'];
      if (b is bool) return b;
      final raw = (map['discountRaw'] as String?) ?? '';
      return raw.trim().toUpperCase() == 'YES';
    }

    double discountedUnit(Map<String, dynamic> map, double regularUnit) {
      if (!lineDiscountEligible(map) || customerDiscPct <= 0) {
        return regularUnit;
      }
      return regularUnit * (1 - customerDiscPct / 100.0);
    }

    buffer.writeln(
      '${'Item / Description'.padRight(34)} Qty  Unit       Total',
    );
    buffer.writeln('-' * 62);

    double regularOrderSum = 0.0;
    double discountedOrderSum = 0.0;

    for (final lineJson in lines) {
      final map = Map<String, dynamic>.from(lineJson as Map);
      final desc = (map['description'] as String?) ?? '';
      final qty = (map['quantity'] as int?) ?? 1;
      final price = (map['price'] as num?)?.toDouble() ?? 0.0;
      final du = discountedUnit(map, price);
      final lineRegular = qty * price;
      final linePay = qty * du;
      regularOrderSum += lineRegular;
      discountedOrderSum += linePay;

      final shortDesc = desc.length > 32 ? '${desc.substring(0, 32)}..' : desc;
      final unitCol = (price - du).abs() > 0.005
          ? '\$${price.toStringAsFixed(2)}→\$${du.toStringAsFixed(2)}'
          : '\$${du.toStringAsFixed(2)}';

      buffer.writeln(
        '${shortDesc.padRight(34)} ${qty.toString().padLeft(3)}  '
        '${unitCol.padLeft(9)}  \$${linePay.toStringAsFixed(2)}',
      );
    }

    buffer.writeln('-' * 62);
    final orderDiscountAmt = regularOrderSum - discountedOrderSum;
    if (orderDiscountAmt > 0.005) {
      buffer.writeln(
        'Regular Total: \$${regularOrderSum.toStringAsFixed(2)}',
      );
      buffer.writeln(
        'Discount: \$${orderDiscountAmt.toStringAsFixed(2)}',
      );
      buffer.writeln(
        'Final Total: \$${discountedOrderSum.toStringAsFixed(2)}',
      );
    } else {
      buffer.writeln('Total: \$${discountedOrderSum.toStringAsFixed(2)}');
    }
    return buffer.toString();
  }

  /// Share quote by id: attaches CSV (Item Number, Quantity) for website upload and optional text summary.
  Future<void> _shareQuoteById(String id, String name) async {
    try {
      if (!await _quoteIdHasActiveEligibleRowInActiveIndexStorage(id)) {
        return;
      }
      final dir = await _getQuotesDirectory();
      final file = File('${dir.path}/quote_$id.json');
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final data = Map<String, dynamic>.from(jsonDecode(content) as Map);
      final csv = _formatQuoteAsCsv(data);

      final tempDir = await getTemporaryDirectory();
      final safeName = name
          .replaceAll(RegExp(r'[^\w\s-]'), '_')
          .replaceAll(RegExp(r'\s+'), '_');

      final csvPath =
          '${tempDir.path}/quote_${safeName.isEmpty ? id : safeName}.csv';

      final csvFile = File(csvPath);
      await csvFile.writeAsString(csv, flush: true);

      final text = _formatQuoteAsText(data);

      await Share.shareXFiles(
        [XFile(csvPath, mimeType: 'text/csv')],
        text: text,
        subject: 'Quote: $name',
      );
    } catch (_) {}
  }

  Future<void> _loadQuoteById(
    String id, {
    bool syncWorkspaceIfUnmounted = false,
  }) async {
    try {
      final dir = await _getQuotesDirectory();
      final file = File('${dir.path}/quote_$id.json');

      if (!await file.exists()) {
        await _removeQuoteFromIndex(id);
        if (!mounted) return;
        _setStateDebug('load_quote_file_missing', () {
          _status = 'Quote file not found; removed from list';
        });
        return;
      }

      // Active workflow only: do not load archive-only or orphan files by id.
      if (!await _quoteIdHasActiveEligibleRowInActiveIndexStorage(id)) {
        if (!mounted) return;
        final archiveOnly = await _isQuoteIdInArchiveButNotActive(id);
        _setStateDebug('load_quote_blocked_non_active', () {
          _status = archiveOnly
              ? 'That quote is in Archive and cannot be loaded here. Restore it from Archive when that is available.'
              : 'That quote is not in your active saved quotes (it may exist on disk only).';
        });
        _requestScannerFocus();
        return;
      }

      final content = await file.readAsString();
      final data = Map<String, dynamic>.from(jsonDecode(content) as Map);

      final name =
          (data['name'] as String? ?? 'EVERYDAY QUOTE').toUpperCase();
      final loadedQuoteBucketKey =
          (data['quoteBucketKey'] as String?)?.trim() ?? '';
      final loadedQuoteBucketLabel =
          (data['quoteBucketLabel'] as String?)?.trim() ?? '';
      final linesList =
          data['lines'] as List<dynamic>? ?? data['items'] as List<dynamic>? ?? [];

      Customer? loadedCustomer;
      final customerMap = data['customer'];
      if (customerMap is Map<String, dynamic>) {
        final savedId = (customerMap['id'] as String?)?.trim() ?? '';
        try {
          loadedCustomer = _customers.firstWhere((c) => c.id == savedId);
        } catch (_) {
          loadedCustomer =
              Customer.fromJson(Map<String, dynamic>.from(customerMap));
        }
      }

      final newOrderLines = <OrderLine>[];
      final newOrderLineByKey = <String, OrderLine>{};

      for (final lineJson in linesList) {
        final map = Map<String, dynamic>.from(lineJson as Map);
        final upc = (map['upc'] as String?) ?? '';
        final itemNumber = (map['itemNumber'] as String?) ?? '';
        final description = (map['description'] as String?) ?? '';
        final price = (map['price'] as num?)?.toDouble() ?? 0.0;
        final productType = (map['productType'] as String?) ?? '';
        final discountRaw = (map['discountRaw'] as String?)?.trim() ?? '';
        final discountEligible = (map['discountEligible'] as bool?) ?? false;
        final category = (map['category'] as String?) ?? '';
        final subCategory = (map['subCategory'] as String?) ?? '';
        final quantity = (map['quantity'] as int?) ?? 1;
        final scans = (map['scans'] as int?) ?? 1;

        Product? product = _productsByUpc[_normalizeUpcLookupKey(upc)];
        product ??= _productsByItemNumber[itemNumber];

        if (product == null) {
          product = Product(
            itemNumber: itemNumber.isEmpty ? upc : itemNumber,
            description: description.isEmpty ? 'Unknown' : description,
            upc: upc,
            price: price,
            productType: productType,
            discountRaw: discountRaw,
            discountEligible: discountEligible,
            category: category,
            subCategory: subCategory,
            minOrderQty: 1,
            caseQty: 1,
          );
        }

        final line = OrderLine(
          product: product,
          quantity: quantity,
          scans: scans,
        );

        newOrderLines.add(line);
        newOrderLineByKey[_orderLineKeyForProduct(product)] = line;
      }

      String activeBucketKey = loadedQuoteBucketKey;
      String activeBucketLabel = loadedQuoteBucketLabel;
      if (activeBucketKey.isEmpty && newOrderLines.isNotEmpty) {
        final inferred = _resolveQuoteBucketForProduct(newOrderLines.first.product);
        activeBucketKey = inferred.bucketKey;
        activeBucketLabel = inferred.displayLabel;
      }
      if (activeBucketKey.isEmpty) {
        activeBucketKey = _defaultQuoteBucketDefinition.bucketKey;
      }
      if (activeBucketLabel.isEmpty) {
        activeBucketLabel = _defaultQuoteBucketDefinition.displayLabel;
      }
      activeBucketKey = _logicalQuoteBucketKey(activeBucketKey);
      if (activeBucketKey.isEmpty) {
        activeBucketKey = _defaultQuoteBucketDefinition.bucketKey;
      }
      if (_logicalQuoteBucketKey(activeBucketKey) == _defaultQuoteBucketKey) {
        activeBucketLabel = _defaultQuoteBucketDefinition.displayLabel;
      }

      void applyWorkspace() {
        _currentQuoteId = id;
        _quoteNameController.text = name;
        _savedQuoteNameBeforeEdit = name;
        _quoteNameUserEdited = false;
        _orderLines.clear();
        _orderLines.addAll(newOrderLines);
        _orderLineByKey.clear();
        _orderLineByKey.addAll(newOrderLineByKey);
        _orderListVersion += 1;
        _selectedCustomer = loadedCustomer;
        _activeQuoteBucketKey = activeBucketKey;
        _activeQuoteBucketLabel = activeBucketLabel;

        _itemsScanned = 0;
        for (final l in _orderLines) {
          _itemsScanned += l.scans;
        }

        _recalculateTotals();
        _selectedLine = _orderLines.isNotEmpty ? _orderLines.first : null;
        _lastAddedUpc = _orderLines.isNotEmpty
            ? _orderLines.first.product.upc
            : null;
        _lastItem = _orderLines.isNotEmpty
            ? _orderLines.first.product.description
            : '-';
        _lastScan = _orderLines.isNotEmpty
            ? _orderLines.first.product.upc
            : '-';
        _qtyAdded = _orderLines.isNotEmpty ? _orderLines.first.quantity : 0;
        _status = 'Quote loaded: $name (${_orderLines.length} items)';
        _quickEntryStatus = '-';
      }

      if (!mounted) {
        if (syncWorkspaceIfUnmounted) {
          applyWorkspace();
          _debugLogQuoteImportExport(
            '[LoadQuoteById] sync workspace without mount id=$id',
          );
        }
        return;
      }

      _setStateDebug('load_quote_by_id_apply', applyWorkspace);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _setStateDebug('load_quote_post_frame_empty', () {});
      });
    } catch (e) {
      if (!mounted) return;
      _setStateDebug('load_quote_error', () {
        _status = 'Error loading quote: $e';
      });
    }

    _requestScannerFocus();
  }

  String _formatSavedQuoteDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showLoadQuoteDialog() async {
    _editDialogOpen = true;
    // Prune before save so a stale [_currentQuoteId] cannot re-insert a
    // superseded empty quote into [quotes_active.json] via [_saveQuote].
    await _pruneSupersededEmptyDuplicateQuotesForAllActiveIndexCustomers();

    // Persist the current working quote so it appears in the Load Quote list
    // (and updates the existing quote by id, not duplicates).
    // Do not mint a new empty index row from default auto-named quotes (e.g. after
    // export + [_startNewQuote]) — that resurrected empty Everyday rows in Load Quote.
    if (_currentQuoteId != null ||
        _orderLines.isNotEmpty ||
        _quoteNameUserEdited) {
      await _saveQuote(
        notifyOnArchiveSideSave: false,
        rebindWorkspaceIfArchiveSideSave: true,
      );
    }

    final list = await _loadQuoteIndex();
    if (kDebugMode && _quoteImportExportEmptyDebug) {
      _debugLogQuoteImportExport(
        '[LoadQuoteDialog] list ids=${list.map((e) => e.id).join(',')}',
      );
    }

    if (!mounted) {
      return;
    }

    if (list.isEmpty) {
      _editDialogOpen = false;
      setState(() => _status = 'No saved quotes');
      _requestScannerFocus();
      return;
    }

    final allQuotes = List<SavedQuoteInfo>.from(list);

    final selectedId = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Load Quote'),
          content: _LoadQuoteDialogContent(
            allQuotes: allQuotes,
            formatDate: _formatSavedQuoteDate,
            dialogContext: ctx,
            onRemoveQuote: _removeQuoteFromIndex,
            onShareQuote: _shareQuoteById,
            searchQuotesFocusNode: _searchQuotesFocusNode,
          ),
          actionsAlignment: MainAxisAlignment.start,
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
          buttonPadding: EdgeInsets.zero,
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    _editDialogOpen = false;

    final id = selectedId;
    if (id != null && mounted) {
      if (id.startsWith('removed:')) {
        final removedId = id.substring(8);
        if (removedId == _currentQuoteId) {
          setState(() {
            _currentQuoteId = null;
            _activeQuoteBucketKey = _defaultQuoteBucketDefinition.bucketKey;
            _activeQuoteBucketLabel = _defaultQuoteBucketDefinition.displayLabel;
            _orderLines.clear();
            _orderLineByKey.clear();
            _orderListVersion += 1;
            _recalculateTotals();
            _quoteNameController.text = 'NEW QUOTE';
            _savedQuoteNameBeforeEdit = 'NEW QUOTE';
            _quoteNameUserEdited = false;
            _selectedLine = null;
            _selectedCustomer = null;
            _status = 'Quote removed';
            _quickEntryStatus = '-';
            _resetQuoteDisplayAndScanState();
          });
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 150));
        if (mounted) await _loadQuoteById(id);
      }
    }

    // Refocus scanner so first scan after closing dialog registers (avoids
    // needing multiple scanner triggers).
    if (mounted) {
      _requestScannerFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_editDialogOpen) _scheduleScannerRefocus();
      });
    }
  }

  void _increaseSelectedLineQty() {
    if (_selectedLine == null) return;

    setState(() {
      _selectedLine!.quantity += _selectedLine!.product.minOrderQty;
      _recalculateTotals();
      _status = 'Quantity increased';
    });

    _requestScannerFocus();
  }

  void _decreaseSelectedLineQty() {
    if (_selectedLine == null) return;

    final line = _selectedLine!;
    final step = line.product.minOrderQty;
    final newQty = line.quantity - step;

    if (newQty < 1) {
      setState(() {
        _orderLines.remove(line);
        _orderLineByKey.remove(_orderLineKeyForProduct(line.product));
        _recalculateTotals();
        _selectedLine = _orderLines.isEmpty ? null : _orderLines.first;
        if (_orderLines.isEmpty) {
          _resetQuoteDisplayAndScanState();
        }
        _status = 'Item removed from order';
      });
      _requestScannerFocus();
      return;
    }

    setState(() {
      line.quantity = newQty;
      _recalculateTotals();
      _status = 'Quantity decreased';
    });

    _requestScannerFocus();
  }

  void _increaseLineQty(OrderLine line) {
    setState(() {
      line.quantity += line.product.minOrderQty;
      _recalculateTotals();
      _status = 'Quantity increased';
    });
    _requestScannerFocus();
  }

  void _decreaseLineQty(OrderLine line) {
    final step = line.product.minOrderQty;
    final newQty = line.quantity - step;

    if (newQty < 1) {
      setState(() {
        _orderLines.remove(line);
        _orderLineByKey.remove(_orderLineKeyForProduct(line.product));
        _recalculateTotals();
        if (_selectedLine == line) {
          _selectedLine = _orderLines.isEmpty ? null : _orderLines.first;
        }
        if (_orderLines.isEmpty) {
          _resetQuoteDisplayAndScanState();
        }
        _status = 'Item removed from order';
      });
      _requestScannerFocus();
      return;
    }

    setState(() {
      line.quantity = newQty;
      _recalculateTotals();
      _status = 'Quantity decreased';
    });
    _requestScannerFocus();
  }

  Color? _scanTabFeedbackTint() {
    if (_scanFeedbackType == ScanFeedbackType.successNewItem ||
        _scanFeedbackType == ScanFeedbackType.successExistingItem) {
      return Colors.green.withValues(alpha: 0.55);
    }
    if (_scanFeedbackType == ScanFeedbackType.notFound) {
      return Colors.red.withValues(alpha: 0.55);
    }
    return null;
  }

  /// Scan tab: quote name, customer, and order summary (fixed region above the list).
  Widget _buildScanQuotePanel() {
    final feedbackColor = _scanTabFeedbackTint();
    final customerLabel = _selectedCustomer == null
        ? (_customers.isEmpty
            ? 'Load customers CSV first'
            : 'No customer selected')
        : _selectedCustomer!.displayName;

    return _ScanQuotePanel(
      feedbackColor: feedbackColor,
      customerLabel: customerLabel,
      customerSelected: _selectedCustomer != null,
      scannerController: _scannerController,
      scannerFocusNode: _scannerFocusNode,
      onScannerChanged: _onScannerChanged,
      onScannerSubmitted: _onScannerSubmitted,
      onScannerEditingComplete: _onScannerEditingComplete,
      quoteNameController: _quoteNameController,
      quoteNameFocusNode: _quoteNameFocusNode,
      onQuoteNameSubmitted: _onQuoteNameSubmitted,
      selectCustomerEnabled: _customers.isNotEmpty,
      onSelectCustomer: _showSelectCustomerDialog,
      itemCount: _orderLines.length,
      totalUnits: _totalUnits,
      orderHasDiscount: _orderHasAnyDiscount(),
      orderTotal: _orderTotal,
      regularOrderTotal: _getRegularOrderTotal(),
      totalDiscountAmount: _getTotalDiscountAmount(),
    );
  }

  /// Selected line controls, empty hint, and last-scan stats (scrollable on Scan tab).
  Widget _buildScanLiveOrderControlPanel() {
    final feedbackColor = _scanTabFeedbackTint();
    final line = _selectedLine;
    return _ScanLiveOrderControlPanel(
      feedbackColor: feedbackColor,
      selectedLine: line,
      lineTotal: line != null ? _getDiscountedLineTotal(line) : 0,
      lineHasDiscount: line != null && _lineHasDiscount(line),
      discountedUnitPrice:
          line != null ? _getDiscountedUnitPrice(line) : 0,
      onDecreaseQty: _decreaseSelectedLineQty,
      onIncreaseQty: _increaseSelectedLineQty,
      onDeleteSelectedLine: _confirmDeleteLine,
      lastScanSummary:
          'Last: +$_qtyAdded added     Scans: $_itemsScanned',
    );
  }

  Widget _buildScanTabLoadCreateQuoteBar() {
    return _ScanTabLoadCreateQuoteBar(
      onLoadQuote: _showLoadQuoteDialog,
      onCreateQuote: _confirmNewQuote,
    );
  }

  /// Item # / UPC field and optional status — fixed bottom block above Load/Create.
  /// Search hits live in [_buildScanTabSearchResultsList] inside the single ListView.
  Widget _buildScanTabItemSearchBlock() {
    return _ScanTabItemSearchBlock(
      quickEntryTextFieldKey: _quickEntryTextFieldKey,
      quickEntryController: _quickEntryController,
      quickEntryFocusNode: _quickEntryFocusNode,
      onSearchChanged: _onSearchChanged,
      onQuickEntryTapOutside: (_) {
        debugPrint(
          '[ManualEntry][Focus] quick entry tap outside; restoring scanner focus.',
        );
        _requestScannerFocusAfterManualEntry(
          debugLabel: 'quickEntryTapOutside',
        );
      },
      onQuickEntrySubmitted: (_) => _addQuickEntry(),
      onAddPressed: _addQuickEntry,
      statusText: _quickEntryStatus,
    );
  }

  /// Search hits for Scan tab — must stay inside the middle scroll, not the bottom bar.
  /// Built as plain children (no nested ListView) so the Scan tab has only one scrollable.
  Widget _buildScanTabSearchResultTile(Product product) {
    final bool alreadyInOrder = _orderLineByKey.containsKey(
      _orderLineKeyForProduct(product),
    );
    return _ScanTabSearchResultTile(
      product: product,
      alreadyInOrder: alreadyInOrder,
      onTap: () async {
        await _ensureRoutingForProduct(product);
        final bucket = _resolveQuoteBucketForProduct(product);
        _addProduct(product, 'SEARCH', bucket: bucket);
        _quickEntryController.clear();
        _setStateDebug('scan_search_tap_clear_results', () {
          _searchResults = [];
        });
        _requestScannerFocusAfterManualEntry(
          debugLabel: 'quickEntrySearchTap',
        );
      },
    );
  }

  Widget _buildScanTabSearchResultsList() {
    if (_searchResults.isEmpty) return const SizedBox.shrink();
    return _ScanTabSearchResultsList(
      products: _searchResults,
      itemBuilder: _buildScanTabSearchResultTile,
    );
  }

  /// Order lines for Scan tab as a single column of cards (parent [ListView] scrolls).
  Widget _buildScanTabOrderListContent() {
    _orderListBuildCount++;
    if (_orderLines.isEmpty) {
      return const _ScanTabOrderListEmpty();
    }
    return _ScanTabOrderLinesColumn(
      listKey: ValueKey('order_list_${_orderListVersion}_${_orderLines.length}'),
      children: [
        for (final line in _orderLines)
          _buildScanTabOrderLineSubtree(line),
      ],
    );
  }

  Widget _buildScanTabOrderLineSubtree(OrderLine line) {
    final lineKey = _orderLineKeyForProduct(line.product);
    return KeyedSubtree(
      key: ValueKey(lineKey),
      child: Container(
        key: _globalKeyForScanTabOrderRow(lineKey),
        color: Colors.transparent,
        child: _buildOrderCard(
          line,
          scanTabHighlightFlash: _scanTabHighlightLineKey == lineKey,
        ),
      ),
    );
  }

  Widget _buildOrderCard(
    OrderLine line, {
    bool scanTabHighlightFlash = false,
  }) {
    return _OrderLineCard(
      dismissibleKey: ValueKey(_orderLineKeyForProduct(line.product)),
      line: line,
      scanTabHighlightFlash: scanTabHighlightFlash,
      lineHasDiscount: _lineHasDiscount(line),
      discountedUnitPrice: _getDiscountedUnitPrice(line),
      lineTotal: _getDiscountedLineTotal(line),
      onSwipeDeletePrompt: () => _confirmDeleteLine(line),
      onCardTap: () {
        _setStateDebug('order_card_tap_select_line', () {
          _selectedLine = line;
        });
        _showEditQuantityDialog(line);
      },
      onDecrease: () => _decreaseLineQty(line),
      onIncrease: () => _increaseLineQty(line),
    );
  }

  Widget _buildOrderList({required ScrollController scrollController}) {
    _orderListBuildCount++;
    if (_orderLines.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('No items added yet')),
      );
    }

    return ListView.builder(
      key: ValueKey('order_list_${_orderListVersion}_${_orderLines.length}'),
      controller: scrollController,
      itemCount: _orderLines.length,
      itemBuilder: (context, index) {
        final line = _orderLines[index];
        return KeyedSubtree(
          key: ValueKey(_orderLineKeyForProduct(line.product)),
          child: _buildOrderCard(line),
        );
      },
    );
  }

  Widget _buildOrderListTab() {
    _orderListTabBuildCount++;
    if (_activeTabIndex != 1) {
      return const SizedBox.shrink();
    }
    return _OrderListTab(
      orderLinesCount: _orderLines.length,
      totalUnits: _totalUnits,
      orderTotal: _orderTotal,
      orderHasDiscount: _orderHasAnyDiscount(),
      regularOrderTotal: _getRegularOrderTotal(),
      totalDiscountAmount: _getTotalDiscountAmount(),
      loadingProducts: _loadingProducts,
      activeTabIndex: _activeTabIndex,
      onImportOrder: _pickAndImportOrderCsv,
      onExportAllQuotes: _exportAllQuotesToCsv,
      onExportCurrentQuote: _exportCurrentQuoteOnlyToCsv,
      orderList: _buildOrderList(
        scrollController: _orderListTabScrollController,
      ),
    );
  }

  Widget _buildScanTab() {
    _scanTabBuildCount++;
    if (kDebugMode && _kScanRebuildInstrumentationEnabled) {
      debugPrint(
        'REBUILD_INSTRUMENT _buildScanTab #$_scanTabBuildCount '
        '(activeTab=$_activeTabIndex)',
      );
    }
    if (_activeTabIndex != 0) {
      return const SizedBox.shrink();
    }
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final quickEntryFloatAboveKeyboard =
        (_quickEntryFocusNode.hasFocus &&
                viewInsets.bottom > 0) ||
            (_quickEntryHoldFloatingLayoutForKeyboard &&
                viewInsets.bottom > 0);
    return _ScanTabLayout(
      quotePanel: _buildScanQuotePanel(),
      loadingProducts: _loadingProducts,
      scanPanelScrollController: _scanPanelScrollController,
      liveOrderControlPanel: _buildScanLiveOrderControlPanel(),
      orderListContent: _buildScanTabOrderListContent(),
      searchResultsList: _buildScanTabSearchResultsList(),
      itemSearchBlock: _buildScanTabItemSearchBlock(),
      quickEntryFloatAboveKeyboard: quickEntryFloatAboveKeyboard,
      quickEntryStatusForPlaceholder: _quickEntryStatus,
      loadCreateQuoteBar: _buildScanTabLoadCreateQuoteBar(),
    );
  }

  Widget _buildSetupTab() {
    return _SetupTab(
      onLoadProducts: _loadCsvFromPhone,
      onLoadCustomers: _loadCustomersCsvFromPhone,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (!_quickEntryFocusNode.hasFocus &&
            !_quoteNameFocusNode.hasFocus &&
            !_editDialogOpen) {
          _requestScannerFocus();
        }
      },
      child: Scaffold(
        // Let the scaffold shrink the body by viewInsets when the keyboard opens.
        // Do not also add viewInsets.bottom to a non-flex child in [_buildScanTab]:
        // that inflates the Column's fixed-height children and can force flex space
        // negative (RenderFlex overflow) on short viewports.
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          toolbarHeight: 48,
          title: const Text('Showroom Scanner'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Scan'),
              Tab(text: 'Orders'),
              Tab(text: 'Archive'),
              Tab(text: 'Setup'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 6),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildScanTab(),
                    _buildOrderListTab(),
                    _buildArchiveTab(),
                    _buildSetupTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Scan / Orders tab UI extracted from [_ScannerHomePageState] (presentation only) ---

/// Shared border radius for scan/order line cards and swipe background (presentation only).
const BorderRadius _kOrderLineCardBorderRadius =
    BorderRadius.all(Radius.circular(12));

/// Full Scan tab body: quote header, scrollable middle, and bottom search / quote actions.
class _ScanTabLayout extends StatelessWidget {
  // REBUILD_INSTRUMENT: remove when done profiling scan-tab rebuild frequency
  static int _debugRebuildCount = 0;

  const _ScanTabLayout({
    required this.quotePanel,
    required this.loadingProducts,
    required this.scanPanelScrollController,
    required this.liveOrderControlPanel,
    required this.orderListContent,
    required this.searchResultsList,
    required this.itemSearchBlock,
    required this.quickEntryFloatAboveKeyboard,
    required this.quickEntryStatusForPlaceholder,
    required this.loadCreateQuoteBar,
  });

  static const EdgeInsets _quotePanelPadding =
      EdgeInsets.fromLTRB(12, 12, 12, 0);
  static const EdgeInsets _livePanelPadding =
      EdgeInsets.symmetric(horizontal: 12);
  static const EdgeInsets _scrollListPadding =
      EdgeInsets.symmetric(horizontal: 12);
  static const EdgeInsets _bottomActionsPadding =
      EdgeInsets.fromLTRB(12, 8, 12, 8);

  /// Single instance while catalog is loading (avoids reallocating each parent rebuild).
  static const Widget _loadingProductsIndicator =
      Center(child: CircularProgressIndicator());

  final Widget quotePanel;
  final bool loadingProducts;
  final ScrollController scanPanelScrollController;
  final Widget liveOrderControlPanel;
  final Widget orderListContent;
  final Widget searchResultsList;
  final Widget itemSearchBlock;
  /// When true, the real [_ScanTabItemSearchBlock] is only in the floating bar;
  /// inline uses [_ScanTabItemSearchPlaceholder] so the field is not under the keyboard.
  final bool quickEntryFloatAboveKeyboard;
  final String quickEntryStatusForPlaceholder;
  final Widget loadCreateQuoteBar;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode && _kScanRebuildInstrumentationEnabled) {
      _debugRebuildCount++;
      debugPrint(
        'REBUILD_INSTRUMENT _ScanTabLayout #$_debugRebuildCount',
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: loadingProducts
                    ? _loadingProductsIndicator
                    : CustomScrollView(
                        controller: scanPanelScrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        slivers: [
                          // Pin quote + last-scanned panels so the middle region can shrink
                          // under the keyboard without a Column flex overflow; order lines scroll.
                          PinnedHeaderSliver(
                            child: Padding(
                              padding: _quotePanelPadding,
                              child: RepaintBoundary(child: quotePanel),
                            ),
                          ),
                          PinnedHeaderSliver(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                _livePanelPadding.left,
                                8,
                                _livePanelPadding.right,
                                0,
                              ),
                              child: RepaintBoundary(
                                child: liveOrderControlPanel,
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),
                          SliverPadding(
                            padding: _scrollListPadding,
                            sliver: SliverToBoxAdapter(
                              child: RepaintBoundary(child: orderListContent),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 8)),
                          SliverPadding(
                            padding: _scrollListPadding,
                            sliver: SliverToBoxAdapter(
                              child: RepaintBoundary(child: searchResultsList),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 8)),
                        ],
                      ),
              ),
              Padding(
                padding: _bottomActionsPadding,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      quickEntryFloatAboveKeyboard
                          ? _ScanTabItemSearchPlaceholder(
                              statusText: quickEntryStatusForPlaceholder,
                            )
                          : itemSearchBlock,
                      const SizedBox(height: 8),
                      loadCreateQuoteBar,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (quickEntryFloatAboveKeyboard)
          Positioned(
            left: 0,
            right: 0,
            // The Scaffold already uses `resizeToAvoidBottomInset: true`, so the
            // Stack's height is reduced when the keyboard opens. Avoid
            // double-offsetting by the viewInsets bottom to prevent RenderFlex
            // overflow stripes while the manual-entry keyboard field is active.
            bottom: 0,
            child: Material(
              elevation: 8,
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: _bottomActionsPadding,
                  child: itemSearchBlock,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Quote name, customer line, and order totals — body of the scan tab quote [Card].
class _ScanQuotePanelBody extends StatelessWidget {
  // REBUILD_INSTRUMENT: remove when done profiling scan-tab rebuild frequency
  static int _debugRebuildCount = 0;

  const _ScanQuotePanelBody({
    required this.quoteNameController,
    required this.quoteNameFocusNode,
    required this.onQuoteNameSubmitted,
    required this.customerLabel,
    required this.customerSelected,
    required this.selectCustomerEnabled,
    required this.onSelectCustomer,
    required this.itemCount,
    required this.totalUnits,
    required this.orderHasDiscount,
    required this.orderTotal,
    required this.regularOrderTotal,
    required this.totalDiscountAmount,
  });

  static final List<TextInputFormatter> _quoteNameInputFormatters =
      <TextInputFormatter>[UpperCaseTextFormatter()];

  static final ButtonStyle _selectCustomerButtonStyle =
      FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  static final TextStyle _discountSublineStyle = TextStyle(
    fontSize: 11,
    color: Colors.green.shade800,
    fontWeight: FontWeight.w600,
  );

  final TextEditingController quoteNameController;
  final FocusNode quoteNameFocusNode;
  final ValueChanged<String> onQuoteNameSubmitted;
  final String customerLabel;
  final bool customerSelected;
  final bool selectCustomerEnabled;
  final VoidCallback onSelectCustomer;
  final int itemCount;
  final int totalUnits;
  final bool orderHasDiscount;
  final double orderTotal;
  final double regularOrderTotal;
  final double totalDiscountAmount;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode && _kScanRebuildInstrumentationEnabled) {
      _debugRebuildCount++;
      debugPrint(
        'REBUILD_INSTRUMENT _ScanQuotePanelBody #$_debugRebuildCount',
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: quoteNameController,
            focusNode: quoteNameFocusNode,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: _quoteNameInputFormatters,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            decoration: const InputDecoration(
              labelText: 'Quote',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
            ),
            onSubmitted: onQuoteNameSubmitted,
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Customer:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  customerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: customerSelected
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              FilledButton.tonal(
                style: _selectCustomerButtonStyle,
                onPressed: selectCustomerEnabled ? onSelectCustomer : null,
                child:
                    const Text('Select', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Items: $itemCount',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              Text(
                'Units: $totalUnits',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              Text(
                '${orderHasDiscount ? 'Total' : 'Order'}: '
                '\$${orderTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          if (orderHasDiscount) ...[
            const SizedBox(height: 2),
            Text(
              'Reg: \$${regularOrderTotal.toStringAsFixed(2)}  '
              '−\$${totalDiscountAmount.toStringAsFixed(2)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _discountSublineStyle,
            ),
          ],
        ],
      ),
    );
  }
}

class _ScanQuotePanel extends StatelessWidget {
  const _ScanQuotePanel({
    required this.feedbackColor,
    required this.customerLabel,
    required this.customerSelected,
    required this.scannerController,
    required this.scannerFocusNode,
    required this.onScannerChanged,
    required this.onScannerSubmitted,
    required this.onScannerEditingComplete,
    required this.quoteNameController,
    required this.quoteNameFocusNode,
    required this.onQuoteNameSubmitted,
    required this.selectCustomerEnabled,
    required this.onSelectCustomer,
    required this.itemCount,
    required this.totalUnits,
    required this.orderHasDiscount,
    required this.orderTotal,
    required this.regularOrderTotal,
    required this.totalDiscountAmount,
  });

  final Color? feedbackColor;
  final String customerLabel;
  final bool customerSelected;
  final TextEditingController scannerController;
  final FocusNode scannerFocusNode;
  final ValueChanged<String> onScannerChanged;
  final ValueChanged<String> onScannerSubmitted;
  final VoidCallback onScannerEditingComplete;
  final TextEditingController quoteNameController;
  final FocusNode quoteNameFocusNode;
  final ValueChanged<String> onQuoteNameSubmitted;
  final bool selectCustomerEnabled;
  final VoidCallback onSelectCustomer;
  final int itemCount;
  final int totalUnits;
  final bool orderHasDiscount;
  final double orderTotal;
  final double regularOrderTotal;
  final double totalDiscountAmount;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 1,
          width: 1,
          child: TextField(
            controller: scannerController,
            focusNode: scannerFocusNode,
            keyboardType: TextInputType.none,
            textInputAction: TextInputAction.done,
            showCursor: false,
            enableInteractiveSelection: false,
            autocorrect: false,
            onChanged: onScannerChanged,
            onSubmitted: onScannerSubmitted,
            onEditingComplete: onScannerEditingComplete,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.all(0),
          clipBehavior: Clip.antiAlias,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            color: feedbackColor ?? Colors.transparent,
            child: _ScanQuotePanelBody(
              quoteNameController: quoteNameController,
              quoteNameFocusNode: quoteNameFocusNode,
              onQuoteNameSubmitted: onQuoteNameSubmitted,
              customerLabel: customerLabel,
              customerSelected: customerSelected,
              selectCustomerEnabled: selectCustomerEnabled,
              onSelectCustomer: onSelectCustomer,
              itemCount: itemCount,
              totalUnits: totalUnits,
              orderHasDiscount: orderHasDiscount,
              orderTotal: orderTotal,
              regularOrderTotal: regularOrderTotal,
              totalDiscountAmount: totalDiscountAmount,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanLiveOrderControlPanel extends StatelessWidget {
  const _ScanLiveOrderControlPanel({
    required this.feedbackColor,
    required this.selectedLine,
    required this.lineTotal,
    required this.lineHasDiscount,
    required this.discountedUnitPrice,
    required this.onDecreaseQty,
    required this.onIncreaseQty,
    required this.onDeleteSelectedLine,
    required this.lastScanSummary,
  });

  final Color? feedbackColor;
  final OrderLine? selectedLine;
  final double lineTotal;
  final bool lineHasDiscount;
  final double discountedUnitPrice;
  final VoidCallback onDecreaseQty;
  final VoidCallback onIncreaseQty;
  final Future<void> Function(OrderLine line) onDeleteSelectedLine;
  final String lastScanSummary;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(0),
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        color: feedbackColor ?? Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selectedLine == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Scan an item to begin',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Builder(
                  builder: (context) {
                    final line = selectedLine!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          line.product.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Item # ${line.product.itemNumber}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            lineHasDiscount
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Price: \$${line.product.price.toStringAsFixed(2)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                      Text(
                                        'Sale: \$${discountedUnitPrice.toStringAsFixed(2)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    'Price: \$${line.product.price.toStringAsFixed(2)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'Min: ${line.product.minOrderQty}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Line total: \$${lineTotal.toStringAsFixed(2)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            const double sideBtn = 52;
                            const double deleteW = 84;
                            const double rowH = 48;
                            const double gap = 8;
                            final double midW = (constraints.maxWidth -
                                    sideBtn * 2 -
                                    deleteW -
                                    gap * 3)
                                .clamp(48.0, constraints.maxWidth);
                            return SizedBox(
                              height: rowH,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: sideBtn,
                                    child: FilledButton(
                                      onPressed: onDecreaseQty,
                                      style: FilledButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .errorContainer,
                                        foregroundColor: Theme.of(context)
                                            .colorScheme
                                            .onErrorContainer,
                                      ),
                                      child: const Icon(
                                        Icons.remove,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: gap),
                                  SizedBox(
                                    width: midW,
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.5),
                                        border: Border.all(color: Colors.grey),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Qty: ${line.quantity}',
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: gap),
                                  SizedBox(
                                    width: sideBtn,
                                    child: FilledButton(
                                      onPressed: onIncreaseQty,
                                      style: FilledButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                      ),
                                      child: const Icon(Icons.add, size: 28),
                                    ),
                                  ),
                                  SizedBox(width: gap),
                                  SizedBox(
                                    width: deleteW,
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .error,
                                        foregroundColor: Theme.of(context)
                                            .colorScheme
                                            .onError,
                                      ),
                                      onPressed: () =>
                                          onDeleteSelectedLine(line),
                                      child: const FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text('Delete'),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              const Divider(height: 12),
              Text(
                lastScanSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reserves vertical space for [_ScanTabItemSearchBlock] while the real block is shown
/// in the keyboard floating bar (same controller/focus — only one field in the tree).
class _ScanTabItemSearchPlaceholder extends StatelessWidget {
  const _ScanTabItemSearchPlaceholder({required this.statusText});

  final String statusText;

  @override
  Widget build(BuildContext context) {
    final hasStatus = statusText != '-' && statusText.isNotEmpty;
    // Approximate [_ScanTabItemSearchBlock]: dense outline field row + optional status line.
    const double rowHeight = 58;
    final double statusHeight = hasStatus ? 16 : 0;
    return SizedBox(height: rowHeight + statusHeight);
  }
}

class _ScanTabLoadCreateQuoteBar extends StatelessWidget {
  const _ScanTabLoadCreateQuoteBar({
    required this.onLoadQuote,
    required this.onCreateQuote,
  });

  final VoidCallback onLoadQuote;
  final VoidCallback onCreateQuote;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        FilledButton(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          onPressed: onLoadQuote,
          child: const Text('Load Quote', style: TextStyle(fontSize: 13)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          onPressed: onCreateQuote,
          child: const Text('Create Quote', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}

class _ScanTabItemSearchBlock extends StatelessWidget {
  const _ScanTabItemSearchBlock({
    required this.quickEntryTextFieldKey,
    required this.quickEntryController,
    required this.quickEntryFocusNode,
    required this.onSearchChanged,
    required this.onQuickEntryTapOutside,
    required this.onQuickEntrySubmitted,
    required this.onAddPressed,
    required this.statusText,
  });

  final Key quickEntryTextFieldKey;
  final TextEditingController quickEntryController;
  final FocusNode quickEntryFocusNode;
  final ValueChanged<String> onSearchChanged;
  final TapRegionCallback onQuickEntryTapOutside;
  final ValueChanged<String> onQuickEntrySubmitted;
  final VoidCallback onAddPressed;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: quickEntryTextFieldKey,
                controller: quickEntryController,
                focusNode: quickEntryFocusNode,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Item # / UPC',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
                onChanged: onSearchChanged,
                onTapOutside: onQuickEntryTapOutside,
                onSubmitted: onQuickEntrySubmitted,
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onAddPressed,
                child: const Text('Add', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
        if (statusText != '-' && statusText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                statusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScanTabSearchResultTile extends StatelessWidget {
  const _ScanTabSearchResultTile({
    required this.product,
    required this.alreadyInOrder,
    required this.onTap,
  });

  final Product product;
  final bool alreadyInOrder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(
        product.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        product.itemNumber,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (alreadyInOrder)
              const Text(
                'In order',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.green,
                ),
              ),
            if (alreadyInOrder) const SizedBox(width: 6),
            Text(
              '\$${product.price.toStringAsFixed(2)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      onTap: onTap,
    );
  }
}

class _ScanTabSearchResultsList extends StatelessWidget {
  const _ScanTabSearchResultsList({
    required this.products,
    required this.itemBuilder,
  });

  final List<Product> products;
  final Widget Function(Product) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final product in products) itemBuilder(product),
      ],
    );
  }
}

class _ScanTabOrderListEmpty extends StatelessWidget {
  const _ScanTabOrderListEmpty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          'No items added yet',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ScanTabOrderLinesColumn extends StatelessWidget {
  const _ScanTabOrderLinesColumn({
    required this.listKey,
    required this.children,
  });

  final Key listKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: listKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Single order line row layout (product details + qty controls) for scan / orders lists.
class _OrderLineCardRow extends StatelessWidget {
  // REBUILD_INSTRUMENT: remove when done profiling scan-tab rebuild frequency
  static int _debugRebuildCount = 0;

  const _OrderLineCardRow({
    required this.line,
    required this.lineHasDiscount,
    required this.discountedUnitPrice,
    required this.lineTotal,
    required this.onDecrease,
    required this.onIncrease,
  });

  static const TextStyle _qtyStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 18,
  );

  static final TextStyle _saleUnitStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Colors.green.shade800,
  );

  static final ButtonStyle _increaseQtyIconStyle = IconButton.styleFrom(
    padding: EdgeInsets.zero,
  );

  final OrderLine line;
  final bool lineHasDiscount;
  final double discountedUnitPrice;
  final double lineTotal;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode && _kScanRebuildInstrumentationEnabled) {
      _debugRebuildCount++;
      debugPrint(
        'REBUILD_INSTRUMENT _OrderLineCardRow #$_debugRebuildCount',
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        const double rightCol = 132;
        final leftW = (constraints.maxWidth - 12 - rightCol)
            .clamp(0.0, double.infinity);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: leftW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    line.product.description,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Item: ${line.product.itemNumber}'),
                  Text('UPC: ${line.product.upc}'),
                  Text(
                    'Min Order Qty: ${line.product.minOrderQty}    Case Qty: ${line.product.caseQty}',
                  ),
                  if (lineHasDiscount) ...[
                    Text(
                      'Reg. unit: \$${line.product.price.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      'Sale unit: \$${discountedUnitPrice.toStringAsFixed(2)}',
                      style: _saleUnitStyle,
                    ),
                  ] else
                    Text(
                      'Price: \$${line.product.price.toStringAsFixed(2)}',
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: rightCol,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          onPressed: onDecrease,
                          icon: const Icon(Icons.remove),
                          style: IconButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: colorScheme.errorContainer
                                .withValues(alpha: 0.5),
                            foregroundColor: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${line.quantity}',
                        style: _qtyStyle,
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          onPressed: onIncrease,
                          icon: const Icon(Icons.add),
                          style: _increaseQtyIconStyle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Scans ${line.scans}'),
                  const SizedBox(height: 4),
                  Text(
                    '\$${lineTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Swipe-delete hint behind [Dismissible] — const so unchanged cards skip subtree work.
class _OrderLineCardDismissBackground extends StatelessWidget {
  const _OrderLineCardDismissBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.shade400,
        borderRadius: _kOrderLineCardBorderRadius,
      ),
      child: const Icon(Icons.delete, color: Colors.white),
    );
  }
}

class _OrderLineCard extends StatelessWidget {
  // REBUILD_INSTRUMENT: remove when done profiling scan-tab rebuild frequency
  static int _debugRebuildCount = 0;

  const _OrderLineCard({
    required this.dismissibleKey,
    required this.line,
    this.scanTabHighlightFlash = false,
    required this.lineHasDiscount,
    required this.discountedUnitPrice,
    required this.lineTotal,
    required this.onSwipeDeletePrompt,
    required this.onCardTap,
    required this.onDecrease,
    required this.onIncrease,
  });

  final Key dismissibleKey;
  final OrderLine line;
  final bool scanTabHighlightFlash;
  final bool lineHasDiscount;
  final double discountedUnitPrice;
  final double lineTotal;
  final Future<void> Function() onSwipeDeletePrompt;
  final VoidCallback onCardTap;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode && _kScanRebuildInstrumentationEnabled) {
      _debugRebuildCount++;
      debugPrint(
        'REBUILD_INSTRUMENT _OrderLineCard #$_debugRebuildCount',
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    final ShapeBorder? cardShape = scanTabHighlightFlash
        ? RoundedRectangleBorder(
            borderRadius: _kOrderLineCardBorderRadius,
            side: BorderSide(
              color: colorScheme.primary.withValues(alpha: 0.5),
              width: 2,
            ),
          )
        : null;

    return Dismissible(
      key: dismissibleKey,
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await onSwipeDeletePrompt();
        return false;
      },
      background: const _OrderLineCardDismissBackground(),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: cardShape,
        child: RepaintBoundary(
          child: InkWell(
            borderRadius: _kOrderLineCardBorderRadius,
            onTap: onCardTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _OrderLineCardRow(
                line: line,
                lineHasDiscount: lineHasDiscount,
                discountedUnitPrice: discountedUnitPrice,
                lineTotal: lineTotal,
                onDecrease: onDecrease,
                onIncrease: onIncrease,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderListTab extends StatelessWidget {
  const _OrderListTab({
    required this.orderLinesCount,
    required this.totalUnits,
    required this.orderTotal,
    required this.orderHasDiscount,
    required this.regularOrderTotal,
    required this.totalDiscountAmount,
    required this.loadingProducts,
    required this.activeTabIndex,
    required this.onImportOrder,
    required this.onExportAllQuotes,
    required this.onExportCurrentQuote,
    required this.orderList,
  });

  final int orderLinesCount;
  final int totalUnits;
  final double orderTotal;
  final bool orderHasDiscount;
  final double regularOrderTotal;
  final double totalDiscountAmount;
  final bool loadingProducts;
  final int activeTabIndex;
  final Future<void> Function() onImportOrder;
  final Future<void> Function() onExportAllQuotes;
  final Future<void> Function() onExportCurrentQuote;
  final Widget orderList;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Items in Order',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$orderLinesCount',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Units',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$totalUnits',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              orderHasDiscount ? 'Final Total' : 'Order Total',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '\$${orderTotal.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (orderHasDiscount) ...[
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Regular: \$${regularOrderTotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          'Discount: \$${totalDiscountAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: loadingProducts ? null : () => onImportOrder(),
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Import Order'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: loadingProducts ? null : () => onExportAllQuotes(),
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Export All Quotes'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: loadingProducts ? null : () => onExportCurrentQuote(),
            icon: const Icon(Icons.download_for_offline_outlined),
            label: const Text('Export Current Quote Only'),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: loadingProducts
                ? const Center(child: CircularProgressIndicator())
                : (activeTabIndex == 1
                    ? orderList
                    : const SizedBox.shrink()),
          ),
        ],
      ),
    );
  }
}

class _SetupTab extends StatelessWidget {
  const _SetupTab({
    required this.onLoadProducts,
    required this.onLoadCustomers,
  });

  final VoidCallback onLoadProducts;
  final VoidCallback onLoadCustomers;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Data / Setup',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onLoadProducts,
                  child: const Text('LOAD PRODUCTS'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: onLoadCustomers,
                  child: const Text('LOAD CUSTOMERS'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Archive / confirmed quotes: index-driven list only; does not touch active scan workspace.
class _ArchiveQuotesTab extends StatefulWidget {
  _ArchiveQuotesTab({
    super.key,
    required this.loadArchive,
    required this.onView,
    required this.onRestore,
    required this.onConfirm,
    required this.onReexport,
    required this.onDelete,
    required this.onPurgeArchived,
    required this.onPurgeConfirmed,
  });

  final Future<List<SavedQuoteInfo>> Function() loadArchive;
  final Future<void> Function(SavedQuoteInfo info) onView;
  final Future<void> Function(SavedQuoteInfo info) onRestore;
  final Future<void> Function(SavedQuoteInfo info) onConfirm;
  final Future<void> Function(SavedQuoteInfo info) onReexport;
  final Future<void> Function(SavedQuoteInfo info) onDelete;
  final Future<void> Function() onPurgeArchived;
  final Future<void> Function() onPurgeConfirmed;

  @override
  State<_ArchiveQuotesTab> createState() => _ArchiveQuotesTabState();
}

class _ArchiveQuotesTabState extends State<_ArchiveQuotesTab> {
  late Future<List<SavedQuoteInfo>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadArchive();
  }

  void _reload() {
    setState(() {
      _future = widget.loadArchive();
    });
  }

  /// Called from parent after archive index / quote file cleanup.
  void reloadArchiveList() {
    _reload();
  }

  int _sortArchiveEntries(SavedQuoteInfo a, SavedQuoteInfo b) {
    final ta = a.exportedAt ?? a.updatedAt;
    final tb = b.exportedAt ?? b.updatedAt;
    return tb.compareTo(ta);
  }

  int _sortConfirmedEntries(SavedQuoteInfo a, SavedQuoteInfo b) {
    final ta = a.confirmedAt ?? a.exportedAt ?? a.updatedAt;
    final tb = b.confirmedAt ?? b.exportedAt ?? b.updatedAt;
    return tb.compareTo(ta);
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _badgeFor(SavedQuoteInfo info) {
    final isConfirmed = info.status == QuoteLifecycleStatus.confirmed;
    final label = isConfirmed ? 'CONFIRMED ORDER' : 'Archived';
    // Archived: stronger neutral chip. Confirmed: darker sage chip (finalized, not alert green).
    if (isConfirmed) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final base = dark ? const Color(0xFF7A9D8A) : const Color(0xFF3A5844);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: base.withValues(alpha: dark ? 0.14 : 0.11),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: base.withValues(alpha: dark ? 0.52 : 0.44)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
            color: base.withValues(alpha: dark ? 0.98 : 0.94),
          ),
        ),
      );
    }
    final color = Colors.blueGrey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color.withValues(alpha: 1.0),
        ),
      ),
    );
  }

  String _displayDate(SavedQuoteInfo info) {
    if (info.status == QuoteLifecycleStatus.confirmed &&
        info.confirmedAt != null) {
      return 'Confirmed: ${info.confirmedAt}';
    }
    if (info.exportedAt != null) {
      return 'Exported: ${info.exportedAt}';
    }
    return 'Updated: ${info.updatedAt}';
  }

  Widget _buildCard(SavedQuoteInfo info) {
    final canConfirm = info.status == QuoteLifecycleStatus.archived;
    final isFinalized = info.status == QuoteLifecycleStatus.confirmed;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Confirmed only: soft green-grey fill + subtle green outline (calm finalized, not a banner).
    final Color? finalizedCardColor = isFinalized
        ? Color.alphaBlend(
            (dark ? const Color(0xFF5FA882) : const Color(0xFF7DAC90))
                .withValues(alpha: dark ? 0.20 : 0.22),
            scheme.surfaceContainerLow,
          )
        : null;
    final BorderSide finalizedBorderSide = BorderSide(
      color: (dark ? const Color(0xFF7EB89A) : const Color(0xFF9BB5A8))
          .withValues(alpha: dark ? 0.50 : 0.48),
      width: 1,
    );
    final card = Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: finalizedCardColor,
      elevation: isFinalized ? 0 : null,
      surfaceTintColor: isFinalized ? Colors.transparent : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isFinalized ? finalizedBorderSide : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.customerName.trim().isEmpty
                            ? '(No customer)'
                            : info.customerName.trim(),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.name.trim().isEmpty
                            ? '(Unnamed quote)'
                            : info.name.trim(),
                        style: TextStyle(
                          fontSize: 14,
                          color: onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        info.quoteBucketLabel.trim().isNotEmpty
                            ? '${info.quoteBucketLabel} (${info.quoteBucketKey})'
                            : info.quoteBucketKey,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _displayDate(info),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete from archive',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await widget.onDelete(info);
                  },
                ),
                _badgeFor(info),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton(
                  onPressed: () => widget.onView(info),
                  child: const Text('View'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await widget.onRestore(info);
                    if (mounted) _reload();
                  },
                  child: const Text('Restore'),
                ),
                if (canConfirm)
                  OutlinedButton(
                    onPressed: () async {
                      await widget.onConfirm(info);
                      if (mounted) _reload();
                    },
                    child: const Text('Mark confirmed'),
                  ),
                OutlinedButton(
                  onPressed: () async {
                    await widget.onReexport(info);
                    if (mounted) _reload();
                  },
                  child: const Text('Re-export'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return card;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: FutureBuilder<List<SavedQuoteInfo>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load archive: ${snapshot.error}'));
          }
          final all = snapshot.data ?? [];
          final archived = all
              .where((e) => e.status == QuoteLifecycleStatus.archived)
              .toList()
            ..sort(_sortArchiveEntries);
          final confirmed = all
              .where((e) => e.status == QuoteLifecycleStatus.confirmed)
              .toList()
            ..sort(_sortConfirmedEntries);

          return RefreshIndicator(
            onRefresh: () async {
              final f = widget.loadArchive();
              setState(() {
                _future = f;
              });
              await f;
            },
            child: archived.isEmpty && confirmed.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Text(
                          'No archived quotes yet.\nExport a quote from Orders to see it here.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () async {
                                await widget.onPurgeArchived();
                              },
                              child: const Text('Purge Archived'),
                            ),
                            OutlinedButton(
                              onPressed: () async {
                                await widget.onPurgeConfirmed();
                              },
                              child: const Text('Purge Confirmed'),
                            ),
                          ],
                        ),
                      ),
                      _sectionHeader('Archived'),
                      if (archived.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(
                            'None',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      else
                        ...archived.map(_buildCard),
                      _sectionHeader('Confirmed (Finalized Orders)'),
                      if (confirmed.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(
                            'None',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      else
                        ...confirmed.map(_buildCard),
                      const SizedBox(height: 24),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

// Showroom Scanner - sound paths: use sounds/... with prefix assets/ to avoid double assets/ (2025-03-11)
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xlsx;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'master_products_sheet_builder.dart';

/// Paths chosen in the master build staging dialog (Build Updated Master Products Sheet).
class _MasterBuildFileSet {
  const _MasterBuildFileSet({
    required this.quotePath,
    required this.productsPath,
    required this.psPath,
    required this.newReleasePath,
    required this.whse1InStockPath,
    required this.whse2InStockPath,
    required this.whse1OutOfStockPath,
    required this.whse2OutOfStockPath,
    required this.whse1ComingSoonPath,
    required this.whse2ComingSoonPath,
  });
  final String quotePath;
  final String productsPath;
  final String psPath;
  final String newReleasePath;
  final String whse1InStockPath;
  final String whse2InStockPath;
  final String whse1OutOfStockPath;
  final String whse2OutOfStockPath;
  final String whse1ComingSoonPath;
  final String whse2ComingSoonPath;
}

const String _productsCsvUrl =
    'https://docs.google.com/spreadsheets/d/1UWduf2UklzxcnCA4dd6eKJN8QJb5gWm17k8F70fx1u8/export?format=csv&gid=1691211520';

const String _customersCsvUrl =
    'https://docs.google.com/spreadsheets/d/1C9KzyNN7P7YVYvjpuCizXtxDdpfsp20UKewBAtStdCg/export?format=csv&gid=1371098168';

/// Locally added customers (showroom / Setup); not synced to Google Sheets.
const String _kAddedCustomersFilename = 'added_customers.json';

String _normalizeCustomerNameForDedup(String raw) {
  var t = raw.trim().toLowerCase();
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  return t;
}

/// Master switch for temporary scan-tab profiling (Steps 3–5).
/// When `true` (debug builds only): `REBUILD_INSTRUMENT`, `SETSTATE_TRACE[...]`, and
/// `SCAN_PATH[...]` logs are printed. When `false`, all of that code stays in place but is silent.
const bool _kScanRebuildInstrumentationEnabled = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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

/// Which tab owns compact order-line expand/collapse.
enum _OrderLineCardCompactExpandHost { ordersTab, scanTab, ecatalogTab }

enum _ECatalogNavigationSource { importOrder, other }

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

/// ECatalog Seasonal: accepted [Product.productType] labels.
/// Used only to scope the Seasonal merchandising chip.
const Map<String, String> _kEcatalogSeasonalLabelToProductType = {
  'Calendar & Planner': 'CALENDAR',
  'Canada Day': 'CANADA DAY',
  'Celebrate Pride': 'PRIDE',
  'Chinese New Year': 'CHINESE NEW YEAR',
  'Christmas': 'CHRISTMAS',
  'Diwali': 'DIWALI',
  'Easter': 'EASTER',
  'Fall/Winter Essentials': 'FALL/WINTER ESSENTIALS',
  'Father\'s Day': 'FATHER\'S DAY',
  'Graduation': 'GRADUATION',
  'Halloween': 'HALLOWEEN',
  'Hanukkah': 'HANUKKAH',
  'Harvest': 'HARVEST',
  'Mother\'s Day': 'MOTHER\'S DAY',
  'New Years': 'NEW YEARS',
  'Spring/Summer General': 'SUMMER GENERAL',
  'Spring/Summer Toys': 'SUMMER TOYS',
  'St Patrick\'s Day': 'ST PATRICK\'S DAY',
  'Valentine\'s Day': 'VALENTINE\'S DAY',
};

class ShowroomScannerApp extends StatelessWidget {
  const ShowroomScannerApp({super.key});

  static ThemeData get _showroomTheme {
    final colorScheme =
        ColorScheme.fromSeed(
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

    final textTheme = ThemeData(useMaterial3: true, colorScheme: colorScheme)
        .textTheme
        .apply(bodyColor: _kHeadingText, displayColor: _kHeadingText)
        .copyWith(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
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
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
        ),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return TextStyle(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            );
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
  final double listPrice;
  final String productType;
  final String discountRaw;
  final bool discountEligible;
  final String netRaw;
  final bool isNet;
  final String psRaw;
  final bool isPs;
  final bool isNewRelease;
  final String category;
  final String subCategory;
  final int minOrderQty;
  final int caseQty;
  final bool whse1InStock;
  final bool whse2InStock;
  final bool whse1OutOfStock;
  final bool whse2OutOfStock;
  final bool whse1ComingSoon;
  final bool whse2ComingSoon;
  /// Raw CSV text from Whse 1 Availability / Whse 2 Availability (2-column format only).
  final String whse1AvailabilityDisplay;
  final String whse2AvailabilityDisplay;

  Product({
    required this.itemNumber,
    required this.description,
    required this.upc,
    required this.price,
    required this.listPrice,
    required this.productType,
    required this.discountRaw,
    required this.discountEligible,
    required this.netRaw,
    required this.isNet,
    required this.psRaw,
    required this.isPs,
    required this.isNewRelease,
    required this.category,
    required this.subCategory,
    required this.minOrderQty,
    required this.caseQty,
    this.whse1InStock = false,
    this.whse2InStock = false,
    this.whse1OutOfStock = false,
    this.whse2OutOfStock = false,
    this.whse1ComingSoon = false,
    this.whse2ComingSoon = false,
    this.whse1AvailabilityDisplay = '',
    this.whse2AvailabilityDisplay = '',
  });
}

// --- Products CSV: background isolate (same parsing rules as _parseAndStoreProducts) ---

class _ProductsCsvIsolateJob {
  const _ProductsCsvIsolateJob({
    required this.rawCsv,
    required this.sourceLabel,
  });
  final String rawCsv;
  final String sourceLabel;
}

class _ProductsCsvIsolateResult {
  const _ProductsCsvIsolateResult({
    required this.productsByUpc,
    required this.productsByItemNumber,
    required this.catalogCount,
    required this.catalogSource,
    required this.productsLoadDebugLine,
    required this.isEmptyFile,
  });
  final Map<String, Product> productsByUpc;
  final Map<String, Product> productsByItemNumber;
  final int catalogCount;
  final String catalogSource;
  final String productsLoadDebugLine;
  final bool isEmptyFile;
}

String _piNormalizedProductHeaderKey(String s) {
  return s.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '');
}

Map<String, int> _piProductHeaderIndexMap(List<String> header) {
  final Map<String, int> map = {};
  for (int i = 0; i < header.length; i++) {
    final nk = _piNormalizedProductHeaderKey(header[i]);
    if (nk.isEmpty) continue;
    map.putIfAbsent(nk, () => i);
  }
  return map;
}

int _piRequireProductColumnIndex(
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

int? _piOptionalProductColumnIndex(
  Map<String, int> byNorm,
  List<String> normalizedKeys,
) {
  for (final nk in normalizedKeys) {
    final i = byNorm[nk];
    if (i != null) return i;
  }
  return null;
}

String _piProductCell(List<dynamic> row, int col) {
  if (col < 0 || col >= row.length) return '';
  return row[col].toString();
}

String _piNormalizeItemNumber(String value) => value.trim().toUpperCase();

String _piDigitsOnly(String value) {
  return value.replaceAll(RegExp(r'[^0-9]'), '').trim();
}

String _piNormalizeUpcLookupKey(String value) {
  final trimmed = value.trim();
  final digits = _piDigitsOnly(trimmed);
  return digits.isNotEmpty ? digits : trimmed.toUpperCase();
}

double _piParsePrice(String value) {
  final cleaned = value.replaceAll('\$', '').replaceAll(',', '').trim();
  return double.tryParse(cleaned) ?? 0.0;
}

int _piParseInt(String value) {
  return int.tryParse(value.trim()) ?? 0;
}

bool _piParseDiscountEligibility(String value) {
  return value.trim().toUpperCase() == 'YES';
}

bool _piParseYesFlag(String value) => value.trim().toUpperCase() == 'YES';

String _repairMojibakeText(String value) {
  var text = value.trim();

  // Attempt automatic UTF-8 recovery (handles common mojibake cases).
  try {
    final recovered = utf8.decode(latin1.encode(text));

    // Only adopt recovered text when it appears to improve accents.
    final looksBetter =
        recovered.contains('é') ||
        recovered.contains('è') ||
        recovered.contains('ê') ||
        recovered.contains('ô') ||
        recovered.contains('à') ||
        recovered.contains('ç');

    if (looksBetter) {
      text = recovered;
    }
  } catch (_) {
    // Ignore and continue with original text.
  }

  final replacements = <String, String>{
    'ÃƒÂ©': 'é',
    'Ã©': 'é',
    'ÃƒÂ¨': 'è',
    'Ã¨': 'è',
    'ÃƒÂª': 'ê',
    'Ãª': 'ê',
    'ÃƒÂ«': 'ë',
    'Ã«': 'ë',
    'ÃƒÂ¢': 'â',
    'Ã¢': 'â',
    'ÃƒÂ®': 'î',
    'Ã®': 'î',
    'ÃƒÂ´': 'ô',
    'Ã´': 'ô',
    'ÃƒÂ»': 'û',
    'Ã»': 'û',
    'ÃƒÂ§': 'ç',
    'Ã§': 'ç',
    'ÃƒÂ‰': 'É',
    'Ã‰': 'É',
    'Ã¢â‚¬â„¢': "'",
    'â€™': "'",
    'Ã¢â‚¬Å“': '"',
    'Ã¢â‚¬Â': '"',
    'â€œ': '"',
    'â€': '"',
    'Ã¢â‚¬â€œ': '-',
    'â€“': '-',
    'Ã‚Â': '',
    'Â': '',
  };

  replacements.forEach((bad, good) {
    text = text.replaceAll(bad, good);
  });

  // Final display/export normalization step: force common accented glyphs to ASCII.
  final asciiReplacements = <String, String>{
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'É': 'E',
    'È': 'E',
    'Ê': 'E',
    'Ë': 'E',
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ä': 'a',
    'À': 'A',
    'Á': 'A',
    'Â': 'A',
    'Ä': 'A',
    'î': 'i',
    'ï': 'i',
    'Î': 'I',
    'Ï': 'I',
    'ô': 'o',
    'ö': 'o',
    'Ô': 'O',
    'Ö': 'O',
    'û': 'u',
    'ü': 'u',
    'Û': 'U',
    'Ü': 'U',
    'ç': 'c',
    'Ç': 'C',
  };

  asciiReplacements.forEach((bad, good) {
    text = text.replaceAll(bad, good);
  });

  return text;
}

/// Single warehouse column: "In Stock" | "Out of Stock" | "Coming Soon".
/// Normalizes with [trim], lowercases, collapses internal whitespace; unknown → all false.
/// At most one of the three flags is true.
({bool inStock, bool outOfStock, bool comingSoon})
    _piParseWarehouseAvailabilityTriState(String raw) {
  final collapsed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  final n = collapsed.toLowerCase();
  if (n == 'in stock') {
    return (inStock: true, outOfStock: false, comingSoon: false);
  }
  if (n == 'out of stock') {
    return (inStock: false, outOfStock: true, comingSoon: false);
  }
  if (n == 'coming soon') {
    return (inStock: false, outOfStock: false, comingSoon: true);
  }
  return (inStock: false, outOfStock: false, comingSoon: false);
}

/// Keeps parity counters referenced so analyzer stays clean without changing outcomes.
void _productsCsvSinkUnused(Object? _) {}

_ProductsCsvIsolateResult _parseProductsCatalogCsvIsolate(_ProductsCsvIsolateJob job) {
  final rawCsv = job.rawCsv;
  final sourceLabel = job.sourceLabel;

  final rows = const CsvToListConverter(
    shouldParseNumbers: false,
  ).convert(rawCsv);

  if (rows.isEmpty) {
    return _ProductsCsvIsolateResult(
      productsByUpc: {},
      productsByItemNumber: {},
      catalogCount: 0,
      catalogSource: '$sourceLabel (empty)',
      productsLoadDebugLine: 'Products Loaded: 0 (empty file)',
      isEmptyFile: true,
    );
  }

  final header = rows.first
      .map((e) => e.toString().trim())
      .toList(growable: false);
  final byNorm = _piProductHeaderIndexMap(header);

  final idxItemNumber = _piRequireProductColumnIndex(
    byNorm,
    'Item Number',
    const ['itemnumber'],
    header,
  );
  final idxDescription = _piRequireProductColumnIndex(
    byNorm,
    'Description',
    const ['description'],
    header,
  );
  final idxUpc = _piRequireProductColumnIndex(byNorm, 'UPC', const [
    'upc',
  ], header);
  final idxPrice = _piRequireProductColumnIndex(byNorm, 'Price', const [
    'price',
  ], header);
  final idxDiscount = _piRequireProductColumnIndex(byNorm, 'DISCOUNT', const [
    'discount',
  ], header);
  final idxNet = _piOptionalProductColumnIndex(byNorm, const ['net']);
  final idxPs = _piOptionalProductColumnIndex(byNorm, const ['ps']);
  final idxListPrice = _piOptionalProductColumnIndex(byNorm, const [
    'listprice',
  ]);
  final idxNewRelease = _piOptionalProductColumnIndex(byNorm, const [
    'newrelease',
  ]);
  final idxWhse1Availability = _piOptionalProductColumnIndex(byNorm, const [
    'whse1availability',
  ]);
  final idxWhse2Availability = _piOptionalProductColumnIndex(byNorm, const [
    'whse2availability',
  ]);
  final warehouseViaAvailabilityColumns =
      idxWhse1Availability != null && idxWhse2Availability != null;

  int? idxWhse1In;
  int? idxWhse2In;
  int? idxWhse1Out;
  int? idxWhse2Out;
  int? idxWhse1Soon;
  int? idxWhse2Soon;
  if (!warehouseViaAvailabilityColumns) {
    idxWhse1In = _piOptionalProductColumnIndex(byNorm, const [
      'whse1instock',
    ]);
    idxWhse2In = _piOptionalProductColumnIndex(byNorm, const [
      'whse2instock',
    ]);
    idxWhse1Out = _piOptionalProductColumnIndex(byNorm, const [
      'whse1outofstock',
    ]);
    idxWhse2Out = _piOptionalProductColumnIndex(byNorm, const [
      'whse2outofstock',
    ]);
    idxWhse1Soon = _piOptionalProductColumnIndex(byNorm, const [
      'whse1comingsoon',
    ]);
    idxWhse2Soon = _piOptionalProductColumnIndex(byNorm, const [
      'whse2comingsoon',
    ]);
    final missingWhseHeaders = <String>[];
    if (idxWhse1In == null) missingWhseHeaders.add('Whse 1 In Stock');
    if (idxWhse2In == null) missingWhseHeaders.add('Whse 2 In Stock');
    if (idxWhse1Out == null) missingWhseHeaders.add('Whse 1 Out of Stock');
    if (idxWhse2Out == null) missingWhseHeaders.add('Whse 2 Out of Stock');
    if (idxWhse1Soon == null) missingWhseHeaders.add('Whse 1 Coming Soon');
    if (idxWhse2Soon == null) missingWhseHeaders.add('Whse 2 Coming Soon');
    if (missingWhseHeaders.isNotEmpty) {
      debugPrint(
        '[WhseDiag] Optional warehouse columns missing '
        '(${missingWhseHeaders.length}/6): ${missingWhseHeaders.join(', ')}; '
        'defaulting to false',
      );
    }
  } else {
    debugPrint(
      '[WhseDiag] Using Whse 1 Availability / Whse 2 Availability columns',
    );
  }
  final idxProductType = _piRequireProductColumnIndex(
    byNorm,
    'Product Type',
    const ['producttype'],
    header,
  );
  final idxCategory = _piRequireProductColumnIndex(byNorm, 'Category', const [
    'category',
  ], header);
  final idxSubCategory = _piRequireProductColumnIndex(
    byNorm,
    'Sub-Category',
    const ['subcategory'],
    header,
  );
  final idxMinOrderQty = _piRequireProductColumnIndex(
    byNorm,
    'Minimum Order Quantity',
    const [
      'minorderqty',
      'minimumorderquantity',
      'moq',
      'minqty',
    ],
    header,
  );
  final idxCaseQty = _piRequireProductColumnIndex(
    byNorm,
    'Case Quantity',
    const [
      'caseqty',
      'casequantity',
      'case',
    ],
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
    if (idxNet != null) idxNet,
    if (idxPs != null) idxPs,
    if (idxListPrice != null) idxListPrice,
    if (idxNewRelease != null) idxNewRelease,
    if (warehouseViaAvailabilityColumns) ...[
      idxWhse1Availability,
      idxWhse2Availability,
    ] else ...[
      if (idxWhse1In != null) idxWhse1In,
      if (idxWhse2In != null) idxWhse2In,
      if (idxWhse1Out != null) idxWhse1Out,
      if (idxWhse2Out != null) idxWhse2Out,
      if (idxWhse1Soon != null) idxWhse1Soon,
      if (idxWhse2Soon != null) idxWhse2Soon,
    ],
  ].reduce((a, b) => a > b ? a : b);

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
    if (row.isEmpty || row.every((e) => e.toString().trim().isEmpty)) {
      skippedParseErrorRows++;
      continue;
    }

    try {
      final itemNumber = _piNormalizeItemNumber(
        _piProductCell(row, idxItemNumber),
      );
      final description = _repairMojibakeText(_piProductCell(row, idxDescription));
      final upc = _piProductCell(row, idxUpc).trim();
      final upcLookup = _piNormalizeUpcLookupKey(upc);
      final price = _piParsePrice(_piProductCell(row, idxPrice));
      final listPrice = idxListPrice == null
          ? 0.0
          : _piParsePrice(_piProductCell(row, idxListPrice));
      final discountRaw = _piProductCell(row, idxDiscount).trim();
      final discountEligible = _piParseDiscountEligibility(discountRaw);
      final netRaw = idxNet == null ? '' : _piProductCell(row, idxNet).trim();
      final isNet = _piParseYesFlag(netRaw);
      final psRaw = idxPs == null ? '' : _piProductCell(row, idxPs).trim();
      final isPs = _piParseYesFlag(psRaw);
      final isNewRelease = idxNewRelease == null
          ? false
          : _piParseYesFlag(_piProductCell(row, idxNewRelease).trim());
      late final bool whse1InStock;
      late final bool whse2InStock;
      late final bool whse1OutOfStock;
      late final bool whse2OutOfStock;
      late final bool whse1ComingSoon;
      late final bool whse2ComingSoon;
      late final String whse1AvailabilityDisplay;
      late final String whse2AvailabilityDisplay;
      if (warehouseViaAvailabilityColumns) {
        final rawW1 = _piProductCell(row, idxWhse1Availability);
        final rawW2 = _piProductCell(row, idxWhse2Availability);
        whse1AvailabilityDisplay = _repairMojibakeText(rawW1);
        whse2AvailabilityDisplay = _repairMojibakeText(rawW2);
        final w1 = _piParseWarehouseAvailabilityTriState(rawW1);
        whse1InStock = w1.inStock;
        whse1OutOfStock = w1.outOfStock;
        whse1ComingSoon = w1.comingSoon;
        final w2 = _piParseWarehouseAvailabilityTriState(rawW2);
        whse2InStock = w2.inStock;
        whse2OutOfStock = w2.outOfStock;
        whse2ComingSoon = w2.comingSoon;
      } else {
        whse1AvailabilityDisplay = '';
        whse2AvailabilityDisplay = '';
        whse1InStock = idxWhse1In == null
            ? false
            : _piParseYesFlag(_piProductCell(row, idxWhse1In).trim());
        whse2InStock = idxWhse2In == null
            ? false
            : _piParseYesFlag(_piProductCell(row, idxWhse2In).trim());
        whse1OutOfStock = idxWhse1Out == null
            ? false
            : _piParseYesFlag(_piProductCell(row, idxWhse1Out).trim());
        whse2OutOfStock = idxWhse2Out == null
            ? false
            : _piParseYesFlag(_piProductCell(row, idxWhse2Out).trim());
        whse1ComingSoon = idxWhse1Soon == null
            ? false
            : _piParseYesFlag(_piProductCell(row, idxWhse1Soon).trim());
        whse2ComingSoon = idxWhse2Soon == null
            ? false
            : _piParseYesFlag(_piProductCell(row, idxWhse2Soon).trim());
      }
      if (discountEligible) discountEligibleCount++;
      final productType = _repairMojibakeText(_piProductCell(row, idxProductType));
      final category = _repairMojibakeText(_piProductCell(row, idxCategory));
      final subCategory = _repairMojibakeText(_piProductCell(row, idxSubCategory));
      final minOrderQty = _piParseInt(_piProductCell(row, idxMinOrderQty));
      final caseQty = _piParseInt(_piProductCell(row, idxCaseQty));

      // Item number is the required identity for catalog indexing.
      // Blank UPC rows are still valid for item-number lookups.
      if (itemNumber.isEmpty) {
        skippedMissingKeyRows++;
        continue;
      }

      final product = Product(
        itemNumber: itemNumber,
        description: description,
        upc: upc,
        price: price,
        listPrice: listPrice,
        productType: productType,
        discountRaw: discountRaw,
        discountEligible: discountEligible,
        netRaw: netRaw,
        isNet: isNet,
        psRaw: psRaw,
        isPs: isPs,
        isNewRelease: isNewRelease,
        category: category,
        subCategory: subCategory,
        minOrderQty: minOrderQty == 0 ? 1 : minOrderQty,
        caseQty: caseQty,
        whse1InStock: whse1InStock,
        whse2InStock: whse2InStock,
        whse1OutOfStock: whse1OutOfStock,
        whse2OutOfStock: whse2OutOfStock,
        whse1ComingSoon: whse1ComingSoon,
        whse2ComingSoon: whse2ComingSoon,
        whse1AvailabilityDisplay: whse1AvailabilityDisplay,
        whse2AvailabilityDisplay: whse2AvailabilityDisplay,
      );

      if (upcLookup.isNotEmpty && newProductsByUpc.containsKey(upcLookup)) {
        duplicateUpcCount++;
        final existing = newProductsByUpc[upcLookup]!;
        debugPrint(
          '[Products][DuplicateUPC] Duplicate UPC detected: $upcLookup\n'
          '  Existing item: ${existing.itemNumber}\n'
          '  New item: $itemNumber\n'
          '  Row index (parsed rows): $i (1-based line in file: ${i + 1})',
        );
      }
      if (newProductsByItemNumber.containsKey(itemNumber)) {
        duplicateItemNumberCount++;
      }

      if (upcLookup.isNotEmpty) {
        newProductsByUpc[upcLookup] = product;
      }
      newProductsByItemNumber[itemNumber] = product;
      processedRows++;
    } catch (e) {
      skippedParseErrorRows++;
      if (firstErrorMessage == null) {
        firstErrorMessage = 'Row ${i + 1} parse error: $e';
      }
    }
  }

  final int skippedRows = skippedMissingKeyRows + skippedParseErrorRows;

  debugPrint(
    '[Products][DuplicateUPC] Total duplicate UPCs: $duplicateUpcCount',
  );

  _productsCsvSinkUnused((
    maxColIndex,
    totalDataRows,
    skippedRows,
    processedRows,
    duplicateUpcCount,
    duplicateItemNumberCount,
    discountEligibleCount,
    firstErrorMessage,
  ));

  return _ProductsCsvIsolateResult(
    productsByUpc: newProductsByUpc,
    productsByItemNumber: newProductsByItemNumber,
    catalogCount: newProductsByUpc.length,
    catalogSource: sourceLabel,
    productsLoadDebugLine: 'Products Loaded: ${newProductsByUpc.length}',
    isEmptyFile: false,
  );
}

// --- Customers CSV: background isolate (same parsing rules as _parseAndStoreCustomers) ---

enum _CustomersCsvIsolateOutcome { earlyFailure, success }

class _CustomersCsvIsolateResult {
  const _CustomersCsvIsolateResult({
    required this.outcome,
    required this.totalRowsRead,
    required this.customersLoaded,
    required this.customersWithDiscount,
    required this.skippedRows,
    required this.duplicateKeyRows,
    required this.customers,
    required this.customersByKey,
  });

  final _CustomersCsvIsolateOutcome outcome;
  final int totalRowsRead;
  final int customersLoaded;
  final int customersWithDiscount;
  final int skippedRows;
  final int duplicateKeyRows;
  final List<Customer> customers;
  final Map<String, Customer> customersByKey;
}

_CustomersCsvIsolateResult _customersCsvEarlyFailure({
  required int totalRowsRead,
  required int customersLoaded,
  required int customersWithDiscount,
  required int skippedRows,
  required int duplicateKeyRows,
}) {
  return _CustomersCsvIsolateResult(
    outcome: _CustomersCsvIsolateOutcome.earlyFailure,
    totalRowsRead: totalRowsRead,
    customersLoaded: customersLoaded,
    customersWithDiscount: customersWithDiscount,
    skippedRows: skippedRows,
    duplicateKeyRows: duplicateKeyRows,
    customers: const <Customer>[],
    customersByKey: <String, Customer>{},
  );
}

void _debugPrintCustomerLoadReportFromResult(_CustomersCsvIsolateResult r) {
  debugPrint('----- CUSTOMER LOAD REPORT -----');
  debugPrint('Total rows read: ${r.totalRowsRead}');
  debugPrint('Customers loaded: ${r.customersLoaded}');
  debugPrint('Customers with discount > 0: ${r.customersWithDiscount}');
  debugPrint('Skipped rows: ${r.skippedRows}');
  if (r.duplicateKeyRows > 0) {
    debugPrint(
      'Duplicate key rows skipped: ${r.duplicateKeyRows} '
      '(first occurrence kept; key is CSV Id, or CompanyName if Id empty)',
    );
  } else {
    debugPrint('Duplicate key rows skipped: 0');
  }
  if (r.customersLoaded == 0) {
    debugPrint(
      '[Customers] Zero customers in memory: check CSV content, headers, '
      'required columns (Id and/or CompanyName), empty data rows, or '
      'parse errors above.',
    );
  }
}

/// Top-level for [compute]; must not touch [State] or call [setState].
_CustomersCsvIsolateResult _parseCustomersCatalogCsvIsolate(String rawCsv) {
  final trimmed = rawCsv.trim();
  if (trimmed.isEmpty) {
    debugPrint('[Customers] CSV text is empty after trim.');
    return _customersCsvEarlyFailure(
      totalRowsRead: 0,
      customersLoaded: 0,
      customersWithDiscount: 0,
      skippedRows: 0,
      duplicateKeyRows: 0,
    );
  }

  final firstLine = rawCsv.split('\n').first;
  final useTab = firstLine.split('\t').length > firstLine.split(',').length;
  List<List<dynamic>> rows;
  try {
    rows = CsvToListConverter(
      shouldParseNumbers: false,
      fieldDelimiter: useTab ? '\t' : ',',
    ).convert(rawCsv);
  } catch (e) {
    debugPrint('[Customers] CSV parse failed: $e');
    return _customersCsvEarlyFailure(
      totalRowsRead: 0,
      customersLoaded: 0,
      customersWithDiscount: 0,
      skippedRows: 0,
      duplicateKeyRows: 0,
    );
  }

  if (rows.isEmpty) {
    debugPrint('[Customers] CSV parse produced no rows.');
    return _customersCsvEarlyFailure(
      totalRowsRead: 0,
      customersLoaded: 0,
      customersWithDiscount: 0,
      skippedRows: 0,
      duplicateKeyRows: 0,
    );
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
    return _customersCsvEarlyFailure(
      totalRowsRead: rows.length > 1 ? rows.length - 1 : 0,
      customersLoaded: 0,
      customersWithDiscount: 0,
      skippedRows: rows.length > 1 ? rows.length - 1 : 0,
      duplicateKeyRows: 0,
    );
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

  return _CustomersCsvIsolateResult(
    outcome: _CustomersCsvIsolateOutcome.success,
    totalRowsRead: totalRowsRead,
    customersLoaded: list.length,
    customersWithDiscount: discountNonZero,
    skippedRows: skippedRows,
    duplicateKeyRows: duplicateKeyRows,
    customers: list,
    customersByKey: byKey,
  );
}

String _availabilityLabelForWhse1(Product product) {
  final display = product.whse1AvailabilityDisplay.trim();
  if (display.isNotEmpty) return display;
  if (product.whse1InStock) return 'In Stock';
  if (product.whse1OutOfStock) return 'Out of Stock';
  if (product.whse1ComingSoon) return 'Coming Soon';
  return '';
}

String _availabilityLabelForWhse2(Product product) {
  final display = product.whse2AvailabilityDisplay.trim();
  if (display.isNotEmpty) return display;
  if (product.whse2InStock) return 'In Stock';
  if (product.whse2OutOfStock) return 'Out of Stock';
  if (product.whse2ComingSoon) return 'Coming Soon';
  return '';
}

/// Order line title text only. Merchandising badges come from [_productFlagChips].
Widget _orderLineTitleWithOptionalNewBadge({
  required String description,
  required TextStyle style,
  TextAlign textAlign = TextAlign.start,
  int maxLines = 2,
}) {
  return Text(
    description,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    textAlign: textAlign,
    style: style,
  );
}

/// Shared merchandising flag chips sourced from [Product] metadata.
List<Widget> _productFlagChips(BuildContext context, Product product) {
  final colorScheme = Theme.of(context).colorScheme;
  final chips = <Widget>[
    if (product.isNewRelease)
      _ECatalogProductDetailSheet._flagChip(context, 'NEW', Colors.blue),
    if (product.isPs)
      _ECatalogProductDetailSheet._flagChip(context, 'PS', colorScheme.primary),
    if (product.isNet)
      _ECatalogProductDetailSheet._flagChip(
        context,
        'NET',
        colorScheme.tertiary,
      ),
  ];
  return chips;
}

/// Cent-rounded money — single source of truth for quote line and order totals.
double _roundMoney(num value) {
  return (value * 100).roundToDouble() / 100.0;
}

double _roundedUnitPrice(double rawUnitPrice) {
  return _roundMoney(rawUnitPrice);
}

double _lineTotalFromRoundedUnitPrice({
  required double rawUnitPrice,
  required num qty,
}) {
  final unit = _roundedUnitPrice(rawUnitPrice);
  return _roundMoney(unit * qty);
}

/// List price for PS "Reg. Price" display when present; otherwise sheet unit price.
double _displayRegUnitPrice(Product product) => _roundedUnitPrice(
  product.listPrice > 0 ? product.listPrice : product.price,
);

enum ProductPricingState { regular, discountEligible, net, ps }

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
  final String upc;
  final int quantity;

  /// From an optional Description column when the import header names it.
  final String description;

  /// From an optional Price column when the import header names it.
  final String price;

  const OrderImportCsvRow({
    required this.item,
    this.upc = '',
    required this.quantity,
    this.description = '',
    this.price = '',
  });
}

/// Represents one row that could not be imported and why.
class OrderImportSkippedRow {
  final String item;
  final String quantity;
  final String description;
  final String price;
  final String reason;

  const OrderImportSkippedRow({
    required this.item,
    required this.quantity,
    this.description = '',
    this.price = '',
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

  /// Non-header data rows from the selected CSV files (valid rows + parse-time skips).
  final int totalRowsProcessed;
  final int newItemsCount;
  final int duplicateChoiceTotalQtyCount;
  final int duplicateChoiceMinimumQtyCount;
  final int duplicateChoiceSkipCount;
  final int duplicateChoiceUseImportedQtyCount;

  const OrderImportApplyOutcome({
    required this.importedRows,
    required this.moqAdjustedRows,
    required this.importedQuantityByBucket,
    required this.skippedRows,
    required this.totalRowsProcessed,
    required this.newItemsCount,
    required this.duplicateChoiceTotalQtyCount,
    required this.duplicateChoiceMinimumQtyCount,
    required this.duplicateChoiceSkipCount,
    required this.duplicateChoiceUseImportedQtyCount,
  });

  int get duplicateItemsCount =>
      duplicateChoiceTotalQtyCount +
      duplicateChoiceMinimumQtyCount +
      duplicateChoiceSkipCount +
      duplicateChoiceUseImportedQtyCount;

  int get moqAdjustedCount => moqAdjustedRows;

  /// Catalog resolution and apply failures only (merge with parse-phase skips for a full report).
  List<OrderImportSkippedRow> get notImportedItems => skippedRows;

  int get notImportedCount => skippedRows.length;
}

/// Resolution for a catalog item that already exists on the order during CSV import.
enum OrderImportDuplicateResolution {
  totalQty,
  minimumQty,
  skip,
  useImportedQty,
}

/// Options shown in the duplicate import review dialog (MOQ-safe presets only; no replace-with-file).
const List<OrderImportDuplicateResolution> _kOrderImportDuplicateReviewOptions =
    [
      OrderImportDuplicateResolution.totalQty,
      OrderImportDuplicateResolution.minimumQty,
      OrderImportDuplicateResolution.skip,
    ];

/// One grouped CSV import row after catalog match and MOQ snap (may conflict with current order).
class OrderImportPreparedLine {
  final String displayItem;
  final Product product;

  /// Quantity from the file after grouping rows and snapping to MOQ (import path).
  final int importedQtyMoq;
  final int rawCsvCombinedQty;

  /// When non-null, the order already has at least one matching line; sum of those quantities.
  final int? existingOrderQtySum;
  final String sourceDescription;
  final String sourcePrice;

  const OrderImportPreparedLine({
    required this.displayItem,
    required this.product,
    required this.importedQtyMoq,
    required this.rawCsvCombinedQty,
    required this.existingOrderQtySum,
    this.sourceDescription = '',
    this.sourcePrice = '',
  });

  bool get isDuplicate => existingOrderQtySum != null;
}

class OrderImportPrepareOutcome {
  final List<OrderImportPreparedLine> lines;
  final List<OrderImportSkippedRow> skippedRows;
  final List<OrderImportItemsWithoutUpcRow> itemsWithoutUpcRows;

  /// Rows where grouped CSV quantity differed from MOQ-rounded import quantity.
  final int csvMoqAdjustedRows;

  /// Non-header data rows from the selected CSV files (valid rows + parse-time skips).
  final int totalRowsProcessed;

  const OrderImportPrepareOutcome({
    required this.lines,
    required this.skippedRows,
    required this.itemsWithoutUpcRows,
    required this.csvMoqAdjustedRows,
    required this.totalRowsProcessed,
  });
}

class OrderImportItemsWithoutUpcRow {
  final String itemNumber;
  final int quantity;
  final String originalUpc;
  final String resolutionStatus;
  final String description;
  final String price;
  final String minimumOrderQuantity;
  final String caseQuantity;

  const OrderImportItemsWithoutUpcRow({
    required this.itemNumber,
    required this.quantity,
    required this.originalUpc,
    required this.resolutionStatus,
    this.description = '',
    this.price = '',
    this.minimumOrderQuantity = '',
    this.caseQuantity = '',
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'itemNumber': itemNumber,
    'quantity': quantity,
    'originalUpc': originalUpc,
    'resolutionStatus': resolutionStatus,
    'description': description,
    'price': price,
    'minimumOrderQuantity': minimumOrderQuantity,
    'caseQuantity': caseQuantity,
  };

  factory OrderImportItemsWithoutUpcRow.fromJson(Map<String, dynamic> json) {
    String resolutionStatusFromJson(Map<String, dynamic> raw) {
      final primary = (raw['resolutionStatus'] ?? '').toString().trim();
      if (primary.isNotEmpty) return primary;
      // Backward-compatible fallbacks for older persisted payloads.
      final legacy = (raw['status'] ?? raw['resolution'] ?? '')
          .toString()
          .trim();
      if (legacy.isNotEmpty) return legacy;
      return '';
    }

    int quantityFromJson(dynamic raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse((raw ?? '').toString().trim()) ?? 0;
    }

    return OrderImportItemsWithoutUpcRow(
      itemNumber: (json['itemNumber'] ?? '').toString(),
      quantity: quantityFromJson(json['quantity']),
      originalUpc: (json['originalUpc'] ?? '').toString(),
      resolutionStatus: resolutionStatusFromJson(json),
      description: (json['description'] ?? '').toString(),
      price: (json['price'] ?? '').toString(),
      minimumOrderQuantity: (json['minimumOrderQuantity'] ?? '').toString(),
      caseQuantity: (json['caseQuantity'] ?? '').toString(),
    );
  }
}

String _orderImportNormalizeItemKey(String value) => value.trim().toUpperCase();

bool _orderImportIsExcelFileName(String fileName) {
  final ext = p.extension(fileName).toLowerCase();
  return ext == '.xlsx' || ext == '.xls';
}

String _orderImportExcelCellAsText(dynamic cell) {
  if (cell == null) return '';
  final dynamic value = cell.value;
  if (value == null) return '';
  if (value is xlsx.TextCellValue) return value.value.toString().trim();
  if (value is xlsx.IntCellValue) return value.value.toString();
  if (value is xlsx.DoubleCellValue) return value.value.toString();
  if (value is xlsx.BoolCellValue) return value.value ? 'TRUE' : 'FALSE';
  final dynamic maybeValue = value.value;
  if (maybeValue != null) return maybeValue.toString().trim();
  return value.toString().trim();
}

OrderImportCsvParseOutcome parseOrderImportExcelBytes(
  List<int> bytes, {
  required String sourceLabel,
}) {
  if (bytes.isEmpty) {
    throw FormatException('Excel file is empty.');
  }
  final workbook = xlsx.Excel.decodeBytes(bytes);
  if (workbook.tables.isEmpty) {
    throw FormatException('Excel file has no worksheets.');
  }
  final defaultSheet = workbook.getDefaultSheet();
  final sheetName = (defaultSheet != null && workbook.tables[defaultSheet] != null)
      ? defaultSheet
      : workbook.tables.keys.first;
  final sheet = workbook.tables[sheetName];
  if (sheet == null) {
    throw FormatException('Unable to read worksheet from "$sourceLabel".');
  }
  if (sheet.rows.length < 2) {
    throw FormatException('Excel has no data rows (only a header).');
  }

  final csvRows = <List<String>>[];
  for (final row in sheet.rows) {
    csvRows.add(row.map(_orderImportExcelCellAsText).toList(growable: false));
  }

  final csvLikeText = const ListToCsvConverter().convert(csvRows);
  print('[ImportFile] path=$sourceLabel');
  print('[ImportFile] bytes=${bytes.length}');
  print(
    '[ImportFile] text contains 12322255=${csvLikeText.contains('12322255')}',
  );
  return parseOrderImportCsv(csvLikeText);
}

String _orderImportNormalizedImportHeaderLabel(String s) {
  return s.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '');
}

String _orderImportOptionalCsvCell(List<dynamic> row, int? columnIndex) {
  if (columnIndex == null || columnIndex >= row.length) return '';
  return row[columnIndex].toString().trim();
}

/// First matching column index for optional Description / Price on order-import CSVs.
({int? descriptionCol, int? priceCol})
_orderImportOptionalDescriptionPriceColumns(List<dynamic> headerRow) {
  int? descriptionCol;
  int? priceCol;
  for (var i = 0; i < headerRow.length; i++) {
    final nk = _orderImportNormalizedImportHeaderLabel(headerRow[i].toString());
    if (nk.isEmpty) continue;
    // Columns 0–1 are always Item and Quantity; optional fields start at index 2+.
    if (i < 2) continue;
    if (descriptionCol == null &&
        (nk == 'description' ||
            nk == 'itemdescription' ||
            nk == 'productdescription')) {
      descriptionCol = i;
    }
    if (priceCol == null &&
        (nk == 'price' ||
            nk == 'unitprice' ||
            nk == 'listprice' ||
            nk == 'saleprice')) {
      priceCol = i;
    }
  }
  return (descriptionCol: descriptionCol, priceCol: priceCol);
}

({int itemCol, int qtyCol, int? upcCol}) _orderImportCoreColumns(
  List<dynamic> headerRow,
) {
  int? itemCol;
  int? qtyCol;
  int? upcCol;
  for (var i = 0; i < headerRow.length; i++) {
    final nk = _orderImportNormalizedImportHeaderLabel(headerRow[i].toString());
    if (nk.isEmpty) continue;
    if (itemCol == null &&
        (nk == 'item' ||
            nk == 'itemnumber' ||
            nk == 'itemno' ||
            nk == 'item#' ||
            nk == 'sku')) {
      itemCol = i;
    }
    if (qtyCol == null &&
        (nk == 'quantity' ||
            nk == 'qty' ||
            nk == 'qtyordered' ||
            nk == 'orderqty' ||
            nk == 'orderedqty')) {
      qtyCol = i;
    }
    if (upcCol == null &&
        (nk == 'upc' ||
            nk == 'upccode' ||
            nk == 'upcnumber' ||
            nk == 'barcode' ||
            nk == 'ean')) {
      upcCol = i;
    }
  }
  return (itemCol: itemCol ?? 0, qtyCol: qtyCol ?? 1, upcCol: upcCol);
}

String _orderImportNormalizeUpcLookupKey(String value) {
  final trimmed = value.trim();
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '').trim();
  return digits.isNotEmpty ? digits : trimmed.toUpperCase();
}

/// Reads [rawCsv], skips the first row (header), trims fields, skips empty rows.
/// Throws [FormatException] when the file is empty, unparseable, or has no data rows after the header.
OrderImportCsvParseOutcome parseOrderImportCsv(String rawCsv) {
  print('🔥 PARSER RUNNING 🔥');
  final trimmed = rawCsv.trim();
  if (trimmed.isEmpty) {
    throw FormatException('CSV file is empty.');
  }
  final List<List<dynamic>> rows;
  try {
    rows = const CsvToListConverter(shouldParseNumbers: false).convert(rawCsv);
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
  final (:itemCol, :qtyCol, :upcCol) = _orderImportCoreColumns(rows[0]);
  final (:descriptionCol, :priceCol) =
      _orderImportOptionalDescriptionPriceColumns(rows[0]);

  for (int i = 1; i < rows.length; i++) {
    final row = rows[i];
    final item = itemCol < row.length ? row[itemCol].toString().trim() : '';
    final upc = upcCol != null && upcCol < row.length
        ? row[upcCol].toString().trim()
        : '';
    final qtyStr = qtyCol < row.length ? row[qtyCol].toString().trim() : '';
    final rowDescription = _orderImportOptionalCsvCell(row, descriptionCol);
    final rowPrice = _orderImportOptionalCsvCell(row, priceCol);
    print('[ImportParse] raw row=$row');
    if (item.isEmpty && upc.isEmpty && qtyStr.isEmpty) {
      const reason = 'Empty item and quantity.';
      print('[ImportParse] skipped row reason=$reason row=$row');
      skippedRows.add(
        OrderImportSkippedRow(
          item: '',
          quantity: qtyStr,
          description: rowDescription,
          price: rowPrice,
          reason: reason,
        ),
      );
      continue;
    }
    final parsedQty = int.tryParse(qtyStr);
    final qty = (parsedQty == null || parsedQty < 1) ? 1 : parsedQty;
    list.add(
      OrderImportCsvRow(
        item: item,
        upc: upc,
        quantity: qty,
        description: rowDescription,
        price: rowPrice,
      ),
    );
  }

  if (list.isEmpty) {
    throw FormatException(
      'No valid data rows with Item and a positive Quantity.',
    );
  }

  print('[ImportParse] rows parsed=${list.length}');
  return OrderImportCsvParseOutcome(rows: list, skippedRows: skippedRows);
}

/// Match import row to catalog: UPC first (when present), then item number.
Product? matchOrderImportProduct(
  String itemLabel,
  Map<String, Product> productsByItemNumber,
  Map<String, Product> productsByUpc, {
  String upcLabel = '',
  List<int>? numericItemFallbackWidths,
}
) {
  Product? lookupByUpcRaw(String raw) {
    final upc = _orderImportNormalizeUpcLookupKey(raw);
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

  final explicitUpc = upcLabel.trim();
  if (explicitUpc.isNotEmpty) {
    final byExplicitUpc = lookupByUpcRaw(explicitUpc);
    if (byExplicitUpc != null) return byExplicitUpc;
  } else {
    // Legacy import formats often place UPC in the first identifier column.
    final byLegacyInlineUpc = lookupByUpcRaw(itemLabel);
    if (byLegacyInlineUpc != null) return byLegacyInlineUpc;
  }

  final itemKey = _orderImportNormalizeItemKey(itemLabel);
  if (itemKey.isEmpty) return null;

  final byItem = productsByItemNumber[itemKey];
  if (byItem != null) {
    debugPrint(
      '[ImportOrderMatch] matched product item=${byItem.itemNumber} upc=${byItem.upc}',
    );
    return byItem;
  }

  final isNumericItemLabel = RegExp(r'^\d+$').hasMatch(itemKey);
  if (isNumericItemLabel) {
    final candidateWidths =
        numericItemFallbackWidths ??
        (productsByItemNumber.keys
              .where(
                (k) =>
                    k.length > itemKey.length && RegExp(r'^\d+$').hasMatch(k),
              )
              .map((k) => k.length)
              .toSet()
              .toList()
          ..sort());
    for (final width in candidateWidths) {
      if (width <= itemKey.length) continue;
      final padded = itemKey.padLeft(width, '0');
      final byPaddedItem = productsByItemNumber[padded];
      if (byPaddedItem != null) {
        debugPrint(
          '[ImportOrderMatch] matched product item=${byPaddedItem.itemNumber} upc=${byPaddedItem.upc}',
        );
        debugPrint(
          '[ImportMatch] item-number leading-zero fallback matched "$itemKey" -> "$padded"',
        );
        return byPaddedItem;
      }
    }
  }
  return null;
}

Future<File> saveOrderExportCsv({
  required String directoryPath,
  required String filename,
  required String csvText,
}) async {
  final fullPath = p.join(directoryPath, ensureCsvFilename(filename));
  final file = File(fullPath);
  await file.writeAsString(csvText, encoding: utf8, flush: true);
  return file;
}

String ensureCsvFilename(String filename) {
  final trimmed = filename.trim();
  if (trimmed.toLowerCase().endsWith('.csv')) return trimmed;
  if (trimmed.isEmpty) return 'export.csv';
  return '$trimmed.csv';
}

/// If [filename] already exists in [directoryPath], appends `_2`, `_3`, … before `.csv`.
Future<String> uniqueCsvFilenameInDirectory(
  String directoryPath,
  String filename,
) async {
  filename = ensureCsvFilename(filename);
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

/// Debug: log absolute path for persistent order CSV exports. Debug builds only; set false to silence.
const bool _kPersistExportPathDebug = true;

void _debugLogPersistExportPath(String action, File file) {
  if (!kDebugMode || !_kPersistExportPathDebug) return;
  debugPrint('[PersistExport] $action -> ${file.path}');
}

Future<void> _debugLogCsvExportFile({
  required String action,
  required String filename,
  required String mimeType,
  required File file,
}) async {
  if (!kDebugMode) return;
  int byteLength = -1;
  try {
    if (await file.exists()) {
      byteLength = await file.length();
    }
  } catch (_) {}
  debugPrint(
    '[CsvExport] action=$action filename=$filename mimeType=$mimeType '
    'pathOrUri=${file.path} bytes=$byteLength',
  );
}

/// Fallback export root under [getApplicationDocumentsDirectory] when user `Documents` is unavailable.
/// Uses the same `Showroom_Sync/Exported orders` layout as the primary paths in
/// [ensureShowroomSyncExportedOrdersRootDirectory] (Android public Documents uses the platform channel).

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

/// Android: `Documents/Showroom_Sync/Exported orders/[customerFolder]/[filename]` via platform channel.
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
  final csvFilename = ensureCsvFilename(filename);
  final path = await _androidPublicDocumentsChannel
      .invokeMethod<String>('savePublicCsvInShowroomExports', <String, dynamic>{
        'customerFolder': sanitizedCustomerFolderName,
        'filename': csvFilename,
        'content': csvText,
      });
  if (path == null || path.isEmpty) {
    throw StateError('savePublicCsvInShowroomExports returned no path');
  }
  final file = File(path);
  await _debugLogCsvExportFile(
    action: 'android_public_showroom_exports',
    filename: csvFilename,
    mimeType: 'text/csv',
    file: file,
  );
  return file;
}

/// Ensures `[getApplicationDocumentsDirectory]/Showroom_Sync/Exported orders` exists.
/// Used only as a fallback when the user Documents tree cannot be resolved (see
/// [ensureShowroomSyncExportedOrdersRootDirectory]).
Future<Directory> ensureLocalShowroomExportsRootDirectory() async {
  final base = await getApplicationDocumentsDirectory();
  final root = Directory(p.join(base.path, 'Showroom_Sync', 'Exported orders'));
  await root.create(recursive: true);
  return root;
}

/// `Documents/Showroom_Sync/Exported orders` (Windows: typically under OneDrive). Used for order CSV layout.
Future<Directory> ensureShowroomSyncExportedOrdersRootDirectory() async {
  if (Platform.isWindows) {
    final profile = Platform.environment['USERPROFILE']?.trim();
    if (profile != null && profile.isNotEmpty) {
      final root = Directory(
        p.join(profile, 'Documents', 'Showroom_Sync', 'Exported orders'),
      );
      await root.create(recursive: true);
      return root;
    }
  }
  if (Platform.isLinux || Platform.isMacOS) {
    final home = Platform.environment['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      final root = Directory(
        p.join(home, 'Documents', 'Showroom_Sync', 'Exported orders'),
      );
      await root.create(recursive: true);
      return root;
    }
  }
  if (Platform.isIOS) {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory(
      p.join(base.path, 'Showroom_Sync', 'Exported orders'),
    );
    await root.create(recursive: true);
    return root;
  }
  return ensureLocalShowroomExportsRootDirectory();
}

/// Writes order CSV to `Showroom_Sync/Exported orders/<customer>/` (Android: public Documents; desktop: user Documents when available).
///
/// When [persistExportDebugAction] is non-null (debug builds), logs the final absolute path written.
Future<File> exportOrderCsvToShowroomExportsLayout({
  required String customerDisplayName,
  required String filename,
  required String csvText,
  String? persistExportDebugAction,
}) async {
  final normalizedFilename = filename.trim().toUpperCase();
  final isLegacyItemsNotImported = RegExp(
    r'^ITEMS_NOT_IMPORTED.*\.CSV$',
  ).hasMatch(normalizedFilename);
  if (isLegacyItemsNotImported) {
    debugPrint('[BlockedExport] ITEMS_NOT_IMPORTED export blocked');
    throw StateError(
      'Legacy ITEMS_NOT_IMPORTED export is disabled. '
      'NOT IMPORTED rows are included in ALL_EXPORTED_ITEMS_*.csv.',
    );
  }
  final csvFilename = ensureCsvFilename(filename);

  late final File file;
  if (Platform.isAndroid) {
    final folder = sanitizeCustomerExportFolderName(customerDisplayName);
    file = await saveOrderExportCsvToAndroidPublicShowroomExports(
      sanitizedCustomerFolderName: folder,
      filename: csvFilename,
      csvText: csvText,
    );
  } else {
    final root = await ensureShowroomSyncExportedOrdersRootDirectory();
    file = await writeOrderExportCsvUnderDesignatedBase(
      exportBasePath: root.path,
      customerDisplayName: customerDisplayName,
      filename: csvFilename,
      csvText: csvText,
    );
    await _debugLogCsvExportFile(
      action: 'designated_base_write',
      filename: p.basename(file.path),
      mimeType: 'text/csv',
      file: file,
    );
  }
  if (persistExportDebugAction != null) {
    _debugLogPersistExportPath(persistExportDebugAction, file);
  }
  return file;
}

enum ScanFeedbackType { none, successNewItem, successExistingItem, notFound }

/// Lifecycle for saved quotes (active workspace vs archive).
enum QuoteLifecycleStatus { active, archived, confirmed }

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

/// Safe quantity read from persisted quote line JSON (avoids cast crashes on bad types).
/// Missing or unparseable values use 1; explicit zero (including "0") is preserved.
int _quantityFromJson(dynamic v) {
  if (v == null) return 1;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 1;
  return 1;
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
    units += _quantityFromJson(map['quantity']);
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
    customerDiscPct = Customer.fromJson(
      Map<String, dynamic>.from(customerMap),
    ).discountPercent;
  }

  bool parseYesFlag(String value) => value.trim().toUpperCase() == 'YES';

  ProductPricingState linePricingState(Map<String, dynamic> map) {
    final psFlag = map['isPs'];
    final psRaw = (map['psRaw'] as String?) ?? '';
    final isPs = (psFlag is bool) ? psFlag : parseYesFlag(psRaw);
    if (isPs) return ProductPricingState.ps;
    final netFlag = map['isNet'];
    final netRaw = (map['netRaw'] as String?) ?? '';
    final isNet = (netFlag is bool) ? netFlag : parseYesFlag(netRaw);
    if (isNet) return ProductPricingState.net;
    final b = map['discountEligible'];
    if (b is bool) {
      return b
          ? ProductPricingState.discountEligible
          : ProductPricingState.regular;
    }
    final raw = (map['discountRaw'] as String?) ?? '';
    return parseYesFlag(raw)
        ? ProductPricingState.discountEligible
        : ProductPricingState.regular;
  }

  double discountedUnit(Map<String, dynamic> map, double regularUnit) {
    if (linePricingState(map) != ProductPricingState.discountEligible ||
        customerDiscPct <= 0) {
      return regularUnit;
    }
    return regularUnit * (1 - customerDiscPct / 100.0);
  }

  var sum = 0.0;
  for (final lineJson in lines) {
    final map = Map<String, dynamic>.from(lineJson as Map);
    final qty = _quantityFromJson(map['quantity']);
    final price = (map['price'] as num?)?.toDouble() ?? 0.0;
    final effectiveUnit = discountedUnit(map, price);
    sum += _lineTotalFromRoundedUnitPrice(
      rawUnitPrice: effectiveUnit,
      qty: qty,
    );
  }
  return _roundMoney(sum);
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

  /// Converts a parsed numeric cell to a 0–100 "percent off" value.
  /// Values strictly between 0 and 1 are treated as decimal fractions (0.10 → 10%).
  /// Values ≥ 1 are whole percents (10 → 10%; 1 → 1%).
  static double normalizeDiscountPercentNumber(double v) {
    if (v.isNaN) return 0.0;
    if (v < 0) return 0.0;
    if (v > 0 && v < 1) return v * 100.0;
    if (v > 100) return 100.0;
    return v;
  }

  /// Parses customers.csv `discount` cell: blank/invalid → 0; clamped to [0, 100].
  /// Accepts optional `%` suffix; decimal fractions in (0, 1) map to percent (e.g. 0.10 → 10%).
  static double parseDiscountPercentFromRaw(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return 0.0;
    if (t.endsWith('%')) {
      t = t.substring(0, t.length - 1).trim();
    }
    if (t.isEmpty) return 0.0;
    final v = double.tryParse(t.replaceAll(',', ''));
    if (v == null || v.isNaN) return 0.0;
    return normalizeDiscountPercentNumber(v);
  }

  static String _discountFieldFromJson(Map<String, dynamic> json) {
    final v = json['discount'];
    if (v == null) return '';
    if (v is String) return v.trim();
    return v.toString();
  }

  String get displayName => companyName.trim().isNotEmpty ? companyName : id;

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
    final discStr = _discountFieldFromJson(json);
    final embedded = json['discountPercent'];
    final double pct;
    if (embedded is num) {
      final d = embedded.toDouble();
      pct = d.isNaN
          ? parseDiscountPercentFromRaw(discStr)
          : normalizeDiscountPercentNumber(d);
    } else if (embedded is String) {
      pct = parseDiscountPercentFromRaw(embedded);
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

class CustomerWalkOrderRow {
  const CustomerWalkOrderRow({
    required this.customerId,
    required this.itemNumber,
    this.description = '',
    this.category = '',
    this.subCategory = '',
    required this.walkPosition,
    required this.subPosition,
    required this.neverAdd,
    required this.neverAddReason,
    required this.walkEnabled,
  });

  final String customerId;
  final String itemNumber;
  final String description;
  final String category;
  final String subCategory;
  final int? walkPosition;
  final int? subPosition;
  final bool neverAdd;
  final String neverAddReason;
  final bool walkEnabled;
}

/// Read-only UI for inspecting bundled customer walk order CSV data.
class _WalkOrderViewerPage extends StatefulWidget {
  const _WalkOrderViewerPage({required this.walkOrderByCustomer});

  final Map<String, Map<String, CustomerWalkOrderRow>> walkOrderByCustomer;

  @override
  State<_WalkOrderViewerPage> createState() => _WalkOrderViewerPageState();
}

enum _WalkOrderQuickFilter {
  all,
  hasWalkPosition,
  missingWalkPosition,
  hasSubPosition,
  missingSubPosition,
  neverAddOnly,
  walkEnabledOnly,
}

enum _WalkOrderSortMode {
  currentWalkOrder,
  itemNumber,
  categorySubCategory,
  missingPositionsFirst,
}

class _WalkOrderViewerPageState extends State<_WalkOrderViewerPage> {
  late String? _customerId;
  String? _categoryFilter;
  String? _subCategoryFilter;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _WalkOrderQuickFilter _quickFilter = _WalkOrderQuickFilter.all;
  _WalkOrderSortMode _sortMode = _WalkOrderSortMode.currentWalkOrder;

  List<String> get _sortedCustomerIds {
    final ids = widget.walkOrderByCustomer.keys.toList()..sort();
    return ids;
  }

  Map<String, CustomerWalkOrderRow> get _rowsForCustomer =>
      widget.walkOrderByCustomer[_customerId ?? ''] ?? const {};

  List<CustomerWalkOrderRow> get _baseRows {
    final m = _rowsForCustomer;
    return m.values.toList(growable: false);
  }

  Set<String> _distinctCategories(Iterable<CustomerWalkOrderRow> rows) {
    final out = <String>{};
    for (final r in rows) {
      final c = r.category.trim();
      if (c.isNotEmpty) out.add(c);
    }
    return out;
  }

  Set<String> _distinctSubCategories(
    Iterable<CustomerWalkOrderRow> rows,
    String? categoryEquals,
  ) {
    final out = <String>{};
    for (final r in rows) {
      if (categoryEquals != null && r.category.trim() != categoryEquals) {
        continue;
      }
      final s = r.subCategory.trim();
      if (s.isNotEmpty) out.add(s);
    }
    return out;
  }

  /// WalkPosition ascending (nulls last), then SubPosition ascending (nulls last), then item number.
  int _compareWalkRowsCurrentOrder(CustomerWalkOrderRow a, CustomerWalkOrderRow b) {
    final ap = a.walkPosition;
    final bp = b.walkPosition;
    if (ap != null && bp != null && ap != bp) return ap.compareTo(bp);
    if (ap != null && bp == null) return -1;
    if (ap == null && bp != null) return 1;
    final as = a.subPosition;
    final bs = b.subPosition;
    if (as != null && bs != null && as != bs) return as.compareTo(bs);
    if (as != null && bs == null) return -1;
    if (as == null && bs != null) return 1;
    return a.itemNumber.compareTo(b.itemNumber);
  }

  int _compareItemNumber(CustomerWalkOrderRow a, CustomerWalkOrderRow b) {
    return a.itemNumber.compareTo(b.itemNumber);
  }

  int _compareCategorySubCategory(CustomerWalkOrderRow a, CustomerWalkOrderRow b) {
    final ca = a.category.trim();
    final cb = b.category.trim();
    final c = ca.compareTo(cb);
    if (c != 0) return c;
    final sa = a.subCategory.trim();
    final sb = b.subCategory.trim();
    final s = sa.compareTo(sb);
    if (s != 0) return s;
    return a.itemNumber.compareTo(b.itemNumber);
  }

  int _missingPositionScore(CustomerWalkOrderRow r) {
    var n = 0;
    if (r.walkPosition == null) n++;
    if (r.subPosition == null) n++;
    return n;
  }

  int _compareMissingPositionsFirst(CustomerWalkOrderRow a, CustomerWalkOrderRow b) {
    final ma = _missingPositionScore(a);
    final mb = _missingPositionScore(b);
    if (ma != mb) return mb.compareTo(ma);
    return _compareWalkRowsCurrentOrder(a, b);
  }

  int _compareForSortMode(CustomerWalkOrderRow a, CustomerWalkOrderRow b) {
    switch (_sortMode) {
      case _WalkOrderSortMode.currentWalkOrder:
        return _compareWalkRowsCurrentOrder(a, b);
      case _WalkOrderSortMode.itemNumber:
        return _compareItemNumber(a, b);
      case _WalkOrderSortMode.categorySubCategory:
        return _compareCategorySubCategory(a, b);
      case _WalkOrderSortMode.missingPositionsFirst:
        return _compareMissingPositionsFirst(a, b);
    }
  }

  List<CustomerWalkOrderRow> get _categoryScopedRows {
    var list = _baseRows;
    if (_categoryFilter != null) {
      list = list
          .where((r) => r.category.trim() == _categoryFilter)
          .toList(growable: false);
    }
    if (_subCategoryFilter != null) {
      list = list
          .where((r) => r.subCategory.trim() == _subCategoryFilter)
          .toList(growable: false);
    }
    return list;
  }

  bool _matchesQuickFilter(CustomerWalkOrderRow r) {
    switch (_quickFilter) {
      case _WalkOrderQuickFilter.all:
        return true;
      case _WalkOrderQuickFilter.hasWalkPosition:
        return r.walkPosition != null;
      case _WalkOrderQuickFilter.missingWalkPosition:
        return r.walkPosition == null;
      case _WalkOrderQuickFilter.hasSubPosition:
        return r.subPosition != null;
      case _WalkOrderQuickFilter.missingSubPosition:
        return r.subPosition == null;
      case _WalkOrderQuickFilter.neverAddOnly:
        return r.neverAdd;
      case _WalkOrderQuickFilter.walkEnabledOnly:
        return r.walkEnabled;
    }
  }

  bool _matchesSearch(CustomerWalkOrderRow r) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (r.itemNumber.toLowerCase().contains(q)) return true;
    if (r.description.toLowerCase().contains(q)) return true;
    if (r.category.toLowerCase().contains(q)) return true;
    if (r.subCategory.toLowerCase().contains(q)) return true;
    return false;
  }

  List<CustomerWalkOrderRow> get _displayRows {
    final list = _categoryScopedRows
        .where(_matchesQuickFilter)
        .where(_matchesSearch)
        .toList(growable: false);
    final sorted = List<CustomerWalkOrderRow>.from(list)
      ..sort(_compareForSortMode);
    return sorted;
  }

  @override
  void initState() {
    super.initState();
    final ids = _sortedCustomerIds;
    if (ids.isEmpty) {
      _customerId = null;
    } else if (ids.contains('302021')) {
      _customerId = '302021';
    } else {
      _customerId = ids.first;
    }
    _categoryFilter = null;
    _subCategoryFilter = null;
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final next = _searchController.text;
    if (next == _searchQuery) return;
    setState(() => _searchQuery = next);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _setCustomer(String? id) {
    setState(() {
      _customerId = id;
      _categoryFilter = null;
      _subCategoryFilter = null;
      _quickFilter = _WalkOrderQuickFilter.all;
      _searchController.clear();
      _searchQuery = '';
    });
  }

  void _setCategoryFilter(String? c) {
    setState(() {
      _categoryFilter = c;
      _subCategoryFilter = null;
    });
  }

  void _setSubCategoryFilter(String? s) {
    setState(() => _subCategoryFilter = s);
  }

  void _setQuickFilter(_WalkOrderQuickFilter f) {
    setState(() => _quickFilter = f);
  }

  void _setSortMode(_WalkOrderSortMode m) {
    setState(() => _sortMode = m);
  }

  static String _sortModeLabel(_WalkOrderSortMode m) {
    switch (m) {
      case _WalkOrderSortMode.currentWalkOrder:
        return 'Current walk order';
      case _WalkOrderSortMode.itemNumber:
        return 'Item Number';
      case _WalkOrderSortMode.categorySubCategory:
        return 'Category / Sub-Category';
      case _WalkOrderSortMode.missingPositionsFirst:
        return 'Missing positions first';
    }
  }

  Widget _quickFilterChip(
    BuildContext context, {
    required String label,
    required _WalkOrderQuickFilter value,
  }) {
    final selected = _quickFilter == value;
    return FilterChip(
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      selected: selected,
      onSelected: (on) => _setQuickFilter(on ? value : _WalkOrderQuickFilter.all),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ids = _sortedCustomerIds;
    final categories = _distinctCategories(_baseRows).toList()..sort();
    final subCats = _distinctSubCategories(
      _baseRows,
      _categoryFilter,
    ).toList()
      ..sort();
    final scoped = _categoryScopedRows;
    final rows = _displayRows;
    final totalScoped = scoped.length;
    final showing = rows.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Walk Order Editor'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(26),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
              child: Text(
                'View only — data is not saved from this screen.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: ids.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No walk order data loaded.'),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 1,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SizedBox(
                              width: double.infinity,
                              child: TextField(
                                controller: _searchController,
                                decoration: const InputDecoration(
                                  hintText:
                                      'Search item #, description, category, sub-category',
                                  hintMaxLines: 2,
                                  prefixIcon: Icon(Icons.search),
                                  isDense: true,
                                ),
                                textInputAction: TextInputAction.search,
                              ),
                            ),
                          ),
                          Text(
                            'Customer',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          DropdownButton<String>(
                            isExpanded: true,
                            value: _customerId != null && ids.contains(_customerId)
                                ? _customerId
                                : ids.first,
                            selectedItemBuilder: (context) => [
                              for (final id in ids)
                                Text(
                                  id,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                            items: [
                              for (final id in ids)
                                DropdownMenuItem(
                                  value: id,
                                  child: Text(
                                    id,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) _setCustomer(v);
                            },
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Category',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          DropdownButton<String?>(
                            isExpanded: true,
                            value: _categoryFilter != null &&
                                    categories.contains(_categoryFilter)
                                ? _categoryFilter
                                : null,
                            selectedItemBuilder: (context) => [
                              Text(
                                'All categories',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              for (final c in categories)
                                Text(
                                  c,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  'All categories',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              for (final c in categories)
                                DropdownMenuItem(
                                  value: c,
                                  child: Text(
                                    c,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _setCategoryFilter,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Sub-Category',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          DropdownButton<String?>(
                            isExpanded: true,
                            value: _subCategoryFilter != null &&
                                    subCats.contains(_subCategoryFilter)
                                ? _subCategoryFilter
                                : null,
                            selectedItemBuilder: (context) => [
                              Text(
                                'All sub-categories',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              for (final s in subCats)
                                Text(
                                  s,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  'All sub-categories',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              for (final s in subCats)
                                DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _setSubCategoryFilter,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Quick filters',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _quickFilterChip(context, label: 'All', value: _WalkOrderQuickFilter.all),
                                _quickFilterChip(
                                  context,
                                  label: 'Has WalkPosition',
                                  value: _WalkOrderQuickFilter.hasWalkPosition,
                                ),
                                _quickFilterChip(
                                  context,
                                  label: 'Missing WalkPosition',
                                  value: _WalkOrderQuickFilter.missingWalkPosition,
                                ),
                                _quickFilterChip(
                                  context,
                                  label: 'Has SubPosition',
                                  value: _WalkOrderQuickFilter.hasSubPosition,
                                ),
                                _quickFilterChip(
                                  context,
                                  label: 'Missing SubPosition',
                                  value: _WalkOrderQuickFilter.missingSubPosition,
                                ),
                                _quickFilterChip(
                                  context,
                                  label: 'NeverAdd only',
                                  value: _WalkOrderQuickFilter.neverAddOnly,
                                ),
                                _quickFilterChip(
                                  context,
                                  label: 'WalkEnabled only',
                                  value: _WalkOrderQuickFilter.walkEnabledOnly,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sort',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          DropdownButton<_WalkOrderSortMode>(
                            isExpanded: true,
                            value: _sortMode,
                            selectedItemBuilder: (context) => [
                              for (final m in _WalkOrderSortMode.values)
                                Text(
                                  _sortModeLabel(m),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                            items: [
                              for (final m in _WalkOrderSortMode.values)
                                DropdownMenuItem(
                                  value: m,
                                  child: Text(
                                    _sortModeLabel(m),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) _setSortMode(v);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(
                    'Showing $showing of $totalScoped items',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  flex: 2,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final walkMissing = r.walkPosition == null;
                      final subMissing = r.subPosition == null;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      r.itemNumber,
                                      style: Theme.of(context).textTheme.titleMedium,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (walkMissing || subMissing || r.neverAdd) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (walkMissing)
                                      _walkStatusBadge(
                                        context,
                                        label: 'WalkPosition missing',
                                        color: Theme.of(context).colorScheme.errorContainer,
                                        onColor: Theme.of(context).colorScheme.onErrorContainer,
                                      ),
                                    if (subMissing)
                                      _walkStatusBadge(
                                        context,
                                        label: 'SubPosition missing',
                                        color: Theme.of(context).colorScheme.secondaryContainer,
                                        onColor: Theme.of(context).colorScheme.onSecondaryContainer,
                                      ),
                                    if (r.neverAdd)
                                      _walkStatusBadge(
                                        context,
                                        label: 'NeverAdd YES',
                                        color: Theme.of(context).colorScheme.tertiaryContainer,
                                        onColor: Theme.of(context).colorScheme.onTertiaryContainer,
                                      ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 6),
                              _walkFieldLine('CustomerID', r.customerId),
                              _walkFieldLine('Description', r.description),
                              _walkFieldLine('Category', r.category),
                              _walkFieldLine('Sub-Category', r.subCategory),
                              _walkFieldLine(
                                'WalkPosition',
                                r.walkPosition?.toString() ?? '—',
                              ),
                              _walkFieldLine(
                                'SubPosition',
                                r.subPosition?.toString() ?? '—',
                              ),
                              _walkFieldLine('NeverAdd', r.neverAdd ? 'Yes' : 'No'),
                              _walkFieldLine(
                                'NeverAddReason',
                                r.neverAddReason.isEmpty ? '—' : r.neverAddReason,
                              ),
                              _walkFieldLine(
                                'WalkEnabled',
                                r.walkEnabled ? 'Yes' : 'No',
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  static Widget _walkStatusBadge(
    BuildContext context, {
    required String label,
    required Color color,
    required Color onColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: onColor,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  static Widget _walkFieldLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

String _orderImportDuplicateResolutionLabel(OrderImportDuplicateResolution r) {
  switch (r) {
    case OrderImportDuplicateResolution.totalQty:
      return 'Total qty (order + file)';
    case OrderImportDuplicateResolution.minimumQty:
      return 'Minimum qty';
    case OrderImportDuplicateResolution.skip:
      return 'Skip (keep order qty)';
    case OrderImportDuplicateResolution.useImportedQty:
      return 'Use imported qty (replace order)';
  }
}

class _OrderImportDuplicateReviewDialog extends StatefulWidget {
  const _OrderImportDuplicateReviewDialog({required this.items});

  final List<OrderImportPreparedLine> items;

  @override
  State<_OrderImportDuplicateReviewDialog> createState() =>
      _OrderImportDuplicateReviewDialogState();
}

class _OrderImportDuplicateReviewDialogState
    extends State<_OrderImportDuplicateReviewDialog> {
  late List<OrderImportDuplicateResolution> _choices;

  @override
  void initState() {
    super.initState();
    _choices = List<OrderImportDuplicateResolution>.generate(
      widget.items.length,
      (_) => OrderImportDuplicateResolution.totalQty,
      growable: false,
    );
  }

  void _applyAll(OrderImportDuplicateResolution value) {
    setState(() {
      for (var i = 0; i < _choices.length; i++) {
        _choices[i] = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final contentHeight = (h * 0.58).clamp(280.0, 560.0);
    return AlertDialog(
      title: const Text('Items already on order'),
      content: SizedBox(
        width: 440,
        height: contentHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'These lines match your current order. Choose how to set quantity for each. '
              'All results use your existing MOQ rounding (no manual quantities).',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () =>
                      _applyAll(OrderImportDuplicateResolution.totalQty),
                  child: const Text('Total qty — all'),
                ),
                TextButton(
                  onPressed: () =>
                      _applyAll(OrderImportDuplicateResolution.minimumQty),
                  child: const Text('Minimum qty — all'),
                ),
                TextButton(
                  onPressed: () =>
                      _applyAll(OrderImportDuplicateResolution.skip),
                  child: const Text('Skip — all'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.separated(
                itemCount: widget.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = widget.items[index];
                  final existing = row.existingOrderQtySum!;
                  final desc = row.product.description.trim();
                  final sub = desc.isEmpty
                      ? ''
                      : (desc.length > 80 ? '${desc.substring(0, 80)}…' : desc);
                  return Material(
                    type: MaterialType.card,
                    elevation: 0.5,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.displayItem.trim().isEmpty
                                ? row.product.itemNumber
                                : row.displayItem.trim(),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (sub.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                sub,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'On order: $existing  ·  From file (MOQ): ${row.importedQtyMoq}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Quantity rule',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 4),
                          DropdownButton<OrderImportDuplicateResolution>(
                            value: _choices[index],
                            isExpanded: true,
                            items: [
                              for (final opt
                                  in _kOrderImportDuplicateReviewOptions)
                                DropdownMenuItem(
                                  value: opt,
                                  child: Text(
                                    _orderImportDuplicateResolutionLabel(opt),
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _choices[index] = v);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(List<OrderImportDuplicateResolution>.from(_choices)),
          child: const Text('Apply import'),
        ),
      ],
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
  State<_LoadQuoteDialogContent> createState() =>
      _LoadQuoteDialogContentState();
}

class _LoadQuoteDialogContentState extends State<_LoadQuoteDialogContent> {
  late final TextEditingController _searchController;
  late final List<SavedQuoteInfo> _quotes;

  @override
  void initState() {
    super.initState();
    _quotes = List<SavedQuoteInfo>.from(widget.allQuotes);
    _searchController = TextEditingController();
    _searchController.addListener(() => setState(() {}));

    // After the first frame the [TextField] has registered this node with the
    // dialog's focus scope. Request on the node directly — not
    // [FocusScope.of(context).requestFocus], which can throw if the scope
    // does not yet include the node (e.g. during dialog attach).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.searchQuotesFocusNode.requestFocus();
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
    final filtered = _quotes.where((info) {
      // Use raw fields for searching so user can type either
      // quote name, customer name, date text, or even pieces
      // of the combined "Customer: X – Quote: Y" label.
      final name = (info.name).toLowerCase();
      final customer = (info.customerName).toLowerCase();
      final bucketLabel = (info.quoteBucketLabel).toLowerCase();
      final dateText = widget.formatDate(info.updatedAt).toLowerCase();
      final displayCustomer = customer.isEmpty
          ? 'no customer'
          : customer; // matches visible label
      final displayQuote = name.isEmpty ? 'unnamed quote' : name;
      final combined = 'customer: $displayCustomer – quote: $displayQuote'
          .toLowerCase();

      if (q.isEmpty) return true;

      return name.contains(q) ||
          customer.contains(q) ||
          bucketLabel.contains(q) ||
          dateText.contains(q) ||
          combined.contains(q);
    }).toList();

    final media = MediaQuery.of(context);
    // Keep panel size stable while typing/searching: do not resize with
    // keyboard insets; use an internal list scroll area instead.
    // Use a screen-derived max height only — not [LayoutBuilder], which
    // participates in intrinsic sizing passes inside [AlertDialog] and can
    // trigger "LayoutBuilder does not support returning intrinsic dimensions".
    final double maxHeight = media.size.height * 0.75;

    // [AlertDialog] may wrap [content] in a scroll view with unbounded height;
    // [Expanded] needs a finite height. [SizedBox] from [MediaQuery] avoids
    // intrinsic-layout conflicts.
    return SizedBox(
      width: double.maxFinite,
      height: maxHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tap a quote to load it. Email to share; remove only after emailing or saving elsewhere.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            onTapOutside: (_) {
              widget.searchQuotesFocusNode.unfocus();
            },
          ),
          const SizedBox(height: 4),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification n) {
                if (n is UserScrollNotification) {
                  widget.searchQuotesFocusNode.unfocus();
                }
                return false;
              },
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No matching quotes',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final info = filtered[i];
                        final String customerName =
                            info.customerName.trim().isEmpty
                            ? 'No customer'
                            : info.customerName.trim();
                        final String quoteName = info.name.isEmpty
                            ? 'Unnamed quote'
                            : info.name;
                        final rawBucketKey = info.quoteBucketKey
                            .trim()
                            .toLowerCase();
                        final rawBucketLabel = info.quoteBucketLabel.trim();
                        final String bucketLabel = rawBucketLabel.isEmpty
                            ? 'EVERYDAY'
                            : (rawBucketKey == 'every_day'
                                  ? 'EVERYDAY'
                                  : rawBucketLabel);
                        final theme = Theme.of(context);
                        return SizedBox(
                          key: ValueKey(info.id),
                          height: 88,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.of(
                                widget.dialogContext,
                              ).pop(info.id),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Customer: $customerName – Quote: $quoteName',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '$bucketLabel • ${widget.formatDate(info.updatedAt)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 112,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.email_outlined,
                                            ),
                                            tooltip: 'Email / Share quote',
                                            onPressed: () =>
                                                widget.onShareQuote(
                                                  info.id,
                                                  info.name,
                                                ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            tooltip:
                                                'Remove from list (after emailing or saving)',
                                            onPressed: () async {
                                              final confirm = await showDialog<bool>(
                                                context: context,
                                                builder: (c) => AlertDialog(
                                                  title: const Text(
                                                    'Delete Quote',
                                                  ),
                                                  content: const Text(
                                                    'Delete this quote from the list? The file will be deleted.\n\n'
                                                    'Only do this after you have emailed or saved the quote elsewhere. This cannot be undone.',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            c,
                                                            false,
                                                          ),
                                                      child: const Text(
                                                        'Cancel',
                                                      ),
                                                    ),
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            c,
                                                            true,
                                                          ),
                                                      child: const Text(
                                                        'Delete',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );

                                              if (confirm == true && mounted) {
                                                await widget.onRemoveQuote(
                                                  info.id,
                                                );
                                                if (mounted) {
                                                  bool becameEmpty = false;
                                                  setState(() {
                                                    _quotes.removeWhere(
                                                      (e) => e.id == info.id,
                                                    );
                                                    becameEmpty =
                                                        _quotes.isEmpty;
                                                  });
                                                  if (becameEmpty) {
                                                    FocusScope.of(
                                                      context,
                                                    ).unfocus();
                                                    _searchController.clear();
                                                  }
                                                }
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal customer picker for full-catalog test/export diagnostics only.
/// Intentionally avoids shared picker helpers, focus management, and [StatefulBuilder].
class _SimpleCatalogTestCustomerPickerDialog extends StatefulWidget {
  const _SimpleCatalogTestCustomerPickerDialog({required this.customers});

  final List<Customer> customers;

  @override
  State<_SimpleCatalogTestCustomerPickerDialog> createState() =>
      _SimpleCatalogTestCustomerPickerDialogState();
}

class _SimpleCatalogTestCustomerPickerDialogState
    extends State<_SimpleCatalogTestCustomerPickerDialog> {
  String _searchText = '';

  List<Customer> _filteredCustomers() {
    final q = _searchText.trim().toLowerCase();
    if (q.isEmpty) {
      return widget.customers;
    }
    return widget.customers
        .where(
          (c) =>
              c.displayName.toLowerCase().contains(q) ||
              c.contact.toLowerCase().contains(q) ||
              c.email.toLowerCase().contains(q) ||
              c.companyName.toLowerCase().contains(q) ||
              c.city.toLowerCase().contains(q) ||
              c.state.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredCustomers();
    return AlertDialog(
      title: const Text('Select Customer'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: false,
              decoration: const InputDecoration(
                labelText: 'Search customers',
                hintText: 'Name, contact, email...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _searchText = v),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('No matching customers'),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final c = filtered[i];
                        return ListTile(
                          title: Text(c.displayName),
                          subtitle: c.contact.isEmpty
                              ? null
                              : Text(c.contact),
                          onTap: () => Navigator.of(context).pop(c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
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

  /// ECatalog list price column: set `true` briefly to log branch selection per row (debug builds only).
  static const bool _ecatalogListPriceColumnDebug = false;

  final FocusNode _scannerFocusNode = FocusNode();
  String _scannerBuffer = '';

  /// Load Quote dialog only — search field ([_LoadQuoteDialogContent]).
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

  Timer? _refocusTimer;
  /// Single follow-up pulse / keyboard hide for [_requestScannerFocus] (prevents stacked retries).
  Timer? _scannerFocusRetryTimer;
  Timer? _scannerFocusHideKeyboardTimer;
  DateTime? _lastScannerFocusRequestTime;
  bool _scannerFocusReclaimInFlight = false;
  Timer? _scanFeedbackTimer;

  /// Cancels stale tail-cutoff pauses so rapid error scans are not clipped by an older timer.
  Timer? _errorBuzzTailPauseTimer;
  Timer? _quoteNameBarcodeDebounce;

  /// Clears [_scanTabHighlightLineKey] after a brief post-scan flash (Scan tab order list only).
  Timer? _scanTabHighlightClearTimer;

  TextEditingController _searchController = TextEditingController();
  List<Product> _searchResults = [];
  String _scanSearchQuery = '';
  Timer? _searchDebounce;

  /// E-Catalog tab (V1): filters over [_productsByItemNumber] only; no extra CSV load.
  final TextEditingController _catalogSearchController =
      TextEditingController();
  final FocusNode _ecatalogSearchFocusNode = FocusNode();
  Timer? _ecatalogSearchKeyboardIdleTimer;
  String _catalogSearchQuery = '';

  /// null means "All Categories".
  String? _selectedCatalogCategory;

  /// null means "All Sub-Categories".
  String? _selectedCatalogSubCategory;

  /// ECatalog merchandising: `newItems` | `everyday` | `homeDecor` | `seasonal` | `sale` (PS) | null (all).
  String? _catalogMerchandising;
  bool _catalogInOrderOnly = false;
  bool _catalogInStockOnly = false;
  bool _catalogPreviouslyOrderedOnly = false;
  String _catalogFilteredCacheKey = '';
  List<Product>? _catalogFilteredProductsCache;
  List<String>? _catalogDistinctCategories;
  String _catalogDistinctCategoriesCacheKey = '';
  String? _catalogSubCategoryOptionsCacheKey;
  List<String>? _catalogSubCategoryOptionsCache;
  String _previouslyOrderedCustomerCacheKey = '';
  String? _previouslyOrderedHistoryLoadInFlightKey;
  Set<String> _previouslyOrderedKeysForSelectedCustomer = <String>{};
  final Map<String, Set<String>> _previouslyOrderedKeysByCustomer = {};

  /// Created in [_doInitAudio] so cold start does not allocate native players in [initState].
  AudioPlayer? _goodScanPlayer;
  AudioPlayer? _goodScanPlayer2;
  AudioPlayer? _errorScanPlayer;

  Future<void>? _audioInitFuture;

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
  bool _loadingProductsFromWeb = false;
  bool _isLoadingCustomers = false;

  /// Debug Setup: full-catalog Excel export (does not touch quote workspace state).
  bool _exportingFullCatalogExcel = false;

  /// Debug Setup: master update sheet exports (does not touch quote workspace state).
  bool _exportingMasterUpdateSheets = false;

  /// Setup: isolated master products workbook build (file-only; no quote workspace state).
  bool _buildingUpdatedMasterSheet = false;

  /// After a CSV/sheet customer reload, used to re-select a locally added customer.
  Customer? _pendingRestoreCustomerAfterLocalMerge;
  bool _editDialogOpen = false;

  /// When true, [_requestScannerFocus] and [_restoreScanFieldFocus] no-op (full catalog test / export flows).
  bool _suspendScannerFocusRecovery = false;

  /// Prevents overlapping order-CSV imports (second tap while apply/write still runs → duplicate ITEMS_NOT_IMPORTED writes).
  bool _orderCsvImportInProgress = false;

  List<OrderImportSkippedRow> _lastItemsNotImportedRows = const [];
  String? _lastItemsNotImportedRowsCustomerId;
  String? _lastItemsNotImportedRowsCustomerName;
  List<OrderImportItemsWithoutUpcRow> _lastItemsWithoutUpcRows = const [];
  String? _lastItemsWithoutUpcRowsCustomerId;
  String? _lastItemsWithoutUpcRowsCustomerName;

  /// When non-null, [_ensureRoutingForProduct] logs each bucket once per CSV import session.
  String? _quoteImportDebugSession;
  final Set<String> _quoteImportLoggedBucketKeys = <String>{};

  /// Grep: [ImportRoute] — first routing touch per customer+bucket during CSV import.
  final Set<String> _orderImportRouteTraceKeys = <String>{};

  /// Every quote id persisted via [_saveQuote] during a single order CSV import (all routed buckets).
  final Set<String> _orderImportTouchedQuoteIds = <String>{};

  /// Quote name to restore when a barcode was mistakenly entered in the quote name field
  String _savedQuoteNameBeforeEdit = 'NEW QUOTE';

  /// Incremented when loading a quote so the order list widget is recreated and items display
  int _orderListVersion = 0;

  OrderLine? _selectedLine;
  ScanFeedbackType _scanFeedbackType = ScanFeedbackType.none;

  /// Order line key ([_orderLineKeyForProduct]) to flash-highlight on the Scan tab list after a successful scan.
  String? _scanTabHighlightLineKey;

  /// Orders tab only: which order line card is expanded ([_orderLineKeyForProduct]); at most one.
  String? _ordersTabExpandedLineKey;

  /// Scan tab only: which order line card is expanded ([_orderLineKeyForProduct]); at most one.
  String? _scanTabExpandedLineKey;

  /// E-Catalog tab only: which catalog row is expanded ([Product.itemNumber.trim]); at most one.
  String? _ecatalogExpandedItemKey;
  bool _ecatalogOrderPanelExpanded = false;

  /// [GlobalKey]s for Scan tab order rows — used with [Scrollable.ensureVisible] after a scan (UI only).
  final Map<String, GlobalKey> _scanTabOrderRowKeys = <String, GlobalKey>{};

  /// Prevent accidental duplicate scans: ignore same barcode if processed within this window (ms).
  static const int _scanDedupeMs = 80;
  // 12ms proved too aggressive on some scanners and can split a single
  // physical scan into partial fragments ("2", "73", "730", ...).
  static const int _scannerRefocusDelayMs = 35;
  static const int _tabReturnRefocusDelayMs = 120;
  /// Collapses burst calls (same-frame / input churn) without blocking tab refocus (~16ms vs ~35ms).
  static const int _scannerFocusRequestCooldownMs = 12;
  static const int _scannerFocusSingleRetryDelayMs = 80;
  /// Yield after the first frame before cold-start I/O and isolate work.
  static const Duration _startupDeferAfterFirstFrame = Duration(milliseconds: 150);
  /// [rootBundle.loadString] can synchronously decode large assets; defer slightly so frames stay light.
  static const Duration _startupBundleLoadDelay = Duration(milliseconds: 120);

  String? _lastProcessedScanUpc;
  DateTime? _lastProcessedScanTime;

  /// Serialize rapid-fire scans so they are processed one at a time in order.
  bool _isProcessingScan = false;
  final Queue<({String value, String source})> _pendingScans =
      Queue<({String value, String source})>();

  List<Customer> _customers = [];
  final Map<String, Customer> _customersByKey = {};
  Customer? _selectedCustomer;
  bool _isCustomerWalkOrderEnabled = false;
  final Map<String, Map<String, CustomerWalkOrderRow>>
  _customerWalkOrderByCustomerAndItem = {};

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
  static const int _tabIndexScan = 0;
  static const int _tabIndexECatalog = 1;
  static const int _tabIndexArchive = 2;
  // Orders workflow remains in code but is intentionally hidden from tab navigation.
  static const int _visibleTabCount = 4;
  bool _scanTabActive = true;
  int _activeTabIndex = _tabIndexScan;

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

  /// When false, [_scheduleScannerRefocus] no-ops so focus timers do not run during heavy startup.
  bool _scannerStartupRefocusEnabled = false;
  bool _printedScannerFocusDiagnosticsTestSteps = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_handleGlobalFocusChange);

    // Startup order (after first frame + short yield): customers → product
    // refresh → quote maintenance → scanner focus (after UI-heavy work).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(_startupDeferAfterFirstFrame);
      if (!mounted) return;
      await _loadCustomersFromAssets();
      if (!mounted) return;
      unawaited(_debugLoadCustomerWalkOrderCsv());
      unawaited(_loadProductsOnStartup());
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
      _discardWorkingOrderIfNoCustomerSelected();
      if (!mounted) return;
      _scannerStartupRefocusEnabled = true;
      _requestScannerFocus();
      // Keep startup focus recovery reliable, but avoid pulses during prune / first paints.
      for (final ms in [90, 320]) {
        Future<void>.delayed(Duration(milliseconds: ms), () {
          if (!mounted || _editDialogOpen) return;
          if (!_scannerFocusNode.hasFocus) _requestScannerFocus();
        });
      }
    });

    _scannerFocusNode.addListener(() {
      debugPrint(
        '[ScannerField][FocusListener] scannerFocusChanged hasFocus=${_scannerFocusNode.hasFocus} '
        'canRequestFocus=${_scannerFocusNode.canRequestFocus} contextExists=${_scannerFocusNode.context != null} '
        'primaryFocus=${FocusManager.instance.primaryFocus} scanTabActive=$_scanTabActive activeTabIndex=$_activeTabIndex',
      );
      debugPrint(
        '[ScannerField][FocusListener] hasFocus=${_scannerFocusNode.hasFocus} primary=${FocusManager.instance.primaryFocus}',
      );
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

    if (!_printedScannerFocusDiagnosticsTestSteps) {
      _printedScannerFocusDiagnosticsTestSteps = true;
      debugPrint('=== TEST STEPS ===');
      debugPrint('1. Type invalid item');
      debugPrint('2. Tap Add');
      debugPrint('3. Wait');
      debugPrint('4. Scan item');
      debugPrint('Copy logs containing [ManualEntry] and [ScannerField]');
    }

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

    _tabController = TabController(length: _visibleTabCount, vsync: this);
    _activeTabIndex = _tabController.index;
    _scanTabActive = _tabController.index == _tabIndexScan;
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (!mounted) return;
      final previousIndex = _activeTabIndex;
      final nextIndex = _tabController.index;
      _setStateDebug('tab_active_index', () {
        _activeTabIndex = nextIndex;
        _scanTabActive = nextIndex == _tabIndexScan;
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

  void _navigateToECatalogTab() {
    if (!mounted) return;
    if (_tabController.index == _tabIndexECatalog) return;
    _tabController.animateTo(_tabIndexECatalog);
  }

  void _maybeNavigateToECatalogTab(_ECatalogNavigationSource source) {
    final shouldNavigate = source == _ECatalogNavigationSource.importOrder;
    if (!shouldNavigate) return;
    _navigateToECatalogTab();
  }

  void _finishScanPerfSample(int seq, {required String outcome}) {
    final sw = _scanPerfWatches.remove(seq);
    if (sw == null) return;
    sw.stop();
    final raw = _scanPerfRawBySeq.remove(seq) ?? '';
    final scanTabBuildDelta =
        _scanTabBuildCount - (_scanStartScanTabBuildCount.remove(seq) ?? 0);
    final orderListTabBuildDelta =
        _orderListTabBuildCount -
        (_scanStartOrderListTabBuildCount.remove(seq) ?? 0);
    final orderListBuildDelta =
        _orderListBuildCount - (_scanStartOrderListBuildCount.remove(seq) ?? 0);
    _perfLog(
      '#$seq total=${sw.elapsedMilliseconds}ms outcome=$outcome raw="$raw" buildDeltas(scanTab=$scanTabBuildDelta orderListTab=$orderListTabBuildDelta orderList=$orderListBuildDelta)',
    );
  }

  void _onCatalogSearchChanged(String value) {
    final normalized = value.trim();

    if (_catalogSearchQuery == normalized) return;

    setState(() {
      _catalogSearchQuery = normalized;
    });
  }

  String _normalizedSearchQuery(String raw) {
    return raw.trim().toLowerCase();
  }

  String _compactSearchToken(String raw) {
    return _normalizedSearchQuery(raw).replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  String _compactQuickEntryLookupToken(String raw) {
    return _normalizedSearchQuery(raw).replaceAll(RegExp(r'[\s-]+'), '');
  }

  Product? _findExactProductForQuickEntry(String rawInput) {
    final token = _compactQuickEntryLookupToken(rawInput);
    if (token.isEmpty) return null;
    Product? exact;
    for (final product in _allProducts) {
      final itemToken = _compactQuickEntryLookupToken(product.itemNumber);
      final upcToken = _compactQuickEntryLookupToken(product.upc);
      if (itemToken != token && upcToken != token) continue;
      if (exact != null &&
          !identical(exact, product) &&
          _orderLineKeyForProduct(exact) != _orderLineKeyForProduct(product)) {
        return null;
      }
      exact = product;
    }
    return exact;
  }

  bool _productMatchesSearch(Product product, String rawQuery) {
    final query = _normalizedSearchQuery(rawQuery);
    if (query.isEmpty) return true;

    bool textContains(String value) {
      return value.trim().toLowerCase().contains(query);
    }

    if (textContains(product.itemNumber) ||
        textContains(product.description) ||
        textContains(product.upc) ||
        textContains(product.productType) ||
        textContains(product.category) ||
        textContains(product.subCategory)) {
      return true;
    }

    final compactQuery = _compactSearchToken(rawQuery);
    if (compactQuery.isEmpty) return false;

    final compactItem = _compactSearchToken(product.itemNumber);
    if (compactItem.contains(compactQuery)) return true;

    final compactUpc = _compactSearchToken(product.upc);
    if (compactUpc.contains(compactQuery)) return true;

    return false;
  }

  bool _onECatalogScrollDismissKeyboard(ScrollNotification notification) {
    final userInitiated =
        notification is UserScrollNotification ||
        (notification is ScrollStartNotification &&
            notification.dragDetails != null);
    if (!userInitiated) return false;
    _ecatalogSearchKeyboardIdleTimer?.cancel();
    if (_ecatalogSearchFocusNode.hasFocus) {
      _ecatalogSearchFocusNode.unfocus();
    }
    return false;
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

  Future<void> _initAudio() {
    _audioInitFuture ??= _doInitAudio();
    return _audioInitFuture!;
  }

  Future<void> _doInitAudio() async {
    try {
      _goodScanPlayer ??= AudioPlayer();
      _goodScanPlayer2 ??= AudioPlayer();
      _errorScanPlayer ??= AudioPlayer();
      final goodScan = _goodScanPlayer!;
      final goodScan2 = _goodScanPlayer2!;
      final errorScan = _errorScanPlayer!;

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
      goodScan.audioCache = scanAudioCache;
      goodScan2.audioCache = scanAudioCache;
      errorScan.audioCache = scanAudioCache;

      await goodScan.setReleaseMode(ReleaseMode.stop);
      await goodScan2.setReleaseMode(ReleaseMode.stop);
      await errorScan.setReleaseMode(ReleaseMode.stop);

      // Short UI sounds: lowLatency is faster on many devices, but some Android OEM
      // builds fail silently with SoundPool; mediaPlayer is slower but reliable.
      final goodMode = Platform.isAndroid
          ? PlayerMode.mediaPlayer
          : PlayerMode.lowLatency;
      await goodScan.setPlayerMode(goodMode);
      await goodScan2.setPlayerMode(goodMode);

      // Slightly reduce good scan volume to avoid audible clipping/distortion.
      await goodScan.setVolume(0.75);
      await goodScan2.setVolume(0.75);

      // Do not pre-load or prepare players in init: on Android, early prepare + stop/pause
      // can break first/double beep. Sources are set on first play and then reused via seek+resume.

      if (Platform.isWindows) {
        _windowsGoodScanBytes = (await rootBundle.load(
          _goodScanAsset,
        )).buffer.asUint8List();
        _windowsGoodScan2Bytes = (await rootBundle.load(
          _goodScan2Asset,
        )).buffer.asUint8List();
        _windowsErrorScanBytes = (await rootBundle.load(
          _errorScanAsset,
        )).buffer.asUint8List();
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
    _refocusTimer?.cancel();
    _scannerFocusRetryTimer?.cancel();
    _scannerFocusHideKeyboardTimer?.cancel();
    _scanFeedbackTimer?.cancel();
    _errorBuzzTailPauseTimer?.cancel();
    _quoteNameBarcodeDebounce?.cancel();
    _searchDebounce?.cancel();
    _manualEntryFocusTraceTimeout?.cancel();
    _quoteNameController.removeListener(_onQuoteNameChanged);

    _goodScanPlayer?.dispose();
    _goodScanPlayer2?.dispose();
    _errorScanPlayer?.dispose();

    _scannerFocusNode.dispose();

    _searchQuotesFocusNode.dispose();
    _searchCustomersFocusNode.dispose();

    _quickEntryFocusNode.dispose();
    _quickEntryController.dispose();

    _quoteNameFocusNode.dispose();
    _quoteNameController.dispose();

    _searchController.dispose();

    _catalogSearchController.dispose();
    _ecatalogSearchKeyboardIdleTimer?.cancel();
    _ecatalogSearchFocusNode.dispose();

    _orderListTabScrollController.dispose();
    _scanPanelScrollController.dispose();
    _scanTabHighlightClearTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  /// Persists the Scan workspace with [_saveQuote] when the app is not in the
  /// foreground. Order edits (scan, manual add, import merge, qty, delete)
  /// otherwise update memory only until routing, export, Load Quote, or import
  /// triggers a save — so closing the app without those would drop changes.
  Future<void> _persistWorkingQuoteIfAny() async {
    if (_orderCsvImportInProgress) return;
    if (_loadingProducts) return;
    if (_orderLines.isEmpty && _currentQuoteId == null) return;
    try {
      await _saveQuote(notifyOnArchiveSideSave: false);
    } catch (e, st) {
      debugPrint('[PersistWorkingQuote] failed: $e\n$st');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_persistWorkingQuoteIfAny());
    }
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
    if (!_scannerStartupRefocusEnabled) return;
    final startedAt = DateTime.now();
    _refocusTimer?.cancel();
    _refocusTimer = Timer(
      const Duration(milliseconds: _scannerRefocusDelayMs),
      () {
        if (!mounted) return;
        if (!_shouldReclaimScannerFocus()) return;
        if (kDebugMode && _kScanRebuildInstrumentationEnabled) {
          debugPrint('SCAN_PATH[focus_refocus_timer_fired]');
        }
        _perfLog(
          'focus restore timer fired after ${DateTime.now().difference(startedAt).inMilliseconds}ms',
        );
        _requestScannerFocus();
      },
    );
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

  bool _isAnyManualTextFieldFocused() {
    if (_quickEntryFocusNode.hasFocus ||
        _quoteNameFocusNode.hasFocus ||
        _searchQuotesFocusNode.hasFocus ||
        _searchCustomersFocusNode.hasFocus) {
      return true;
    }

    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary == _scannerFocusNode) return false;
    final ctx = primary.context;
    if (ctx == null) return false;
    final widget = ctx.widget;
    if (widget is EditableText ||
        widget is TextField ||
        widget is TextFormField) {
      return true;
    }
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null ||
        ctx.findAncestorWidgetOfExactType<TextField>() != null ||
        ctx.findAncestorWidgetOfExactType<TextFormField>() != null;
  }

  void _requestScannerFocus() {
    if (_suspendScannerFocusRecovery) return;
    if (!mounted) return;

    final primary = FocusManager.instance.primaryFocus;
    final scannerAlreadyFocused = _scannerFocusNode.hasFocus;
    if (scannerAlreadyFocused && !_editDialogOpen && _scanTabActive) {
      _perfLog('focus restore skipped (scanner already focused)');
      debugPrint('[ScannerFocus] reclaim skipped (already focused)');
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
      debugPrint('[ScannerFocus] reclaim skipped (should not reclaim)');
      return;
    }

    if (_scannerFocusReclaimInFlight) {
      debugPrint('[ScannerFocus] reclaim skipped (in-flight)');
      return;
    }

    final now = DateTime.now();
    // Cooldown is only for redundant pulses when the scanner already holds focus.
    // When unfocused, parallel startup (init + product load) can call within a few
    // ms; throttling those drops real reclaim attempts and wedge scanners never bind.
    if (_scannerFocusNode.hasFocus &&
        _lastScannerFocusRequestTime != null &&
        now.difference(_lastScannerFocusRequestTime!).inMilliseconds <
            _scannerFocusRequestCooldownMs) {
      debugPrint(
        '[ScannerFocus] reclaim skipped (cooldown '
        '${now.difference(_lastScannerFocusRequestTime!).inMilliseconds}ms)',
      );
      return;
    }

    _scannerFocusReclaimInFlight = true;
    try {
      _lastScannerFocusRequestTime = now;
      debugPrint('[ScannerFocus] reclaim requested');

      if (_manualEntryFocusTraceActive) {
        debugPrint(
          '[ScannerFocus][Request] calling requestFocus(scanner). '
          'scannerHasFocus=${_scannerFocusNode.hasFocus} primaryFocusMatchesScanner=${primary == _scannerFocusNode}',
        );
      }

      if (!mounted) return;
      FocusScope.of(context).requestFocus(_scannerFocusNode);

      if (_suspendScannerFocusRecovery) return;

      _scannerFocusRetryTimer?.cancel();
      _scannerFocusRetryTimer = Timer(
        const Duration(milliseconds: _scannerFocusSingleRetryDelayMs),
        () {
          _scannerFocusRetryTimer = null;
          if (_suspendScannerFocusRecovery) return;
          if (!mounted) return;
          if (!_shouldReclaimScannerFocus()) return;
          if (!_scannerFocusNode.hasFocus) {
            debugPrint('[ScannerFocus] reclaim retry (still unfocused)');
            FocusScope.of(context).requestFocus(_scannerFocusNode);
          }
        },
      );

      if (_suspendScannerFocusRecovery) return;

      // Hide the keyboard after focusing the hidden scanner input.
      // Delay slightly to avoid racing with the user's attempt to focus another
      // text field (which can leave the keyboard suppressed).
      _scannerFocusHideKeyboardTimer?.cancel();
      _scannerFocusHideKeyboardTimer = Timer(const Duration(milliseconds: 60), () {
        _scannerFocusHideKeyboardTimer = null;
        if (_suspendScannerFocusRecovery) return;
        if (!mounted || _editDialogOpen) return;
        if (!_scannerFocusNode.hasFocus) return;

        final hidePrimary = FocusManager.instance.primaryFocus;
        if (hidePrimary != _scannerFocusNode) return;

        // If the app already moved focus into a normal entry field, don't hide
        // the keyboard.
        if (_quickEntryFocusNode.hasFocus || _quoteNameFocusNode.hasFocus) {
          return;
        }

        SystemChannels.textInput.invokeMethod('TextInput.hide');
      });
    } finally {
      _scannerFocusReclaimInFlight = false;
    }
  }

  /// After catalog data is ready, reclaim scanner focus once the frame has built
  /// the hidden [TextField] (avoids requestFocus racing a [setState] layout).
  void _requestScannerFocusAfterCatalogReady() {
    _requestScannerFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestScannerFocus();
    });
  }

  /// Scanner-only focus recovery used after scan processing paths where
  /// rebuilds/snackbars can briefly steal focus from the hidden scanner field.
  void _restoreScanFieldFocus() {
    if (!mounted) return;
    if (_suspendScannerFocusRecovery) return;

    void reclaim() {
      if (_suspendScannerFocusRecovery) return;
      debugPrint(
        '[DependentsDiag] _restoreScanFieldFocus.reclaim: enter mounted=$mounted',
      );
      if (!mounted) return;
      if (!_scanTabActive || _editDialogOpen) return;
      if (!_shouldReclaimScannerFocus()) return;
      if (!_scannerFocusNode.canRequestFocus) return;
      debugPrint(
        '[DependentsDiag] _restoreScanFieldFocus: before FocusScope.requestFocus(scanner)',
      );
      FocusScope.of(context).requestFocus(_scannerFocusNode);
      debugPrint(
        '[DependentsDiag] _restoreScanFieldFocus: after FocusScope.requestFocus(scanner)',
      );
    }

    if (_suspendScannerFocusRecovery) return;

    // First restore after the current frame settles.
    debugPrint(
      '[DependentsDiag] _restoreScanFieldFocus: before addPostFrameCallback',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_suspendScannerFocusRecovery) return;
      debugPrint(
        '[DependentsDiag] _restoreScanFieldFocus: addPostFrameCallback fired',
      );
      reclaim();
    });
    debugPrint(
      '[DependentsDiag] _restoreScanFieldFocus: after addPostFrameCallback scheduled',
    );
    if (_suspendScannerFocusRecovery) return;

    // Then add one small delayed pulse for snackbar/rebuild races.
    debugPrint(
      '[DependentsDiag] _restoreScanFieldFocus: before Future.delayed(60ms)',
    );
    Future.delayed(const Duration(milliseconds: 60), () {
      if (_suspendScannerFocusRecovery) return;
      reclaim();
    });
    debugPrint(
      '[DependentsDiag] _restoreScanFieldFocus: after Future.delayed(60ms) scheduled',
    );
  }

  Future<void> _stopAllSounds() async {
    // Do NOT stop good scan players to avoid Android playback issues.
    // Pause (not stop) on the error player so the asset source stays prepared
    // for faster repeated error feedback; see [_playErrorBuzz].
    _errorBuzzTailPauseTimer?.cancel();
    _errorBuzzTailPauseTimer = null;
    final errorPlayer = _errorScanPlayer;
    if (errorPlayer == null) return;
    try {
      await errorPlayer.pause();
    } catch (_) {}
  }

  Future<void> _deliverScanFeedbackSounds(
    ScanFeedbackType type,
    int sampleId,
    String source,
  ) async {
    if (source == 'ecatalog') {
      await _playEcatalogClick();
      if (sampleId > 0) {
        _logScanPerfStep(sampleId, 'click triggered (ecatalog)');
      }
      HapticFeedback.selectionClick();
      return;
    }

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

  Future<void> _playEcatalogClick() async {
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {
      // No-op fallback: ECatalog flow should remain beep-free if click is unavailable.
    }
  }

  void _triggerScanFeedback(
    ScanFeedbackType type, {
    String source = 'scanner',
  }) {
    final int sampleId = _currentScanSampleId;
    _scanFeedbackTimer?.cancel();

    if (_scanFeedbackType != type) {
      _setStateDebug('scan_feedback_apply', () {
        _scanFeedbackType = type;
      });
    }

    // Ensure only one sound plays per scan / entry: finish pause on the error
    // player before seek/resume, or pause races with replay on the same native player.
    unawaited(_deliverScanFeedbackSounds(type, sampleId, source));

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
      await _initAudio();
      if (!mounted) return;

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
        final bytes = isSingle ? _windowsGoodScanBytes : _windowsGoodScan2Bytes;
        if (bytes == null) {
          debugPrint(
            '[Audio] Windows scan sound bytes missing '
            '(single=$isSingle)',
          );
          return;
        }
        final player = isSingle ? _goodScanPlayer! : _goodScanPlayer2!;
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
          await _goodScanPlayer!.setSource(_goodScanAssetSource);
          if (!mounted) return;
          _goodScanPlayer1SourceReady = true;
        }
        await _goodScanPlayer!.seek(Duration.zero);
        await _goodScanPlayer!.resume();
      } else {
        if (!_goodScanPlayer2SourceReady) {
          if (kDebugMode) {
            debugPrint('[Audio] player2 setSource($_goodScan2Asset)');
          }
          await _goodScanPlayer2!.setSource(_goodScan2AssetSource);
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
        await _goodScanPlayer2!.seek(Duration.zero);
        await _goodScanPlayer2!.resume();
      }
      if (kDebugMode) {
        debugPrint('Play attempt');
      }
    } catch (e, st) {
      debugPrint('[Audio] good beep error (single=$isSingle): $e');
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
      await _initAudio();
      if (!mounted) return;
      final errorScan = _errorScanPlayer!;
      // Avoid stop() before play: on some Android devices it puts MediaPlayer in error state (-38)
      if (!_errorScanPlayerVolumeRateSet) {
        await errorScan.setVolume(1.0);
        await errorScan.setPlaybackRate(1.0);
        _errorScanPlayerVolumeRateSet = true;
      }
      if (Platform.isWindows) {
        final bytes = _windowsErrorScanBytes;
        if (bytes != null) {
          if (!_errorScanPlayerSourceReady) {
            await errorScan.setSourceBytes(
              bytes,
              mimeType: 'audio/mpeg',
            );
            if (!mounted) return;
            _errorScanPlayerSourceReady = true;
          } else {
            await errorScan.seek(Duration.zero);
          }
          await errorScan.resume();
          soundPlayed = true;
        }
      } else {
        if (!_errorScanPlayerSourceReady) {
          await errorScan.setSource(_errorScanAssetSource);
          if (!mounted) return;
          _errorScanPlayerSourceReady = true;
        } else {
          await errorScan.seek(Duration.zero);
        }
        await errorScan.resume();
        soundPlayed = true;
      }
      if (soundPlayed) {
        // Same 500ms cutoff as before (avoid long tails); pause keeps source prepared
        // for the next bad scan instead of stop()+clearing [_errorScanPlayerSourceReady].
        _errorBuzzTailPauseTimer?.cancel();
        _errorBuzzTailPauseTimer = Timer(
          const Duration(milliseconds: 500),
          () async {
            _errorBuzzTailPauseTimer = null;
            if (!mounted) return;
            try {
              await errorScan.pause();
            } catch (_) {}
          },
        );
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

    if (t == 'halloween' || t == 'halloween_quote' || t == 'halloween quote') {
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

  /// Grep: [ImportRoute] — once per customer+bucket per CSV import.
  void _traceOrderImportRouteFirstTouch({
    required Customer customer,
    required String targetLogicalBucket,
    required String normType,
    required String note,
  }) {
    if (!kDebugMode || !_orderCsvImportInProgress) return;
    final k = '${customer.id}|$targetLogicalBucket';
    if (!_orderImportRouteTraceKeys.add(k)) return;
    debugPrint(
      '[ImportRoute] $note logicalBucket=$targetLogicalBucket '
      'productType="$normType" quoteId=${_currentQuoteId ?? 'null'} '
      'customer="${customer.displayName}"',
    );
  }

  bool _parseYesFlag(String value) => value.trim().toUpperCase() == 'YES';

  ProductPricingState _productPricingState(Product product) {
    // PS takes precedence when both PS and NET are set.
    if (product.isPs) return ProductPricingState.ps;
    if (product.isNet) return ProductPricingState.net;
    if (product.discountEligible) return ProductPricingState.discountEligible;
    return ProductPricingState.regular;
  }

  String? _productPricingIndicator(Product product) {
    switch (_productPricingState(product)) {
      case ProductPricingState.ps:
        return 'PS';
      case ProductPricingState.net:
        return 'NET';
      case ProductPricingState.regular:
      case ProductPricingState.discountEligible:
        return null;
    }
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
      final resolved =
          _quoteBucketsByRawType[_normalizeBucketLookup(fromProductType)];
      if (resolved != null) return resolved;
    }

    final fromCategory = product.category.trim();
    if (fromCategory.isNotEmpty) {
      final resolved =
          _quoteBucketsByRawType[_normalizeBucketLookup(fromCategory)];
      if (resolved != null) return resolved;
    }

    // Pride should always route to the PRIDE quote, even when product type
    // values include additional words not listed as explicit mappings.
    if (_containsPrideToken(fromProductType) ||
        _containsPrideToken(fromCategory)) {
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
  Future<void>
  _pruneSupersededEmptyDuplicateQuotesForAllActiveIndexCustomers() async {
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

      final archiveIds = (await _loadArchiveQuoteIndex())
          .map((e) => e.id)
          .toSet();
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
          if (cur != null && emptyIds.contains(cur) && nonEmptyIds.isNotEmpty) {
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

      for (final m in list) {
        try {
          final info = SavedQuoteInfo.fromJson(
            Map<String, dynamic>.from(m as Map),
          );
          if (info.id.isEmpty) continue;
          if (archiveIds.contains(info.id)) continue;
          if (info.status != QuoteLifecycleStatus.active) continue;
          if (!_savedQuoteInfoMatchesCustomer(info, customer)) continue;
          await _ensureActiveIndexRowForQuoteFile(info.id);
        } catch (_) {}
      }

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
    return RegExp(
      r'^QUOTE_\d{4}_\d{2}_\d{2}_\d{3}$',
      caseSensitive: false,
    ).hasMatch(text);
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
          '[Routing] No customer selected — routing/switch skipped (no order line added)',
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
          final emptyReuseId =
              await _findEmptyPersistedQuoteIdForCustomerBucket(
                customer: customer,
                bucketKey: _activeQuoteBucketKey,
              );
          if (emptyReuseId != null) {
            if (_orderLines.isEmpty) {
              await _loadQuoteById(emptyReuseId);
              if (!mounted) return;
            } else {
              _currentQuoteId = emptyReuseId;
              if (_orderCsvImportInProgress) {
                _orderImportTouchedQuoteIds.add(emptyReuseId);
              }
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
      _traceOrderImportRouteFirstTouch(
        customer: customer,
        targetLogicalBucket: targetId,
        normType: normType,
        note: 'alreadyOnTargetBucket',
      );
      return;
    }

    final currentRouteKey = _routeKeyForCustomerBucket(
      customer,
      _activeQuoteBucketKey,
    );
    final targetRouteKey = _routeKeyForCustomerBucket(
      customer,
      bucket.bucketKey,
    );
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
          message:
              '$tracePrefix Existing quote found: yes (id=$existingQuoteId)',
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
      _traceOrderImportRouteFirstTouch(
        customer: customer,
        targetLogicalBucket: targetId,
        normType: normType,
        note: 'reusedPersistedQuote',
      );
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
    _traceOrderImportRouteFirstTouch(
      customer: customer,
      targetLogicalBucket: targetId,
      normType: normType,
      note: 'startNewRoutedQuote',
    );
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
      await Future<void>.delayed(_startupBundleLoadDelay);
      if (!mounted) return;
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
        final displayLabel =
            (rawValue['displayLabel'] as String?)?.trim() ?? '';
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

  String _customerHistoryCacheKey(Customer? customer) {
    if (customer == null) return '';
    final id = customer.id.trim();
    if (id.isNotEmpty) return 'ID:${id.toLowerCase()}';
    final name = customer.displayName.trim().toLowerCase();
    return 'NAME:$name';
  }

  String? _orderLineKeyFromPersistedQuoteLine(Map<String, dynamic> map) {
    final item = normalizeItemNumber((map['itemNumber'] as String?)?.trim() ?? '');
    if (item.isNotEmpty) return 'ITEM:$item';
    final upc = _normalizeUpcLookupKey((map['upc'] as String?)?.trim() ?? '');
    if (upc.isEmpty) return null;
    return 'UPC:$upc';
  }

  Future<void> _refreshPreviouslyOrderedHistoryForSelectedCustomer({
    bool force = false,
  }) async {
    final customer = _selectedCustomer;
    final cacheKey = _customerHistoryCacheKey(customer);
    if (cacheKey.isEmpty) {
      if (_previouslyOrderedCustomerCacheKey.isNotEmpty ||
          _previouslyOrderedKeysForSelectedCustomer.isNotEmpty) {
        if (!mounted) {
          _previouslyOrderedCustomerCacheKey = '';
          _previouslyOrderedKeysForSelectedCustomer = <String>{};
          return;
        }
        setState(() {
          _previouslyOrderedCustomerCacheKey = '';
          _previouslyOrderedKeysForSelectedCustomer = <String>{};
        });
      }
      return;
    }
    if (!force && _previouslyOrderedCustomerCacheKey == cacheKey) return;
    if (_previouslyOrderedHistoryLoadInFlightKey == cacheKey) return;

    final cached = _previouslyOrderedKeysByCustomer[cacheKey];
    if (cached != null) {
      if (!mounted) {
        _previouslyOrderedCustomerCacheKey = cacheKey;
        _previouslyOrderedKeysForSelectedCustomer = cached;
        return;
      }
      setState(() {
        _previouslyOrderedCustomerCacheKey = cacheKey;
        _previouslyOrderedKeysForSelectedCustomer = cached;
      });
      return;
    }

    _previouslyOrderedHistoryLoadInFlightKey = cacheKey;
    final computedKeys = <String>{};
    try {
      final archive = await _loadArchiveQuoteIndex();
      final matching = archive
          .where((info) => _savedQuoteInfoMatchesCustomer(info, customer!))
          .toList(growable: false);
      if (matching.isNotEmpty) {
        final dir = await _getQuotesDirectory();
        for (final info in matching) {
          final file = File('${dir.path}/quote_${info.id}.json');
          if (!await file.exists()) continue;
          try {
            final decoded = jsonDecode(await file.readAsString());
            if (decoded is! Map) continue;
            final data = Map<String, dynamic>.from(decoded);
            final lines =
                data['lines'] as List<dynamic>? ??
                data['items'] as List<dynamic>? ??
                const [];
            for (final lineJson in lines) {
              if (lineJson is! Map) continue;
              final key = _orderLineKeyFromPersistedQuoteLine(
                Map<String, dynamic>.from(lineJson),
              );
              if (key != null && key.isNotEmpty) {
                computedKeys.add(key);
              }
            }
          } catch (_) {
            // Keep history resilient when one archive quote file is malformed.
          }
        }
      }
      _previouslyOrderedKeysByCustomer[cacheKey] = computedKeys;
      if (!mounted) {
        _previouslyOrderedCustomerCacheKey = cacheKey;
        _previouslyOrderedKeysForSelectedCustomer = computedKeys;
        return;
      }
      if (_customerHistoryCacheKey(_selectedCustomer) != cacheKey) return;
      setState(() {
        _previouslyOrderedCustomerCacheKey = cacheKey;
        _previouslyOrderedKeysForSelectedCustomer = computedKeys;
      });
    } catch (_) {
      if (!mounted) return;
      if (_customerHistoryCacheKey(_selectedCustomer) != cacheKey) return;
      setState(() {
        _previouslyOrderedCustomerCacheKey = cacheKey;
        _previouslyOrderedKeysForSelectedCustomer = <String>{};
      });
    } finally {
      if (_previouslyOrderedHistoryLoadInFlightKey == cacheKey) {
        _previouslyOrderedHistoryLoadInFlightKey = null;
      }
    }
  }

  bool _isPreviouslyOrdered(Product p) {
    return _previouslyOrderedKeysForSelectedCustomer.contains(
      _orderLineKeyForProduct(p),
    );
  }

  String _sanitizeOrderExportFileSegment(
    String value, {
    String ifEmpty = 'Quote',
  }) {
    final trimmed = _repairMojibakeText(value).trim();
    if (trimmed.isEmpty) return ifEmpty;
    var s = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    s = s
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '')
        .trim()
        .toUpperCase();
    if (s.isEmpty) return ifEmpty;
    if (s.length > 120) s = s.substring(0, 120);
    return s;
  }

  /// Export CSV basename: `{TYPE}_{yyyy_MM_dd}_{seq}_{customer}_{yyyyMMdd_HHmmss_mmm}.csv`.
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

  ({String quoteType, DateTime? quoteDate, String? uniqueNumber})
  _extractQuoteNamingParts(String quoteName) {
    final normalized = _sanitizeOrderExportFileSegment(quoteName, ifEmpty: '');
    if (normalized.isEmpty) {
      return (quoteType: 'QUOTE', quoteDate: null, uniqueNumber: null);
    }

    final full = RegExp(
      r'^(.+)_(\d{4})_(\d{2})_(\d{2})_(\d{3})$',
    ).firstMatch(normalized);
    if (full != null) {
      final y = int.tryParse(full.group(2)!);
      final mo = int.tryParse(full.group(3)!);
      final d = int.tryParse(full.group(4)!);
      DateTime? date;
      if (y != null && mo != null && d != null) {
        date = DateTime(y, mo, d);
      }
      return (
        quoteType: full.group(1) ?? 'QUOTE',
        quoteDate: date,
        uniqueNumber: full.group(5),
      );
    }

    final withSequence = RegExp(r'^(.+)_(\d{3})$').firstMatch(normalized);
    if (withSequence != null) {
      return (
        quoteType: withSequence.group(1) ?? 'QUOTE',
        quoteDate: null,
        uniqueNumber: withSequence.group(2),
      );
    }

    return (quoteType: normalized, quoteDate: null, uniqueNumber: null);
  }

  String _buildExportSystemCsvFilename({
    required String exportType,
    required String customerName,
    String? customerId,
    DateTime? exportedOn,
  }) {
    final now = exportedOn ?? DateTime.now();
    final rawExportType = exportType.trim();
    final normalizedExportTypeKey = rawExportType.toUpperCase();
    final canonicalSystemType =
        normalizedExportTypeKey == 'ALL_EXPORTED_QUOTE_ITEMS'
            ? 'ALL_EXPORTED_ITEMS'
            : normalizedExportTypeKey == 'ITEMS_NOT_FOUND'
            ? 'ITEMS_NOT_FOUND'
            : normalizedExportTypeKey == 'ITEMS_WITHOUT_UPC'
            ? 'ITEMS_WITHOUT_UPC'
            : rawExportType;
    final pseudoQuoteName =
        '${_sanitizeOrderExportFileSegment(canonicalSystemType, ifEmpty: 'QUOTE')}_'
        '${now.year.toString().padLeft(4, '0')}_'
        '${now.month.toString().padLeft(2, '0')}_'
        '${now.day.toString().padLeft(2, '0')}_001';
    return _buildExportOrderCsvFilename(
      quoteName: pseudoQuoteName,
      customerName: customerName,
      customerId: customerId,
      customerFolderName: customerName,
      quoteDate: now,
      exportedOn: now,
    );
  }

  String _buildQuoteExportCsvFilename({
    required String quoteType,
    required DateTime quoteDate,
    required String uniqueQuoteNumber,
    required String customerName,
    DateTime? exportedAt,
  }) {
    final exportTime = exportedAt ?? DateTime.now();
    final datePart =
        '${quoteDate.year.toString().padLeft(4, '0')}_'
        '${quoteDate.month.toString().padLeft(2, '0')}_'
        '${quoteDate.day.toString().padLeft(2, '0')}';
    final timestamp = _formatExportTimestamp(exportTime);

    final safeType = _sanitizeOrderExportFileSegment(quoteType, ifEmpty: 'QUOTE');
    final safeCustomer = _sanitizeOrderExportFileSegment(
      customerName,
      ifEmpty: 'UNKNOWN_CUSTOMER',
    );
    final parsedSequence = int.tryParse(uniqueQuoteNumber.trim());
    final safeUnique =
        parsedSequence == null
            ? '001'
            : parsedSequence.toString().padLeft(3, '0');

    // Keep customer + timestamp in the filename even when clipping is needed.
    final requiredTail = '_${datePart}_${safeUnique}_${safeCustomer}_$timestamp';
    final maxTypeLen =
        _kMaxExportCsvFilenameLength - '.csv'.length - requiredTail.length - 1;
    final adjustedType =
        maxTypeLen >= 5
            ? (safeType.length > maxTypeLen
                ? safeType.substring(0, maxTypeLen)
                : safeType)
            : 'QUOTE';

    return _clipExportCsvFilename(
      ensureCsvFilename('$adjustedType$requiredTail'),
    );
  }

  DateTime _quoteDateFromMapOrFallback(
    Map<String, dynamic> quoteData,
    DateTime fallback,
  ) {
    final createdAt = DateTime.tryParse((quoteData['createdAt'] as String?) ?? '');
    if (createdAt != null) return createdAt;
    final updatedAt = DateTime.tryParse((quoteData['updatedAt'] as String?) ?? '');
    if (updatedAt != null) return updatedAt;
    return fallback;
  }

  String _buildExportOrderCsvFilename({
    required String quoteName,
    String? customerName,
    String? customerId,
    Map<String, dynamic>? quoteData,
    String? customerFolderName,
    String? quoteBucketLabel,
    String? quoteBucketKey,
    DateTime? quoteDate,
    required DateTime exportedOn,
  }) {
    final parsed = _extractQuoteNamingParts(quoteName);
    final rawTypeCandidate =
        parsed.quoteType.trim().isNotEmpty
            ? parsed.quoteType
            : ((quoteBucketLabel ?? quoteBucketKey ?? '').trim().isNotEmpty
                ? '${(quoteBucketLabel ?? quoteBucketKey ?? '').trim()} QUOTE'
                : 'QUOTE');
    final normalizedType = _sanitizeOrderExportFileSegment(
      rawTypeCandidate,
      ifEmpty: 'QUOTE',
    );
    final normalizedSequence = (parsed.uniqueNumber ?? '').trim();
    final resolvedCustomerName = _resolveCustomerNameForQuoteExport(
      customerName: customerName,
      customerId: customerId,
      quoteData: quoteData,
      customerFolderName: customerFolderName,
    );
    final safeCustomer = _sanitizeOrderExportFileSegment(
      resolvedCustomerName,
      ifEmpty: 'UNKNOWN_CUSTOMER',
    );
    var filename = _buildQuoteExportCsvFilename(
      quoteType: normalizedType,
      quoteDate: parsed.quoteDate ?? quoteDate ?? exportedOn,
      uniqueQuoteNumber: normalizedSequence.isEmpty ? '001' : normalizedSequence,
      customerName: resolvedCustomerName,
      exportedAt: exportedOn,
    );
    if (!filename.toUpperCase().contains('_${safeCustomer}_')) {
      filename = _forceCustomerSegmentIntoQuoteFilename(
        filename: filename,
        safeCustomerName: safeCustomer,
      );
    }
    return filename;
  }

  String _resolveCustomerNameForQuoteExport({
    String? customerName,
    String? customerId,
    Map<String, dynamic>? quoteData,
    String? customerFolderName,
  }) {
    final explicit = (customerName ?? '').trim();
    if (explicit.isNotEmpty) return explicit;

    final qdCustomer = quoteData?['customer'];
    if (qdCustomer is Map) {
      try {
        final c = Customer.fromJson(Map<String, dynamic>.from(qdCustomer));
        final company = c.companyName.trim();
        if (company.isNotEmpty) return company;
        final display = c.displayName.trim();
        if (display.isNotEmpty) return display;
      } catch (_) {}
    }

    final id = (customerId ?? '').trim();
    if (id.isNotEmpty) {
      final byMap = _customersByKey[id];
      if (byMap != null) {
        final company = byMap.companyName.trim();
        if (company.isNotEmpty) return company;
        final display = byMap.displayName.trim();
        if (display.isNotEmpty) return display;
      }
      for (final c in _customers) {
        if (c.id.trim() != id) continue;
        final company = c.companyName.trim();
        if (company.isNotEmpty) return company;
        final display = c.displayName.trim();
        if (display.isNotEmpty) return display;
      }
    }

    final folder = (customerFolderName ?? '').trim();
    if (folder.isNotEmpty) return folder;
    return 'UNKNOWN_CUSTOMER';
  }

  String _forceCustomerSegmentIntoQuoteFilename({
    required String filename,
    required String safeCustomerName,
  }) {
    final csv = ensureCsvFilename(filename);
    final stem = p.basenameWithoutExtension(csv);
    final timestampMatch = RegExp(r'_(\d{8}_\d{6}_\d{3})$').firstMatch(stem);
    String rebuilt;
    if (timestampMatch != null) {
      final tsStart = timestampMatch.start;
      final ts = timestampMatch.group(1)!;
      var prefix = stem.substring(0, tsStart).replaceFirst(RegExp(r'_+$'), '');
      if (!prefix.toUpperCase().contains('_${safeCustomerName.toUpperCase()}_')) {
        prefix = '${prefix}_$safeCustomerName';
      }
      rebuilt = '${prefix}_$ts.csv';
    } else {
      rebuilt = '${stem}_$safeCustomerName.csv';
    }
    return _clipExportCsvFilename(rebuilt);
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
          content: SingleChildScrollView(child: SelectableText(message)),
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
      await _debugLogCsvExportFile(
        action: 'share_single_csv',
        filename: p.basename(file.path),
        mimeType: 'text/csv',
        file: file,
      );
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to share file')));
    }
  }

  Future<void> _shareMultipleExportedCsvs(List<File> files) async {
    try {
      final existing = <XFile>[];
      for (final file in files) {
        if (await file.exists()) {
          await _debugLogCsvExportFile(
            action: 'share_multiple_csv',
            filename: p.basename(file.path),
            mimeType: 'text/csv',
            file: file,
          );
          existing.add(XFile(file.path, mimeType: 'text/csv'));
        }
      }
      if (existing.isEmpty) {
        throw StateError('No exported files found.');
      }
      await Share.shareXFiles(existing);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to share files')));
    }
  }

  Future<void> _openCsvWithSystemHandler(File file) async {
    try {
      if (!await file.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('File not found.')));
        return;
      }
      final path = file.path;
      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      } else {
        await _shareSingleExportedCsv(file);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open file')));
    }
  }

  String _csvEscape(String value) {
    if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }

  String _csvPreserveLeadingZerosCell(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return '';
    // Excel/Sheets: force text so values like 00123 stay zero-padded.
    return '="$trimmed"';
  }

  Product _productForExportedQuoteLine(Map<String, dynamic> lineMap) {
    final upc = (lineMap['upc'] as String?)?.trim() ?? '';
    final itemNumber = (lineMap['itemNumber'] as String?)?.trim() ?? '';
    final description = _repairMojibakeText(
      (lineMap['description'] as String?)?.trim() ?? '',
    );
    final price = (lineMap['price'] as num?)?.toDouble() ?? 0.0;
    final productType = _repairMojibakeText(
      (lineMap['productType'] as String?)?.trim() ?? '',
    );
    final discountRaw = (lineMap['discountRaw'] as String?)?.trim() ?? '';
    final discountEligible = (lineMap['discountEligible'] as bool?) ?? false;
    final netRaw = (lineMap['netRaw'] as String?)?.trim() ?? '';
    final isNet = (lineMap['isNet'] as bool?) ?? _parseYesFlag(netRaw);
    final psRaw = (lineMap['psRaw'] as String?)?.trim() ?? '';
    final isPs = (lineMap['isPs'] as bool?) ?? _parseYesFlag(psRaw);
    final isNewRelease = (lineMap['isNewRelease'] as bool?) ?? false;
    final category = _repairMojibakeText(
      (lineMap['category'] as String?)?.trim() ?? '',
    );
    final subCategory = _repairMojibakeText(
      (lineMap['subCategory'] as String?)?.trim() ?? '',
    );
    final whse1InStock = (lineMap['whse1InStock'] as bool?) ?? false;
    final whse2InStock = (lineMap['whse2InStock'] as bool?) ?? false;
    final whse1OutOfStock = (lineMap['whse1OutOfStock'] as bool?) ?? false;
    final whse2OutOfStock = (lineMap['whse2OutOfStock'] as bool?) ?? false;
    final whse1ComingSoon = (lineMap['whse1ComingSoon'] as bool?) ?? false;
    final whse2ComingSoon = (lineMap['whse2ComingSoon'] as bool?) ?? false;
    final whse1AvailabilityDisplay =
        _repairMojibakeText(
          (lineMap['whse1AvailabilityDisplay'] as String?)?.trim() ?? '',
        );
    final whse2AvailabilityDisplay =
        _repairMojibakeText(
          (lineMap['whse2AvailabilityDisplay'] as String?)?.trim() ?? '',
        );
    final minOrderQty = _quantityFromJson(lineMap['minOrderQty']);
    final caseQty = _quantityFromJson(lineMap['caseQty']);
    final listPrice = (lineMap['listPrice'] as num?)?.toDouble() ?? 0.0;

    Product? product = _productsByUpc[_normalizeUpcLookupKey(upc)];
    if (product == null) {
      // Keep export layout unchanged; only enrich missing product fields by
      // resolving with the same normalized products.csv item key logic used
      // elsewhere in import/export flows.
      product = _lookupProductForNotImportedExportRow(
        rawItemNumber: itemNumber,
        rawUpc: upc,
        includeUpcFallback: false,
      );
    }
    if (product == null) {
      final normalizedItem = normalizeItemNumber(itemNumber);
      if (normalizedItem.isNotEmpty) {
        product = _productsByItemNumber[normalizedItem];
      }
    }
    if (product != null) return product;

    return Product(
      itemNumber: itemNumber.isEmpty ? upc : itemNumber,
      description: description.isEmpty ? 'Unknown' : description,
      upc: upc,
      price: price,
      listPrice: listPrice,
      productType: productType,
      discountRaw: discountRaw,
      discountEligible: discountEligible,
      netRaw: netRaw,
      isNet: isNet,
      psRaw: psRaw,
      isPs: isPs,
      isNewRelease: isNewRelease,
      category: category,
      subCategory: subCategory,
      minOrderQty: minOrderQty <= 0 ? 1 : minOrderQty,
      caseQty: caseQty <= 0 ? 1 : caseQty,
      whse1InStock: whse1InStock,
      whse2InStock: whse2InStock,
      whse1OutOfStock: whse1OutOfStock,
      whse2OutOfStock: whse2OutOfStock,
      whse1ComingSoon: whse1ComingSoon,
      whse2ComingSoon: whse2ComingSoon,
      whse1AvailabilityDisplay: whse1AvailabilityDisplay,
      whse2AvailabilityDisplay: whse2AvailabilityDisplay,
    );
  }

  Product? _lookupProductForNotImportedExportRow({
    required String rawItemNumber,
    required String rawUpc,
    bool includeUpcFallback = true,
  }) {
    final itemKey = _orderImportNormalizeItemKey(rawItemNumber);
    if (itemKey.isNotEmpty) {
      final byItem = _productsByItemNumber[itemKey];
      if (byItem != null) return byItem;

      final isNumericItemLabel = RegExp(r'^\d+$').hasMatch(itemKey);
      if (isNumericItemLabel) {
        final candidateWidths =
            (_productsByItemNumber.keys
                  .where(
                    (k) =>
                        k.length > itemKey.length && RegExp(r'^\d+$').hasMatch(k),
                  )
                  .map((k) => k.length)
                  .toSet()
                  .toList()
                ..sort());
        for (final width in candidateWidths) {
          if (width <= itemKey.length) continue;
          final padded = itemKey.padLeft(width, '0');
          final byPaddedItem = _productsByItemNumber[padded];
          if (byPaddedItem != null) return byPaddedItem;
        }
      }
    }

    if (!includeUpcFallback) return null;

    final upcKey = _orderImportNormalizeUpcLookupKey(rawUpc);
    if (upcKey.isEmpty) return null;
    Product? byUpc = _productsByUpc[upcKey];
    if (byUpc == null && upcKey.length == 12 && upcKey.startsWith('0')) {
      byUpc = _productsByUpc[upcKey.substring(1)];
    }
    if (byUpc == null && upcKey.length == 11) {
      byUpc = _productsByUpc['0$upcKey'];
    }
    return byUpc;
  }

  Future<List<OrderImportSkippedRow>> _resolveLastNotImportedRowsForCustomer(
    Customer customer,
  ) async {
    final rowsCustomerMatch = _sameLogicalCustomerQuoteRows(
      customerIdA: customer.id,
      customerNameA: customer.displayName,
      customerIdB: _lastItemsNotImportedRowsCustomerId ?? '',
      customerNameB: _lastItemsNotImportedRowsCustomerName ?? '',
    );
    if (rowsCustomerMatch && _lastItemsNotImportedRows.isNotEmpty) {
      return List<OrderImportSkippedRow>.from(_lastItemsNotImportedRows);
    }
    return const [];
  }

  String _formatItemsWithoutUpcRowsCsv(
    List<OrderImportItemsWithoutUpcRow> rows,
  ) {
    final out = <String>[
      'Item Number,Quantity,Original UPC,Resolution Status,Description,Price,Minimum Order Quantity,Case Quantity',
    ];
    for (final r in rows) {
      out.add(
        '${_csvEscape(r.itemNumber)},'
        '${_csvEscape(r.quantity.toString())},'
        '${_csvEscape(r.originalUpc)},'
        '${_csvEscape(r.resolutionStatus)},'
        '${_csvEscape(r.description)},'
        '${_csvEscape(r.price)},'
        '${_csvEscape(r.minimumOrderQuantity)},'
        '${_csvEscape(r.caseQuantity)}',
      );
    }
    return out.join('\n');
  }

  String _formatItemsNotFoundRowsCsv(
    List<OrderImportItemsWithoutUpcRow> rows,
  ) {
    final out = <String>['Item Number,Quantity'];
    for (final r in rows) {
      out.add('${_csvEscape(r.itemNumber)},${_csvEscape(r.quantity.toString())}');
    }
    return out.join('\n');
  }

  bool _itemsWithoutUpcRowIsNotFound(OrderImportItemsWithoutUpcRow row) {
    final normalized = row.resolutionStatus
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    if (normalized == 'NOT_FOUND') return true;
    if (normalized == 'ITEM_NOT_FOUND') return true;
    return normalized.contains('NOT_FOUND');
  }

  Future<List<OrderImportItemsWithoutUpcRow>>
  _resolveItemsWithoutUpcRowsForCustomer(Customer customer) async {
    final rowsCustomerMatch = _sameLogicalCustomerQuoteRows(
      customerIdA: customer.id,
      customerNameA: customer.displayName,
      customerIdB: _lastItemsWithoutUpcRowsCustomerId ?? '',
      customerNameB: _lastItemsWithoutUpcRowsCustomerName ?? '',
    );
    if (rowsCustomerMatch && _lastItemsWithoutUpcRows.isNotEmpty) {
      return List<OrderImportItemsWithoutUpcRow>.from(_lastItemsWithoutUpcRows);
    }
    final persistedRows = await _readPersistedItemsWithoutUpcRowsForCustomer(
      customer,
    );
    if (persistedRows.isNotEmpty) {
      _lastItemsWithoutUpcRows = List<OrderImportItemsWithoutUpcRow>.from(
        persistedRows,
      );
      _lastItemsWithoutUpcRowsCustomerId = customer.id;
      _lastItemsWithoutUpcRowsCustomerName = customer.displayName;
      return persistedRows;
    }
    return const [];
  }

  String _itemsWithoutUpcStateFilenameForCustomer(Customer customer) {
    var token = sanitizeCustomerExportFolderName(customer.displayName);
    token = token.replaceAll(RegExp(r'\s+'), '_');
    token = token.replaceAll(RegExp(r'_+'), '_');
    token = token.replaceAll(RegExp(r'^_+|_+$'), '');
    if (token.isEmpty) token = kNoCustomerExportFolderName;
    token = token.toUpperCase();
    return 'import_items_without_upc_$token.json';
  }

  Future<File> _itemsWithoutUpcStateFileForCustomer(Customer customer) async {
    final dir = await _getQuotesDirectory();
    return File(
      '${dir.path}/${_itemsWithoutUpcStateFilenameForCustomer(customer)}',
    );
  }

  Future<void> _persistItemsWithoutUpcRowsForCustomer(
    Customer customer,
    List<OrderImportItemsWithoutUpcRow> rows,
  ) async {
    try {
      final file = await _itemsWithoutUpcStateFileForCustomer(customer);
      final payload = <String, dynamic>{
        'customerId': customer.id.trim(),
        'customerName': customer.displayName.trim(),
        'updatedAt': DateTime.now().toIso8601String(),
        'rows': rows.map((r) => r.toJson()).toList(growable: false),
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (e) {
      debugPrint('[ItemsWithoutUpc] persist failed: $e');
    }
  }

  Future<List<OrderImportItemsWithoutUpcRow>>
  _readPersistedItemsWithoutUpcRowsForCustomer(Customer customer) async {
    try {
      final file = await _itemsWithoutUpcStateFileForCustomer(customer);
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const [];
      final payload = Map<String, dynamic>.from(decoded);
      final storedCustomerId = (payload['customerId'] ?? '').toString().trim();
      final storedCustomerName =
          (payload['customerName'] ?? '').toString().trim();
      if (!_sameLogicalCustomerQuoteRows(
        customerIdA: customer.id,
        customerNameA: customer.displayName,
        customerIdB: storedCustomerId,
        customerNameB: storedCustomerName,
      )) {
        return const [];
      }
      final rowsRaw = payload['rows'];
      if (rowsRaw is! List) return const [];
      final out = <OrderImportItemsWithoutUpcRow>[];
      for (final row in rowsRaw) {
        if (row is Map) {
          out.add(
            OrderImportItemsWithoutUpcRow.fromJson(
              Map<String, dynamic>.from(row),
            ),
          );
        }
      }
      return out;
    } catch (e) {
      debugPrint('[ItemsWithoutUpc] read persisted state failed: $e');
      return const [];
    }
  }

  Future<File> _writeItemsWithoutUpcCsv({
    required String customerDisplayName,
    String? customerId,
    DateTime? exportedOn,
    required List<OrderImportItemsWithoutUpcRow> rows,
  }) async {
    final filename = _buildExportSystemCsvFilename(
      exportType: 'ITEMS_WITHOUT_UPC',
      customerName: customerDisplayName,
      customerId: customerId,
      exportedOn: exportedOn,
    );
    final csvText = _formatItemsWithoutUpcRowsCsv(rows);
    return exportOrderCsvToShowroomExportsLayout(
      customerDisplayName: customerDisplayName,
      filename: filename,
      csvText: csvText,
      persistExportDebugAction: 'items_without_UPC',
    );
  }

  Future<File> _writeItemsNotFoundCsv({
    required String customerDisplayName,
    String? customerId,
    DateTime? exportedOn,
    required List<OrderImportItemsWithoutUpcRow> rows,
  }) async {
    final filename = _buildExportSystemCsvFilename(
      exportType: 'ITEMS_NOT_FOUND',
      customerName: customerDisplayName,
      customerId: customerId,
      exportedOn: exportedOn,
    );
    final csvText = _formatItemsNotFoundRowsCsv(rows);
    return exportOrderCsvToShowroomExportsLayout(
      customerDisplayName: customerDisplayName,
      filename: filename,
      csvText: csvText,
      persistExportDebugAction: 'items_not_found',
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

  /// Temporary trace: active saved quotes for [customer] after order CSV import (grep: [ImportApply]).
  Future<void> _debugLogImportApplyQuoteSnapshot(
    Customer customer,
    String phase,
  ) async {
    if (!kDebugMode) return;
    try {
      final idx = await _loadQuoteIndex();
      final dir = await _getQuotesDirectory();
      final parts = <String>[];
      for (final q in idx) {
        if (!_savedQuoteInfoMatchesCustomer(q, customer)) continue;
        final f = File('${dir.path}/quote_${q.id}.json');
        var lineCount = 0;
        if (await f.exists()) {
          try {
            final raw = await f.readAsString();
            final d = Map<String, dynamic>.from(jsonDecode(raw) as Map);
            final lines =
                d['lines'] as List<dynamic>? ?? d['items'] as List<dynamic>?;
            lineCount = lines?.length ?? 0;
          } catch (_) {}
        }
        parts.add(
          'id=${q.id} logicalBucket=${_logicalQuoteBucketKey(q.quoteBucketKey)} '
          'lines=$lineCount status=${quoteLifecycleStatusToJson(q.status)}',
        );
      }
      debugPrint(
        '[ImportApply] $phase customer="${customer.displayName}" '
        'count=${parts.length} ${parts.join(' || ')}',
      );
    } catch (e) {
      debugPrint('[ImportApply] $phase snapshot failed: $e');
    }
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
      debugPrint(
        '[ExportAll] preSave id=$_currentQuoteId lines=${_orderLines.length}',
      );
      await _saveQuote(notifyOnArchiveSideSave: false);

      await _debugLogActiveIndexSnapshot('ExportAll after save+loadIndex');
      await _debugLogQuoteIndexAuditForCustomer('before Export All');
      final archivedIds = (await _loadArchiveQuoteIndex())
          .map((e) => e.id)
          .toSet();
      var index = await _loadQuoteIndex();
      for (final info in index) {
        if (!_sameLogicalCustomerQuoteRows(
          customerIdA: customer.id,
          customerNameA: customer.displayName,
          customerIdB: info.customerId,
          customerNameB: info.customerName,
        )) {
          continue;
        }
        await _ensureActiveIndexRowForQuoteFile(info.id);
      }
      // Fresh read immediately before candidate selection — do not rely on earlier snapshots.
      index = await _loadQuoteIndex();
      if (kDebugMode) {
        final forCustomer = index
            .where(
              (i) => _sameLogicalCustomerQuoteRows(
                customerIdA: customer.id,
                customerNameA: customer.displayName,
                customerIdB: i.customerId,
                customerNameB: i.customerName,
              ),
            )
            .toList();
        debugPrint(
          '[ExportAll] activeIndexRowsForCustomer=${forCustomer.length} '
          'ids=${forCustomer.map((e) => e.id).join(',')}',
        );
      }
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
      final exportAllBatchTime = DateTime.now();
      final allItemsFilename = _buildExportSystemCsvFilename(
        exportType: 'ALL_EXPORTED_ITEMS',
        customerName: customerName,
        customerId: customer.id,
        exportedOn: exportAllBatchTime,
      );
      final allItemsRows = <String>[
        'Import Status,Quote Number,Customer,PO Number,Quantity,Item Number,Description,UPC,List Price,Price,DISCOUNT,NET,PS,New Release,Whse 1 Availability,Whse 2 Availability,Product Type,Category,Sub-Category,Minimum Order Quantity,Case Quantity',
      ];
      var allItemsImportedRowCount = 0;
      var allItemsNotImportedRowCount = 0;
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
        _debugLogQuoteImportExport(
          '[ExportAll] candidates: ${parts.join('; ')}',
        );
      }

      for (final info in matchingByBucket.values) {
        final bucketLabel = info.quoteBucketLabel.trim().isEmpty
            ? '?'
            : info.quoteBucketLabel;
        if (!exportedQuoteIds.add(info.id)) {
          if (kDebugMode) {
            debugPrint(
              '[ExportAll] candidate quoteId=${info.id} bucket=$bucketLabel '
              'included=no reason=duplicate_id_set',
            );
          }
          continue;
        }
        if (!await _quoteIdHasActiveEligibleRowInActiveIndexStorage(info.id)) {
          if (kDebugMode) {
            debugPrint(
              '[ExportAll] candidate quoteId=${info.id} bucket=$bucketLabel '
              'included=no reason=not_active_eligible_storage',
            );
          }
          _debugLogQuoteLifecycleExport(
            'ExportAll skip id=${info.id} (no active eligible row at export time)',
          );
          continue;
        }
        final quoteFile = File('${quotesDir.path}/quote_${info.id}.json');
        if (!await quoteFile.exists()) {
          if (kDebugMode) {
            debugPrint(
              '[ExportAll] candidate quoteId=${info.id} bucket=$bucketLabel '
              'included=no reason=quote_file_missing',
            );
          }
          skippedMissingOnDisk.add(info.id);
          continue;
        }
        try {
          final quoteRaw = await quoteFile.readAsString();
          final quoteData = Map<String, dynamic>.from(
            jsonDecode(quoteRaw) as Map,
          );
          debugPrint(
            '[ExportAll] disk lines=${quoteDataLineStatsAndTotal(quoteData).$1}',
          );
          if (persistedQuoteDataIsEmptyForReuse(quoteData)) {
            if (kDebugMode) {
              debugPrint(
                '[ExportAll] candidate quoteId=${info.id} bucket=$bucketLabel '
                'included=no reason=persisted_empty',
              );
            }
            _debugLogQuoteImportExport(
              '[ExportAll] skip-empty id=${info.id} '
              'bucket=${_logicalQuoteBucketKey(info.quoteBucketKey)}',
            );
            continue;
          }
          final quoteNameRaw = (quoteData['name'] as String?)?.trim() ?? '';
          final quoteNumber = quoteNameRaw.isNotEmpty
              ? quoteNameRaw
              : info.name.trim();
          final quoteCustomerMap = quoteData['customer'];
          Customer quoteCustomer = customer;
          var quoteCustomerName = customerName;
          if (quoteCustomerMap is Map<String, dynamic>) {
            try {
              quoteCustomer = Customer.fromJson(
                Map<String, dynamic>.from(quoteCustomerMap),
              );
              final n = quoteCustomer.displayName.trim();
              if (n.isNotEmpty) quoteCustomerName = n;
            } catch (_) {}
          }
          final poNumber = ((quoteData['poNumber'] as String?) ??
                  (quoteData['po'] as String?) ??
                  (quoteData['purchaseOrderNumber'] as String?) ??
                  '')
              .trim();
          final quoteLines =
              quoteData['lines'] as List<dynamic>? ??
              quoteData['items'] as List<dynamic>? ??
              const [];
          for (final lineJson in quoteLines) {
            if (lineJson is! Map) continue;
            final lineMap = Map<String, dynamic>.from(lineJson);
            final qty = _quantityFromJson(lineMap['quantity']);
            final product = _productForExportedQuoteLine(lineMap);
            final pricing = _applyPricingLogic(product, quoteCustomer);
            debugPrint(
              '[ExportAllQuotes] exporting item=${product.itemNumber} '
              'description=${product.description} upc=${product.upc} '
              'price=${pricing.price.toStringAsFixed(2)}',
            );
            final row = <String>[
              _csvEscape('IMPORTED'),
              _csvEscape(quoteNumber),
              _csvEscape(quoteCustomerName),
              _csvEscape(poNumber),
              '$qty',
              _csvEscape(_csvPreserveLeadingZerosCell(product.itemNumber)),
              _csvEscape(product.description),
              _csvEscape(_csvPreserveLeadingZerosCell(product.upc)),
              _csvEscape(pricing.listPrice.toStringAsFixed(2)),
              _csvEscape(pricing.price.toStringAsFixed(2)),
              _csvEscape(pricing.discountCol),
              _csvEscape(pricing.netCol),
              _csvEscape(pricing.psCol),
              _csvEscape(product.isNewRelease ? 'YES' : ''),
              _csvEscape(_availabilityLabelForWhse1(product)),
              _csvEscape(_availabilityLabelForWhse2(product)),
              _csvEscape(product.productType),
              _csvEscape(product.category),
              _csvEscape(product.subCategory),
              '${product.minOrderQty}',
              '${product.caseQty}',
            ];
            allItemsRows.add(row.join(','));
            allItemsImportedRowCount++;
          }
          final csvText = _formatQuoteAsCsv(quoteData);
          final exportedOn = DateTime.now();
          final filename = _buildExportOrderCsvFilename(
            quoteName: info.name,
            customerName: customerName,
            customerId: info.customerId,
            quoteData: quoteData,
            customerFolderName: customerName,
            quoteBucketLabel:
                (quoteData['quoteBucketLabel'] as String?)?.trim().isNotEmpty ==
                        true
                    ? (quoteData['quoteBucketLabel'] as String?)?.trim()
                    : info.quoteBucketLabel,
            quoteBucketKey:
                (quoteData['quoteBucketKey'] as String?)?.trim().isNotEmpty ==
                        true
                    ? (quoteData['quoteBucketKey'] as String?)?.trim()
                    : info.quoteBucketKey,
            quoteDate: _quoteDateFromMapOrFallback(quoteData, exportedOn),
            exportedOn: exportedOn,
          );
          final file = await exportOrderCsvToShowroomExportsLayout(
            customerDisplayName: customerName,
            filename: filename,
            csvText: csvText,
            persistExportDebugAction: 'export_all_quotes',
          );
          if (kDebugMode) {
            debugPrint(
              '[ExportAll] candidate quoteId=${info.id} bucket=$bucketLabel '
              'included=yes reason=exported',
            );
            debugPrint('[ExportAll] normal csv added: ${file.path}');
          }
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
          if (kDebugMode) {
            debugPrint(
              '[ExportAll] candidate quoteId=${info.id} bucket=$bucketLabel '
              'included=no reason=export_error',
            );
            debugPrint('[ExportAll] fail id=${info.id} error=$e');
          }
          debugPrint('[OrderExportAll] quote id=${info.id} failed: $e\n$st');
        }
      }

      final notImportedRows = await _resolveLastNotImportedRowsForCustomer(
        customer,
      );
      final itemsWithoutUpcRows = await _resolveItemsWithoutUpcRowsForCustomer(
        customer,
      );
      for (final r in notImportedRows) {
        final itemRaw = r.item;
        final qtyRaw = r.quantity.trim();
        final normalizedItemKey = _piNormalizeItemNumber(
          itemRaw.replaceAll(RegExp(r'[\r\n\t]'), '').trim(),
        );
        debugPrint('[NotImportedExport] raw item=$itemRaw');
        debugPrint('[NotImportedExport] normalized key=$normalizedItemKey');
        final matchedProduct = normalizedItemKey.isEmpty
            ? null
            : _productsByItemNumber[normalizedItemKey];
        debugPrint(
          '[NotImportedExport] item=$itemRaw key=$normalizedItemKey '
          'found=${matchedProduct != null} desc=${matchedProduct?.description} '
          'upc=${matchedProduct?.upc}',
        );
        final pricing = matchedProduct == null
            ? null
            : _applyPricingLogic(matchedProduct, customer);
        final row = <String>[
          _csvEscape('NOT IMPORTED'),
          '',
          _csvEscape(customerName),
          '',
          _csvEscape(qtyRaw),
          _csvEscape(_csvPreserveLeadingZerosCell(itemRaw)),
          _csvEscape(matchedProduct?.description ?? ''),
          _csvEscape(
            _csvPreserveLeadingZerosCell(matchedProduct?.upc.trim() ?? ''),
          ),
          _csvEscape(
            pricing == null ? '' : pricing.listPrice.toStringAsFixed(2),
          ),
          _csvEscape(pricing == null ? '' : pricing.price.toStringAsFixed(2)),
          _csvEscape(pricing?.discountCol ?? ''),
          _csvEscape(pricing?.netCol ?? ''),
          _csvEscape(pricing?.psCol ?? ''),
          _csvEscape(matchedProduct?.isNewRelease == true ? 'YES' : ''),
          _csvEscape(
            matchedProduct == null ? '' : _availabilityLabelForWhse1(matchedProduct),
          ),
          _csvEscape(
            matchedProduct == null ? '' : _availabilityLabelForWhse2(matchedProduct),
          ),
          _csvEscape(matchedProduct?.productType ?? ''),
          _csvEscape(matchedProduct?.category ?? ''),
          _csvEscape(matchedProduct?.subCategory ?? ''),
          matchedProduct == null ? '' : '${matchedProduct.minOrderQty}',
          matchedProduct == null ? '' : '${matchedProduct.caseQty}',
        ];
        allItemsRows.add(row.join(','));
        allItemsNotImportedRowCount++;
      }

      if (itemsWithoutUpcRows.isNotEmpty) {
        final itemsWithoutUpcFile = await _writeItemsWithoutUpcCsv(
          customerDisplayName: customerName,
          customerId: customer.id,
          exportedOn: exportAllBatchTime,
          rows: itemsWithoutUpcRows,
        );
        if (kDebugMode) {
          debugPrint(
            '[ExportAll] ITEMS_WITHOUT_UPC export rows=${itemsWithoutUpcRows.length}',
          );
        }
        exportedFiles.add(itemsWithoutUpcFile);
      }
      final itemsNotFoundRows = itemsWithoutUpcRows
          .where(_itemsWithoutUpcRowIsNotFound)
          .toList();
      debugPrint(
        '[ExportCheck] itemsWithoutUpcRows total=${itemsWithoutUpcRows.length}',
      );
      debugPrint('[ExportCheck] NOT_FOUND rows=${itemsNotFoundRows.length}');
      if (itemsNotFoundRows.isNotEmpty) {
        final itemsNotFoundFile = await _writeItemsNotFoundCsv(
          customerDisplayName: customerName,
          customerId: customer.id,
          exportedOn: exportAllBatchTime,
          rows: itemsNotFoundRows,
        );
        if (kDebugMode) {
          debugPrint(
            '[ExportAll] ITEMS_NOT_FOUND export rows=${itemsNotFoundRows.length}',
          );
        }
        exportedFiles.add(itemsNotFoundFile);
      }

      if (allItemsRows.length > 1) {
        final allItemsFile = await exportOrderCsvToShowroomExportsLayout(
          customerDisplayName: customerName,
          filename: allItemsFilename,
          csvText: allItemsRows.join('\n'),
          persistExportDebugAction: 'export_all_quotes_all_items',
        );
        debugPrint(
          '[ExportAll] ALL_EXPORTED_ITEMS export rows: '
          'IMPORTED=$allItemsImportedRowCount '
          'NOT_IMPORTED=$allItemsNotImportedRowCount '
          'TOTAL=${allItemsImportedRowCount + allItemsNotImportedRowCount}',
        );
        if (kDebugMode) {
          debugPrint('[ExportAll] combined csv added: ${allItemsFile.path}');
        }
        exportedFiles.add(allItemsFile);
      }

      if (mounted && movedToArchiveCount > 0) {
        setState(() {});
      }

      final quoteCsvFilesExported = exportedFiles.length;
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
        quotesExported: quoteCsvFilesExported,
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
      debugPrint(
        '[ExportCurrent] preSave id=$_currentQuoteId lines=${_orderLines.length}',
      );
      await _saveQuote(notifyOnArchiveSideSave: false);
      final currentId = _currentQuoteId;
      if (currentId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Current quote is not available to export.'),
          ),
        );
        return;
      }

      await _ensureActiveIndexRowForQuoteFile(currentId);

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
      debugPrint(
        '[ExportCurrent] disk lines=${quoteDataLineStatsAndTotal(quoteData).$1}',
      );
      if (kDebugMode) {
        final stats = quoteDataLineStatsAndTotal(quoteData);
        debugPrint(
          '[ExportCurrent] quoteId=$currentId lineCount=${stats.$1} '
          'unitCount=${stats.$2}',
        );
      }
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
        customerId: customer.id.trim(),
        quoteData: quoteData,
        customerFolderName: customer.displayName.trim(),
        quoteBucketLabel: (quoteData['quoteBucketLabel'] as String?)?.trim(),
        quoteBucketKey: (quoteData['quoteBucketKey'] as String?)?.trim(),
        quoteDate: _quoteDateFromMapOrFallback(quoteData, exportedOn),
        exportedOn: exportedOn,
      );
      final file = await exportOrderCsvToShowroomExportsLayout(
        customerDisplayName: customer.displayName.trim(),
        filename: filename,
        csvText: csvText,
        persistExportDebugAction: 'export_current_quote',
      );
      if (kDebugMode) {
        debugPrint('[ExportCurrent] wrote path=${file.path}');
      }

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

  /// Collapses all import-merge matches to a single primary line with [newQuantity].
  void _replaceImportMergedOrderLinesQuantity(
    Product product,
    int newQuantity, {
    required int scanIncrement,
  }) {
    final matching = <OrderLine>[];
    for (final line in _orderLines) {
      if (_productsMatchForOrderImportMerge(line.product, product)) {
        matching.add(line);
      }
    }

    if (matching.isEmpty) {
      final key = _orderLineKeyForProduct(product);
      final line = OrderLine(product: product, quantity: newQuantity, scans: 1);
      _orderLines.insert(0, line);
      _orderLineByKey[key] = line;
      return;
    }

    final primary = matching.first;
    for (var i = 1; i < matching.length; i++) {
      final dup = matching[i];
      _orderLineByKey.remove(_orderLineKeyForProduct(dup.product));
      _orderLines.remove(dup);
    }
    primary.quantity = newQuantity;
    primary.scans += scanIncrement;
    _orderLines.remove(primary);
    _orderLines.insert(0, primary);

    final key = _orderLineKeyForProduct(product);
    _orderLineByKey.removeWhere((_, v) => identical(v, primary));
    _orderLineByKey[key] = primary;
  }

  /// Resolves catalog products per CSV row, applies file-side MOQ rounding, and
  /// tags lines that already exist on the order (import merge identity).
  Future<OrderImportPrepareOutcome> _prepareOrderImportLines(
    List<OrderImportCsvRow> rows, {
    required int totalRowsProcessed,
  }) async {
    const int matchBatchSize = 250;
    const int progressLogInterval = 1000;
    var csvMoqAdjustedRows = 0;
    final skippedRows = <OrderImportSkippedRow>[];
    final itemsWithoutUpcRows = <OrderImportItemsWithoutUpcRow>[];

    String? normalizedUpcForImportMerge(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
      final digits = digitsOnly(compact);
      if (digits.isNotEmpty) {
        if (RegExp(r'^0+$').hasMatch(digits)) return null;
        return digits;
      }
      final upper = compact.toUpperCase();
      if (upper.isEmpty) return null;
      if (RegExp(r'^0+$').hasMatch(upper)) return null;
      return upper;
    }

    String? normalizedItemForImportMerge(String raw) {
      final n = normalizeItemNumber(raw);
      return n.isEmpty ? null : n;
    }

    String canonicalUpcMergeKey(String upc) {
      if (upc.length == 12 && upc.startsWith('0')) {
        return upc.substring(1);
      }
      return upc;
    }

    Product? lookupByUpcOnly(String raw) {
      final upc = _orderImportNormalizeUpcLookupKey(raw);
      if (upc.isEmpty) return null;
      Product? product = _productsByUpc[upc];
      if (product == null && upc.length == 12 && upc.startsWith('0')) {
        product = _productsByUpc[upc.substring(1)];
      }
      if (product == null && upc.length == 11) {
        product = _productsByUpc['0$upc'];
      }
      return product;
    }

    final numericItemFallbackWidths =
        _productsByItemNumber.keys
            .where((k) => RegExp(r'^\d+$').hasMatch(k))
            .map((k) => k.length)
            .toSet()
            .toList()
          ..sort();

    Product? lookupByItemNumberOnly(String raw) {
      final itemKey = _orderImportNormalizeItemKey(raw);
      if (itemKey.isEmpty) return null;
      final direct = _productsByItemNumber[itemKey];
      if (direct != null) return direct;
      if (!RegExp(r'^\d+$').hasMatch(itemKey)) return null;
      for (final width in numericItemFallbackWidths) {
        if (width <= itemKey.length) continue;
        final padded = itemKey.padLeft(width, '0');
        final paddedMatch = _productsByItemNumber[padded];
        if (paddedMatch != null) return paddedMatch;
      }
      return null;
    }

    final qtyByUpcMergeKey = <String, int>{};
    final qtyByItemMergeKeyWithoutUpc = <String, int>{};
    for (final line in _orderLines) {
      final lineUpc = normalizedUpcForImportMerge(line.product.upc);
      if (lineUpc != null) {
        final key = canonicalUpcMergeKey(lineUpc);
        qtyByUpcMergeKey[key] = (qtyByUpcMergeKey[key] ?? 0) + line.quantity;
        continue;
      }
      final lineItem = normalizedItemForImportMerge(line.product.itemNumber);
      if (lineItem != null) {
        qtyByItemMergeKeyWithoutUpc[lineItem] =
            (qtyByItemMergeKeyWithoutUpc[lineItem] ?? 0) + line.quantity;
      }
    }

    final lines = <OrderImportPreparedLine>[];
    print('[ImportPrepare] total rows=${rows.length}');
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final item = r.item;
      final rowQuantity = r.quantity;
      final explicitUpc = r.upc.trim();
      print('[ImportPrepare] processing item=$item upc=$explicitUpc');
      print(
        '[ImportPrepare] row item=$item upc=$explicitUpc qty=$rowQuantity',
      );
      final hasExplicitUpc = explicitUpc.isNotEmpty;
      final matchedByUpc = hasExplicitUpc ? lookupByUpcOnly(explicitUpc) : null;
      final matchedByItemNumber = lookupByItemNumberOnly(item);
      final product = matchedByUpc ?? matchedByItemNumber;
      final upcMatched = hasExplicitUpc && matchedByUpc != null;
      final itemNumberMatched = matchedByItemNumber != null;
      final shouldReportMissingOrFailedUpc = !upcMatched && product != null;
      if (shouldReportMissingOrFailedUpc) {
        final resolved = itemNumberMatched;
        itemsWithoutUpcRows.add(
          OrderImportItemsWithoutUpcRow(
            itemNumber: item,
            quantity: rowQuantity,
            originalUpc: explicitUpc,
            resolutionStatus: resolved
                ? 'RESOLVED_BY_ITEM_NUMBER'
                : 'NOT_FOUND',
            description: resolved ? product.description : '',
            price: resolved ? product.price.toStringAsFixed(2) : '',
            minimumOrderQuantity: resolved ? '${product.minOrderQty}' : '',
            caseQuantity: resolved ? '${product.caseQty}' : '',
          ),
        );
      }
      if (product == null) {
        print('[ItemsNotFound] captured item=$item');
        print(
          '[ItemsNotFound] captured item=$item upc=$explicitUpc qty=$rowQuantity',
        );
        itemsWithoutUpcRows.add(
          OrderImportItemsWithoutUpcRow(
            itemNumber: item,
            quantity: rowQuantity,
            originalUpc: explicitUpc,
            resolutionStatus: 'NOT_FOUND',
            description: '',
            price: '',
            minimumOrderQuantity: '',
            caseQuantity: '',
          ),
        );
        skippedRows.add(
          OrderImportSkippedRow(
            item: item,
            quantity: rowQuantity.toString(),
            description: r.description,
            price: r.price,
            reason: 'Item not found',
          ),
        );
        continue;
      }
      final importedQty = _nearestValidMoqMultiple(
        requestedQty: rowQuantity,
        minOrderQty: product.minOrderQty,
      );
      if (importedQty != rowQuantity) {
        csvMoqAdjustedRows++;
      }
      int? existingSum;
      final productUpc = normalizedUpcForImportMerge(product.upc);
      if (productUpc != null) {
        existingSum = qtyByUpcMergeKey[canonicalUpcMergeKey(productUpc)];
      } else {
        final productItem = normalizedItemForImportMerge(product.itemNumber);
        if (productItem != null) {
          existingSum = qtyByItemMergeKeyWithoutUpc[productItem];
        }
      }
      lines.add(
        OrderImportPreparedLine(
          displayItem: item,
          product: product,
          importedQtyMoq: importedQty,
          rawCsvCombinedQty: rowQuantity,
          existingOrderQtySum: existingSum,
          sourceDescription: r.description,
          sourcePrice: r.price,
        ),
      );
      debugPrint(
        '[ImportOrderLine] creating matched line item=$item '
        'productDescription=${product.description} productUpc=${product.upc}',
      );
      if (productUpc != null) {
        final key = canonicalUpcMergeKey(productUpc);
        qtyByUpcMergeKey[key] = (qtyByUpcMergeKey[key] ?? 0) + importedQty;
      } else {
        final productItem = normalizedItemForImportMerge(product.itemNumber);
        if (productItem != null) {
          qtyByItemMergeKeyWithoutUpc[productItem] =
              (qtyByItemMergeKeyWithoutUpc[productItem] ?? 0) + importedQty;
        }
      }

      final processed = i + 1;
      if (processed % progressLogInterval == 0) {
        debugPrint('[ImportOrder] match progress: $processed/${rows.length}');
      }
      if (processed % matchBatchSize == 0) {
        // Yield to keep the UI responsive during large imports.
        await Future<void>.delayed(Duration.zero);
      }
    }
    final notFoundCount = itemsWithoutUpcRows
        .where(_itemsWithoutUpcRowIsNotFound)
        .length;
    print(
      '[ImportPrepare] itemsWithoutUpcRows total=${itemsWithoutUpcRows.length}',
    );
    print('[ImportPrepare] NOT_FOUND count=$notFoundCount');
    return OrderImportPrepareOutcome(
      lines: lines,
      skippedRows: skippedRows,
      itemsWithoutUpcRows: itemsWithoutUpcRows,
      csvMoqAdjustedRows: csvMoqAdjustedRows,
      totalRowsProcessed: totalRowsProcessed,
    );
  }

  Future<OrderImportApplyOutcome?> _applyOrderImportPrepareOutcome({
    required OrderImportPrepareOutcome prepare,
    required List<OrderImportDuplicateResolution> duplicateChoices,
  }) async {
    final expectedDupes = prepare.lines
        .where((OrderImportPreparedLine l) => l.isDuplicate)
        .length;
    if (duplicateChoices.length != expectedDupes) {
      debugPrint(
        '[OrderImport] duplicate choice mismatch: got ${duplicateChoices.length} '
        'expected $expectedDupes — aborting apply',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Import could not apply duplicate resolutions '
              '(${duplicateChoices.length} vs $expectedDupes). Try again.',
            ),
          ),
        );
      }
      return null;
    }

    var importedRows = 0;
    var moqAdjustedRows = prepare.csvMoqAdjustedRows;
    var newItemsCount = 0;
    var duplicateChoiceTotalQtyCount = 0;
    var duplicateChoiceMinimumQtyCount = 0;
    var duplicateChoiceSkipCount = 0;
    var duplicateChoiceUseImportedQtyCount = 0;
    final importedQuantityByBucket = <String, int>{};
    final skippedRows = <OrderImportSkippedRow>[...prepare.skippedRows];
    var dupIndex = 0;

    for (final line in prepare.lines) {
      try {
        if (!line.isDuplicate) {
          await _ensureRoutingForProduct(line.product);
          _mergeImportedProductIntoOrder(line.product, line.importedQtyMoq);
          importedRows++;
          newItemsCount++;
          _addImportedUnitsToQuoteBucketMap(
            line.product,
            line.importedQtyMoq,
            importedQuantityByBucket,
          );
          continue;
        }

        final choice = duplicateChoices[dupIndex++];
        switch (choice) {
          case OrderImportDuplicateResolution.skip:
            importedRows++;
            duplicateChoiceSkipCount++;
            break;
          case OrderImportDuplicateResolution.totalQty:
            await _ensureRoutingForProduct(line.product);
            final existing = line.existingOrderQtySum!;
            final raw = existing + line.importedQtyMoq;
            final finalQty = _nearestValidMoqMultiple(
              requestedQty: raw,
              minOrderQty: line.product.minOrderQty,
            );
            if (finalQty != raw) moqAdjustedRows++;
            _replaceImportMergedOrderLinesQuantity(
              line.product,
              finalQty,
              scanIncrement: 1,
            );
            importedRows++;
            duplicateChoiceTotalQtyCount++;
            _addImportedUnitsToQuoteBucketMap(
              line.product,
              line.importedQtyMoq,
              importedQuantityByBucket,
            );
            break;
          case OrderImportDuplicateResolution.minimumQty:
            await _ensureRoutingForProduct(line.product);
            final existing = line.existingOrderQtySum!;
            final raw = existing < line.importedQtyMoq
                ? existing
                : line.importedQtyMoq;
            final finalQty = _nearestValidMoqMultiple(
              requestedQty: raw,
              minOrderQty: line.product.minOrderQty,
            );
            if (finalQty != raw) moqAdjustedRows++;
            _replaceImportMergedOrderLinesQuantity(
              line.product,
              finalQty,
              scanIncrement: 1,
            );
            importedRows++;
            duplicateChoiceMinimumQtyCount++;
            _addImportedUnitsToQuoteBucketMap(
              line.product,
              line.importedQtyMoq,
              importedQuantityByBucket,
            );
            break;
          case OrderImportDuplicateResolution.useImportedQty:
            await _ensureRoutingForProduct(line.product);
            final raw = line.importedQtyMoq;
            final finalQty = _nearestValidMoqMultiple(
              requestedQty: raw,
              minOrderQty: line.product.minOrderQty,
            );
            if (finalQty != raw) moqAdjustedRows++;
            _replaceImportMergedOrderLinesQuantity(
              line.product,
              finalQty,
              scanIncrement: 1,
            );
            importedRows++;
            duplicateChoiceUseImportedQtyCount++;
            _addImportedUnitsToQuoteBucketMap(
              line.product,
              line.importedQtyMoq,
              importedQuantityByBucket,
            );
            break;
        }
      } catch (e) {
        skippedRows.add(
          OrderImportSkippedRow(
            item: line.displayItem,
            quantity: line.rawCsvCombinedQty.toString(),
            description: line.sourceDescription,
            price: line.sourcePrice,
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
      totalRowsProcessed: prepare.totalRowsProcessed,
      newItemsCount: newItemsCount,
      duplicateChoiceTotalQtyCount: duplicateChoiceTotalQtyCount,
      duplicateChoiceMinimumQtyCount: duplicateChoiceMinimumQtyCount,
      duplicateChoiceSkipCount: duplicateChoiceSkipCount,
      duplicateChoiceUseImportedQtyCount: duplicateChoiceUseImportedQtyCount,
    );
  }

  void _addImportedUnitsToQuoteBucketMap(
    Product product,
    int importedQtyMoq,
    Map<String, int> importedQuantityByBucket,
  ) {
    final bucket = _resolveQuoteBucketForProduct(product);
    final label = bucket.displayLabel.trim().isEmpty
        ? 'EVERYDAY'
        : bucket.displayLabel.trim().toUpperCase();
    importedQuantityByBucket.update(
      label,
      (value) => value + importedQtyMoq,
      ifAbsent: () => importedQtyMoq,
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

  Future<void> _showOrderImportSummaryDialog({
    required String filesImportedDescription,
    required OrderImportApplyOutcome applyOutcome,
    required int notImportedRowCount,
  }) async {
    final dupUse = applyOutcome.duplicateChoiceUseImportedQtyCount;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Import Summary'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Files imported: $filesImportedDescription'),
                const SizedBox(height: 8),
                Text(
                  'Total rows processed: ${applyOutcome.totalRowsProcessed}',
                ),
                const SizedBox(height: 16),
                Text('New Items Added: ${applyOutcome.newItemsCount}'),
                const SizedBox(height: 12),
                Text(
                  'Duplicates Resolved: ${applyOutcome.duplicateItemsCount}',
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total qty: ${applyOutcome.duplicateChoiceTotalQtyCount}',
                      ),
                      Text(
                        'Minimum qty: ${applyOutcome.duplicateChoiceMinimumQtyCount}',
                      ),
                      Text('Skipped: ${applyOutcome.duplicateChoiceSkipCount}'),
                      if (dupUse > 0) Text('Use imported qty: $dupUse'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('MOQ Adjustments: ${applyOutcome.moqAdjustedCount}'),
                const SizedBox(height: 12),
                Text('Items Not Imported: $notImportedRowCount'),
              ],
            ),
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

  /// Import merge only: normalized UPC (when both meaningful), else item/SKU;
  /// if only one side has UPC, still merge when normalized item numbers match.
  bool _productsMatchForOrderImportMerge(Product a, Product b) {
    String? normalizedUpcForMerge(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
      final digits = digitsOnly(compact);
      if (digits.isNotEmpty) {
        if (RegExp(r'^0+$').hasMatch(digits)) return null;
        return digits;
      }
      final upper = compact.toUpperCase();
      if (upper.isEmpty) return null;
      if (RegExp(r'^0+$').hasMatch(upper)) return null;
      return upper;
    }

    String? normalizedItemForMerge(String raw) {
      final n = normalizeItemNumber(raw);
      return n.isEmpty ? null : n;
    }

    bool upcDigitsEquivalent(String x, String y) {
      if (x == y) return true;
      if (x.length == 12 && x.startsWith('0') && x.substring(1) == y) {
        return true;
      }
      if (y.length == 12 && y.startsWith('0') && y.substring(1) == x) {
        return true;
      }
      if (x.length == 11 && y == '0$x') return true;
      if (y.length == 11 && x == '0$y') return true;
      return false;
    }

    final aUpc = normalizedUpcForMerge(a.upc);
    final bUpc = normalizedUpcForMerge(b.upc);
    final aItem = normalizedItemForMerge(a.itemNumber);
    final bItem = normalizedItemForMerge(b.itemNumber);

    if (aUpc != null && bUpc != null) {
      return upcDigitsEquivalent(aUpc, bUpc);
    }
    // At least one side lacks a usable UPC: merge on item/SKU when both present.
    return aItem != null && bItem != null && aItem == bItem;
  }

  void _mergeImportedProductIntoOrder(Product product, int addQty) {
    final matching = <OrderLine>[];
    for (final line in _orderLines) {
      if (_productsMatchForOrderImportMerge(line.product, product)) {
        matching.add(line);
      }
    }

    if (matching.isEmpty) {
      final key = _orderLineKeyForProduct(product);
      final line = OrderLine(product: product, quantity: addQty, scans: 1);
      _orderLines.insert(0, line);
      _orderLineByKey[key] = line;
      return;
    }

    final primary = matching.first;
    var qtyToAdd = addQty;
    for (var i = 1; i < matching.length; i++) {
      final dup = matching[i];
      qtyToAdd += dup.quantity;
      _orderLineByKey.remove(_orderLineKeyForProduct(dup.product));
      _orderLines.remove(dup);
    }
    primary.quantity += qtyToAdd;
    primary.scans += 1;
    _orderLines.remove(primary);
    _orderLines.insert(0, primary);

    final key = _orderLineKeyForProduct(product);
    _orderLineByKey.removeWhere((_, v) => identical(v, primary));
    _orderLineByKey[key] = primary;
  }

  void _syncItemsScannedFromOrderLines() {
    var sum = 0;
    for (final l in _orderLines) {
      sum += l.scans;
    }
    _itemsScanned = sum;
  }

  Future<void> _pickAndImportOrderCsv() async {
    print('🔥 IMPORT ENTRY HIT 🔥');
    if (_loadingProducts) return;
    if (_orderCsvImportInProgress) return;
    _orderCsvImportInProgress = true;
    _orderImportRouteTraceKeys.clear();
    _orderImportTouchedQuoteIds.clear();
    try {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Select Order File'),
          content: const Text(
            'Please choose your file from:\nOneDrive → Import folder',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed != true) return;

      _editDialogOpen = true;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
        withData: true,
        allowMultiple: true,
      );
      _editDialogOpen = false;
      debugPrint(
        '[ImportOrder] picker returned '
        '${result == null ? 'cancel' : '${result.files.length} file(s)'}',
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final combinedRows = <OrderImportCsvRow>[];
      final allParseSkipped = <OrderImportSkippedRow>[];
      final contributingFileNames = <String>[];

      for (final file in result.files) {
        print(
          '[ImportOrderFile] picked file name=${file.name} path=${file.path ?? '(none)'} bytes=${file.bytes?.length ?? 0}',
        );
        debugPrint('[ImportOrder] file name: ${file.name}');
        debugPrint('[ImportOrder] path: ${file.path ?? '(none)'}');
        debugPrint(
          '[ImportOrder] bytes length: ${file.bytes?.length ?? 0}',
        );

        final ext = p.extension(file.name).toLowerCase();
        final isExcel = _orderImportIsExcelFileName(file.name);
        List<int>? fileBytes = file.bytes;
        if (fileBytes == null && file.path != null && file.path!.isNotEmpty) {
          fileBytes = await File(file.path!).readAsBytes();
        }

        if (fileBytes == null) {
          throw FormatException(
            'Could not read "${file.name}". The file provider returned no path '
            'and no bytes. Try downloading it locally and import again.',
          );
        }
        print('[ImportFile] path=${file.path ?? '(none)'}');
        print('[ImportFile] bytes=${fileBytes.length}');
        debugPrint('[ImportOrder] raw length: ${fileBytes.length}');

        try {
          debugPrint('[ImportOrder] parse starting');
          final outcome = isExcel
              ? parseOrderImportExcelBytes(fileBytes, sourceLabel: file.name)
              : () {
                  final bytesForDebug = fileBytes;
                  print('[ImportFile] bytes=${bytesForDebug?.length ?? 0}');
                  if (bytesForDebug != null) {
                    final rawText = utf8.decode(
                      bytesForDebug,
                      allowMalformed: true,
                    );
                    print('[ImportFile] path=${file.path ?? file.name}');
                    print('[ImportFile] bytes=${bytesForDebug.length}');
                    print(
                      '[ImportFile] text contains 12322255=${rawText.contains('12322255')}',
                    );
                    return parseOrderImportCsv(rawText);
                  } else {
                    print('[ImportFile] path=${file.path ?? file.name}');
                    print('[ImportFile] bytes=0');
                    print('[ImportFile] text contains 12322255=false');
                    throw FormatException(
                      'Could not read "${file.name}". The file provider returned no path '
                      'and no bytes. Try downloading it locally and import again.',
                    );
                  }
                }();
          debugPrint('[ImportOrder] parse complete: rows=${outcome.rows.length}');
          combinedRows.addAll(outcome.rows);
          allParseSkipped.addAll(outcome.skippedRows);
          contributingFileNames.add(file.name);
        } on FormatException catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            SnackBar(
              content: Text(
                '${file.name}: ${e.message} '
                '(detected type: ${ext.isEmpty ? 'unknown' : ext})',
              ),
            ),
          );
          return;
        } catch (e) {
          debugPrint('[ImportOrder] import failed: $e');
          rethrow;
        }
      }

      if (combinedRows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid rows to import from selected files.'),
          ),
        );
        return;
      }

      final sourceFileLabel = contributingFileNames.length == 1
          ? contributingFileNames.single
          : '${contributingFileNames.length} files: '
                '${contributingFileNames.join(', ')}';

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

      _quoteImportDebugSession = kDebugMode
          ? 'imp_${DateTime.now().millisecondsSinceEpoch}'
          : null;
      _quoteImportLoggedBucketKeys.clear();
      debugPrint('[ImportOrder] import started');
      final totalRowsProcessed = combinedRows.length + allParseSkipped.length;
      debugPrint('[ImportOrder] match starting');
      final prepare = await _prepareOrderImportLines(
        combinedRows,
        totalRowsProcessed: totalRowsProcessed,
      );
      final duplicateLines = prepare.lines
          .where((l) => l.isDuplicate)
          .toList(growable: false);
      final List<OrderImportDuplicateResolution> dupChoices;
      if (duplicateLines.isEmpty) {
        dupChoices = const [];
      } else {
        if (!mounted) return;
        final fromDialog =
            await showDialog<List<OrderImportDuplicateResolution>>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) =>
                  _OrderImportDuplicateReviewDialog(items: duplicateLines),
            );
        if (fromDialog == null) return;
        dupChoices = fromDialog;
      }
      final applyOutcome = await _applyOrderImportPrepareOutcome(
        prepare: prepare,
        duplicateChoices: dupChoices,
      );
      debugPrint('[ImportOrder] match complete');
      if (applyOutcome == null) {
        return;
      }
      debugPrint('[ImportOrder] quote save starting');
      await _saveQuote();
      debugPrint('[ImportOrder] quote save complete');
      await _pruneSupersededEmptyDuplicateQuotesForCustomer(_selectedCustomer!);
      await _syncOrderImportTouchedQuotesInActiveIndex();
      await _debugLogImportApplyQuoteSnapshot(
        _selectedCustomer!,
        'after import save+prune',
      );
      await _debugLogQuoteIndexAuditForCustomer('after import (persisted)');
      final skippedRows = <OrderImportSkippedRow>[
        ...allParseSkipped,
        ...applyOutcome.skippedRows,
      ];
      _lastItemsWithoutUpcRows = List<OrderImportItemsWithoutUpcRow>.from(
        prepare.itemsWithoutUpcRows,
      );
      _lastItemsWithoutUpcRowsCustomerId = _selectedCustomer!.id;
      _lastItemsWithoutUpcRowsCustomerName = _selectedCustomer!.displayName;
      await _persistItemsWithoutUpcRowsForCustomer(
        _selectedCustomer!,
        _lastItemsWithoutUpcRows,
      );
      if (skippedRows.isNotEmpty) {
        _lastItemsNotImportedRows = List<OrderImportSkippedRow>.from(skippedRows);
        _lastItemsNotImportedRowsCustomerId = _selectedCustomer!.id;
        _lastItemsNotImportedRowsCustomerName = _selectedCustomer!.displayName;
      } else {
        _lastItemsNotImportedRows = const [];
        _lastItemsNotImportedRowsCustomerId = null;
        _lastItemsNotImportedRowsCustomerName = null;
      }

      final quoteIdToSync = _currentQuoteId;
      if (quoteIdToSync != null) {
        await _loadQuoteById(quoteIdToSync);
        if (kDebugMode) {
          debugPrint('[ImportSync] quote reloaded id=$quoteIdToSync');
        }
      }
      await _loadQuoteIndex();

      if (!mounted) return;
      setState(() {
        if (quoteIdToSync == null) {
          _syncItemsScannedFromOrderLines();
          _recalculateTotals();
          _orderListVersion += 1;
          if (_orderLines.isNotEmpty) {
            _selectedLine = _orderLines.first;
            _lastAddedUpc = _orderLines.first.product.upc;
          }
        }
        _status = 'Imported order from $sourceFileLabel';
      });
      _maybeNavigateToECatalogTab(_ECatalogNavigationSource.importOrder);

      if (!mounted) return;
      await _showOrderImportSummaryDialog(
        filesImportedDescription: sourceFileLabel,
        applyOutcome: applyOutcome,
        notImportedRowCount: skippedRows.length,
      );
      debugPrint('[ImportOrder] import success');
    } catch (e, st) {
      _editDialogOpen = false;
      debugPrint('[ImportOrder] import failed: $e');
      debugPrint('[OrderImport] failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            'Import failed: ${e is FormatException ? e.message : e.toString()}',
          ),
        ),
      );
    } finally {
      _quoteImportDebugSession = null;
      _quoteImportLoggedBucketKeys.clear();
      _orderCsvImportInProgress = false;
    }
  }

  Future<void> _parseAndStoreProducts(
    String rawCsv, {
    required String sourceLabel,
  }) async {
    final result = await compute(
      _parseProductsCatalogCsvIsolate,
      _ProductsCsvIsolateJob(rawCsv: rawCsv, sourceLabel: sourceLabel),
    );

    _productsByUpc
      ..clear()
      ..addAll(result.productsByUpc);

    _productsByItemNumber
      ..clear()
      ..addAll(result.productsByItemNumber);

    _catalogCount = result.catalogCount;
    _catalogSource = result.catalogSource;

    _productsLoadDebugLine = result.productsLoadDebugLine;

    debugPrint(
      '[ProductsLoad] productsByItemNumber count=${_productsByItemNumber.length}',
    );
    debugPrint('[ProductsLoad] productsByUpc count=${_productsByUpc.length}');
    debugPrint(
      '[ProductsLoad] contains item 13932=${_productsByItemNumber.containsKey('13932')}',
    );

    if (!result.isEmptyFile) {
      _debugLogMissingProductTypeMappings();
    }
  }

  Future<void> _loadProductsOnStartup() async {
    await _loadQuoteBucketConfig();
    final ok = await _loadProductsFromWeb();
    if (ok) {
      await _initAudio();
      if (mounted) {
        setState(() {
          _loadingProducts = false;
          _readyToScan = true;
          _status = 'Ready to scan';
        });
        _requestScannerFocusAfterCatalogReady();
      }
      return;
    }
    await _loadProductsFromAssets();
  }

  Future<void> _loadProductsFromAssets() async {
    if (kDebugMode) debugPrint('[Products] _loadProductsFromAssets called');
    try {
      if (kDebugMode) {
        debugPrint('[Products] Attempting to load assets/data/products.csv');
      }
      await Future<void>.delayed(_startupBundleLoadDelay);
      if (!mounted) return;
      final rawCsv = await rootBundle.loadString('assets/data/products.csv');
      if (kDebugMode) {
        debugPrint(
          '[Products] products.csv loaded successfully '
          '(${rawCsv.length} characters)',
        );
        debugPrint('[Products] parse started');
      }
      await _parseAndStoreProducts(rawCsv, sourceLabel: 'Built-in catalog');
      if (kDebugMode) debugPrint('[Products] parse completed');

      await _initAudio();

      setState(() {
        _loadingProducts = false;
        _readyToScan = true;
        _status = 'Ready to scan';
      });

      _requestScannerFocusAfterCatalogReady();
    } catch (e, st) {
      debugPrint('[Products] Error loading built-in products.csv: $e');
      debugPrint('[Products] Stack: $st');
      await _initAudio();
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
      await Future<void>.delayed(_startupBundleLoadDelay);
      if (!mounted) return;
      final rawCsv = await rootBundle.loadString('assets/data/customers.csv');
      debugPrint(
        '[Customers] customers.csv loaded successfully '
        '(${rawCsv.length} characters)',
      );
      await _parseAndStoreCustomers(rawCsv);
      debugPrint('[Customers] parse completed');
    } catch (e, st) {
      debugPrint('[Customers] Failed to load assets/data/customers.csv: $e');
      debugPrint('[Customers] Stack: $st');
      if (mounted) {
        setState(() {
          _customers = [];
          _customersByKey.clear();
          _selectedCustomer = null;
          _syncCustomerWalkOrderEnabledForCustomer(null);
          debugPrint('[WalkOrder] sync source: customers load failure');
          _customersLoadDebugLine =
              'Customers Loaded: FAILED (see debug log for $e)';
        });
      } else {
        _customers = [];
        _customersByKey.clear();
        _selectedCustomer = null;
        _syncCustomerWalkOrderEnabledForCustomer(null);
        debugPrint('[WalkOrder] sync source: customers load failure');
      }
      scheduleMicrotask(() => _reapplyLocalAddedCustomers());
      _discardWorkingOrderIfNoCustomerSelected();
    }
  }

  Future<void> _debugLoadCustomerWalkOrderCsv() async {
    try {
      final rawCsv =
          await rootBundle.loadString('assets/data/customer_walk_order.csv');
      final lines = const LineSplitter().convert(rawCsv);
      List<List<dynamic>> rows;
      try {
        rows = const CsvToListConverter(
          shouldParseNumbers: false,
        ).convert(rawCsv);
      } catch (e) {
        _customerWalkOrderByCustomerAndItem.clear();
        debugPrint('[WalkOrder] CSV parse failed: $e');
        debugPrint('[WalkOrder] total CSV lines: ${lines.length}');
        return;
      }

      if (rows.isEmpty) {
        _customerWalkOrderByCustomerAndItem.clear();
        debugPrint('[WalkOrder] total CSV lines: ${lines.length}');
        debugPrint('[WalkOrder] total parsed rows: 0');
        debugPrint('[WalkOrder] number of customers found: 0');
        debugPrint('[WalkOrder] customer 302021 rows: 0');
        debugPrint('[WalkOrder] NeverAdd YES rows: 0');
        debugPrint('[WalkOrder] rows with WalkPosition: 0');
        debugPrint('[WalkOrder] rows with SubPosition: 0');
        return;
      }

      final header = rows.first.map((e) => e.toString().trim()).toList();
      int headerIndex(String name) {
        final wanted = name.trim().toLowerCase();
        for (var i = 0; i < header.length; i++) {
          if (header[i].toLowerCase() == wanted) return i;
        }
        return -1;
      }

      final idxCustomerId = headerIndex('CustomerID');
      final idxItemNumber = headerIndex('Item Number');
      final idxDescription = headerIndex('Description');
      final idxCategory = headerIndex('Category');
      final idxSubCategory = headerIndex('Sub-Category');
      final idxWalkPosition = headerIndex('WalkPosition');
      final idxSubPosition = headerIndex('SubPosition');
      final idxNeverAdd = headerIndex('NeverAdd');
      final idxNeverAddReason = headerIndex('NeverAddReason');
      final idxWalkEnabled = headerIndex('WalkEnabled');

      if (idxCustomerId < 0 || idxItemNumber < 0) {
        _customerWalkOrderByCustomerAndItem.clear();
        debugPrint(
          '[WalkOrder] Missing required columns. '
          'CustomerID=$idxCustomerId Item Number=$idxItemNumber',
        );
        debugPrint('[WalkOrder] total CSV lines: ${lines.length}');
        debugPrint('[WalkOrder] total parsed rows: 0');
        debugPrint('[WalkOrder] number of customers found: 0');
        debugPrint('[WalkOrder] customer 302021 rows: 0');
        debugPrint('[WalkOrder] NeverAdd YES rows: 0');
        debugPrint('[WalkOrder] rows with WalkPosition: 0');
        debugPrint('[WalkOrder] rows with SubPosition: 0');
        return;
      }

      String cell(List<dynamic> row, int idx) {
        if (idx < 0 || idx >= row.length) return '';
        return row[idx].toString().trim();
      }

      int? parseNullableInt(String raw) {
        final t = raw.trim();
        if (t.isEmpty) return null;
        return int.tryParse(t);
      }

      bool parseYesNo(String raw, {required bool blankDefault}) {
        final t = raw.trim();
        if (t.isEmpty) return blankDefault;
        final upper = t.toUpperCase();
        if (upper == 'YES' || upper == 'Y' || upper == 'TRUE' || upper == '1') {
          return true;
        }
        if (upper == 'NO' || upper == 'N' || upper == 'FALSE' || upper == '0') {
          return false;
        }
        return blankDefault;
      }

      final parsed = <String, Map<String, CustomerWalkOrderRow>>{};
      var parsedRows = 0;
      var neverAddYesRows = 0;
      var rowsWithWalkPosition = 0;
      var rowsWithSubPosition = 0;

      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        final customerId = cell(row, idxCustomerId);
        final itemNumber = cell(row, idxItemNumber);
        if (customerId.isEmpty || itemNumber.isEmpty) continue;

        final walkPosition = parseNullableInt(cell(row, idxWalkPosition));
        final subPosition = parseNullableInt(cell(row, idxSubPosition));
        final neverAdd = parseYesNo(
          cell(row, idxNeverAdd),
          blankDefault: false,
        );
        final walkEnabled = parseYesNo(
          cell(row, idxWalkEnabled),
          blankDefault: true,
        );
        final rowData = CustomerWalkOrderRow(
          customerId: customerId,
          itemNumber: itemNumber,
          description: cell(row, idxDescription),
          category: cell(row, idxCategory),
          subCategory: cell(row, idxSubCategory),
          walkPosition: walkPosition,
          subPosition: subPosition,
          neverAdd: neverAdd,
          neverAddReason: cell(row, idxNeverAddReason),
          walkEnabled: walkEnabled,
        );

        final byItem = parsed.putIfAbsent(customerId, () => {});
        byItem[itemNumber] = rowData;
        parsedRows++;
        if (neverAdd) neverAddYesRows++;
        if (walkPosition != null) rowsWithWalkPosition++;
        if (subPosition != null) rowsWithSubPosition++;
      }

      _customerWalkOrderByCustomerAndItem
        ..clear()
        ..addAll(parsed);

      final customer302021Rows =
          _customerWalkOrderByCustomerAndItem['302021']?.length ?? 0;
      debugPrint('[WalkOrder] total CSV lines: ${lines.length}');
      debugPrint('[WalkOrder] total parsed rows: $parsedRows');
      debugPrint(
        '[WalkOrder] number of customers found: '
        '${_customerWalkOrderByCustomerAndItem.length}',
      );
      debugPrint('[WalkOrder] customer 302021 rows: $customer302021Rows');
      debugPrint('[WalkOrder] NeverAdd YES rows: $neverAddYesRows');
      debugPrint('[WalkOrder] rows with WalkPosition: $rowsWithWalkPosition');
      debugPrint('[WalkOrder] rows with SubPosition: $rowsWithSubPosition');
    } catch (e, st) {
      debugPrint('[WalkOrder] ERROR $e');
      debugPrint('[WalkOrder] ERROR stack: $st');
    }
  }

  /// Read-only walk order CSV inspection (not wired into scanning or exports).
  void _openWalkOrderViewer() {
    final snapshot =
        UnmodifiableMapView<String, Map<String, CustomerWalkOrderRow>>(
      _customerWalkOrderByCustomerAndItem.map(
        (k, v) => MapEntry(
          k,
          UnmodifiableMapView<String, CustomerWalkOrderRow>(v),
        ),
      ),
    );
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) =>
            _WalkOrderViewerPage(walkOrderByCustomer: snapshot),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _loadCsvFromPhone() async {
    print('🔥 IMPORT ENTRY HIT 🔥');
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

      if (kDebugMode) debugPrint('[Products] parse started (phone CSV)');
      await _parseAndStoreProducts(rawCsv, sourceLabel: file.name);
      if (kDebugMode) {
        debugPrint('[Products] parse completed (phone CSV)');
        debugPrint(
          '[Products] Loaded CSV from phone "${file.name}" '
          '(${rawCsv.length} characters). Catalog now has $_catalogCount '
          'products from source "$_catalogSource".',
        );
      }

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

  Future<bool> _loadProductsFromWeb() async {
    if (_loadingProductsFromWeb) return false;
    setState(() => _loadingProductsFromWeb = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Updating products...'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    try {
      if (kDebugMode) {
        debugPrint(
          '[Products][Verify] Load from web — full URL: $_productsCsvUrl',
        );
        debugPrint(
          '[Products][Verify] gid query param: '
          '${Uri.parse(_productsCsvUrl).queryParameters['gid'] ?? '(missing)'}',
        );
      }
      final response = await http.get(Uri.parse(_productsCsvUrl));

      if (response.statusCode != 200) {
        print('Failed to download products CSV');
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download products'),
            duration: Duration(seconds: 2),
          ),
        );
        return false;
      }

      final csvString = response.body;
      if (kDebugMode) {
        debugPrint(
          '[Products][Verify] HTTP body length (chars): ${csvString.length}',
        );
      }
      int productCount = 0;

      await _parseAndStoreProducts(csvString, sourceLabel: 'Google Sheets CSV');
      productCount = _catalogCount;
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Products updated successfully ($productCount loaded)'),
          duration: Duration(seconds: 2),
        ),
      );

      print('Products successfully updated from Google Sheets');
      return true;
    } catch (e) {
      print('Error loading products: $e');
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating products'),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _loadingProductsFromWeb = false);
      }
    }
  }

  Future<void> _loadCustomersFromSheet() async {
    if (_isLoadingCustomers) return;
    setState(() => _isLoadingCustomers = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Updating customers...'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    try {
      final response = await http.get(Uri.parse(_customersCsvUrl));

      if (response.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to load customers'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      final csvString = response.body;
      await _parseAndStoreCustomers(csvString);
      final count = _customers.length;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count customers loaded'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load customers'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingCustomers = false);
      }
    }
  }

  Future<File> _addedCustomersFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _kAddedCustomersFilename));
  }

  Future<List<Customer>> _readAddedCustomersFromDisk() async {
    try {
      final file = await _addedCustomersFile();
      if (!await file.exists()) return [];
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! List<dynamic>) return [];
      final out = <Customer>[];
      for (final e in decoded) {
        if (e is Map<String, dynamic>) {
          out.add(Customer.fromJson(e));
        } else if (e is Map) {
          out.add(Customer.fromJson(Map<String, dynamic>.from(e)));
        }
      }
      return out;
    } catch (e, st) {
      debugPrint('[Customers] Read $_kAddedCustomersFilename failed: $e\n$st');
      return [];
    }
  }

  Future<void> _writeAddedCustomersToDisk(List<Customer> customers) async {
    final file = await _addedCustomersFile();
    final payload = customers.map((c) => c.toJson()).toList(growable: false);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  bool _customerNameCollides(
    String companyNameTrimmed,
    Iterable<Customer> pool,
  ) {
    final n = _normalizeCustomerNameForDedup(companyNameTrimmed);
    if (n.isEmpty) return false;
    for (final c in pool) {
      if (_normalizeCustomerNameForDedup(c.companyName) == n) return true;
    }
    return false;
  }

  bool _customerIdCollides(String idTrimmed, Iterable<Customer> pool) {
    final key = idTrimmed.trim().toLowerCase();
    if (key.isEmpty) return false;
    for (final c in pool) {
      if (c.id.trim().toLowerCase() == key) return true;
    }
    return false;
  }

  Customer _customerFromManualEntry({
    required String companyName,
    required String idOrEmpty,
  }) {
    final name = companyName.trim();
    final idPart = idOrEmpty.trim();
    final id = idPart.isNotEmpty ? idPart : name;
    return Customer(
      id: id,
      companyName: name,
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

  Future<void> _reapplyLocalAddedCustomers() async {
    final Customer? restore = _pendingRestoreCustomerAfterLocalMerge;
    _pendingRestoreCustomerAfterLocalMerge = null;

    List<Customer> local;
    try {
      local = await _readAddedCustomersFromDisk();
    } catch (e, st) {
      debugPrint('[Customers] Reapply read failed: $e\n$st');
      return;
    }
    if (local.isEmpty) {
      _tryRestoreCustomerSelectionAfterMerge(restore);
      return;
    }

    final seenNames = <String>{
      for (final c in _customers) _normalizeCustomerNameForDedup(c.companyName),
    };
    final seenIds = <String>{
      for (final c in _customers)
        if (c.id.trim().isNotEmpty) c.id.trim().toLowerCase(),
    };

    final toAdd = <Customer>[];
    for (final c in local) {
      final nn = _normalizeCustomerNameForDedup(c.companyName);
      if (nn.isEmpty) continue;
      if (seenNames.contains(nn)) continue;
      final idn = c.id.trim().toLowerCase();
      if (idn.isNotEmpty && seenIds.contains(idn)) continue;
      toAdd.add(c);
      seenNames.add(nn);
      if (idn.isNotEmpty) seenIds.add(idn);
    }

    if (toAdd.isEmpty) {
      _tryRestoreCustomerSelectionAfterMerge(restore);
      return;
    }
    if (!mounted) return;

    setState(() {
      _customers = List<Customer>.from(_customers)..addAll(toAdd);
      for (final c in toAdd) {
        _customersByKey[c.idOrKey] = c;
      }
    });
    _tryRestoreCustomerSelectionAfterMerge(restore);
  }

  void _tryRestoreCustomerSelectionAfterMerge(Customer? restore) {
    if (restore == null || !mounted) return;
    if (_selectedCustomer != null) return;
    final rid = restore.id;
    Customer? match;
    for (final c in _customers) {
      if (c.id == rid) {
        match = c;
        break;
      }
    }
    if (match != null) {
      setState(() {
        _selectedCustomer = match;
        _syncCustomerWalkOrderEnabledForCustomer(match);
        debugPrint('[WalkOrder] sync source: startup restore');
      });
    }
  }

  void _syncCustomerWalkOrderEnabledForCustomer(Customer? customer) {
    final customerId = customer?.id.trim() ?? '';
    _isCustomerWalkOrderEnabled =
        customerId.isNotEmpty &&
        _customerWalkOrderByCustomerAndItem.containsKey(customerId);
    debugPrint(
      '[WalkOrder] Enabled for customer: $_isCustomerWalkOrderEnabled',
    );
    debugPrint(
      '[WalkOrder] Current customer: ${customerId.isEmpty ? 'none' : customerId}',
    );
  }

  Future<void> _showAddCustomerDialog() async {
    _editDialogOpen = true;
    final nameController = TextEditingController();
    final idController = TextEditingController();
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Add Customer'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Customer Name',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: idController,
                    decoration: const InputDecoration(
                      labelText: 'Customer ID / Code (optional)',
                      helperText: 'If blank, the name is used as the ID',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
      if (saved != true || !mounted) return;

      final name = nameController.text.trim();
      if (name.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer name is required')),
        );
        return;
      }

      if (_customerNameCollides(name, _customers)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A customer with this name already exists'),
          ),
        );
        return;
      }

      final idPart = idController.text.trim();
      final effectiveId = idPart.isNotEmpty ? idPart : name;
      if (_customerIdCollides(effectiveId, _customers)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This customer ID is already in use')),
        );
        return;
      }

      List<Customer> onDisk;
      try {
        onDisk = await _readAddedCustomersFromDisk();
      } catch (e, st) {
        debugPrint('[Customers] Add load disk: $e\n$st');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read saved customers from device'),
          ),
        );
        return;
      }

      final newCustomer = _customerFromManualEntry(
        companyName: name,
        idOrEmpty: idPart,
      );
      if (_customerNameCollides(name, onDisk) ||
          _customerIdCollides(effectiveId, onDisk)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This customer is already in local additions'),
          ),
        );
        return;
      }

      try {
        await _writeAddedCustomersToDisk([...onDisk, newCustomer]);
      } catch (e, st) {
        debugPrint('[Customers] Add write disk: $e\n$st');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save customer to device')),
        );
        return;
      }

      if (!mounted) return;
      await _reapplyLocalAddedCustomers();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Customer added')));
    } finally {
      _editDialogOpen = false;
      nameController.dispose();
      idController.dispose();
      _requestScannerFocus();
    }
  }

  /// Customers.csv headers: Id, CompanyName, Address, Address2, City, State, Zip, Phone, Fax, Email, Contact, SalesRepName, PriceList, Discount, PaymentTerms.
  Future<void> _parseAndStoreCustomers(String rawCsv) async {
    debugPrint('[Customers] parse started');
    final result = await compute(_parseCustomersCatalogCsvIsolate, rawCsv);
    _debugPrintCustomerLoadReportFromResult(result);

    void applyEmpty() {
      _pendingRestoreCustomerAfterLocalMerge = _selectedCustomer;
      final debugLine = 'Customers Loaded: ${result.customersLoaded}';
      if (mounted) {
        setState(() {
          _customers = [];
          _customersByKey.clear();
          _selectedCustomer = null;
          _syncCustomerWalkOrderEnabledForCustomer(null);
          debugPrint('[WalkOrder] sync source: startup restore');
          _customersLoadDebugLine = debugLine;
        });
      } else {
        _customers = [];
        _customersByKey.clear();
        _selectedCustomer = null;
        _syncCustomerWalkOrderEnabledForCustomer(null);
        debugPrint('[WalkOrder] sync source: startup restore');
        _customersLoadDebugLine = debugLine;
      }
      scheduleMicrotask(() => _reapplyLocalAddedCustomers());
      _discardWorkingOrderIfNoCustomerSelected();
    }

    if (result.outcome == _CustomersCsvIsolateOutcome.earlyFailure) {
      applyEmpty();
      return;
    }

    final list = result.customers;
    final byKey = result.customersByKey;
    final previous = _selectedCustomer;
    Customer? resolvedSelection;
    if (previous != null && list.isNotEmpty) {
      final prevId = previous.id;
      for (final c in list) {
        if (c.id == prevId) {
          resolvedSelection = c;
          break;
        }
      }
    }

    _pendingRestoreCustomerAfterLocalMerge = previous;
    final debugLine = 'Customers Loaded: ${result.customersLoaded}';
    if (mounted) {
      setState(() {
        _customers = list;
        _customersByKey
          ..clear()
          ..addAll(byKey);
        _selectedCustomer = resolvedSelection;
        _syncCustomerWalkOrderEnabledForCustomer(resolvedSelection);
        debugPrint('[WalkOrder] sync source: startup restore');
        _customersLoadDebugLine = debugLine;
      });
      unawaited(_refreshPreviouslyOrderedHistoryForSelectedCustomer());
    } else {
      _customers = list;
      _customersByKey
        ..clear()
        ..addAll(byKey);
      _selectedCustomer = resolvedSelection;
      _syncCustomerWalkOrderEnabledForCustomer(resolvedSelection);
      debugPrint('[WalkOrder] sync source: startup restore');
      _customersLoadDebugLine = debugLine;
    }
    scheduleMicrotask(() => _reapplyLocalAddedCustomers());
  }

  /// Isolated minimal picker for full-catalog test/export flows (dependents crash diagnosis).
  /// Does not use [_runCustomerPickerDialog], focus nodes, or scanner recovery hooks.
  Future<Customer?> _showSimpleCustomerPickerForCatalogTests() async {
    if (_customers.isEmpty) return null;
    return showDialog<Customer>(
      context: context,
      builder: (ctx) => _SimpleCatalogTestCustomerPickerDialog(
        customers: List<Customer>.from(_customers),
      ),
    );
  }

  /// Same UI as [_showSelectCustomerDialog] but does not update [_selectedCustomer]
  /// or status — for flows that must not touch app quote/customer selection.
  Future<Customer?> _runCustomerPickerDialog() async {
    debugPrint('[DependentsDiag] entering _runCustomerPickerDialog');
    if (_customers.isEmpty) return null;
    _editDialogOpen = true;
    final searchController = TextEditingController();
    try {
      final filtered = <Customer>[];
      filtered.addAll(_customers);
      debugPrint('[DependentsDiag] opening picker dialog');
      final picked = await showDialog<Customer>(
        context: context,
        builder: (ctx) {
          bool dialogAlive = true;

          void popCustomerPicker([Customer? result]) {
            if (!dialogAlive) return;
            dialogAlive = false;
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop(result);
          }

          return StatefulBuilder(
            builder: (_, setDialogState) {
              void applyCustomerFilter(String query) {
                if (!dialogAlive || !ctx.mounted) return;
                final q = query.trim().toLowerCase();
                filtered
                  ..clear()
                  ..addAll(
                    _customers.where((c) {
                      if (q.isEmpty) return true;
                      return c.displayName.toLowerCase().contains(q) ||
                          c.contact.toLowerCase().contains(q) ||
                          c.email.toLowerCase().contains(q) ||
                          c.companyName.toLowerCase().contains(q) ||
                          c.city.toLowerCase().contains(q) ||
                          c.state.toLowerCase().contains(q);
                    }),
                  );
                if (!dialogAlive || !ctx.mounted) return;
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
                        autofocus: false,
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
                                    onTap: () => popCustomerPicker(c),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => popCustomerPicker(),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => popCustomerPicker(null),
                    child: const Text('Clear selection'),
                  ),
                ],
              );
            },
          );
        },
      );
      debugPrint(
        '[DependentsDiag] closing picker dialog result=$picked',
      );
      return picked;
    } finally {
      debugPrint(
        '[DependentsDiag] customer picker finally: dispose search, _editDialogOpen=false',
      );
      _editDialogOpen = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        searchController.dispose();
      });
    }
  }

  Future<void> _showSelectCustomerDialog() async {
    final picked = await _runCustomerPickerDialog();
    if (!mounted) return;
    debugPrint('[WalkOrder] sync source: customer picker');
    setState(() {
      _selectedCustomer = picked;
      _syncCustomerWalkOrderEnabledForCustomer(picked);
      _status = picked == null
          ? 'Customer cleared'
          : 'Customer: ${picked.displayName}';
    });
    unawaited(_refreshPreviouslyOrderedHistoryForSelectedCustomer());
    if (!mounted) return;
    debugPrint(
      '[DependentsDiag] _showSelectCustomerDialog: before _requestScannerFocus()',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestScannerFocus();
    });
    debugPrint(
      '[DependentsDiag] _showSelectCustomerDialog: after _requestScannerFocus()',
    );
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

  Future<bool> _ensureQuoteReadyForManualAdd() async {
    if (_selectedCustomer != null) return true;
    if (_customers.isEmpty) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Load customers CSV first.')),
      );
      return false;
    }
    await _confirmNewQuote();
    return mounted && _selectedCustomer != null;
  }

  void _showExactLookupMessageForQuery(
    String query, {
    required bool scanTab,
  }) {
    final trimmed = query.trim();
    final hasPartialMatches =
        trimmed.isNotEmpty &&
        _allProducts.any((p) => _productMatchesSearch(p, trimmed));
    final message = hasPartialMatches
        ? 'Select an item from the results'
        : 'No exact item or UPC found';
    if (scanTab) {
      _setStateDebug('quick_entry_exact_lookup_message', () {
        _quickEntryStatus = message;
        _status = message;
      });
      _triggerScanFeedback(ScanFeedbackType.notFound, source: 'quickEntry');
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  bool _productIsDiscountEligible(Product product) =>
      _productPricingState(product) == ProductPricingState.discountEligible;

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

  double _getRegularLineTotal(OrderLine line) => _lineTotalFromRoundedUnitPrice(
    rawUnitPrice: line.product.price,
    qty: line.quantity,
  );

  double _getDiscountedLineTotal(OrderLine line) =>
      _lineTotalFromRoundedUnitPrice(
        rawUnitPrice: _getDiscountedUnitPrice(line),
        qty: line.quantity,
      );

  double _getLineDiscountAmount(OrderLine line) =>
      _getRegularLineTotal(line) - _getDiscountedLineTotal(line);

  bool _lineHasDiscount(OrderLine line) => _getLineDiscountAmount(line) > 0.005;

  bool _orderHasAnyDiscount() => _orderDiscountAmount > 0.005;

  double _getTotalDiscountAmount() => _orderDiscountAmount;

  double _getRegularOrderTotal() => _regularOrderTotal;

  String _formatCurrency(double amount) {
    final negative = amount < 0;
    final absolute = amount.abs();
    final fixed = absolute.toStringAsFixed(2);
    final dotIndex = fixed.indexOf('.');
    final whole = dotIndex >= 0 ? fixed.substring(0, dotIndex) : fixed;
    final cents = dotIndex >= 0 ? fixed.substring(dotIndex) : '.00';
    final withCommas = whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${negative ? '-' : ''}\$$withCommas$cents';
  }

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
    _regularOrderTotal = _roundMoney(regularSum);
    _orderTotal = _roundMoney(discountedSum);
    _orderDiscountAmount = _roundMoney(regularSum - discountedSum);
  }

  /// Call when quote/list becomes empty so next scan or manual entry is "first time" (single beep).
  void _resetQuoteDisplayAndScanState() {
    _ordersTabExpandedLineKey = null;
    _scanTabExpandedLineKey = null;
    _ecatalogExpandedItemKey = null;
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

  /// Scan tab only: scroll parent Scan panel [Scrollable] so the row is visible and flash-highlight briefly.
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

  /// Returns false when the add was blocked (e.g. no customer selected).
  bool _addProduct(
    Product product,
    String source, {
    required QuoteBucketDefinition bucket,

    /// When true (scanner path only): reveal/highlight the row instead of [_scrollToTopSoon].
    bool scheduleScanTabOrderRowReveal = false,
    String feedbackSource = 'scanner',
  }) {
    if (!_requireSelectedCustomerForWorkingOrder()) return false;

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
      line = OrderLine(product: product, quantity: addedQty, scans: 1);

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
      source: feedbackSource,
    );
    return true;
  }

  Future<Product?> _processScan(
    String value, {
    String source = 'scanner',
  }) async {
    try {
      final int sampleId = _currentScanSampleId;
      if (sampleId > 0) {
        _logScanPerfStep(sampleId, 'scan processing started');
      }
      final raw = value.trim();
      debugPrint('[ScanLookup] input=<$raw>');
      final upc = digitsOnly(raw);

      if (raw.isEmpty || upc.isEmpty) {
        _restoreScanFieldFocus();
        return null;
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
        _restoreScanFieldFocus();
        return null;
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
          _logScanPerfStep(
            sampleId,
            'setState complete (not-found state updated)',
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _logScanPerfStep(sampleId, 'setState frame complete');
            _logScanPerfStep(sampleId, 'UI refresh triggered');
          });
        }
        _triggerScanFeedback(ScanFeedbackType.notFound, source: source);
        _restoreScanFieldFocus();
        if (sampleId > 0) {
          _logScanPerfStep(sampleId, 'app ready for next scan');
          _finishScanPerfSample(sampleId, outcome: 'not-found');
          _currentScanSampleId = 0;
        }
        return null;
      }
      await _ensureRoutingForProduct(product);
      final bucket = _resolveQuoteBucketForProduct(product);
      final added = _addProduct(
        product,
        raw,
        bucket: bucket,
        scheduleScanTabOrderRowReveal: true,
        feedbackSource: source,
      );
      _restoreScanFieldFocus();
      if (sampleId > 0) {
        _logScanPerfStep(sampleId, 'app ready for next scan');
        _finishScanPerfSample(
          sampleId,
          outcome: added ? 'item-added' : 'no-customer',
        );
        _currentScanSampleId = 0;
      }
      return added ? product : null;
    } catch (e) {
      final int sampleId = _currentScanSampleId;
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No match — try again')));
      _quickEntryController.clear();
      _restoreScanFieldFocus();
      if (sampleId > 0) {
        _finishScanPerfSample(sampleId, outcome: 'exception');
      }
      _currentScanSampleId = 0;
      return null;
    }
  }

  void _enqueueScan(String value, {String source = 'scanner'}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (_currentScanSampleId > 0) {
      _logScanPerfStep(_currentScanSampleId, 'scan received');
    }

    _pendingScans.addLast((value: trimmed, source: source));
    if (_isProcessingScan) {
      return;
    }
    unawaited(_drainScanQueue());
  }

  _CameraScanOverlayUpdate _cameraOverlayUpdateForProduct(Product product) {
    return _CameraScanOverlayUpdate(
      itemNumber: product.itemNumber,
      quantity: _qtyInCurrentQuoteForProduct(product),
    );
  }

  Future<void> _openCameraScanner() async {
    _editDialogOpen = true;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CameraScannerPage(
          onDetect: (rawValue) async {
            final value = rawValue.trim();
            if (value.isEmpty) return null;
            final product = await _processScan(value);
            if (product == null) return null;
            return _cameraOverlayUpdateForProduct(product);
          },
        ),
      ),
    );

    _editDialogOpen = false;
    if (!mounted) return;
    _requestScannerFocus();
  }

  Future<void> _drainScanQueue() async {
    if (_isProcessingScan) return;
    _isProcessingScan = true;
    try {
      while (_pendingScans.isNotEmpty && mounted) {
        final next = _pendingScans.removeFirst();
        await _processScan(next.value, source: next.source);
      }
    } finally {
      _isProcessingScan = false;
    }
  }

  void _handleScannerCharacter(String char) {
    if (char.isEmpty) return;
    _scannerBuffer += char;
  }

  void _processScannerBuffer() {
    final scanned = _scannerBuffer.trim();
    _scannerBuffer = '';
    if (scanned.isEmpty) {
      _restoreScanFieldFocus();
      return;
    }

    if (_manualEntryFocusTraceActive) {
      _manualEntryFocusTraceActive = false;
      _manualEntryFocusTraceTimeout?.cancel();
      debugPrint(
        '[ManualEntry][Debug] ending focus trace: scanner input received. scannerHasFocus=${_scannerFocusNode.hasFocus}',
      );
    }

    if (_quickEntryController.text.trim().isNotEmpty) {
      _quickEntryController.clear();
      if (_scanSearchQuery.isNotEmpty || _searchResults.isNotEmpty) {
        _setStateDebug('quick_entry_clear_search_on_scan_start', () {
          _scanSearchQuery = '';
          _searchResults = [];
        });
      }
    }

    debugPrint('[ScannerInput] committed=<$scanned>');
    final int sampleId = _startScanPerfSample(scanned);
    _currentScanSampleId = sampleId;
    _logScanPerfStep(sampleId, 'barcode text fully received (hardware enter)');
    _enqueueScan(scanned);
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _requestScannerFocusAfterManualEntry(
            debugLabel: 'quickEntryEmptySubmit',
          );
        });
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
      final product = _findExactProductForQuickEntry(input);

      if (product == null) {
        _showExactLookupMessageForQuery(input, scanTab: true);
        _quickEntryController.clear();
        _setStateDebug('quick_entry_clear_search_not_found', () {
          _scanSearchQuery = '';
          _searchResults = [];
        });
        _forceScannerFocusAfterInvalidQuickEntry();
        return;
      }

      if (!await _ensureQuoteReadyForManualAdd()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _requestScannerFocusAfterManualEntry(
            debugLabel: 'quickEntryQuoteNotReady',
          );
        });
        return;
      }
      await _ensureRoutingForProduct(product);
      final bucket = _resolveQuoteBucketForProduct(product);
      final added = _addProduct(product, input, bucket: bucket);
      if (!added) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _requestScannerFocusAfterManualEntry(debugLabel: 'quickEntryAddFailed');
        });
        return;
      }

      _quickEntryController.clear();

      _setStateDebug('quick_entry_clear_search_after_add', () {
        _scanSearchQuery = '';
        _searchResults = [];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _requestScannerFocusAfterManualEntry(debugLabel: 'quickEntrySuccess');
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No match — try again')));
      _quickEntryController.clear();
      _setStateDebug('quick_entry_clear_search_after_error', () {
        _scanSearchQuery = '';
        _searchResults = [];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _requestScannerFocusAfterManualEntry(debugLabel: 'quickEntryCatch');
      });
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
      final canForceScannerFocus =
          _scanTabActive &&
          !_editDialogOpen &&
          !_quickEntryFocusNode.hasFocus &&
          !_ecatalogSearchFocusNode.hasFocus;
      if (canForceScannerFocus) {
        FocusScope.of(context).requestFocus(_scannerFocusNode);
      }
      _scheduleScannerRefocus();
      debugPrint(
        '[ManualEntry][Submit] scanner focus recovery scheduled. '
        'scannerHasFocus=${_scannerFocusNode.hasFocus}',
      );

      // Mark trace "complete" for the next scanner scan path.
      // (If scanner never receives input, the timeout above will end trace.)
    });
  }

  void _forceScannerFocusAfterInvalidQuickEntry() {
    debugPrint('[ManualEntry][InvalidFocusRestore] start');
    if (!mounted) {
      debugPrint('[ManualEntry][InvalidFocusRestore] return early: not mounted');
      return;
    }
    if (!_scanTabActive) {
      debugPrint(
        '[ManualEntry][InvalidFocusRestore] return early: scan tab inactive',
      );
      return;
    }
    if (_editDialogOpen) {
      debugPrint(
        '[ManualEntry][InvalidFocusRestore] return early: edit dialog open',
      );
      return;
    }

    _quickEntryFocusNode.unfocus();
    FocusScope.of(context).requestFocus(_scannerFocusNode);
    _scheduleScannerRefocus();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();

    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      final query = value.trim();

      if (query.isEmpty) {
        _setStateDebug('search_debounce_clear_results', () {
          _scanSearchQuery = '';
          _searchResults = [];
        });
        return;
      }

      final results = _allProducts
          .where((p) {
            return _productMatchesSearch(p, query);
          })
          .take(10)
          .toList();

      _setStateDebug('search_debounce_apply_results', () {
        _scanSearchQuery = query;
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
                decoration: InputDecoration(
                  labelText: line.product.description,
                ),
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

  /// Shared gate for any path that builds or mutates the working order (scan,
  /// quick entry, search add, eCatalog add, qty changes). Browsing/search without
  /// a customer stays allowed; order work requires selection first.
  bool _requireSelectedCustomerForWorkingOrder() {
    if (_selectedCustomer != null) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please select a customer first.')),
    );
    return false;
  }

  /// Clears persisted in-memory workspace when no customer is selected (invalid
  /// state from older builds or bad restores). Optional snackbar when user-facing.
  void _discardWorkingOrderIfNoCustomerSelected({bool showMessage = false}) {
    if (_selectedCustomer != null) return;
    if (_currentQuoteId == null && _orderLines.isEmpty) return;

    void clear() {
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
      _quickEntryStatus = '-';
      _status = 'Select a customer to start an order';
    }

    if (mounted) {
      _setStateDebug('discard_workspace_no_customer', clear);
    } else {
      clear();
    }
    if (showMessage && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer first.')),
      );
    }
  }

  Future<Customer?> _resolveCustomerForActiveQuoteIndexRow(
    String quoteId,
  ) async {
    final idx = await _loadQuoteIndex();
    SavedQuoteInfo? row;
    for (final q in idx) {
      if (q.id == quoteId) {
        row = q;
        break;
      }
    }
    if (row == null) return null;
    final wantId = row.customerId.trim();
    final wantName = row.customerName.trim().toLowerCase();
    if (wantId.isNotEmpty) {
      for (final c in _customers) {
        if (c.id.trim() == wantId) return c;
      }
    }
    if (wantName.isNotEmpty) {
      for (final c in _customers) {
        final dn = c.displayName.trim().toLowerCase();
        final cn = c.companyName.trim().toLowerCase();
        if (dn == wantName || cn == wantName) return c;
      }
    }
    return null;
  }

  Future<void> _confirmNewQuote() async {
    if (!mounted) return;
    // Create Quote must not require a pre-selected customer: open the picker first,
    // then continue into the same quote flow. Working-order paths still use
    // [_requireSelectedCustomerForWorkingOrder].
    if (_selectedCustomer == null) {
      if (_customers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Load customers CSV first.')),
        );
        return;
      }
      await _showSelectCustomerDialog();
      if (!mounted || _selectedCustomer == null) return;
    }

    final hasItems = _orderLines.isNotEmpty;
    final customerForNewQuote = _selectedCustomer!;

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
      _ordersTabExpandedLineKey = null;
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
      _syncCustomerWalkOrderEnabledForCustomer(customer);
      debugPrint('[WalkOrder] sync source: create quote');
      _currentQuoteId = null;
      _activeQuoteBucketKey = bucket.bucketKey;
      _activeQuoteBucketLabel = bucket.displayLabel;
    });
    unawaited(_refreshPreviouslyOrderedHistoryForSelectedCustomer());

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
      final newArchive = archiveEntries
          .where((e) => !removeSet.contains(e.id))
          .toList();
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
  Future<bool> _restoreArchivedQuoteToActiveIndex(
    SavedQuoteInfo archived,
  ) async {
    if (archived.id.isEmpty) return false;
    try {
      final dir = await _getQuotesDirectory();
      final quoteFile = File('${dir.path}/quote_${archived.id}.json');
      if (!await quoteFile.exists()) return false;

      final archiveEntries = await _loadArchiveQuoteIndex();
      if (!archiveEntries.any((e) => e.id == archived.id)) return false;

      final previousArchive = List<SavedQuoteInfo>.from(archiveEntries);
      final newArchive = archiveEntries
          .where((e) => e.id != archived.id)
          .toList();

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
      final customerName = _customerDisplayNameForExportFromQuoteData(
        quoteData,
        info,
      );
      final exportedOn = DateTime.now();
      final filename = _buildExportOrderCsvFilename(
        quoteName: quoteName,
        customerName: customerName,
        customerId: info.customerId,
        quoteData: quoteData,
        customerFolderName: info.customerName,
        quoteBucketLabel:
            (quoteData['quoteBucketLabel'] as String?)?.trim().isNotEmpty == true
                ? (quoteData['quoteBucketLabel'] as String?)?.trim()
                : info.quoteBucketLabel,
        quoteBucketKey:
            (quoteData['quoteBucketKey'] as String?)?.trim().isNotEmpty == true
                ? (quoteData['quoteBucketKey'] as String?)?.trim()
                : info.quoteBucketKey,
        quoteDate: _quoteDateFromMapOrFallback(quoteData, exportedOn),
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
      data = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
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
        data['lines'] as List<dynamic>? ??
        data['items'] as List<dynamic>? ??
        [];
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
                  Text(
                    'Quote: ${info.name.trim().isEmpty ? '(unnamed)' : info.name.trim()}',
                  ),
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
                  const Text(
                    'Line items',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  ...lines.map((lineJson) {
                    final map = Map<String, dynamic>.from(lineJson as Map);
                    final desc = (map['description'] as String?) ?? '';
                    final item = (map['itemNumber'] as String?) ?? '';
                    final qty = _quantityFromJson(map['quantity']);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not restore quote.')));
    }
  }

  Future<void> _onArchiveConfirmPressed(SavedQuoteInfo info) async {
    final ok = await _archiveMarkQuoteConfirmed(info);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Quote marked Confirmed.')));
      setState(() {});
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not update quote.')));
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(archivedMsg)));
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(confirmedMsg)));
  }

  static const String _kEcatalogDecorAndGiftwareCategory = 'Decor & Giftware';

  /// ECatalog-only merchandising bucket (uses [Product.productType], [Product.category], [Product.isNewRelease]).
  bool _productMatchesEcatalogMerchandising(Product p) {
    final m = _catalogMerchandising;
    if (m == null) return true;
    if (m == 'newItems') return p.isNewRelease;
    final pt = p.productType.trim().toUpperCase();
    if (m == 'everyday') return pt == 'EVERYDAY';
    if (m == 'homeDecor') {
      return p.category.trim() == _kEcatalogDecorAndGiftwareCategory;
    }
    if (m == 'seasonal') {
      return _kEcatalogSeasonalLabelToProductType.values.contains(pt);
    }
    if (m == 'sale') return p.isPs;
    return true;
  }

  bool _matchesCatalogBaseFilters(
    Product p, {
    required String rawQuery,
    required bool inOrderOnly,
    required bool inStockOnly,
    required bool previouslyOrderedOnly,
  }) {
    if (!_productMatchesEcatalogMerchandising(p)) return false;
    if (inOrderOnly && !_orderLineByKey.containsKey(_orderLineKeyForProduct(p))) {
      return false;
    }
    if (inStockOnly && !_isProductInStockForEcatalog(p)) return false;
    if (previouslyOrderedOnly && !_isPreviouslyOrdered(p)) return false;
    if (!_productMatchesSearch(p, rawQuery)) {
      return false;
    }
    return true;
  }

  String _ecatalogQuoteSummaryLabel() {
    final customerName = _selectedCustomer?.displayName.trim() ?? '';
    final quoteName = _quoteNameController.text.trim();
    if (customerName.isNotEmpty && quoteName.isNotEmpty) {
      return '$customerName - $quoteName';
    }
    if (customerName.isNotEmpty) return customerName;
    if (quoteName.isNotEmpty) return quoteName;
    return 'No customer / quote selected';
  }

  Widget _buildECatalogOrderSummaryBar({
    required TextTheme textTheme,
    required bool orderHasDiscount,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _ecatalogQuoteSummaryLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _orderLines.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _ecatalogOrderPanelExpanded =
                                !_ecatalogOrderPanelExpanded;
                          });
                        },
                  icon: Icon(
                    _ecatalogOrderPanelExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
                  label: Text(
                    _ecatalogOrderPanelExpanded ? 'Hide Order' : 'View Order',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text(
                  'Items: ${_orderLines.length}',
                  style: textTheme.bodyMedium,
                ),
                Text('Units: $_totalUnits', style: textTheme.bodyMedium),
                Text(
                  '${orderHasDiscount ? 'Final Total' : 'Order Total'}: ${_formatCurrency(_orderTotal)}',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildECatalogOrderPanel() {
    if (_orderLines.isEmpty) {
      return Card(
        margin: const EdgeInsets.only(top: 6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            'No items added yet',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _kSecondaryText),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 360),
      child: Material(
        color: Colors.transparent,
        child: ListView.builder(
          itemCount: _orderLines.length,
          itemBuilder: (context, index) {
            final line = _orderLines[index];
            final lineKey = _orderLineKeyForProduct(line.product);
            final displayProduct = _productsByItemNumber[lineKey];
            return KeyedSubtree(
              key: ValueKey('ecatalog_order_panel_$lineKey'),
              child: _buildOrderCard(
                line,
                compactLayout: true,
                compactExpandHost: _OrderLineCardCompactExpandHost.ecatalogTab,
                displayProduct: displayProduct ?? line.product,
              ),
            );
          },
        ),
      ),
    );
  }

  List<String> _catalogCategories() {
    final n = _productsByItemNumber.length;
    final merch = _catalogMerchandising;
    final q = _catalogSearchQuery.trim();
    final normalizedQ = _normalizedSearchQuery(q);
    final inOrderOnly = _catalogInOrderOnly;
    final inStockOnly = _catalogInStockOnly;
    final previouslyOrderedOnly = _catalogPreviouslyOrderedOnly;
    final customerHistoryKey = _previouslyOrderedCustomerCacheKey;
    final orderSeqSig = Object.hashAll(
      _orderLines.map((l) => _orderLineKeyForProduct(l.product)),
    );
    final key =
        '$n|${merch ?? ''}|$normalizedQ|$inOrderOnly|$inStockOnly|$previouslyOrderedOnly|$customerHistoryKey|${_orderLineByKey.length}|$orderSeqSig';
    if (_catalogDistinctCategories != null &&
        _catalogDistinctCategoriesCacheKey == key) {
      return _catalogDistinctCategories!;
    }
    final set = <String>{};
    for (final p in _productsByItemNumber.values) {
      if (!_matchesCatalogBaseFilters(
        p,
        rawQuery: q,
        inOrderOnly: inOrderOnly,
        inStockOnly: inStockOnly,
        previouslyOrderedOnly: previouslyOrderedOnly,
      )) {
        continue;
      }
      final c = p.category.trim();
      if (c.isNotEmpty) set.add(c);
    }
    final list = set.toList()..sort();
    _catalogDistinctCategories = list;
    _catalogDistinctCategoriesCacheKey = key;
    return list;
  }

  /// Category filter applied to ECatalog lists: null if "All" or selection is not in the current subset.
  String? _resolvedCatalogCategoryForEcatalogFilters() {
    final raw = _selectedCatalogCategory?.trim();
    if (raw == null || raw.isEmpty) return null;
    return _catalogCategories().contains(raw) ? raw : null;
  }

  /// Distinct sub-categories for the dropdown, scoped to selected parent filters.
  List<String> _catalogSubCategoriesForSelectedCategory() {
    final n = _productsByItemNumber.length;
    final cat = _resolvedCatalogCategoryForEcatalogFilters();
    final merch = _catalogMerchandising;
    final q = _catalogSearchQuery.trim();
    final normalizedQ = _normalizedSearchQuery(q);
    final inOrderOnly = _catalogInOrderOnly;
    final inStockOnly = _catalogInStockOnly;
    final previouslyOrderedOnly = _catalogPreviouslyOrderedOnly;
    final customerHistoryKey = _previouslyOrderedCustomerCacheKey;
    final orderSeqSig = Object.hashAll(
      _orderLines.map((l) => _orderLineKeyForProduct(l.product)),
    );
    final key =
        '$n|${cat ?? ''}|${merch ?? ''}|$normalizedQ|$inOrderOnly|$inStockOnly|$previouslyOrderedOnly|$customerHistoryKey|${_orderLineByKey.length}|$orderSeqSig';
    if (_catalogSubCategoryOptionsCacheKey == key &&
        _catalogSubCategoryOptionsCache != null) {
      return _catalogSubCategoryOptionsCache!;
    }
    final set = <String>{};
    for (final p in _productsByItemNumber.values) {
      if (!_matchesCatalogBaseFilters(
        p,
        rawQuery: q,
        inOrderOnly: inOrderOnly,
        inStockOnly: inStockOnly,
        previouslyOrderedOnly: previouslyOrderedOnly,
      )) {
        continue;
      }
      if (cat != null && p.category.trim() != cat) continue;
      final sub = p.subCategory.trim();
      if (sub.isNotEmpty) set.add(sub);
    }
    final list = set.toList()..sort();
    _catalogSubCategoryOptionsCacheKey = key;
    _catalogSubCategoryOptionsCache = list;
    return list;
  }

  List<Product> _filteredCatalogProducts() {
    final q = _catalogSearchQuery.trim();
    final normalizedQ = _normalizedSearchQuery(q);
    final cat = _resolvedCatalogCategoryForEcatalogFilters();
    final subCategories = _catalogSubCategoriesForSelectedCategory();
    final subRaw = _selectedCatalogSubCategory;
    final subCategory = subRaw != null && subCategories.contains(subRaw)
        ? subRaw
        : null;
    final inOrderOnly = _catalogInOrderOnly;
    final inStockOnly = _catalogInStockOnly;
    final previouslyOrderedOnly = _catalogPreviouslyOrderedOnly;
    final merch = _catalogMerchandising;
    final customerHistoryKey = _previouslyOrderedCustomerCacheKey;
    final selectedCustomerId = _selectedCustomer?.id.trim() ?? '';
    final walkSortEnabledForList =
        _isCustomerWalkOrderEnabled && selectedCustomerId.isNotEmpty;
    // Keep ECatalog in stable catalog order. Cache invalidation only needs the
    // order membership count for "In Order only" filtering.
    final key =
        '${_productsByItemNumber.length}|$normalizedQ|${cat ?? ''}|${subCategory ?? ''}|${merch ?? ''}|$inOrderOnly|$inStockOnly|$previouslyOrderedOnly|$customerHistoryKey|${_orderLineByKey.length}|$walkSortEnabledForList|$selectedCustomerId';
    if (_catalogFilteredCacheKey == key &&
        _catalogFilteredProductsCache != null) {
      return _catalogFilteredProductsCache!;
    }
    // Temporary: compare archive history vs walk-order CSV for Previously Ordered Only (302021, Spices).
    const dbgPrevOrderedCustomer = '302021';
    const dbgPrevOrderedCategory = 'Spices & Foods';
    if (previouslyOrderedOnly &&
        selectedCustomerId == dbgPrevOrderedCustomer &&
        cat == dbgPrevOrderedCategory) {
      final walk302021 = _customerWalkOrderByCustomerAndItem[dbgPrevOrderedCustomer];
      final walkNorm302021 = <String, CustomerWalkOrderRow>{};
      if (walk302021 != null) {
        for (final e in walk302021.entries) {
          walkNorm302021[normalizeItemNumber(e.key)] = e.value;
        }
      }
      var dbgSpicesBeforePo = 0;
      var dbgKeptByHistory = 0;
      var dbgInWalkCsv = 0;
      var dbgMissingHistoryButWalk = 0;
      for (final p in _productsByItemNumber.values) {
        if (!_productMatchesEcatalogMerchandising(p)) continue;
        if (cat != null && p.category.trim() != cat) continue;
        if (subCategory != null && p.subCategory.trim() != subCategory) {
          continue;
        }
        if (inOrderOnly &&
            !_orderLineByKey.containsKey(_orderLineKeyForProduct(p))) {
          continue;
        }
        if (inStockOnly && !_isProductInStockForEcatalog(p)) continue;
        if (!_productMatchesSearch(p, q)) continue;
        dbgSpicesBeforePo++;
        final itemRaw = p.itemNumber.trim();
        final historyPo = _isPreviouslyOrdered(p);
        final walkMapHasKey =
            walk302021 != null && walk302021.containsKey(itemRaw);
        final row = walk302021 == null
            ? null
            : (walk302021[itemRaw] ??
                walkNorm302021[normalizeItemNumber(itemRaw)]);
        debugPrint(
          '[PrevOrderedDebug] item=$itemRaw historyPo=$historyPo '
          'walk302021.containsKey(itemNumber)=$walkMapHasKey '
          'walkPos=${row?.walkPosition} subPos=${row?.subPosition}',
        );
        if (historyPo) dbgKeptByHistory++;
        if (row != null) dbgInWalkCsv++;
        if (row != null && !historyPo) dbgMissingHistoryButWalk++;
      }
      debugPrint(
        '[PrevOrderedDebug] SUMMARY customer=$dbgPrevOrderedCustomer '
        'category=$dbgPrevOrderedCategory subCategory=${subCategory ?? '(all)'} '
        'spicesBeforePreviouslyOrderedFilter=$dbgSpicesBeforePo '
        'keptByExistingHistory=$dbgKeptByHistory '
        'foundInWalkOrderCsv=$dbgInWalkCsv '
        'missingHistoryButInWalkCsv=$dbgMissingHistoryButWalk',
      );
    }
    Map<String, CustomerWalkOrderRow>? walkOrderByItemForPreviouslyOrdered;
    Map<String, CustomerWalkOrderRow>? walkOrderNormalizedForPreviouslyOrdered;
    if (previouslyOrderedOnly && walkSortEnabledForList) {
      final m = _customerWalkOrderByCustomerAndItem[selectedCustomerId];
      if (m != null && m.isNotEmpty) {
        walkOrderByItemForPreviouslyOrdered = m;
        walkOrderNormalizedForPreviouslyOrdered = {};
        for (final e in m.entries) {
          walkOrderNormalizedForPreviouslyOrdered[
              normalizeItemNumber(e.key)] = e.value;
        }
      }
    }
    final out = <Product>[];
    for (final p in _productsByItemNumber.values) {
      if (!_productMatchesEcatalogMerchandising(p)) continue;
      if (cat != null && p.category.trim() != cat) continue;
      if (subCategory != null) {
        if (p.subCategory.trim() != subCategory) continue;
      }
      if (!_matchesCatalogBaseFilters(
        p,
        rawQuery: q,
        inOrderOnly: inOrderOnly,
        inStockOnly: inStockOnly,
        previouslyOrderedOnly: false,
      )) {
        continue;
      }
      if (previouslyOrderedOnly) {
        final historyPo = _isPreviouslyOrdered(p);
        final rawItem = p.itemNumber.trim();
        final inWalkCsv = walkOrderByItemForPreviouslyOrdered != null &&
            (walkOrderByItemForPreviouslyOrdered.containsKey(rawItem) ||
                walkOrderNormalizedForPreviouslyOrdered!.containsKey(
                  normalizeItemNumber(rawItem),
                ));
        if (walkSortEnabledForList &&
            walkOrderByItemForPreviouslyOrdered != null) {
          if (!historyPo && !inWalkCsv) continue;
          if (inWalkCsv && !historyPo) {
            debugPrint(
              '[PrevOrderedDebug] kept by walk CSV item=$rawItem',
            );
          }
        } else if (!historyPo) {
          continue;
        }
      }
      out.add(p);
    }
    if (walkSortEnabledForList) {
      debugPrint('[WalkOrder] final sort path hit');
      debugPrint('[WalkOrder] customer=$selectedCustomerId');
      debugPrint('[WalkOrder] list count=${out.length}');

      final byItem =
          _customerWalkOrderByCustomerAndItem[selectedCustomerId] ?? const {};
      int positionedCount = 0;
      final normalizedByItem = <String, CustomerWalkOrderRow>{};
      for (final entry in byItem.entries) {
        normalizedByItem[normalizeItemNumber(entry.key)] = entry.value;
      }

      final indexed = out.indexed.map((entry) {
        final product = entry.$2;
        final rawKey = product.itemNumber.trim();
        final row =
            byItem[rawKey] ?? normalizedByItem[normalizeItemNumber(rawKey)];
        if (row?.walkPosition != null) positionedCount++;
        return (index: entry.$1, product: product, row: row);
      }).toList(growable: false);

      debugPrint('[WalkOrder] positioned count=$positionedCount');
      indexed.sort((a, b) {
        final aw = a.row?.walkPosition;
        final bw = b.row?.walkPosition;
        if (aw == null && bw != null) return 1;
        if (aw != null && bw == null) return -1;
        if (aw != null && bw != null) {
          final walkCmp = aw.compareTo(bw);
          if (walkCmp != 0) return walkCmp;
        }

        final as = a.row?.subPosition;
        final bs = b.row?.subPosition;
        if (as == null && bs != null) return 1;
        if (as != null && bs == null) return -1;
        if (as != null && bs != null) {
          final subCmp = as.compareTo(bs);
          if (subCmp != 0) return subCmp;
        }
        return a.index.compareTo(b.index);
      });

      out
        ..clear()
        ..addAll(indexed.map((e) => e.product));

      final first10 = indexed
          .take(10)
          .map((e) {
            final item = e.product.itemNumber.trim();
            final walk = e.row?.walkPosition?.toString() ?? 'null';
            final sub = e.row?.subPosition?.toString() ?? 'null';
            return '$item/$walk/$sub';
          })
          .join(', ');
      debugPrint('[WalkOrder] first 10 after sort=$first10');
    }
    // Intentionally no quote-priority sort: preserve normal catalog browse order.
    _catalogFilteredCacheKey = key;
    _catalogFilteredProductsCache = out;
    return out;
  }

  bool _isProductInStockForEcatalog(Product product) {
    return product.whse1InStock || product.whse2InStock;
  }

  int _qtyInCurrentQuoteForProduct(Product product) {
    final key = _orderLineKeyForProduct(product);
    return _orderLineByKey[key]?.quantity ?? 0;
  }

  /// Value passed to [_enqueueScan] / [_processScan]: prefer UPC, else item #.
  /// Must contain at least one digit (same gate as [_processScan]).
  String? _ecatalogScanPayloadForProduct(Product product) {
    final upc = product.upc.trim();
    if (upc.isNotEmpty && digitsOnly(upc).isNotEmpty) {
      return upc;
    }
    final item = product.itemNumber.trim();
    if (item.isNotEmpty && digitsOnly(item).isNotEmpty) {
      return item;
    }
    return null;
  }

  void _incrementCatalogProductQty(Product product) {
    final payload = _ecatalogScanPayloadForProduct(product);
    if (payload == null) {
      debugPrint(
        '[ECatalog] add skipped: no scannable digits in UPC or item # '
        '(item=${product.itemNumber})',
      );
      return;
    }
    _enqueueScan(payload, source: 'ecatalog');
  }

  Future<void> _addECatalogSearchEntry() async {
    final input = _catalogSearchController.text.trim();
    if (input.isEmpty) return;
    final product = _findExactProductForQuickEntry(input);
    if (product == null) {
      _showExactLookupMessageForQuery(input, scanTab: false);
      return;
    }
    if (!await _ensureQuoteReadyForManualAdd()) return;
    await _ensureRoutingForProduct(product);
    final bucket = _resolveQuoteBucketForProduct(product);
    final added = _addProduct(
      product,
      input,
      bucket: bucket,
      feedbackSource: 'ecatalog',
    );
    if (!added) return;
    _catalogSearchController.clear();
    if (!mounted) return;
    _setStateDebug('ecatalog_quick_entry_clear_search', () {
      _catalogSearchQuery = '';
      _ecatalogExpandedItemKey = null;
    });
  }

  /// ECatalog catalog row only. Branch order: (1) PS → Reg.+Sale; (2) NET → NET;
  /// (3) discount-eligible + customer discount → Reg.+Your Price; (4) Price.
  /// Uses [Product.isPs] / [Product.isNet] (same source as chips and [_productPricingState]).
  Widget _buildECatalogListPriceColumn({
    required Product product,
    required TextTheme textTheme,
    required ColorScheme colorScheme,
  }) {
    final isPs = product.isPs;
    final isNet = product.isNet;
    final discountEligible = product.discountEligible;
    final customerDiscountPct = _getCustomerDiscountPercent();
    final hasCustomerDiscount = customerDiscountPct > 0;
    final showRegAndYourPrice = discountEligible && hasCustomerDiscount;

    if (kDebugMode && _ecatalogListPriceColumnDebug) {
      final branch = isPs
          ? 'PS'
          : isNet
          ? 'NET'
          : showRegAndYourPrice
          ? 'DISCOUNT'
          : 'PRICE_ONLY';
      debugPrint(
        '[ECatalog price] #${product.itemNumber} | "${product.description}" '
        '| psRaw="${product.psRaw}" isPs=$isPs | isNet=$isNet '
        '| discountEligible=$discountEligible | custDiscPct=$customerDiscountPct '
        '| branch=$branch',
      );
    }

    final catalogLine = OrderLine(product: product, quantity: 1, scans: 0);
    final yourPrice = showRegAndYourPrice
        ? _roundedUnitPrice(_getDiscountedUnitPrice(catalogLine))
        : null;
    return _buildProductPriceSummary(
      product: product,
      hasDiscount: showRegAndYourPrice,
      discountedUnitPrice: yourPrice,
      regularStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      mutedStyle: textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurfaceVariant,
      ),
      highlightedStyle: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: Colors.green.shade800,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  void _showECatalogProductDetail(Product product) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final safeBottom = MediaQuery.of(context).padding.bottom;
        final theme = Theme.of(context);
        return SingleChildScrollView(
          padding: EdgeInsets.only(bottom: safeBottom + 16),
          child: _ECatalogProductDetailSheet(
            product: product,
            ecatalogPricing: _buildECatalogListPriceColumn(
              product: product,
              textTheme: theme.textTheme,
              colorScheme: theme.colorScheme,
            ),
          ),
        );
      },
    );
  }

  /// ECatalog category and sub-category dropdowns: identical [InputDecorator] +
  /// [DropdownButton] styling (theme [InputDecorationTheme] applies to both).
  Widget _ecatalogCatalogFilterDropdown({
    required String labelText,
    required String? value,
    required List<DropdownMenuItem<String?>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(labelText: labelText),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: value,
          style: theme.textTheme.titleMedium,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildECatalogTab() {
    if (_activeTabIndex != _tabIndexECatalog) {
      return const SizedBox.shrink();
    }
    if (_loadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }
    final selectedCustomerHistoryKey = _customerHistoryCacheKey(_selectedCustomer);
    if (_selectedCustomer != null &&
        selectedCustomerHistoryKey.isNotEmpty &&
        _previouslyOrderedCustomerCacheKey != selectedCustomerHistoryKey &&
        _previouslyOrderedHistoryLoadInFlightKey != selectedCustomerHistoryKey) {
      unawaited(_refreshPreviouslyOrderedHistoryForSelectedCustomer());
    }
    final filtered = _filteredCatalogProducts();
    final int totalCatalogProducts = _productsByItemNumber.length;
    final categories = _catalogCategories();
    final validatedCatalogCategory =
        _resolvedCatalogCategoryForEcatalogFilters();
    if (_selectedCatalogCategory != null &&
        !categories.contains(_selectedCatalogCategory!)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedCatalogCategory = null;
          _selectedCatalogSubCategory = null;
        });
      });
    }
    final subCategories = _catalogSubCategoriesForSelectedCategory();
    final validatedCatalogSubCategory =
        _selectedCatalogSubCategory != null &&
            subCategories.contains(_selectedCatalogSubCategory)
        ? _selectedCatalogSubCategory
        : null;
    if (_selectedCatalogSubCategory != null &&
        !subCategories.contains(_selectedCatalogSubCategory!)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedCatalogSubCategory = null);
      });
    }
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final int quoteItemCount = _orderLines.length;
    final bool orderHasDiscount = _orderHasAnyDiscount();
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onECatalogScrollDismissKeyboard,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildECatalogOrderSummaryBar(
                          textTheme: textTheme,
                          orderHasDiscount: orderHasDiscount,
                        ),
                        const SizedBox(height: 8),
                        _buildECatalogTopActionBar(),
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: _buildECatalogOrderPanel(),
                          crossFadeState: _ecatalogOrderPanelExpanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 180),
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _catalogSearchController,
                                focusNode: _ecatalogSearchFocusNode,
                                decoration: const InputDecoration(
                                  labelText: 'Search',
                                  hintText:
                                      'Item #, description, UPC, type, category',
                                ),
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) => unawaited(
                                  _addECatalogSearchEntry(),
                                ),
                                onChanged: _onCatalogSearchChanged,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: FilledButton.tonal(
                                onPressed: () => unawaited(
                                  _addECatalogSearchEntry(),
                                ),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                ),
                                child: const Text('Add'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilterChip(
                              label: const Text('New Items'),
                              selected: _catalogMerchandising == 'newItems',
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _catalogMerchandising = 'newItems';
                                  } else if (_catalogMerchandising ==
                                      'newItems') {
                                    _catalogMerchandising = null;
                                  }
                                  _selectedCatalogCategory = null;
                                  _selectedCatalogSubCategory = null;
                                });
                              },
                            ),
                            FilterChip(
                              label: const Text('Everyday'),
                              selected: _catalogMerchandising == 'everyday',
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _catalogMerchandising = 'everyday';
                                  } else if (_catalogMerchandising ==
                                      'everyday') {
                                    _catalogMerchandising = null;
                                  }
                                  _selectedCatalogCategory = null;
                                  _selectedCatalogSubCategory = null;
                                });
                              },
                            ),
                            FilterChip(
                              label: const Text('Decor & Giftware'),
                              selected: _catalogMerchandising == 'homeDecor',
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _catalogMerchandising = 'homeDecor';
                                  } else if (_catalogMerchandising ==
                                      'homeDecor') {
                                    _catalogMerchandising = null;
                                  }
                                  _selectedCatalogCategory = null;
                                  _selectedCatalogSubCategory = null;
                                });
                              },
                            ),
                            FilterChip(
                              label: const Text('Seasonal'),
                              selected: _catalogMerchandising == 'seasonal',
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _catalogMerchandising = 'seasonal';
                                  } else if (_catalogMerchandising ==
                                      'seasonal') {
                                    _catalogMerchandising = null;
                                  }
                                  _selectedCatalogCategory = null;
                                  _selectedCatalogSubCategory = null;
                                });
                              },
                            ),
                            FilterChip(
                              label: const Text('Sale'),
                              selected: _catalogMerchandising == 'sale',
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _catalogMerchandising = 'sale';
                                  } else if (_catalogMerchandising == 'sale') {
                                    _catalogMerchandising = null;
                                  }
                                  _selectedCatalogCategory = null;
                                  _selectedCatalogSubCategory = null;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilterChip(
                              label: const Text('In Order'),
                              selected: _catalogInOrderOnly,
                              onSelected: (selected) {
                                setState(() => _catalogInOrderOnly = selected);
                              },
                            ),
                            FilterChip(
                              label: const Text('In Stock Only'),
                              selected: _catalogInStockOnly,
                              onSelected: (selected) {
                                setState(() => _catalogInStockOnly = selected);
                              },
                            ),
                            FilterChip(
                              label: const Text('Previously Ordered Only'),
                              selected: _catalogPreviouslyOrderedOnly,
                              onSelected: (selected) {
                                setState(
                                  () => _catalogPreviouslyOrderedOnly = selected,
                                );
                              },
                            ),
                            TextButton.icon(
                              onPressed:
                                  (_catalogMerchandising != null ||
                                      _catalogInOrderOnly ||
                                      _catalogInStockOnly ||
                                      _catalogPreviouslyOrderedOnly ||
                                      _selectedCatalogCategory != null ||
                                      _selectedCatalogSubCategory != null)
                                  ? () {
                                      setState(() {
                                        _catalogMerchandising = null;
                                        _catalogInOrderOnly = false;
                                        _catalogInStockOnly = false;
                                        _catalogPreviouslyOrderedOnly = false;
                                        _selectedCatalogCategory = null;
                                        _selectedCatalogSubCategory = null;
                                      });
                                    }
                                  : null,
                              icon: const Icon(Icons.clear),
                              label: const Text('Clear Filters'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _ecatalogCatalogFilterDropdown(
                                  labelText: 'Category',
                                  value: validatedCatalogCategory,
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('All Categories'),
                                    ),
                                    for (final c in categories)
                                      DropdownMenuItem<String?>(
                                        value: c,
                                        child: Text(
                                          c,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) {
                                    setState(() {
                                      _selectedCatalogCategory = v;
                                      _selectedCatalogSubCategory = null;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _ecatalogCatalogFilterDropdown(
                                  labelText: 'Sub-Category',
                                  value: validatedCatalogSubCategory,
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('All Sub-Categories'),
                                    ),
                                    for (final sub in subCategories)
                                      DropdownMenuItem<String?>(
                                        value: sub,
                                        child: Text(
                                          sub,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) {
                                    setState(
                                      () => _selectedCatalogSubCategory = v,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Showing ${filtered.length} of $totalCatalogProducts products',
                          style: textTheme.bodySmall?.copyWith(
                            color: _kSecondaryText,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  if (filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          _catalogSearchQuery.trim().isNotEmpty
                              ? "No products found for '${_catalogSearchQuery.trim()}'"
                              : _catalogInOrderOnly
                              ? 'No items from this order match the current filter.'
                              : 'No products match',
                          style: textTheme.bodyLarge?.copyWith(
                            color: _kSecondaryText,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final listedProduct = filtered[index];
                        final orderLineKey = _orderLineKeyForProduct(listedProduct);
                        final line = _orderLineByKey[orderLineKey];
                        final displayProduct = _productsByItemNumber[orderLineKey];
                        final product =
                            displayProduct ?? line?.product ?? listedProduct;
                        final inCurrentOrder = line != null;
                        final qtyInQuote = line?.quantity ?? 0;
                        final lineTotal = line != null
                            ? _getDiscountedLineTotal(line)
                            : 0.0;
                        final previouslyOrdered = _isPreviouslyOrdered(product);
                        final productFlagChips = <Widget>[
                          ..._productFlagChips(context, product),
                          if (previouslyOrdered)
                            _ecatalogPreviouslyOrderedBadge(context),
                        ];
                        final catLabel = product.category.trim().isEmpty
                            ? '—'
                            : product.category.trim();
                        final subLabel = product.subCategory.trim().isEmpty
                            ? '—'
                            : product.subCategory.trim();
                        final ecKey = product.itemNumber.trim();
                        final isExpanded = _ecatalogExpandedItemKey == ecKey;
                        final Widget ecatalogItemCard = Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            type: MaterialType.card,
                            color: qtyInQuote > 0
                                ? colorScheme.primaryContainer.withValues(
                                    alpha: 0.22,
                                  )
                                : colorScheme.surface,
                            elevation: 0.5,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Row(
                                key: ValueKey(product.itemNumber),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () {
                                        _setStateDebug(
                                          'ecatalog_toggle_row_expand',
                                          () {
                                            if (_ecatalogExpandedItemKey ==
                                                ecKey) {
                                              _ecatalogExpandedItemKey = null;
                                            } else {
                                              _ecatalogExpandedItemKey = ecKey;
                                            }
                                          },
                                        );
                                      },
                                      onLongPress: () =>
                                          _showECatalogProductDetail(product),
                                      borderRadius: BorderRadius.circular(8),
                                      child: isExpanded
                                          ? Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  child: AspectRatio(
                                                    aspectRatio: 4 / 3,
                                                    child: Image.network(
                                                      'https://showroom-images.netlify.app/images/$ecKey.jpeg',
                                                      fit: BoxFit.cover,
                                                      cacheWidth: 800,
                                                      cacheHeight: 600,
                                                      filterQuality:
                                                          FilterQuality.low,
                                                      loadingBuilder:
                                                          (
                                                            context,
                                                            child,
                                                            loadingProgress,
                                                          ) {
                                                            if (loadingProgress ==
                                                                null) {
                                                              return child;
                                                            }
                                                            return ColoredBox(
                                                              color: colorScheme
                                                                  .surfaceContainerHighest,
                                                              child: Icon(
                                                                Icons
                                                                    .image_outlined,
                                                                size: 48,
                                                                color:
                                                                    colorScheme
                                                                        .outline,
                                                              ),
                                                            );
                                                          },
                                                      errorBuilder:
                                                          (
                                                            context,
                                                            error,
                                                            stackTrace,
                                                          ) {
                                                            return ColoredBox(
                                                              color: colorScheme
                                                                  .surfaceContainerHighest,
                                                              child: Icon(
                                                                Icons
                                                                    .image_not_supported_outlined,
                                                                size: 48,
                                                                color:
                                                                    colorScheme
                                                                        .outline,
                                                              ),
                                                            );
                                                          },
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              product
                                                                  .itemNumber,
                                                              style: textTheme
                                                                  .titleSmall
                                                                  ?.copyWith(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                  ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                          if (inCurrentOrder)
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets.only(
                                                                    left: 6,
                                                                  ),
                                                              child:
                                                                  _ecatalogInOrderQtyBadge(
                                                                    context,
                                                                    qtyInQuote,
                                                                  ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                    if (productFlagChips
                                                        .isNotEmpty)
                                                      Flexible(
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                left: 6,
                                                              ),
                                                          child: Align(
                                                            alignment: Alignment
                                                                .centerRight,
                                                            child: Wrap(
                                                              spacing: 6,
                                                              runSpacing: 6,
                                                              alignment:
                                                                  WrapAlignment
                                                                      .end,
                                                              children:
                                                                  productFlagChips,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    Icon(
                                                      Icons.keyboard_arrow_up,
                                                      size: 22,
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  product.description,
                                                  style: textTheme.bodyMedium,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '$catLabel / $subLabel',
                                                  style: textTheme.bodySmall
                                                      ?.copyWith(
                                                        color: _kSecondaryText,
                                                      ),
                                                ),
                                                const SizedBox(height: 2),
                                                _buildECatalogListPriceColumn(
                                                  product: product,
                                                  textTheme: textTheme,
                                                  colorScheme: colorScheme,
                                                ),
                                                _warehouseAvailabilityLinesWidget(
                                                  context,
                                                  product,
                                                  padding: const EdgeInsets.only(
                                                    top: 4,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _ECatalogProductThumbnail(
                                                  product: product,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Row(
                                                              children: [
                                                                Expanded(
                                                                  child: Text(
                                                                    product
                                                                        .itemNumber,
                                                                    style: textTheme
                                                                        .titleSmall
                                                                        ?.copyWith(
                                                                          fontWeight:
                                                                              FontWeight.w600,
                                                                        ),
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                ),
                                                                if (inCurrentOrder)
                                                                  Padding(
                                                                    padding:
                                                                        const EdgeInsets.only(
                                                                          left:
                                                                              6,
                                                                        ),
                                                                    child: _ecatalogInOrderQtyBadge(
                                                                      context,
                                                                      qtyInQuote,
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                          if (productFlagChips
                                                              .isNotEmpty)
                                                            Flexible(
                                                              child: Padding(
                                                                padding:
                                                                    const EdgeInsets.only(
                                                                      left: 6,
                                                                    ),
                                                                child: Align(
                                                                  alignment:
                                                                      Alignment
                                                                          .centerRight,
                                                                  child: Wrap(
                                                                    spacing: 6,
                                                                    runSpacing:
                                                                        6,
                                                                    alignment:
                                                                        WrapAlignment
                                                                            .end,
                                                                    children:
                                                                        productFlagChips,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          Icon(
                                                            Icons
                                                                .keyboard_arrow_down,
                                                            size: 22,
                                                            color: colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        product.description,
                                                        style: textTheme
                                                            .bodyMedium,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        '$catLabel / $subLabel',
                                                        style: textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color:
                                                                  _kSecondaryText,
                                                            ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      const SizedBox(height: 2),
                                                      _buildECatalogListPriceColumn(
                                                        product: product,
                                                        textTheme: textTheme,
                                                        colorScheme:
                                                            colorScheme,
                                                      ),
                                                      _warehouseAvailabilityLinesWidget(
                                                        context,
                                                        product,
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 4,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 132,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        SizedBox(
                                          height: 40,
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: inCurrentOrder
                                                ? Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(
                                                              minWidth: 40,
                                                              minHeight: 40,
                                                            ),
                                                        onPressed: () =>
                                                            _decreaseLineQty(
                                                              line,
                                                            ),
                                                        icon: const Icon(
                                                          Icons
                                                              .remove_circle_outline,
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 28,
                                                        child: Text(
                                                          '$qtyInQuote',
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: textTheme
                                                              .titleSmall
                                                              ?.copyWith(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                        ),
                                                      ),
                                                      IconButton(
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(
                                                              minWidth: 40,
                                                              minHeight: 40,
                                                            ),
                                                        onPressed: () =>
                                                            _increaseLineQty(
                                                              line,
                                                            ),
                                                        icon: const Icon(
                                                          Icons
                                                              .add_circle_outline,
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : TextButton(
                                                    onPressed: () =>
                                                        _incrementCatalogProductQty(
                                                          product,
                                                        ),
                                                    style: TextButton.styleFrom(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 4,
                                                          ),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                    ),
                                                    child: Text(
                                                      'Add',
                                                      style: textTheme
                                                          .labelLarge
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 16,
                                          child: inCurrentOrder
                                              ? Text(
                                                  _formatCurrency(lineTotal),
                                                  textAlign: TextAlign.right,
                                                  style: textTheme.bodySmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color:
                                                            colorScheme.primary,
                                                      ),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                        if (line != null) {
                          return KeyedSubtree(
                            key: ValueKey(orderLineKey),
                            child: _buildOrderCard(
                              line,
                              compactLayout: true,
                              compactExpandHost:
                                  _OrderLineCardCompactExpandHost.ecatalogTab,
                              displayProduct: displayProduct ?? product,
                            ),
                          );
                        }
                        return ecatalogItemCard;
                      }, childCount: filtered.length),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: SafeArea(
                top: false,
                minimum: EdgeInsets.zero,
                child: Text(
                  '$quoteItemCount items | $_totalUnits qty | ${_formatCurrency(_orderTotal)}',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveTab() {
    if (_activeTabIndex != _tabIndexArchive) {
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
      final bucketExportKey = _logicalQuoteBucketKey(
        primaryInfo.quoteBucketKey,
      );

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
        if (_logicalQuoteBucketKey(info.quoteBucketKey) != bucketExportKey) {
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
      final matchesEverydayPrefix = upperName.startsWith(
        'EVERYDAY QUOTE_${datePart}_',
      );
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
          final info = SavedQuoteInfo.fromJson(Map<String, dynamic>.from(e));
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

  /// Ensures [quoteId] has an active, archive-disjoint row in the active index when
  /// [quote_<id>.json] exists and is non-empty. Used after multi-bucket import so
  /// Export / Load Quote see every routed quote without a UI refresh.
  Future<void> _ensureActiveIndexRowForQuoteFile(String quoteId) async {
    if (quoteId.isEmpty) return;
    try {
      final dir = await _getQuotesDirectory();
      await _ensureLegacyQuoteIndexMigratedIfNeeded();
      final quoteFile = File('${dir.path}/quote_$quoteId.json');
      if (!await quoteFile.exists()) return;

      final data = Map<String, dynamic>.from(
        jsonDecode(await quoteFile.readAsString()) as Map,
      );
      if (persistedQuoteDataIsEmptyForReuse(data)) return;

      if (await _quoteIdHasActiveEligibleRowInActiveIndexStorage(quoteId)) {
        return;
      }

      var name = (data['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) name = 'NEW QUOTE';
      name = name.toUpperCase();

      String customerName = '';
      String customerId = '';
      final customerMap = data['customer'];
      if (customerMap is Map<String, dynamic>) {
        final c = Customer.fromJson(Map<String, dynamic>.from(customerMap));
        customerName = c.displayName.trim();
        customerId = c.id.trim();
      }

      var rawBucketKey = (data['quoteBucketKey'] as String?)?.trim() ?? '';
      var persistedBucketKey = _logicalQuoteBucketKey(rawBucketKey);
      final rootBucketKeyForRow = persistedBucketKey.isNotEmpty
          ? persistedBucketKey
          : _defaultQuoteBucketDefinition.bucketKey;

      var bucketLabel = (data['quoteBucketLabel'] as String?)?.trim() ?? '';
      if (bucketLabel.isEmpty) {
        final fromConfig = _quoteBucketsByBucketKey[rootBucketKeyForRow];
        bucketLabel =
            fromConfig?.displayLabel ??
            _defaultQuoteBucketDefinition.displayLabel;
      }
      if (_logicalQuoteBucketKey(rootBucketKeyForRow) ==
          _defaultQuoteBucketKey) {
        bucketLabel = _defaultQuoteBucketDefinition.displayLabel;
      }

      final updatedAt =
          DateTime.tryParse((data['updatedAt'] as String?) ?? '') ??
          DateTime.now();

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

      final priorIdx = list.indexWhere((e) => e['id']?.toString() == quoteId);
      final priorEntry = priorIdx >= 0
          ? Map<String, dynamic>.from(list[priorIdx])
          : <String, dynamic>{};

      list.removeWhere((e) => e['id']?.toString() == quoteId);

      final row = <String, dynamic>{
        ...priorEntry,
        'id': quoteId,
        'name': name,
        'customerName': customerName,
        'customerId': customerId,
        'quoteBucketKey': rootBucketKeyForRow,
        'quoteBucketLabel': bucketLabel,
        'updatedAt': updatedAt.toIso8601String(),
        'quoteStatus': quoteLifecycleStatusToJson(QuoteLifecycleStatus.active),
      };

      list.insert(0, row);
      await indexFile.writeAsString(jsonEncode(list), flush: true);
      await _removeQuoteFromArchiveIndexIfPresent(quoteId);
    } catch (e, st) {
      debugPrint(
        '[QuoteIndex] ensure active row for id=$quoteId failed: $e\n$st',
      );
    }
  }

  Future<void> _syncOrderImportTouchedQuotesInActiveIndex() async {
    final touchedIds = <String>{..._orderImportTouchedQuoteIds};
    final cur = _currentQuoteId;
    if (cur != null && cur.isNotEmpty) {
      touchedIds.add(cur);
    }
    if (touchedIds.isEmpty) return;
    final touched = touchedIds.toList();
    for (final id in touched) {
      await _ensureActiveIndexRowForQuoteFile(id);
    }
    await _loadQuoteIndex();
    if (kDebugMode) {
      final dir = await _getQuotesDirectory();
      for (final id in touched) {
        final qf = File('${dir.path}/quote_$id.json');
        final onDisk = await qf.exists();
        var bucketTag = '';
        if (onDisk) {
          try {
            final raw = await qf.readAsString();
            final d = Map<String, dynamic>.from(jsonDecode(raw) as Map);
            bucketTag =
                (d['quoteBucketLabel'] as String?)?.trim() ??
                _logicalQuoteBucketKey(
                  (d['quoteBucketKey'] as String?)?.trim() ?? '',
                );
          } catch (_) {
            bucketTag = '?';
          }
        }
        final eligible = await _quoteIdHasActiveEligibleRowInActiveIndexStorage(
          id,
        );
        debugPrint(
          '[ImportTouched] quoteId=$id bucket=${bucketTag.isEmpty ? '?' : bucketTag} '
          'saved=${onDisk ? 'yes' : 'no'} activeIndex=${eligible ? 'yes' : 'no'}',
        );
      }
      final idx = await _loadQuoteIndex();
      final visible = touched
          .where((id) => idx.any((e) => e.id == id))
          .toList();
      debugPrint(
        '[ImportPostSync] activeIndexCount=${idx.length} '
        'touchedVisible=${visible.join(',')}',
      );
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
    if (_selectedCustomer == null) {
      if (_orderLines.isEmpty && _currentQuoteId == null) {
        return;
      }
      _discardWorkingOrderIfNoCustomerSelected();
      return;
    }

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
        'listPrice': line.product.listPrice,
        'productType': line.product.productType,
        'discountRaw': line.product.discountRaw,
        'discountEligible': line.product.discountEligible,
        'netRaw': line.product.netRaw,
        'isNet': line.product.isNet,
        'psRaw': line.product.psRaw,
        'isPs': line.product.isPs,
        'isNewRelease': line.product.isNewRelease,
        'category': line.product.category,
        'subCategory': line.product.subCategory,
        'whse1InStock': line.product.whse1InStock,
        'whse2InStock': line.product.whse2InStock,
        'whse1OutOfStock': line.product.whse1OutOfStock,
        'whse2OutOfStock': line.product.whse2OutOfStock,
        'whse1ComingSoon': line.product.whse1ComingSoon,
        'whse2ComingSoon': line.product.whse2ComingSoon,
        'whse1AvailabilityDisplay': line.product.whse1AvailabilityDisplay,
        'whse2AvailabilityDisplay': line.product.whse2AvailabilityDisplay,
        'minOrderQty': line.product.minOrderQty,
        'caseQty': line.product.caseQty,
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
        final eligible = await _quoteIdHasActiveEligibleRowInActiveIndexStorage(
          workspaceId,
        );
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
              _activeQuoteBucketLabel =
                  _defaultQuoteBucketDefinition.displayLabel;
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
      // Active index rows must stay eligible for Load Quote / export. A stale
      // quoteStatus copied from [priorEntry] (e.g. archived/confirmed) would
      // otherwise persist and hide otherwise valid routed quotes from
      // [_loadQuoteIndex] / [_quoteIdHasActiveEligibleRowInActiveIndexStorage].
      row['quoteStatus'] = quoteLifecycleStatusToJson(
        QuoteLifecycleStatus.active,
      );

      list.insert(0, row);

      await indexFile.writeAsString(jsonEncode(list), flush: true);
      await _removeQuoteFromArchiveIndexIfPresent(id);

      if (_orderCsvImportInProgress) {
        _orderImportTouchedQuoteIds.add(id);
      }

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

  /// Debug-only: one persisted quote containing every loaded catalog line, without
  /// [_ensureRoutingForProduct] / workspace switches (no multi-bucket split).
  Future<void> _persistFullCatalogTestQuote(Customer customer) async {
    final now = DateTime.now();
    final defaultSeq = await _generateDefaultQuoteName();
    final name = 'FULL CATALOG TEST $defaultSeq'.toUpperCase();
    final id = now.millisecondsSinceEpoch.toString();

    final orderedProducts = _productsByItemNumber.values.toList()
      ..sort((a, b) => _compareItemNumberAscending(a.itemNumber, b.itemNumber));

    final linesJson = <Map<String, dynamic>>[];
    for (final product in orderedProducts) {
      final bucket = _resolveQuoteBucketForProduct(product);
      linesJson.add({
        'upc': product.upc,
        'itemNumber': product.itemNumber,
        'description': product.description,
        'price': product.price,
        'productType': product.productType,
        'discountRaw': product.discountRaw,
        'discountEligible': product.discountEligible,
        'netRaw': product.netRaw,
        'isNet': product.isNet,
        'psRaw': product.psRaw,
        'isPs': product.isPs,
        'isNewRelease': product.isNewRelease,
        'category': product.category,
        'subCategory': product.subCategory,
        'whse1InStock': product.whse1InStock,
        'whse2InStock': product.whse2InStock,
        'whse1OutOfStock': product.whse1OutOfStock,
        'whse2OutOfStock': product.whse2OutOfStock,
        'whse1ComingSoon': product.whse1ComingSoon,
        'whse2ComingSoon': product.whse2ComingSoon,
        'quoteBucketKey': bucket.bucketKey,
        'quoteBucketLabel': bucket.displayLabel,
        'quantity': 1,
        'scans': 0,
      });
    }

    final def = _defaultQuoteBucketDefinition;
    final persistedBucketKey = _logicalQuoteBucketKey(def.bucketKey);
    final rootBucketKey = persistedBucketKey.isNotEmpty
        ? persistedBucketKey
        : def.bucketKey;

    final customerName = customer.displayName.trim();
    final customerId = customer.id.trim();

    try {
      final dir = await _getQuotesDirectory();

      final quoteJson = {
        'id': id,
        'name': name,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'quoteBucketKey': rootBucketKey,
        'quoteBucketLabel': def.displayLabel,
        'lines': linesJson,
        'customer': customer.toJson(),
      };

      final file = File('${dir.path}/quote_$id.json');
      await file.writeAsString(jsonEncode(quoteJson), flush: true);

      final indexFile = await _activeQuoteIndexFileForReadWrite(dir);
      var list = <Map<String, dynamic>>[];

      if (await indexFile.exists()) {
        final content = await indexFile.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          list = List<Map<String, dynamic>>.from(
            decoded.map((e) => Map<String, dynamic>.from(e as Map)),
          );
        }
      }

      list.removeWhere((e) => e['id']?.toString() == id);

      final row = <String, dynamic>{
        'id': id,
        'name': name,
        'customerName': customerName,
        'customerId': customerId,
        'quoteBucketKey': rootBucketKey,
        'quoteBucketLabel': def.displayLabel,
        'updatedAt': now.toIso8601String(),
      };
      row['quoteStatus'] = quoteLifecycleStatusToJson(
        QuoteLifecycleStatus.active,
      );

      list.insert(0, row);

      await indexFile.writeAsString(jsonEncode(list), flush: true);
      await _removeQuoteFromArchiveIndexIfPresent(id);

      if (!mounted) return;
      setState(() {
        _status =
            'Full catalog test quote saved: $name (${linesJson.length} lines)';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved full catalog test quote ($name, ${linesJson.length} lines).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Error saving full catalog test quote: $e';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving test quote: $e')));
    }

    if (!mounted) return;
    debugPrint(
      '[DependentsDiag] _persistFullCatalogTestQuote: before _requestScannerFocus()',
    );
    _requestScannerFocus();
    debugPrint(
      '[DependentsDiag] _persistFullCatalogTestQuote: after _requestScannerFocus()',
    );
  }

  Future<void> _buildFullCatalogTestQuoteFlow() async {
    if (!kDebugMode) return;
    if (_productsByItemNumber.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Load products first.')));
      return;
    }
    if (_customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Load customers CSV first.')),
      );
      return;
    }

    _suspendScannerFocusRecovery = true;
    try {
      debugPrint('[DependentsDiag] opening simple picker');
      final customer = await _showSimpleCustomerPickerForCatalogTests();
      debugPrint('[DependentsDiag] closing simple picker result=$customer');
      if (!mounted || customer == null) return;

      debugPrint('[DependentsDiag] opening confirm dialog');
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Full catalog test quote'),
            content: const Text(
              'This will create one large single test quote with all loaded products. Continue?',
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
      debugPrint(
        '[DependentsDiag] closing confirm dialog confirm=$confirm',
      );
      if (confirm != true || !mounted) return;

      await _persistFullCatalogTestQuote(customer);
      if (!mounted) return;
    } finally {
      _suspendScannerFocusRecovery = false;
    }
  }

  /// Same unit/list rules as [_iterQuoteShareAttachmentLines] for a live [Product]
  /// (customer discount only when [_productPricingState] is discount-eligible).
  ({
    double listPrice,
    double price,
    String discountCol,
    String netCol,
    String psCol,
  })
  _applyPricingLogic(Product product, Customer customer) {
    final customerDiscPct = customer.discountPercent;
    final state = _productPricingState(product);
    final shelfUnit = product.price;

    final double unitRaw;
    if (state == ProductPricingState.discountEligible && customerDiscPct > 0) {
      unitRaw = shelfUnit * (1 - customerDiscPct / 100.0);
    } else {
      unitRaw = shelfUnit;
    }

    final listPrice = _roundedUnitPrice(product.listPrice);

    var discountCol = '';
    if (state == ProductPricingState.discountEligible && customerDiscPct > 0) {
      discountCol = customerDiscPct == customerDiscPct.roundToDouble()
          ? customerDiscPct.round().toString()
          : customerDiscPct.toStringAsFixed(2);
    }

    final netCol = product.isNet ? 'YES' : '';
    final psCol = product.isPs ? 'YES' : '';

    return (
      listPrice: listPrice,
      price: _roundedUnitPrice(unitRaw),
      discountCol: discountCol,
      netCol: netCol,
      psCol: psCol,
    );
  }

  String _formatExportFileSizeKbMb(int byteLength) {
    if (byteLength >= 1024 * 1024) {
      return '${(byteLength / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (byteLength >= 1024) {
      return '${(byteLength / 1024).toStringAsFixed(1)} KB';
    }
    return '$byteLength B';
  }

  Future<void> _exportFullCatalogExcelQuoteFlow() async {
    if (!kDebugMode) return;
    debugPrint('[ExportDiag] export flow entered');
    if (_exportingFullCatalogExcel) return;
    if (_productsByItemNumber.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Load products first.')));
      return;
    }
    if (_customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Load customers CSV first.')),
      );
      return;
    }

    _suspendScannerFocusRecovery = true;
    try {
      debugPrint('[DependentsDiag] opening simple picker');
      final customer = await _showSimpleCustomerPickerForCatalogTests();
      debugPrint('[DependentsDiag] closing simple picker result=$customer');
      if (!mounted || customer == null) return;
      debugPrint('[ExportDiag] customer selected');

      debugPrint('[DependentsDiag] opening confirm dialog');
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Export full catalog'),
            content: const Text(
              'This will build and export a full catalog Excel quote (~18,000 items) '
              'without opening it in the app. Continue?',
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
      debugPrint(
        '[DependentsDiag] closing confirm dialog confirm=$confirm',
      );
      if (confirm != true || !mounted) return;
      debugPrint('[ExportDiag] confirm accepted');

      debugPrint(
        'Full catalog Excel: customer selected '
        '(id=${customer.id}, name=${customer.displayName})',
      );

      if (!mounted) return;
      setState(() => _exportingFullCatalogExcel = true);
      final sw = Stopwatch()..start();
      String? outPath;
      var rowCount = 0;
      try {
        final products = _sortByItemNumberAscending<Product>(
          _allProducts,
          (p) => p.itemNumber,
        );
        rowCount = products.length;
        debugPrint('Full catalog Excel: export start (products=$rowCount)');

        final excel = xlsx.Excel.createExcel();
        final defaultSheet = excel.getDefaultSheet() ?? excel.tables.keys.first;
        excel.rename(defaultSheet, 'Quote');
        final sheet = excel['Quote'];
        xlsx.TextCellValue t(String v) => xlsx.TextCellValue(v);

        sheet.appendRow([
          t('Item Number'),
          t('Description'),
          t('UPC'),
          t('List Price'),
          t('Price'),
          t('DISCOUNT'),
          t('NET'),
          t('PS'),
          t('Product Type'),
          t('Category'),
          t('Sub-Category'),
          t('Qty'),
          t('Minimum Order Quantity'),
          t('Case Quantity'),
        ]);

        debugPrint('[ExportDiag] row build start');
        for (var i = 0; i < products.length; i++) {
          final product = products[i];
          final pr = _applyPricingLogic(product, customer);
          final discountable = _productIsDiscountEligible(product);
          sheet.appendRow([
            t(product.itemNumber),
            t(product.description),
            t(product.upc),
            xlsx.DoubleCellValue(pr.listPrice),
            xlsx.DoubleCellValue(pr.price),
            t(discountable ? 'YES' : ''),
            t(discountable ? '' : 'YES'),
            t(pr.psCol),
            t(product.productType),
            t(product.category),
            t(product.subCategory),
            xlsx.IntCellValue(1),
            xlsx.IntCellValue(product.minOrderQty),
            xlsx.IntCellValue(product.caseQty),
          ]);
          if (i % 400 == 0 && i > 0) {
            debugPrint(
              '[DependentsDiag] _exportFullCatalogExcelQuoteFlow: before '
              'Future<void>.delayed(Duration.zero) yield i=$i',
            );
            await Future<void>.delayed(Duration.zero);
            debugPrint(
              '[DependentsDiag] _exportFullCatalogExcelQuoteFlow: after '
              'Future<void>.delayed(Duration.zero) yield i=$i mounted=$mounted',
            );
            if (!mounted) return;
          }
        }
        debugPrint('[ExportDiag] row build complete with row count $rowCount');

        debugPrint(
          'Full catalog Excel: rows written=$rowCount '
          '(matches products iterated=${products.length})',
        );

        const colWidths = <double>[
          14, // Item Number
          42, // Description
          14, // UPC
          12, // List Price
          12, // Price
          10, // DISCOUNT
          8, // NET
          8, // PS
          14, // Product Type
          18, // Category
          18, // Sub-Category
          8, // Qty
          12, // Minimum Order Quantity
          12, // Case Quantity
        ];
        for (var c = 0; c < colWidths.length; c++) {
          sheet.setColumnWidth(c, colWidths[c]);
        }

        final docs = await getApplicationDocumentsDirectory();
        debugPrint('[ExportDiag] output directory resolved: ${docs.path}');
        if (!mounted) return;
        final now = DateTime.now();
        final stamp =
            '${now.year.toString().padLeft(4, '0')}'
            '${now.month.toString().padLeft(2, '0')}'
            '${now.day.toString().padLeft(2, '0')}_'
            '${now.hour.toString().padLeft(2, '0')}'
            '${now.minute.toString().padLeft(2, '0')}'
            '${now.second.toString().padLeft(2, '0')}';
        final filename = 'FULL_CATALOG_$stamp.xlsx';
        final file = File(p.join(docs.path, filename));
        debugPrint('[ExportDiag] output file path chosen: ${file.path}');

        debugPrint('[ExportDiag] excel.encode() start');
        final bytes = excel.encode();
        final bytesNull = bytes == null;
        final bytesLen = bytes?.length ?? 0;
        debugPrint(
          '[ExportDiag] excel.encode() complete bytes is null=$bytesNull '
          'bytes length=$bytesLen',
        );

        if (bytes == null || bytes.isEmpty) {
          debugPrint('[ExportDiag] encode returned null/empty');
          sw.stop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Export failed: Excel encode returned no data.',
                ),
              ),
            );
            await showDialog<void>(
              context: context,
              builder: (dialogContext) {
                return AlertDialog(
                  title: const Text('Export failed'),
                  content: const Text(
                    'Excel encode returned no data. Nothing was written.',
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
          return;
        }

        debugPrint('[ExportDiag] writeAsBytes start');
        await file.writeAsBytes(bytes, flush: true);
        debugPrint('[ExportDiag] writeAsBytes complete');

        final existsAfter = await file.exists();
        final lenAfter = existsAfter ? await file.length() : 0;
        debugPrint(
          '[ExportDiag] after write: file.exists()=$existsAfter '
          'file.length()=$lenAfter',
        );

        if (!existsAfter || lenAfter <= 0) {
          sw.stop();
          debugPrint(
            '[ExportDiag] write verification failed path=${file.path} '
            'exists=$existsAfter length=$lenAfter',
          );
          if (mounted) {
            await showDialog<void>(
              context: context,
              builder: (dialogContext) {
                return AlertDialog(
                  title: const Text('Export failed'),
                  content: SelectableText(
                    'The file was not written correctly.\n\nPath:\n${file.path}',
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
          return;
        }

        if (!mounted) return;
        outPath = file.path;

        sw.stop();
        final elapsedSec = sw.elapsedMilliseconds / 1000.0;
        final sizeLabel = _formatExportFileSizeKbMb(lenAfter);
        debugPrint(
          'Full catalog Excel: export complete '
          'rows=$rowCount path=$outPath elapsed=${elapsedSec.toStringAsFixed(2)}s',
        );

        if (!mounted) return;
        debugPrint('[DependentsDiag] opening completion dialog');
        await showDialog<void>(
          context: context,
          builder: (ctx) {
            debugPrint('[ExportDiag] completion dialog shown');
            final pathStr = outPath ?? file.path;
            final body =
                'Rows exported: $rowCount\n'
                'Elapsed: ${elapsedSec.toStringAsFixed(2)} s\n'
                'File size: $sizeLabel\n'
                'Path:\n$pathStr';
            return AlertDialog(
              title: const Text('Export complete'),
              content: SingleChildScrollView(
                child: SelectableText(body),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: pathStr));
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Path copied')),
                      );
                    }
                  },
                  child: const Text('Copy Path'),
                ),
                TextButton(
                  onPressed: () async {
                    try {
                      await Share.shareXFiles([
                        XFile(
                          pathStr,
                          mimeType:
                              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                        ),
                      ]);
                    } catch (_) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Unable to share file'),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Share File'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    if (mounted) {
                      await _openCsvWithSystemHandler(File(pathStr));
                    }
                  },
                  child: const Text('Open File'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
        debugPrint('[DependentsDiag] closing completion dialog');
      } catch (e, st) {
        debugPrint('Full catalog Excel export failed: $e\n$st');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
        }
      } finally {
        sw.stop();
        if (mounted) {
          setState(() => _exportingFullCatalogExcel = false);
        }
      }
    } finally {
      _suspendScannerFocusRecovery = false;
    }
  }

  String _masterUpdateDebugTimestampSuffix() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
  }

  /// Writes one .xlsx using [ExportDiag] logging. Does not mutate quote/order state.
  Future<bool> _exportDiagEncodeWriteXlsxFile({
    required xlsx.Excel excel,
    required File file,
    required String diagFileTag,
  }) async {
    debugPrint('[ExportDiag] $diagFileTag excel.encode() start');
    final bytes = excel.encode();
    final bytesNull = bytes == null;
    final bytesLen = bytes?.length ?? 0;
    debugPrint(
      '[ExportDiag] $diagFileTag encode result isNull=$bytesNull bytesLength=$bytesLen',
    );
    if (bytes == null || bytes.isEmpty) {
      debugPrint('[ExportDiag] $diagFileTag encode returned null/empty');
      return false;
    }
    debugPrint('[ExportDiag] $diagFileTag writeAsBytes start path=${file.path}');
    await file.writeAsBytes(bytes, flush: true);
    debugPrint('[ExportDiag] $diagFileTag writeAsBytes complete');
    final existsAfter = await file.exists();
    final lenAfter = existsAfter ? await file.length() : 0;
    debugPrint(
      '[ExportDiag] $diagFileTag file exists=$existsAfter size=$lenAfter',
    );
    if (!existsAfter || lenAfter <= 0) {
      debugPrint(
        '[ExportDiag] $diagFileTag write verification failed path=${file.path}',
      );
      return false;
    }
    return true;
  }

  /// Single .xlsx pick for master build staging; cancel returns null (no snackbars).
  Future<String?> _pickMasterBuildXlsxFile(String dialogTitle) async {
    print('🔥 IMPORT ENTRY HIT 🔥');
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      dialogTitle: dialogTitle,
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.first.path;
    if (path == null || path.isEmpty) return null;
    return path;
  }

  /// File-only master workbook build: Quote + Products + PS + New Release → one .xlsx.
  /// Does not use catalog, [_orderLines], quotes, or tabs.
  Future<void> _buildUpdatedMasterProductsSheetFlow() async {
    if (!kDebugMode) return;
    if (_buildingUpdatedMasterSheet) return;
    if (!mounted) return;

    final fileSet = await showDialog<_MasterBuildFileSet>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        String? quotePath;
        String? productsPath;
        String? psPath;
        String? newReleasePath;
        String? whse1InStockPath;
        String? whse2InStockPath;
        String? whse1OutOfStockPath;
        String? whse2OutOfStockPath;
        String? whse1ComingSoonPath;
        String? whse2ComingSoonPath;

        return StatefulBuilder(
          builder: (context, setLocalState) {
            Widget fileRow({
              required String label,
              required String? path,
              required Future<void> Function() onPick,
            }) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: onPick,
                      child: Text(label),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      path == null ? '—' : p.basename(path),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _kSecondaryText,
                          ),
                    ),
                  ],
                ),
              );
            }

            final allSet = quotePath != null &&
                productsPath != null &&
                psPath != null &&
                newReleasePath != null &&
                whse1InStockPath != null &&
                whse2InStockPath != null &&
                whse1OutOfStockPath != null &&
                whse2OutOfStockPath != null &&
                whse1ComingSoonPath != null &&
                whse2ComingSoonPath != null;

            return AlertDialog(
              title: const Text('Build Updated Master Products Sheet'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    fileRow(
                      label: 'Quote file',
                      path: quotePath,
                      onPick: () async {
                        final path = await _pickMasterBuildXlsxFile(
                          'Master build: select Quote workbook (.xlsx)',
                        );
                        if (!dialogContext.mounted) return;
                        if (path != null) {
                          setLocalState(() => quotePath = path);
                          debugPrint(
                            '[MasterBuildDiag] Quote selected: $path',
                          );
                        }
                      },
                    ),
                    fileRow(
                      label: 'Products file',
                      path: productsPath,
                      onPick: () async {
                        final path = await _pickMasterBuildXlsxFile(
                          'Master build: select Products workbook (.xlsx)',
                        );
                        if (!dialogContext.mounted) return;
                        if (path != null) {
                          setLocalState(() => productsPath = path);
                          debugPrint(
                            '[MasterBuildDiag] Products selected: $path',
                          );
                        }
                      },
                    ),
                    fileRow(
                      label: 'PS file',
                      path: psPath,
                      onPick: () async {
                        final path = await _pickMasterBuildXlsxFile(
                          'Master build: select PS workbook (.xlsx)',
                        );
                        if (!dialogContext.mounted) return;
                        if (path != null) {
                          setLocalState(() => psPath = path);
                          debugPrint('[MasterBuildDiag] PS selected: $path');
                        }
                      },
                    ),
                    fileRow(
                      label: 'New Release file',
                      path: newReleasePath,
                      onPick: () async {
                        final path = await _pickMasterBuildXlsxFile(
                          'Master build: select New Release workbook (.xlsx)',
                        );
                        if (!dialogContext.mounted) return;
                        if (path != null) {
                          setLocalState(() => newReleasePath = path);
                          debugPrint(
                            '[MasterBuildDiag] New Release selected: $path',
                          );
                        }
                      },
                    ),
                    fileRow(
                      label: 'Whse 1 In Stock (IN Stock WHSE1.xlsx)',
                      path: whse1InStockPath,
                      onPick: () async {
                        final path = await _pickMasterBuildXlsxFile(
                          'Master build: select Whse 1 In Stock workbook (.xlsx)',
                        );
                        if (!dialogContext.mounted) return;
                        if (path != null) {
                          setLocalState(() => whse1InStockPath = path);
                          debugPrint(
                            '[MasterBuildDiag] Whse 1 In Stock selected: $path',
                          );
                        }
                      },
                    ),
                    fileRow(
                      label: 'Whse 2 In Stock (IN Stock WHSE2.xlsx)',
                      path: whse2InStockPath,
                      onPick: () async {
                        final path = await _pickMasterBuildXlsxFile(
                          'Master build: select Whse 2 In Stock workbook (.xlsx)',
                        );
                        if (!dialogContext.mounted) return;
                        if (path != null) {
                          setLocalState(() => whse2InStockPath = path);
                          debugPrint(
                            '[MasterBuildDiag] Whse 2 In Stock selected: $path',
                          );
                        }
                      },
                    ),
                    fileRow(
                      label: 'Whse 1 Out of Stock',
                      path: whse1OutOfStockPath,
                      onPick: () async {
                        final path = await _pickMasterBuildXlsxFile(
                          'Master build: select Whse 1 Out of Stock workbook (.xlsx)',
                        );
                        if (!dialogContext.mounted) return;
                        if (path != null) {
                          setLocalState(() => whse1OutOfStockPath = path);
                          debugPrint(
                            '[MasterBuildDiag] Whse 1 Out of Stock selected: $path',
                          );
                        }
                      },
                    ),
                    fileRow(
                      label: 'Whse 2 Out of Stock',
                      path: whse2OutOfStockPath,
                      onPick: () async {
                        final path = await _pickMasterBuildXlsxFile(
                          'Master build: select Whse 2 Out of Stock workbook (.xlsx)',
                        );
                        if (!dialogContext.mounted) return;
                        if (path != null) {
                          setLocalState(() => whse2OutOfStockPath = path);
                          debugPrint(
                            '[MasterBuildDiag] Whse 2 Out of Stock selected: $path',
                          );
                        }
                      },
                    ),
                    fileRow(
                      label: 'Whse 1 Coming Soon',
                      path: whse1ComingSoonPath,
                      onPick: () async {
                        final path = await _pickMasterBuildXlsxFile(
                          'Master build: select Whse 1 Coming Soon workbook (.xlsx)',
                        );
                        if (!dialogContext.mounted) return;
                        if (path != null) {
                          setLocalState(() => whse1ComingSoonPath = path);
                          debugPrint(
                            '[MasterBuildDiag] Whse 1 Coming Soon selected: $path',
                          );
                        }
                      },
                    ),
                    fileRow(
                      label: 'Whse 2 Coming Soon',
                      path: whse2ComingSoonPath,
                      onPick: () async {
                        final path = await _pickMasterBuildXlsxFile(
                          'Master build: select Whse 2 Coming Soon workbook (.xlsx)',
                        );
                        if (!dialogContext.mounted) return;
                        if (path != null) {
                          setLocalState(() => whse2ComingSoonPath = path);
                          debugPrint(
                            '[MasterBuildDiag] Whse 2 Coming Soon selected: $path',
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: allSet
                      ? () {
                          debugPrint(
                            '[MasterBuildDiag] Build pressed with all files selected',
                          );
                          Navigator.of(dialogContext).pop(
                            _MasterBuildFileSet(
                              quotePath: quotePath!,
                              productsPath: productsPath!,
                              psPath: psPath!,
                              newReleasePath: newReleasePath!,
                              whse1InStockPath: whse1InStockPath!,
                              whse2InStockPath: whse2InStockPath!,
                              whse1OutOfStockPath: whse1OutOfStockPath!,
                              whse2OutOfStockPath: whse2OutOfStockPath!,
                              whse1ComingSoonPath: whse1ComingSoonPath!,
                              whse2ComingSoonPath: whse2ComingSoonPath!,
                            ),
                          );
                        }
                      : null,
                  child: const Text('Build Master Sheet'),
                ),
              ],
            );
          },
        );
      },
    );

    if (fileSet == null || !mounted) return;

    setState(() => _buildingUpdatedMasterSheet = true);
    try {
      final report = await runUpdatedMasterProductsBuild(
        quoteFilePath: fileSet.quotePath,
        productsFilePath: fileSet.productsPath,
        psFilePath: fileSet.psPath,
        newReleaseFilePath: fileSet.newReleasePath,
        whse1InStockFilePath: fileSet.whse1InStockPath,
        whse2InStockFilePath: fileSet.whse2InStockPath,
        whse1OutOfStockFilePath: fileSet.whse1OutOfStockPath,
        whse2OutOfStockFilePath: fileSet.whse2OutOfStockPath,
        whse1ComingSoonFilePath: fileSet.whse1ComingSoonPath,
        whse2ComingSoonFilePath: fileSet.whse2ComingSoonPath,
      );

      if (!report.success || report.bytes == null) {
        debugPrint(
          '[MasterBuildDiag] build failed: ${report.errorMessage}',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Master build failed: ${report.errorMessage ?? "unknown"}',
              ),
            ),
          );
        }
        return;
      }

      final docs = await getApplicationDocumentsDirectory();
      if (!mounted) return;
      final stamp = _masterUpdateDebugTimestampSuffix();
      final outFile = File(
        p.join(docs.path, 'MASTER_PRODUCTS_UPDATED_$stamp.xlsx'),
      );
      await outFile.writeAsBytes(report.bytes!, flush: true);
      final existsAfter = await outFile.exists();
      final lenAfter = existsAfter ? await outFile.length() : 0;
      debugPrint(
        '[MasterBuildDiag] output path=${outFile.path} exists=$existsAfter '
        'length=$lenAfter',
      );

      if (!existsAfter || lenAfter <= 0) {
        debugPrint(
          '[MasterBuildDiag] write verification failed path=${outFile.path} '
          'exists=$existsAfter length=$lenAfter',
        );
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Master build failed'),
              content: SelectableText(
                'The file was not written correctly.\n\nPath:\n${outFile.path}',
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
        return;
      }

      if (!mounted) return;
      final pathStr = outFile.path;
      final totalRows = report.finalDataRowCount;
      final addedRows = report.addedFromNewRelease;
      final removedRows = report.removedRows;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          debugPrint('[MasterBuildDiag] completion dialog shown');
          final body =
              'Path:\n$pathStr\n\n'
              'Total rows: $totalRows\n'
              'Added rows: $addedRows\n'
              'Removed rows: $removedRows';
          return AlertDialog(
            title: const Text('Master Products Build Complete'),
            content: SingleChildScrollView(
              child: SelectableText(body),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    await Share.shareXFiles([
                      XFile(
                        pathStr,
                        mimeType:
                            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                      ),
                    ]);
                  } catch (_) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Unable to share file'),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Share File'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  if (mounted) {
                    await _openCsvWithSystemHandler(File(pathStr));
                  }
                },
                child: const Text('Open File'),
              ),
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: pathStr));
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Path copied')),
                    );
                  }
                },
                child: const Text('Copy Path'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (e, st) {
      debugPrint('[MasterBuildDiag] exception $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Master build failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _buildingUpdatedMasterSheet = false);
      } else {
        _buildingUpdatedMasterSheet = false;
      }
    }
  }

  /// Debug-only: Excel workbooks for Master sheet updates (list price, PS, new release).
  /// Does not load into UI workspace or mutate [_orderLines] / quotes / tabs.
  Future<void> _exportMasterUpdateSheetsFlow() async {
    if (!kDebugMode) return;
    debugPrint('[ExportDiag] MASTER_UPDATE start');
    if (_exportingMasterUpdateSheets) return;
    if (_productsByItemNumber.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Load products first.')));
      return;
    }
    if (_customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Load customers CSV first.')),
      );
      return;
    }

    _suspendScannerFocusRecovery = true;
    try {
      final customer = await _showSimpleCustomerPickerForCatalogTests();
      if (!mounted || customer == null) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Export Master Update Sheets'),
            content: const Text(
              'Generate Master update Excel files from the loaded product catalog. '
              'Continue?',
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
      if (confirm != true || !mounted) return;

      if (!mounted) return;
      setState(() => _exportingMasterUpdateSheets = true);

      final stamp = _masterUpdateDebugTimestampSuffix();
      final products = _sortByItemNumberAscending<Product>(
        _allProducts,
        (p) => p.itemNumber,
      );

      final listPriceRows = products.length;
      final psProducts =
          products.where((p) => p.isPs).toList(growable: false);
      final newProducts =
          products.where((p) => p.isNewRelease).toList(growable: false);
      final psRows = psProducts.length;
      final newRows = newProducts.length;

      debugPrint(
        '[ExportDiag] MASTER_UPDATE row counts '
        'List_Price_Update=$listPriceRows PS_Update=$psRows New_Update=$newRows',
      );

      final docs = await getApplicationDocumentsDirectory();
      if (!mounted) return;

      xlsx.TextCellValue txt(String v) => xlsx.TextCellValue(v);

      // --- List Price (all loaded products; list price matches [_applyPricingLogic].)
      final excelListPrice = xlsx.Excel.createExcel();
      final listPriceDefault =
          excelListPrice.getDefaultSheet() ?? excelListPrice.tables.keys.first;
      excelListPrice.rename(listPriceDefault, 'List Price Update');
      final sheetListPrice = excelListPrice['List Price Update'];
      sheetListPrice.appendRow([txt('Item Number'), txt('List Price')]);
      for (var i = 0; i < products.length; i++) {
        final product = products[i];
        final pr = _applyPricingLogic(product, customer);
        sheetListPrice.appendRow([
          txt(product.itemNumber),
          xlsx.DoubleCellValue(pr.listPrice),
        ]);
        if (i % 400 == 0 && i > 0) {
          await Future<void>.delayed(Duration.zero);
          if (!mounted) return;
        }
      }

      // --- PS only
      final excelPs = xlsx.Excel.createExcel();
      final psDefault = excelPs.getDefaultSheet() ?? excelPs.tables.keys.first;
      excelPs.rename(psDefault, 'PS Update');
      final sheetPs = excelPs['PS Update'];
      sheetPs.appendRow([txt('Item Number'), txt('PS')]);
      for (final p in psProducts) {
        sheetPs.appendRow([txt(p.itemNumber), txt('YES')]);
      }

      // --- New release only
      final excelNew = xlsx.Excel.createExcel();
      final newDefault = excelNew.getDefaultSheet() ?? excelNew.tables.keys.first;
      excelNew.rename(newDefault, 'New Update');
      final sheetNew = excelNew['New Update'];
      sheetNew.appendRow([txt('Item Number'), txt('New Release')]);
      for (final p in newProducts) {
        sheetNew.appendRow([txt(p.itemNumber), txt('YES')]);
      }

      // --- Combined pack
      final excelPack = xlsx.Excel.createExcel();
      final packDefault = excelPack.getDefaultSheet() ?? excelPack.tables.keys.first;
      excelPack.rename(packDefault, 'List Price Update');
      final packList = excelPack['List Price Update'];
      packList.appendRow([txt('Item Number'), txt('List Price')]);
      for (var i = 0; i < products.length; i++) {
        final product = products[i];
        final pr = _applyPricingLogic(product, customer);
        packList.appendRow([
          txt(product.itemNumber),
          xlsx.DoubleCellValue(pr.listPrice),
        ]);
        if (i % 400 == 0 && i > 0) {
          await Future<void>.delayed(Duration.zero);
          if (!mounted) return;
        }
      }
      final packPs = excelPack['PS Update'];
      packPs.appendRow([txt('Item Number'), txt('PS')]);
      for (final p in psProducts) {
        packPs.appendRow([txt(p.itemNumber), txt('YES')]);
      }
      final packNew = excelPack['New Update'];
      packNew.appendRow([txt('Item Number'), txt('New Release')]);
      for (final p in newProducts) {
        packNew.appendRow([txt(p.itemNumber), txt('YES')]);
      }

      final pathListPrice =
          p.join(docs.path, 'MASTER_UPDATE_LIST_PRICE_$stamp.xlsx');
      final pathPs = p.join(docs.path, 'MASTER_UPDATE_PS_$stamp.xlsx');
      final pathNew = p.join(docs.path, 'MASTER_UPDATE_NEW_$stamp.xlsx');
      final pathPack = p.join(docs.path, 'MASTER_UPDATE_PACK_$stamp.xlsx');

      final okList = await _exportDiagEncodeWriteXlsxFile(
        excel: excelListPrice,
        file: File(pathListPrice),
        diagFileTag: 'MASTER_UPDATE_LIST_PRICE',
      );
      if (!mounted) return;
      if (!okList) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Master update export failed: list price encode/write.'),
            ),
          );
        }
        return;
      }

      final okPs = await _exportDiagEncodeWriteXlsxFile(
        excel: excelPs,
        file: File(pathPs),
        diagFileTag: 'MASTER_UPDATE_PS',
      );
      if (!mounted) return;
      if (!okPs) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Master update export failed: PS encode/write.'),
            ),
          );
        }
        return;
      }

      final okNew = await _exportDiagEncodeWriteXlsxFile(
        excel: excelNew,
        file: File(pathNew),
        diagFileTag: 'MASTER_UPDATE_NEW',
      );
      if (!mounted) return;
      if (!okNew) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Master update export failed: New encode/write.'),
            ),
          );
        }
        return;
      }

      final okPack = await _exportDiagEncodeWriteXlsxFile(
        excel: excelPack,
        file: File(pathPack),
        diagFileTag: 'MASTER_UPDATE_PACK',
      );
      if (!mounted) return;
      if (!okPack) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Master update export failed: pack encode/write.'),
            ),
          );
        }
        return;
      }

      final body =
          'Files created (4):\n'
          '• MASTER_UPDATE_LIST_PRICE_$stamp.xlsx\n'
          '• MASTER_UPDATE_PS_$stamp.xlsx\n'
          '• MASTER_UPDATE_NEW_$stamp.xlsx\n'
          '• MASTER_UPDATE_PACK_$stamp.xlsx\n\n'
          'Data rows (excluding headers):\n'
          '• List Price Update: $listPriceRows\n'
          '• PS Update: $psRows\n'
          '• New Update: $newRows\n\n'
          'Paths:\n'
          '$pathListPrice\n'
          '$pathPs\n'
          '$pathNew\n'
          '$pathPack';

      debugPrint('[ExportDiag] MASTER_UPDATE completion dialog shown');
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Master update export complete'),
            content: SingleChildScrollView(
              child: SelectableText(body),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (e, st) {
      debugPrint('Master update sheets export failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Master update export failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _exportingMasterUpdateSheets = false);
      } else {
        _exportingMasterUpdateSheets = false;
      }
      _suspendScannerFocusRecovery = false;
    }
  }

  /// Active (working) quotes for Load Quote and daily use — same eligibility as
  /// [_quoteIdHasActiveEligibleRowInActiveIndexStorage] (active index row, not in archive).
  Future<List<SavedQuoteInfo>> _loadQuoteIndex() async {
    try {
      await _ensureLegacyQuoteIndexMigratedIfNeeded();
      final dir = await _getQuotesDirectory();
      final archiveIds = (await _loadArchiveQuoteIndex())
          .map((e) => e.id)
          .toSet();
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

  /// List Price column for email/share attachments: persisted line [listPrice], else
  /// [Product.listPrice] from [upc]/[itemNumber]. Never uses line [price].
  double? _listUnitForQuoteShareAttachmentLine(Map<String, dynamic> map) {
    final lp = map['listPrice'];
    if (lp is num) {
      return _roundedUnitPrice(lp.toDouble());
    }
    final upc = (map['upc'] as String?)?.trim() ?? '';
    final itemNumber = (map['itemNumber'] as String?)?.trim() ?? '';
    Product? product = _productsByUpc[_normalizeUpcLookupKey(upc)];
    product ??= _productsByItemNumber[itemNumber];
    if (product == null) return null;
    return _roundedUnitPrice(product.listPrice);
  }

  /// Shared line iteration for email/share CSV + XLSX attachments.
  /// [listUnit] from [_listUnitForQuoteShareAttachmentLine] (never line [price]).
  /// [unit] is persisted line [price] after [_formatQuoteAsText]-style customer discount.
  Iterable<
    ({
      String itemNumber,
      String description,
      double? listUnit,
      double unit,
      int qty,
      double lineTotal,
    })
  >
  _iterQuoteShareAttachmentLines(Map<String, dynamic> data) sync* {
    final lines =
        data['lines'] as List<dynamic>? ??
        data['items'] as List<dynamic>? ??
        [];

    var customerDiscPct = 0.0;
    final customerMap = data['customer'];
    if (customerMap is Map<String, dynamic>) {
      customerDiscPct = Customer.fromJson(
        Map<String, dynamic>.from(customerMap),
      ).discountPercent;
    }

    ProductPricingState linePricingState(Map<String, dynamic> map) {
      final psFlag = map['isPs'];
      final psRaw = (map['psRaw'] as String?) ?? '';
      final isPs = (psFlag is bool) ? psFlag : _parseYesFlag(psRaw);
      if (isPs) return ProductPricingState.ps;
      final netFlag = map['isNet'];
      final netRaw = (map['netRaw'] as String?) ?? '';
      final isNet = (netFlag is bool) ? netFlag : _parseYesFlag(netRaw);
      if (isNet) return ProductPricingState.net;
      final b = map['discountEligible'];
      if (b is bool) {
        return b
            ? ProductPricingState.discountEligible
            : ProductPricingState.regular;
      }
      final raw = (map['discountRaw'] as String?) ?? '';
      return _parseYesFlag(raw)
          ? ProductPricingState.discountEligible
          : ProductPricingState.regular;
    }

    double discountedUnit(Map<String, dynamic> map, double regularUnit) {
      if (linePricingState(map) != ProductPricingState.discountEligible ||
          customerDiscPct <= 0) {
        return regularUnit;
      }
      return regularUnit * (1 - customerDiscPct / 100.0);
    }

    for (final lineJson in lines) {
      final map = Map<String, dynamic>.from(lineJson as Map);
      final itemNumber = (map['itemNumber'] as String?) ?? '';
      final desc = (map['description'] as String?) ?? '';
      final qty = _quantityFromJson(map['quantity']);
      final shelfUnit = (map['price'] as num?)?.toDouble() ?? 0.0;
      final unitRaw = discountedUnit(map, shelfUnit);
      yield (
        itemNumber: itemNumber,
        description: desc,
        listUnit: _listUnitForQuoteShareAttachmentLine(map),
        unit: _roundedUnitPrice(unitRaw),
        qty: qty,
        lineTotal: _lineTotalFromRoundedUnitPrice(
          rawUnitPrice: unitRaw,
          qty: qty,
        ),
      );
    }
  }

  String _formatQuoteShareAttachmentCurrency(double amount) =>
      '\$${amount.toStringAsFixed(2)}';

  String _formatQuoteShareAttachmentListPriceCell(double? listUnit) =>
      listUnit == null ? '' : _formatQuoteShareAttachmentCurrency(listUnit);

  num? _parseSortableItemNumber(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return num.tryParse(trimmed);
  }

  int _compareItemNumberAscending(String a, String b) {
    final aTrimmed = a.trim();
    final bTrimmed = b.trim();
    final aNumeric = _parseSortableItemNumber(aTrimmed);
    final bNumeric = _parseSortableItemNumber(bTrimmed);
    if (aNumeric != null && bNumeric != null) {
      return aNumeric.compareTo(bNumeric);
    }
    if (aNumeric != null && bNumeric == null) return -1;
    if (aNumeric == null && bNumeric != null) return 1;
    return aTrimmed.compareTo(bTrimmed);
  }

  List<T> _sortByItemNumberAscending<T>(
    Iterable<T> rows,
    String Function(T row) itemNumberOf,
  ) {
    final sorted = rows.toList();
    sorted.sort(
      (a, b) => _compareItemNumberAscending(itemNumberOf(a), itemNumberOf(b)),
    );
    return sorted;
  }

  /// [richEmailShareAttachments]: full line detail for Email/Share only (see [_shareQuoteById]).
  /// Default: compact `Item,Quantity` for website upload and other quote CSV exports.
  String _formatQuoteAsCsv(
    Map<String, dynamic> data, {
    bool richEmailShareAttachments = false,
    bool sortByItemNumberAsc = false,
  }) {
    if (!richEmailShareAttachments) {
      const header = 'Item,Quantity';
      final lines =
          data['lines'] as List<dynamic>? ??
          data['items'] as List<dynamic>? ??
          [];
      final rows = <String>[header];
      final csvLines = <({String itemNumber, int qty})>[];

      for (final lineJson in lines) {
        final map = Map<String, dynamic>.from(lineJson as Map);
        final itemNumber = (map['itemNumber'] as String?) ?? '';
        final qty = _quantityFromJson(map['quantity']);
        csvLines.add((itemNumber: itemNumber, qty: qty));
      }

      final orderedCsvLines = sortByItemNumberAsc
          ? _sortByItemNumberAscending(csvLines, (r) => r.itemNumber)
          : csvLines;

      for (final line in orderedCsvLines) {
        final itemEscaped = _csvEscape(line.itemNumber);
        rows.add('$itemEscaped,${line.qty}');
      }

      return rows.join('\n');
    }

    const header =
        'Item Number,Description,List Price,Price,Qty Ordered,Line Total';
    final rows = <String>[header];
    final richLines = _iterQuoteShareAttachmentLines(data).toList();
    final orderedRichLines = sortByItemNumberAsc
        ? _sortByItemNumberAscending(richLines, (r) => r.itemNumber)
        : richLines;
    for (final r in orderedRichLines) {
      rows.add(
        [
          _csvEscape(r.itemNumber),
          _csvEscape(r.description),
          _csvEscape(_formatQuoteShareAttachmentListPriceCell(r.listUnit)),
          _formatQuoteShareAttachmentCurrency(r.unit),
          '${r.qty}',
          _formatQuoteShareAttachmentCurrency(r.lineTotal),
        ].join(','),
      );
    }
    return rows.join('\n');
  }

  /// Email/share attachment: .xlsx with one row per order line (same columns as rich CSV).
  /// Pricing matches [_formatQuoteAsText] (customer discount on eligible lines).
  List<int> _buildQuoteEmailExcelBytes(
    Map<String, dynamic> data, {
    bool sortByItemNumberAsc = false,
  }) {
    final excel = xlsx.Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? excel.tables.keys.first;
    final sheet = excel[sheetName];

    xlsx.TextCellValue cell(String v) => xlsx.TextCellValue(v);

    void appendMeta(String label, String value) {
      sheet.appendRow([
        cell(label),
        cell(value),
        cell(''),
        cell(''),
        cell(''),
        cell(''),
      ]);
    }

    final quoteName = (data['name'] as String?)?.trim() ?? '';
    final bucketLabel = (data['quoteBucketLabel'] as String?)?.trim() ?? '';
    final bucketKey = (data['quoteBucketKey'] as String?)?.trim() ?? '';
    final productType = bucketLabel.isNotEmpty
        ? bucketLabel
        : (bucketKey.isNotEmpty ? bucketKey : '');

    var customerNumber = '';
    var customerName = '';
    final customerMap = data['customer'];
    if (customerMap is Map<String, dynamic>) {
      final c = Customer.fromJson(Map<String, dynamic>.from(customerMap));
      customerNumber = c.id.trim();
      customerName = c.displayName.trim();
    }

    appendMeta('Quote Name', quoteName);
    appendMeta('Product Type', productType);
    appendMeta('Customer Number', customerNumber);
    appendMeta('Customer Name', customerName);

    final updatedAt = DateTime.tryParse((data['updatedAt'] as String?) ?? '');
    if (updatedAt != null) {
      final y = updatedAt.year.toString().padLeft(4, '0');
      final m = updatedAt.month.toString().padLeft(2, '0');
      final d = updatedAt.day.toString().padLeft(2, '0');
      appendMeta('Generated Date', '$y-$m-$d');
    }

    sheet.appendRow([
      cell(''),
      cell(''),
      cell(''),
      cell(''),
      cell(''),
      cell(''),
    ]);

    sheet.appendRow([
      cell('Item Number'),
      cell('Description'),
      cell('List Price'),
      cell('Price'),
      cell('Qty Ordered'),
      cell('Line Total'),
    ]);

    var metaRows = 4;
    if (updatedAt != null) metaRows++;
    const blankRows = 1;
    const headerRows = 1;
    var rowIndex = metaRows + blankRows + headerRows;

    final currencyStyle = xlsx.CellStyle(
      numberFormat: xlsx.NumFormat.custom(formatCode: r'"$"#,##0.00'),
    );
    final leftAlignStyle = xlsx.CellStyle(
      horizontalAlign: xlsx.HorizontalAlign.Left,
    );
    sheet
            .cell(
              xlsx.CellIndex.indexByColumnRow(
                columnIndex: 0,
                rowIndex: rowIndex - 1,
              ),
            )
            .cellStyle =
        leftAlignStyle;

    final richLines = _iterQuoteShareAttachmentLines(data).toList();
    final orderedRichLines = sortByItemNumberAsc
        ? _sortByItemNumberAscending(richLines, (r) => r.itemNumber)
        : richLines;
    for (final line in orderedRichLines) {
      final listPriceCell = line.listUnit == null
          ? cell('')
          : xlsx.DoubleCellValue(line.listUnit!);
      sheet.appendRow([
        xlsx.TextCellValue(line.itemNumber),
        xlsx.TextCellValue(line.description),
        listPriceCell,
        xlsx.DoubleCellValue(line.unit),
        xlsx.IntCellValue(line.qty),
        xlsx.DoubleCellValue(line.lineTotal),
      ]);
      sheet
              .cell(
                xlsx.CellIndex.indexByColumnRow(
                  columnIndex: 0,
                  rowIndex: rowIndex,
                ),
              )
              .cellStyle =
          leftAlignStyle;
      if (line.listUnit != null) {
        sheet
                .cell(
                  xlsx.CellIndex.indexByColumnRow(
                    columnIndex: 2,
                    rowIndex: rowIndex,
                  ),
                )
                .cellStyle =
            currencyStyle;
      }
      for (final col in [3, 5]) {
        sheet
                .cell(
                  xlsx.CellIndex.indexByColumnRow(
                    columnIndex: col,
                    rowIndex: rowIndex,
                  ),
                )
                .cellStyle =
            currencyStyle;
      }
      rowIndex++;
    }

    final out = excel.save(fileName: 'quote.xlsx');
    if (out == null) {
      throw StateError('Excel save returned no bytes');
    }
    return out;
  }

  /// Build shareable text for a quote from its JSON data.
  String _formatQuoteAsText(Map<String, dynamic> data) {
    final name = data['name'] as String? ?? 'Quote';
    final lines =
        data['lines'] as List<dynamic>? ??
        data['items'] as List<dynamic>? ??
        [];
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

    ProductPricingState linePricingState(Map<String, dynamic> map) {
      final psFlag = map['isPs'];
      final psRaw = (map['psRaw'] as String?) ?? '';
      final isPs = (psFlag is bool) ? psFlag : _parseYesFlag(psRaw);
      if (isPs) return ProductPricingState.ps;
      final netFlag = map['isNet'];
      final netRaw = (map['netRaw'] as String?) ?? '';
      final isNet = (netFlag is bool) ? netFlag : _parseYesFlag(netRaw);
      if (isNet) return ProductPricingState.net;
      final b = map['discountEligible'];
      if (b is bool) {
        return b
            ? ProductPricingState.discountEligible
            : ProductPricingState.regular;
      }
      final raw = (map['discountRaw'] as String?) ?? '';
      return _parseYesFlag(raw)
          ? ProductPricingState.discountEligible
          : ProductPricingState.regular;
    }

    double discountedUnit(Map<String, dynamic> map, double regularUnit) {
      if (linePricingState(map) != ProductPricingState.discountEligible ||
          customerDiscPct <= 0) {
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
      final qty = _quantityFromJson(map['quantity']);
      final price = (map['price'] as num?)?.toDouble() ?? 0.0;
      final du = discountedUnit(map, price);
      final lineRegular = _lineTotalFromRoundedUnitPrice(
        rawUnitPrice: price,
        qty: qty,
      );
      final linePay = _lineTotalFromRoundedUnitPrice(
        rawUnitPrice: du,
        qty: qty,
      );
      regularOrderSum += lineRegular;
      discountedOrderSum += linePay;

      final shortDesc = desc.length > 32 ? '${desc.substring(0, 32)}..' : desc;
      final ru = _roundedUnitPrice(price);
      final rdu = _roundedUnitPrice(du);
      final unitCol = (ru - rdu).abs() > 0.005
          ? '\$${ru.toStringAsFixed(2)}→\$${rdu.toStringAsFixed(2)}'
          : '\$${rdu.toStringAsFixed(2)}';

      buffer.writeln(
        '${shortDesc.padRight(34)} ${qty.toString().padLeft(3)}  '
        '${unitCol.padLeft(9)}  \$${linePay.toStringAsFixed(2)}',
      );
    }

    buffer.writeln('-' * 62);
    regularOrderSum = _roundMoney(regularOrderSum);
    discountedOrderSum = _roundMoney(discountedOrderSum);
    final orderDiscountAmt = _roundMoney(regularOrderSum - discountedOrderSum);
    if (orderDiscountAmt > 0.005) {
      buffer.writeln('Regular Total: \$${regularOrderSum.toStringAsFixed(2)}');
      buffer.writeln('Discount: \$${orderDiscountAmt.toStringAsFixed(2)}');
      buffer.writeln('Final Total: \$${discountedOrderSum.toStringAsFixed(2)}');
    } else {
      buffer.writeln('Total: \$${discountedOrderSum.toStringAsFixed(2)}');
    }
    return buffer.toString();
  }

  /// Share quote by id: attaches line-detail CSV + .xlsx (same columns) and text summary.
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
      final csv = _formatQuoteAsCsv(data, sortByItemNumberAsc: true);

      final tempDir = await getTemporaryDirectory();

      String safeFileToken(String raw) {
        final t = raw
            .replaceAll(RegExp(r'[^\w\s-]'), '_')
            .replaceAll(RegExp(r'\s+'), '_')
            .replaceAll(RegExp(r'_+'), '_')
            .trim();
        return t.length > 80 ? t.substring(0, 80) : t;
      }

      final exportedOn = DateTime.now();
      final customerMap = data['customer'];
      var customerName = '';
      if (customerMap is Map<String, dynamic>) {
        try {
          customerName = Customer.fromJson(
            Map<String, dynamic>.from(customerMap),
          ).displayName.trim();
        } catch (_) {}
      }
      final csvFilename = _buildExportOrderCsvFilename(
        quoteName: (data['name'] as String?)?.trim() ?? name,
        customerName: customerName,
        customerId: (data['customerId'] as String?)?.trim(),
        quoteData: data,
        customerFolderName: customerName,
        quoteBucketLabel: (data['quoteBucketLabel'] as String?)?.trim(),
        quoteBucketKey: (data['quoteBucketKey'] as String?)?.trim(),
        quoteDate: _quoteDateFromMapOrFallback(data, exportedOn),
        exportedOn: exportedOn,
      );
      final csvPath = '${tempDir.path}/$csvFilename';

      final csvFile = File(csvPath);
      await csvFile.writeAsString(csv, encoding: utf8, flush: true);
      await _debugLogCsvExportFile(
        action: 'quote_email_temp_csv',
        filename: csvFilename,
        mimeType: 'text/csv',
        file: csvFile,
      );

      final text = _formatQuoteAsText(data);

      final attachments = <XFile>[XFile(csvPath, mimeType: 'text/csv')];
      try {
        final bucketLabel = (data['quoteBucketLabel'] as String?)?.trim() ?? '';
        final bucketKey = (data['quoteBucketKey'] as String?)?.trim() ?? '';
        final productTypeRaw = bucketLabel.isNotEmpty ? bucketLabel : bucketKey;
        final productToken = safeFileToken(
          productTypeRaw.isNotEmpty ? productTypeRaw : 'Unknown',
        );

        var customerToken = '';
        final cm = data['customer'];
        if (cm is Map<String, dynamic>) {
          final cust = Customer.fromJson(Map<String, dynamic>.from(cm));
          final company = cust.companyName.trim();
          final identifyingCustomer = company.isNotEmpty
              ? company
              : cust.id.trim();
          customerToken = safeFileToken(identifyingCustomer);
        }
        if (customerToken.isEmpty) {
          customerToken = 'Unknown';
        }

        final quoteNameOptional = safeFileToken(
          (data['name'] as String?)?.trim() ?? name,
        );
        final updated = DateTime.tryParse((data['updatedAt'] as String?) ?? '');
        final dateToken = updated != null
            ? '${updated.year}-${updated.month.toString().padLeft(2, '0')}-${updated.day.toString().padLeft(2, '0')}'
            : '';

        final xlsxBase = [
          'Quote',
          productToken,
          customerToken,
          if (quoteNameOptional.isNotEmpty) quoteNameOptional,
          if (dateToken.isNotEmpty) dateToken,
        ].join('_');
        final xlsxPath = '${tempDir.path}/$xlsxBase.xlsx';
        final xlsxBytes = _buildQuoteEmailExcelBytes(
          data,
          sortByItemNumberAsc: true,
        );
        await File(xlsxPath).writeAsBytes(xlsxBytes, flush: true);
        attachments.add(
          XFile(
            xlsxPath,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        );
      } catch (_) {}

      await Share.shareXFiles(attachments, text: text, subject: 'Quote: $name');
    } catch (_) {}
  }

  Future<void> _loadQuoteById(
    String id, {
    bool syncWorkspaceIfUnmounted = false,
    _ECatalogNavigationSource navigationSource = _ECatalogNavigationSource.other,
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

      final name = (data['name'] as String? ?? 'EVERYDAY QUOTE').toUpperCase();
      final loadedQuoteBucketKey =
          (data['quoteBucketKey'] as String?)?.trim() ?? '';
      final loadedQuoteBucketLabel =
          (data['quoteBucketLabel'] as String?)?.trim() ?? '';
      final linesList =
          data['lines'] as List<dynamic>? ??
          data['items'] as List<dynamic>? ??
          [];

      Customer? loadedCustomer;
      final customerMap = data['customer'];
      if (customerMap is Map<String, dynamic>) {
        final savedId = (customerMap['id'] as String?)?.trim() ?? '';
        try {
          loadedCustomer = _customers.firstWhere((c) => c.id == savedId);
        } catch (_) {
          loadedCustomer = Customer.fromJson(
            Map<String, dynamic>.from(customerMap),
          );
        }
      }
      loadedCustomer ??= await _resolveCustomerForActiveQuoteIndexRow(id);

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
        final netRaw = (map['netRaw'] as String?)?.trim() ?? '';
        final isNet = (map['isNet'] as bool?) ?? _parseYesFlag(netRaw);
        final psRaw = (map['psRaw'] as String?)?.trim() ?? '';
        final isPs = (map['isPs'] as bool?) ?? _parseYesFlag(psRaw);
        final isNewRelease = (map['isNewRelease'] as bool?) ?? false;
        final category = (map['category'] as String?) ?? '';
        final subCategory = (map['subCategory'] as String?) ?? '';
        final whse1InStock = (map['whse1InStock'] as bool?) ?? false;
        final whse2InStock = (map['whse2InStock'] as bool?) ?? false;
        final whse1OutOfStock = (map['whse1OutOfStock'] as bool?) ?? false;
        final whse2OutOfStock = (map['whse2OutOfStock'] as bool?) ?? false;
        final whse1ComingSoon = (map['whse1ComingSoon'] as bool?) ?? false;
        final whse2ComingSoon = (map['whse2ComingSoon'] as bool?) ?? false;
        final quantity = _quantityFromJson(map['quantity']);
        final scans = (map['scans'] as int?) ?? 1;

        Product? product = _productsByUpc[_normalizeUpcLookupKey(upc)];
        product ??= _productsByItemNumber[itemNumber];

        if (product == null) {
          product = Product(
            itemNumber: itemNumber.isEmpty ? upc : itemNumber,
            description: description.isEmpty ? 'Unknown' : description,
            upc: upc,
            price: price,
            listPrice: 0.0,
            productType: productType,
            discountRaw: discountRaw,
            discountEligible: discountEligible,
            netRaw: netRaw,
            isNet: isNet,
            psRaw: psRaw,
            isPs: isPs,
            isNewRelease: isNewRelease,
            category: category,
            subCategory: subCategory,
            minOrderQty: 1,
            caseQty: 1,
            whse1InStock: whse1InStock,
            whse2InStock: whse2InStock,
            whse1OutOfStock: whse1OutOfStock,
            whse2OutOfStock: whse2OutOfStock,
            whse1ComingSoon: whse1ComingSoon,
            whse2ComingSoon: whse2ComingSoon,
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
        final inferred = _resolveQuoteBucketForProduct(
          newOrderLines.first.product,
        );
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

      if (loadedCustomer == null) {
        if (!mounted) return;
        _setStateDebug('load_quote_no_resolved_customer', () {
          _status = 'Cannot load quote: no matching customer.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a customer first.')),
        );
        _requestScannerFocus();
        return;
      }

      void applyWorkspace() {
        _ordersTabExpandedLineKey = null;
        _scanTabExpandedLineKey = null;
        if (_orderCsvImportInProgress) {
          _orderImportTouchedQuoteIds.add(id);
        }
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
        _syncCustomerWalkOrderEnabledForCustomer(loadedCustomer);
        debugPrint(
          '[WalkOrder] sync source: ${_orderCsvImportInProgress ? 'import order' : 'load quote'}',
        );
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
      unawaited(_refreshPreviouslyOrderedHistoryForSelectedCustomer());
      _maybeNavigateToECatalogTab(navigationSource);

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
    // Rebuild so [MediaQuery.removeViewInsets] above the scaffold applies before
    // the dialog search field raises the keyboard (avoids a one-frame overflow).
    setState(() {});
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
        return MediaQuery.removeViewInsets(
          removeLeft: true,
          removeTop: true,
          removeRight: true,
          removeBottom: true,
          context: ctx,
          child: AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ],
          ),
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
            _activeQuoteBucketLabel =
                _defaultQuoteBucketDefinition.displayLabel;
            _orderLines.clear();
            _orderLineByKey.clear();
            _orderListVersion += 1;
            _recalculateTotals();
            _quoteNameController.text = 'NEW QUOTE';
            _savedQuoteNameBeforeEdit = 'NEW QUOTE';
            _quoteNameUserEdited = false;
            _selectedLine = null;
            _selectedCustomer = null;
            _syncCustomerWalkOrderEnabledForCustomer(null);
            debugPrint('[WalkOrder] sync source: load quote');
            _status = 'Quote removed';
            _quickEntryStatus = '-';
            _resetQuoteDisplayAndScanState();
          });
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 150));
        if (mounted) {
          await _loadQuoteById(id);
        }
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
    if (!_requireSelectedCustomerForWorkingOrder()) return;

    setState(() {
      _selectedLine!.quantity += _selectedLine!.product.minOrderQty;
      _recalculateTotals();
      _status = 'Quantity increased';
    });

    _requestScannerFocus();
  }

  void _decreaseSelectedLineQty() {
    if (_selectedLine == null) return;
    if (!_requireSelectedCustomerForWorkingOrder()) return;

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
    if (!_requireSelectedCustomerForWorkingOrder()) return;
    setState(() {
      line.quantity += line.product.minOrderQty;
      _recalculateTotals();
      _status = 'Quantity increased';
    });
    _requestScannerFocus();
  }

  void _decreaseLineQty(OrderLine line) {
    if (!_requireSelectedCustomerForWorkingOrder()) return;
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
      scannerFocusNode: _scannerFocusNode,
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
      discountedUnitPrice: line != null
          ? _roundedUnitPrice(_getDiscountedUnitPrice(line))
          : 0,
      priceIndicator: line != null
          ? _productPricingIndicator(line.product)
          : null,
      onDecreaseQty: _decreaseSelectedLineQty,
      onIncreaseQty: _increaseSelectedLineQty,
      onDeleteSelectedLine: _confirmDeleteLine,
      lastScanSummary: 'Last: +$_qtyAdded added     Scans: $_itemsScanned',
    );
  }

  Widget _buildScanTabLoadCreateQuoteBar() {
    return _ScanTabLoadCreateQuoteBar(
      onLoadQuote: _showLoadQuoteDialog,
      onCreateQuote: _confirmNewQuote,
      onScanWithCamera: _openCameraScanner,
    );
  }

  Widget _buildECatalogTopActionBar() {
    return _ECatalogTopActionBar(
      onCreateQuote: _confirmNewQuote,
      onLoadQuote: _showLoadQuoteDialog,
      onImportOrder: _pickAndImportOrderCsv,
      onExportAll: _exportAllQuotesToCsv,
      onExportCurrentQuote: _exportCurrentQuoteOnlyToCsv,
      loadingProducts: _loadingProducts,
    );
  }

  /// Item # / UPC field and optional status — fixed bottom block above Load/Create.
  /// Search hits live in [_buildScanTabSearchResultsList] inside the Scan panel [CustomScrollView].
  Widget _buildScanTabItemSearchBlock() {
    return _ScanTabItemSearchBlock(
      quickEntryTextFieldKey: _quickEntryTextFieldKey,
      quickEntryController: _quickEntryController,
      quickEntryFocusNode: _quickEntryFocusNode,
      onQuickEntryTap: () {
        _quickEntryFocusNode.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show');
      },
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
        final added = _addProduct(product, 'SEARCH', bucket: bucket);
        if (!added) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _requestScannerFocusAfterManualEntry(
              debugLabel: 'quickEntrySearchTapAddFailed',
            );
          });
          return;
        }
        _quickEntryController.clear();
        _setStateDebug('scan_search_tap_clear_results', () {
          _scanSearchQuery = '';
          _searchResults = [];
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _requestScannerFocusAfterManualEntry(debugLabel: 'quickEntrySearchTap');
        });
      },
    );
  }

  Widget _buildScanTabSearchResultsList() {
    if (_searchResults.isEmpty) {
      final query = _scanSearchQuery.trim();
      if (query.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          "No products found for '$query'",
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: _kSecondaryText),
        ),
      );
    }
    return _ScanTabSearchResultsList(
      products: _searchResults,
      itemBuilder: _buildScanTabSearchResultTile,
    );
  }

  /// Order lines for Scan tab — lazy [SliverList] segment in the Scan panel
  /// [CustomScrollView] (no nested shrink-wrapped list).
  Widget _buildScanTabOrderListSliver() {
    _orderListBuildCount++;
    if (_orderLines.isEmpty) {
      return SliverToBoxAdapter(
        child: RepaintBoundary(child: const _ScanTabOrderListEmpty()),
      );
    }
    return SliverList(
      key: ValueKey<String>('order_list_${_orderListVersion}'),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildScanTabOrderLineSubtree(_orderLines[index]),
        childCount: _orderLines.length,
      ),
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
          compactLayout: true,
          compactExpandHost: _OrderLineCardCompactExpandHost.scanTab,
        ),
      ),
    );
  }

  Widget _buildOrderCard(
    OrderLine line, {
    bool scanTabHighlightFlash = false,
    bool compactLayout = false,
    _OrderLineCardCompactExpandHost? compactExpandHost,
    Product? displayProduct,
  }) {
    final Product presentationProduct = displayProduct ?? line.product;
    final OrderLine presentationLine = identical(presentationProduct, line.product)
        ? line
        : OrderLine(
            product: presentationProduct,
            quantity: line.quantity,
            scans: line.scans,
          );
    final String lineKey = _orderLineKeyForProduct(line.product);
    assert(
      !compactLayout || compactExpandHost != null,
      'compactLayout requires compactExpandHost',
    );
    final String? expandedKeyForHost = switch (compactExpandHost) {
      _OrderLineCardCompactExpandHost.ordersTab => _ordersTabExpandedLineKey,
      _OrderLineCardCompactExpandHost.scanTab => _scanTabExpandedLineKey,
      _OrderLineCardCompactExpandHost.ecatalogTab => _ecatalogExpandedItemKey,
      null => null,
    };
    final bool compactExpanded = compactLayout && expandedKeyForHost == lineKey;
    return _OrderLineCard(
      dismissibleKey: ValueKey(lineKey),
      line: line,
      displayProduct: presentationProduct,
      scanTabHighlightFlash: scanTabHighlightFlash,
      compactLayout: compactLayout,
      expandedOrdersCompact: compactExpanded,
      restrictCardTapToProductArea: compactLayout,
      lineHasDiscount: _lineHasDiscount(presentationLine),
      discountedUnitPrice: _roundedUnitPrice(
        _getDiscountedUnitPrice(presentationLine),
      ),
      priceIndicator: _productPricingIndicator(presentationProduct),
      lineTotal: _getDiscountedLineTotal(presentationLine),
      onSwipeDeletePrompt: () => _confirmDeleteLine(line),
      onCardTap: compactLayout
          ? () {
              _setStateDebug('order_card_compact_toggle_expand', () {
                switch (compactExpandHost!) {
                  case _OrderLineCardCompactExpandHost.ordersTab:
                    if (_ordersTabExpandedLineKey == lineKey) {
                      _ordersTabExpandedLineKey = null;
                    } else {
                      _ordersTabExpandedLineKey = lineKey;
                    }
                  case _OrderLineCardCompactExpandHost.scanTab:
                    if (_scanTabExpandedLineKey == lineKey) {
                      _scanTabExpandedLineKey = null;
                    } else {
                      _scanTabExpandedLineKey = lineKey;
                    }
                  case _OrderLineCardCompactExpandHost.ecatalogTab:
                    if (_ecatalogExpandedItemKey == lineKey) {
                      _ecatalogExpandedItemKey = null;
                    } else {
                      _ecatalogExpandedItemKey = lineKey;
                    }
                }
              });
            }
          : () {
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
          child: _buildOrderCard(
            line,
            compactLayout: true,
            compactExpandHost: _OrderLineCardCompactExpandHost.ordersTab,
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Widget _buildOrderListTab() {
    _orderListTabBuildCount++;
    if (_activeTabIndex != 2) {
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
    if (_activeTabIndex != _tabIndexScan) {
      return const SizedBox.shrink();
    }
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final quickEntryFloatAboveKeyboard =
        (_quickEntryFocusNode.hasFocus && viewInsets.bottom > 0) ||
        (_quickEntryHoldFloatingLayoutForKeyboard && viewInsets.bottom > 0);
    return Focus(
      autofocus: true,
      focusNode: _scannerFocusNode,
      canRequestFocus: !_quickEntryFocusNode.hasFocus,
      descendantsAreFocusable: true,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (_isAnyManualTextFieldFocused()) {
          return KeyEventResult.ignored;
        }

        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _processScannerBuffer();
          return KeyEventResult.handled;
        }

        final key = event.logicalKey.keyLabel;
        if (key.isNotEmpty &&
            key != 'Shift' &&
            key != 'Control' &&
            key != 'Alt' &&
            key != 'Meta') {
          _handleScannerCharacter(key);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: _ScanTabLayout(
        quotePanel: _buildScanQuotePanel(),
        loadingProducts: _loadingProducts,
        scanPanelScrollController: _scanPanelScrollController,
        liveOrderControlPanel: _buildScanLiveOrderControlPanel(),
        orderListSliver: _buildScanTabOrderListSliver(),
        searchResultsList: _buildScanTabSearchResultsList(),
        itemSearchBlock: _buildScanTabItemSearchBlock(),
        quickEntryFloatAboveKeyboard: quickEntryFloatAboveKeyboard,
        quickEntryStatusForPlaceholder: _quickEntryStatus,
        loadCreateQuoteBar: _buildScanTabLoadCreateQuoteBar(),
      ),
    );
  }

  Widget _buildSetupTab() {
    return _SetupTab(
      onLoadProducts: () {
        unawaited(_loadProductsFromWeb());
      },
      onLoadCustomers: _loadCustomersFromSheet,
      onAddCustomer: _showAddCustomerDialog,
      onWalkOrderEditor: _openWalkOrderViewer,
      loadingProductsFromWeb: _loadingProductsFromWeb,
      loadingCustomersFromWeb: _isLoadingCustomers,
      onBuildFullCatalogTestQuote: kDebugMode
          ? _buildFullCatalogTestQuoteFlow
          : null,
      onExportFullCatalogExcel: kDebugMode
          ? _exportFullCatalogExcelQuoteFlow
          : null,
      exportingFullCatalogExcel: _exportingFullCatalogExcel,
      onExportMasterUpdateSheets:
          kDebugMode ? _exportMasterUpdateSheetsFlow : null,
      exportingMasterUpdateSheets: _exportingMasterUpdateSheets,
      onBuildUpdatedMasterProductsSheet:
          kDebugMode ? _buildUpdatedMasterProductsSheetFlow : null,
      buildingUpdatedMasterSheet: _buildingUpdatedMasterSheet,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (!_quickEntryFocusNode.hasFocus &&
            !_quoteNameFocusNode.hasFocus &&
            !_editDialogOpen) {
          _requestScannerFocus();
        }
      },
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: _editDialogOpen,
        child: Scaffold(
          // Let the scaffold shrink the body by viewInsets when the keyboard opens.
          // Do not also add viewInsets.bottom to a non-flex child in [_buildScanTab]:
          // that inflates the Column's fixed-height children and can force flex space
          // negative (RenderFlex overflow) on short viewports.
          // While [_editDialogOpen], bottom insets are stripped above so modal dialogs
          // (Load Quote search field) do not shrink the scaffold and overflow the Scan tab.
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            toolbarHeight: 48,
            title: const Text('Showroom Scanner'),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Scan'),
                Tab(text: 'E-Catalog'),
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
                      _buildECatalogTab(),
                      _buildArchiveTab(),
                      _buildSetupTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Scan / Orders tab UI extracted from [_ScannerHomePageState] (presentation only) ---

/// Shared border radius for scan/order line cards and swipe background (presentation only).
const BorderRadius _kOrderLineCardBorderRadius = BorderRadius.all(
  Radius.circular(12),
);

/// Full Scan tab body: quote header, scrollable middle, and bottom search / quote actions.
class _ScanTabLayout extends StatelessWidget {
  // REBUILD_INSTRUMENT: remove when done profiling scan-tab rebuild frequency
  static int _debugRebuildCount = 0;

  const _ScanTabLayout({
    required this.quotePanel,
    required this.loadingProducts,
    required this.scanPanelScrollController,
    required this.liveOrderControlPanel,
    required this.orderListSliver,
    required this.searchResultsList,
    required this.itemSearchBlock,
    required this.quickEntryFloatAboveKeyboard,
    required this.quickEntryStatusForPlaceholder,
    required this.loadCreateQuoteBar,
  });

  static const EdgeInsets _quotePanelPadding = EdgeInsets.fromLTRB(
    12,
    12,
    12,
    0,
  );
  static const EdgeInsets _modeHeaderPadding = EdgeInsets.fromLTRB(12, 12, 12, 0);
  static const EdgeInsets _livePanelPadding = EdgeInsets.symmetric(
    horizontal: 12,
  );
  static const EdgeInsets _scrollListPadding = EdgeInsets.symmetric(
    horizontal: 12,
  );
  static const EdgeInsets _bottomActionsPadding = EdgeInsets.fromLTRB(
    12,
    8,
    12,
    8,
  );

  /// Single instance while catalog is loading (avoids reallocating each parent rebuild).
  static const Widget _loadingProductsIndicator = Center(
    child: CircularProgressIndicator(),
  );

  final Widget quotePanel;
  final bool loadingProducts;
  final ScrollController scanPanelScrollController;
  final Widget liveOrderControlPanel;

  /// Must be a sliver widget (e.g. [SliverList], [SliverToBoxAdapter]).
  final Widget orderListSliver;
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
      debugPrint('REBUILD_INSTRUMENT _ScanTabLayout #$_debugRebuildCount');
    }
    final Widget scanBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: _modeHeaderPadding,
          child: Text(
            'Fast Scan Mode',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: _quotePanelPadding,
          child: RepaintBoundary(child: quotePanel),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            _livePanelPadding.left,
            8,
            _livePanelPadding.right,
            0,
          ),
          child: RepaintBoundary(child: liveOrderControlPanel),
        ),
        Expanded(
          child: loadingProducts
              ? _loadingProductsIndicator
              : CustomScrollView(
                  controller: scanPanelScrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: _scrollListPadding,
                      sliver: orderListSliver,
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
    );

    if (!quickEntryFloatAboveKeyboard) return scanBody;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: scanBody),
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

  static final ButtonStyle _selectCustomerButtonStyle = FilledButton.styleFrom(
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
      debugPrint('REBUILD_INSTRUMENT _ScanQuotePanelBody #$_debugRebuildCount');
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
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
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
                child: const Text('Select', style: TextStyle(fontSize: 12)),
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
    required this.scannerFocusNode,
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
  final FocusNode scannerFocusNode;
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
        AnimatedBuilder(
          animation: scannerFocusNode,
          builder: (context, _) {
            final isActive = scannerFocusNode.hasFocus;
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Text(
                isActive
                    ? 'Scanner Focus: ACTIVE'
                    : 'Scanner Focus: NOT ACTIVE',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isActive ? Colors.green.shade700 : Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
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
    required this.priceIndicator,
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
  final String? priceIndicator;
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
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selectedLine == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
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
                    final colorScheme = Theme.of(context).colorScheme;
                    const double imgSize = 150;
                    const double gap = 6;
                    const double ctrlColW = 128;
                    const double sideBtn = 44;
                    const double qtyRowH = 44;
                    const double widePanelMinW = 352;

                    Widget lineImage(double size) {
                      return SizedBox(
                        width: size,
                        height: size,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            'https://showroom-images.netlify.app/images/${line.product.itemNumber.trim()}.jpeg',
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  size: 32,
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    }

                    Widget priceBlockFor(
                      TextAlign textAlign,
                      CrossAxisAlignment priceCross,
                    ) {
                      final p = line.product;
                      if (p.isPs) {
                        return Column(
                          crossAxisAlignment: priceCross,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Reg. Price: \$${_displayRegUnitPrice(p).toStringAsFixed(2)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: textAlign,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              'Sale: \$${_roundedUnitPrice(p.price).toStringAsFixed(2)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: textAlign,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ],
                        );
                      }
                      if (lineHasDiscount) {
                        return Column(
                          crossAxisAlignment: priceCross,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Reg. Price: \$${_displayRegUnitPrice(line.product).toStringAsFixed(2)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: textAlign,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              'Your Price: \$${discountedUnitPrice.toStringAsFixed(2)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: textAlign,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ],
                        );
                      }
                      return Text(
                        'Price: \$${_roundedUnitPrice(line.product.price).toStringAsFixed(2)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: textAlign,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    }

                    List<Widget> detailColumnChildren(
                      TextAlign textAlign,
                      CrossAxisAlignment priceCross,
                    ) {
                      return [
                        _orderLineTitleWithOptionalNewBadge(
                          description: line.product.description,
                          textAlign: textAlign,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Item # ${line.product.itemNumber}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: textAlign,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        priceBlockFor(textAlign, priceCross),
                        const SizedBox(height: 3),
                        Text(
                          'Min: ${line.product.minOrderQty}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: textAlign,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Line total: \$${lineTotal.toStringAsFixed(2)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: textAlign,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        _warehouseAvailabilityLinesWidget(
                          context,
                          line.product,
                          textAlign: textAlign,
                          padding: EdgeInsets.zero,
                        ),
                      ];
                    }

                    Widget rightQtyDeleteColumn() {
                      return SizedBox(
                        width: ctrlColW,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: qtyRowH,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: sideBtn,
                                    child: FilledButton(
                                      onPressed: onDecreaseQty,
                                      style: FilledButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        backgroundColor:
                                            colorScheme.errorContainer,
                                        foregroundColor:
                                            colorScheme.onErrorContainer,
                                      ),
                                      child: const Icon(Icons.remove, size: 24),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.5),
                                        border: Border.all(color: Colors.grey),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${line.quantity}',
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
                                  const SizedBox(width: 4),
                                  SizedBox(
                                    width: sideBtn,
                                    child: FilledButton(
                                      onPressed: onIncreaseQty,
                                      style: FilledButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Icon(Icons.add, size: 24),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 8,
                                ),
                                minimumSize: const Size(0, 40),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                backgroundColor: colorScheme.error,
                                foregroundColor: colorScheme.onError,
                              ),
                              onPressed: () => onDeleteSelectedLine(line),
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Delete'),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth >= widePanelMinW) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              lineImage(imgSize),
                              SizedBox(width: gap),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: detailColumnChildren(
                                      TextAlign.center,
                                      CrossAxisAlignment.center,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: gap),
                              rightQtyDeleteColumn(),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                lineImage(104),
                                SizedBox(width: gap),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: detailColumnChildren(
                                      TextAlign.start,
                                      CrossAxisAlignment.start,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LayoutBuilder(
                              builder: (context, c2) {
                                const double sideB = 52;
                                const double deleteW = 84;
                                const double rowH = 48;
                                const double g = 8;
                                final double midW =
                                    (c2.maxWidth - sideB * 2 - deleteW - g * 3)
                                        .clamp(48.0, c2.maxWidth);
                                return SizedBox(
                                  height: rowH,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        width: sideB,
                                        child: FilledButton(
                                          onPressed: onDecreaseQty,
                                          style: FilledButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                            backgroundColor:
                                                colorScheme.errorContainer,
                                            foregroundColor:
                                                colorScheme.onErrorContainer,
                                          ),
                                          child: const Icon(
                                            Icons.remove,
                                            size: 28,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: g),
                                      SizedBox(
                                        width: midW,
                                        child: Container(
                                          alignment: Alignment.center,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.5),
                                            border: Border.all(
                                              color: Colors.grey,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
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
                                      SizedBox(width: g),
                                      SizedBox(
                                        width: sideB,
                                        child: FilledButton(
                                          onPressed: onIncreaseQty,
                                          style: FilledButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                          ),
                                          child: const Icon(
                                            Icons.add,
                                            size: 28,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: g),
                                      SizedBox(
                                        width: deleteW,
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            backgroundColor: colorScheme.error,
                                            foregroundColor:
                                                colorScheme.onError,
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
                    );
                  },
                ),
              const Divider(height: 10),
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
    required this.onScanWithCamera,
  });

  final VoidCallback onLoadQuote;
  final VoidCallback onCreateQuote;
  final VoidCallback onScanWithCamera;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        FilledButton(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: onLoadQuote,
          child: const Text('Load Quote', style: TextStyle(fontSize: 13)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: onCreateQuote,
          child: const Text('Create Quote', style: TextStyle(fontSize: 13)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: onScanWithCamera,
          child: const Text('Scan with Camera', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}

class _ECatalogTopActionBar extends StatelessWidget {
  const _ECatalogTopActionBar({
    required this.onCreateQuote,
    required this.onLoadQuote,
    required this.onImportOrder,
    required this.onExportAll,
    required this.onExportCurrentQuote,
    required this.loadingProducts,
  });

  final VoidCallback onCreateQuote;
  final VoidCallback onLoadQuote;
  final VoidCallback onImportOrder;
  final VoidCallback onExportAll;
  final Future<void> Function() onExportCurrentQuote;
  final bool loadingProducts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        FilledButton(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: onCreateQuote,
          child: const Text('Create Quote', style: TextStyle(fontSize: 13)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: onLoadQuote,
          child: const Text('Load Quote', style: TextStyle(fontSize: 13)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: onImportOrder,
          child: const Text('Import Order', style: TextStyle(fontSize: 13)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: onExportAll,
          child: const Text('Export All Quotes', style: TextStyle(fontSize: 13)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: loadingProducts
              ? null
              : () => unawaited(onExportCurrentQuote()),
          child: const Text(
            'Export Current Quote Only',
            style: TextStyle(fontSize: 13),
          ),
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
    required this.onQuickEntryTap,
    required this.onSearchChanged,
    required this.onQuickEntryTapOutside,
    required this.onQuickEntrySubmitted,
    required this.onAddPressed,
    required this.statusText,
  });

  final Key quickEntryTextFieldKey;
  final TextEditingController quickEntryController;
  final FocusNode quickEntryFocusNode;
  final VoidCallback onQuickEntryTap;
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
                onTap: onQuickEntryTap,
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

/// Two-line warehouse availability for product detail surfaces (always shown).
Widget _warehouseAvailabilityLinesWidget(
  BuildContext context,
  Product product, {
  TextAlign textAlign = TextAlign.start,
  EdgeInsetsGeometry padding = const EdgeInsets.only(bottom: 10),
}) {
  final textTheme = Theme.of(context).textTheme;
  final style = textTheme.bodySmall?.copyWith(height: 1.15);
  final effectiveStyle = style ?? textTheme.bodySmall ?? const TextStyle();
  final cross = textAlign == TextAlign.center
      ? CrossAxisAlignment.center
      : CrossAxisAlignment.start;

  Widget availabilityLine(String label, String value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: label,
            style: effectiveStyle.copyWith(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: value,
            style: effectiveStyle.copyWith(fontWeight: FontWeight.w400),
          ),
        ],
      ),
      textAlign: textAlign,
      softWrap: true,
    );
  }

  return Padding(
    padding: padding,
    child: Column(
      crossAxisAlignment: cross,
      mainAxisSize: MainAxisSize.min,
      children: [
        availabilityLine(
          'Availability Whse 1: ',
          _availabilityLabelForWhse1(product),
        ),
        availabilityLine(
          'Availability Whse 2: ',
          _availabilityLabelForWhse2(product),
        ),
      ],
    ),
  );
}

/// Read-only ECatalog product detail (bottom sheet body).
class _ECatalogProductDetailSheet extends StatelessWidget {
  const _ECatalogProductDetailSheet({
    required this.product,
    required this.ecatalogPricing,
  });

  final Product product;

  /// Same branch order and formatting as [_ScannerHomePageState._buildECatalogListPriceColumn].
  final Widget ecatalogPricing;

  static Widget _labeledRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final v = value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(color: _kSecondaryText),
            ),
          ),
          Expanded(
            child: Text(v.isEmpty ? '—' : v, style: textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final url =
        'https://showroom-images.netlify.app/images/${product.itemNumber.trim()}.jpeg';
    final flags = <Widget>[
      if (product.isNewRelease) _flagChip(context, 'NEW', Colors.blue),
      if (product.isPs) _flagChip(context, 'PS', colorScheme.primary),
      if (product.isNet) _flagChip(context, 'NET', colorScheme.tertiary),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Product details',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: 800,
                cacheHeight: 600,
                filterQuality: FilterQuality.low,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return ColoredBox(
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.image_outlined,
                      size: 48,
                      color: colorScheme.outline,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return ColoredBox(
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      size: 48,
                      color: colorScheme.outline,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          _labeledRow(context, label: 'Item #', value: product.itemNumber),
          _labeledRow(
            context,
            label: 'Description',
            value: product.description,
          ),
          _labeledRow(context, label: 'UPC', value: product.upc),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    'Pricing',
                    style: textTheme.bodySmall?.copyWith(
                      color: _kSecondaryText,
                    ),
                  ),
                ),
                Expanded(child: ecatalogPricing),
              ],
            ),
          ),
          _labeledRow(
            context,
            label: 'Product type',
            value: product.productType,
          ),
          _labeledRow(context, label: 'Category', value: product.category),
          _labeledRow(
            context,
            label: 'Sub-category',
            value: product.subCategory,
          ),
          _labeledRow(
            context,
            label: 'Min order qty',
            value: product.minOrderQty > 0 ? '${product.minOrderQty}' : '',
          ),
          _labeledRow(
            context,
            label: 'Case qty',
            value: product.caseQty > 0 ? '${product.caseQty}' : '',
          ),
          _warehouseAvailabilityLinesWidget(context, product),
          if (flags.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Flags',
              style: textTheme.bodySmall?.copyWith(color: _kSecondaryText),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: flags),
          ],
        ],
      ),
    );
  }

  static Widget _flagChip(BuildContext context, String text, Color color) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// ECatalog catalog row: compact pill for quantity already in the current order.
Widget _ecatalogInOrderQtyBadge(BuildContext context, int quantity) {
  final textTheme = Theme.of(context).textTheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.green.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      'QTY $quantity',
      style: textTheme.bodySmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.green.shade800,
      ),
    ),
  );
}

Widget _ecatalogPreviouslyOrderedBadge(BuildContext context) {
  final textTheme = Theme.of(context).textTheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.deepPurple.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      'Purchase History',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: textTheme.bodySmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.deepPurple.shade700,
      ),
    ),
  );
}

/// Same JPEG URL as [_OrderLineCardRow]; small decode bounds for list scrolling.
class _ECatalogProductThumbnail extends StatelessWidget {
  const _ECatalogProductThumbnail({required this.product});

  final Product product;

  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final url =
        'https://showroom-images.netlify.app/images/${product.itemNumber.trim()}.jpeg';
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          width: size,
          height: size,
          cacheWidth: 128,
          cacheHeight: 128,
          filterQuality: FilterQuality.low,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return ColoredBox(
              color: colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.image_outlined,
                size: 22,
                color: colorScheme.outline,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return ColoredBox(
              color: colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 20,
                color: colorScheme.outline,
              ),
            );
          },
        ),
      ),
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
                style: TextStyle(fontSize: 11, color: Colors.green),
              ),
            if (alreadyInOrder) const SizedBox(width: 6),
            if (product.isPs)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Reg. Price: \$${_displayRegUnitPrice(product).toStringAsFixed(2)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'Sale: \$${_roundedUnitPrice(product.price).toStringAsFixed(2)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade800,
                    ),
                  ),
                ],
              )
            else
              Text(
                '\$${_roundedUnitPrice(product.price).toStringAsFixed(2)}',
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

class _ProductPriceLine {
  const _ProductPriceLine({
    required this.label,
    required this.amount,
    this.emphasized = false,
    this.muted = false,
  });

  final String label;
  final double amount;
  final bool emphasized;
  final bool muted;
}

List<_ProductPriceLine> _productPriceLines({
  required Product product,
  required bool hasDiscount,
  double? discountedUnitPrice,
}) {
  if (product.isPs) {
    return [
      _ProductPriceLine(
        label: 'Reg. Price',
        amount: _displayRegUnitPrice(product),
        muted: true,
      ),
      _ProductPriceLine(
        label: 'Sale',
        amount: _roundedUnitPrice(product.price),
        emphasized: true,
      ),
    ];
  }
  if (product.isNet) {
    return [
      _ProductPriceLine(
        label: 'NET',
        amount: _roundedUnitPrice(product.price),
        emphasized: true,
      ),
    ];
  }
  if (hasDiscount && discountedUnitPrice != null) {
    return [
      _ProductPriceLine(
        label: 'Reg. Price',
        amount: _displayRegUnitPrice(product),
        muted: true,
      ),
      _ProductPriceLine(
        label: 'Your Price',
        amount: _roundedUnitPrice(discountedUnitPrice),
        emphasized: true,
      ),
    ];
  }
  return [
    _ProductPriceLine(
      label: 'Price',
      amount: _roundedUnitPrice(product.price),
      emphasized: true,
    ),
  ];
}

Widget _buildProductPriceSummary({
  required Product product,
  required bool hasDiscount,
  double? discountedUnitPrice,
  required TextStyle? regularStyle,
  TextStyle? mutedStyle,
  TextStyle? highlightedStyle,
  CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.start,
  TextAlign textAlign = TextAlign.start,
  int? maxLines = 1,
  TextOverflow overflow = TextOverflow.ellipsis,
}) {
  final lines = _productPriceLines(
    product: product,
    hasDiscount: hasDiscount,
    discountedUnitPrice: discountedUnitPrice,
  );

  if (lines.length == 1) {
    final line = lines.first;
    final style = line.emphasized
        ? (highlightedStyle ?? regularStyle)
        : (line.muted ? (mutedStyle ?? regularStyle) : regularStyle);
    return Text(
      '${line.label}: \$${line.amount.toStringAsFixed(2)}',
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: style,
    );
  }

  return Column(
    crossAxisAlignment: crossAxisAlignment,
    mainAxisSize: MainAxisSize.min,
    children: lines
        .map((line) {
          final style = line.emphasized
              ? (highlightedStyle ?? regularStyle)
              : (line.muted ? (mutedStyle ?? regularStyle) : regularStyle);
          return Text(
            '${line.label}: \$${line.amount.toStringAsFixed(2)}',
            maxLines: maxLines,
            overflow: overflow,
            textAlign: textAlign,
            style: style,
          );
        })
        .toList(growable: false),
  );
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
      children: [for (final product in products) itemBuilder(product)],
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
        child: Text('No items added yet', textAlign: TextAlign.center),
      ),
    );
  }
}

/// Qty + scans + line total column shared by [_OrderLineCardRow] and [_OrderLineCard].
class _OrderLineQtyColumn extends StatelessWidget {
  const _OrderLineQtyColumn({
    required this.line,
    required this.lineTotal,
    required this.onDecrease,
    required this.onIncrease,
    this.compactLayout = false,
  });

  static const TextStyle _qtyStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 18,
  );

  static final ButtonStyle _increaseQtyIconStyle = IconButton.styleFrom(
    padding: EdgeInsets.zero,
  );

  static const double _width = 132;

  final OrderLine line;
  final double lineTotal;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final bool compactLayout;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final double gap = compactLayout ? 3.0 : 2.0;
    return SizedBox(
      width: _width,
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
                    backgroundColor: colorScheme.errorContainer.withValues(
                      alpha: 0.5,
                    ),
                    foregroundColor: colorScheme.onErrorContainer,
                  ),
                ),
              ),
              SizedBox(width: compactLayout ? 8 : 6),
              Text(
                '${line.quantity}',
                style: compactLayout
                    ? _qtyStyle
                    : _qtyStyle.copyWith(fontSize: 17),
              ),
              SizedBox(width: compactLayout ? 8 : 6),
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
          SizedBox(height: gap),
          Text(
            'Scans ${line.scans}',
            style: compactLayout
                ? null
                : const TextStyle(fontSize: 12, height: 1.1),
          ),
          SizedBox(height: gap),
          Text(
            '\$${lineTotal.toStringAsFixed(2)}',
            style: compactLayout
                ? const TextStyle(fontWeight: FontWeight.w600)
                : const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.1,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Single order line row layout (product details + qty controls) for scan / orders lists.
class _OrderLineCardRow extends StatelessWidget {
  // REBUILD_INSTRUMENT: remove when done profiling scan-tab rebuild frequency
  static int _debugRebuildCount = 0;

  const _OrderLineCardRow({
    required this.line,
    this.displayProduct,
    this.compactLayout = false,
    this.expandedOrdersCompact = false,
    this.includeQtyColumn = true,
    required this.lineHasDiscount,
    required this.discountedUnitPrice,
    required this.priceIndicator,
    required this.lineTotal,
    required this.onDecrease,
    required this.onIncrease,
  });

  /// When true (Orders tab + Scan tab order lists), use denser text lines and bottom-right image.
  final bool compactLayout;

  /// Compact order lists: expanded card uses a large top image and untruncated text.
  final bool expandedOrdersCompact;

  /// When false, only the product / image block is built (qty sits outside the card tap target).
  final bool includeQtyColumn;

  final OrderLine line;
  final Product? displayProduct;
  final bool lineHasDiscount;
  final double discountedUnitPrice;
  final String? priceIndicator;
  final double lineTotal;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  Widget _productNetworkImage(double size, double cornerRadius) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(cornerRadius),
        child: Image.network(
          'https://showroom-images.netlify.app/images/${line.product.itemNumber.trim()}.jpeg',
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Icon(Icons.image_not_supported, size: 16),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode && _kScanRebuildInstrumentationEnabled) {
      _debugRebuildCount++;
      debugPrint('REBUILD_INSTRUMENT _OrderLineCardRow #$_debugRebuildCount');
    }
    final colorScheme = Theme.of(context).colorScheme;
    final product = displayProduct ?? line.product;
    final productFlagChips = _productFlagChips(context, product);

    final Widget qtyColumn = _OrderLineQtyColumn(
      line: line,
      lineTotal: lineTotal,
      onDecrease: onDecrease,
      onIncrease: onIncrease,
      compactLayout: compactLayout,
    );

    if (compactLayout) {
      const double collapsedImageSize = 84;
      const double expandedImageSize = 192;
      const double imageGutter = 8;
      final TextStyle line3BaseStyle = TextStyle(
        fontSize: 11.5,
        height: 1.1,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurface,
      );
      final TextStyle highlightPriceStyle = TextStyle(
        color: Colors.green.shade800,
        fontWeight: FontWeight.w700,
      );

      Widget buildCompactPriceLine({required bool ellipsize}) {
        return _buildProductPriceSummary(
          product: product,
          hasDiscount: lineHasDiscount,
          discountedUnitPrice: discountedUnitPrice,
          regularStyle: line3BaseStyle.copyWith(
            fontWeight: FontWeight.w700,
          ),
          mutedStyle: line3BaseStyle,
          highlightedStyle: line3BaseStyle.copyWith(
            color: highlightPriceStyle.color,
            fontWeight: FontWeight.w700,
          ),
          maxLines: ellipsize ? 1 : null,
          overflow: ellipsize ? TextOverflow.ellipsis : TextOverflow.visible,
        );
      }

      final Widget line3Collapsed = buildCompactPriceLine(ellipsize: true);
      final Widget line3Expanded = buildCompactPriceLine(ellipsize: false);

      final Widget compactProductBlock = expandedOrdersCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _productNetworkImage(expandedImageSize, 14),
                SizedBox(height: imageGutter + 2),
                _orderLineTitleWithOptionalNewBadge(
                  description: product.description,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.12,
                  ),
                ),
                if (productFlagChips.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 6, children: productFlagChips),
                ],
                const SizedBox(height: 1),
                Text(
                  'Item ${product.itemNumber}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.08,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  'UPC ${product.upc}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.08,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 1),
                line3Expanded,
                _warehouseAvailabilityLinesWidget(
                  context,
                  product,
                  padding: const EdgeInsets.only(top: 2),
                ),
              ],
            )
          : Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    right: collapsedImageSize + imageGutter,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: collapsedImageSize),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _orderLineTitleWithOptionalNewBadge(
                          description: product.description,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            height: 1.12,
                          ),
                        ),
                        if (productFlagChips.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: productFlagChips,
                          ),
                        ],
                        const SizedBox(height: 1),
                        Text(
                          'Item ${product.itemNumber} · UPC ${product.upc}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.08,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 1),
                        line3Collapsed,
                        _warehouseAvailabilityLinesWidget(
                          context,
                          product,
                          padding: const EdgeInsets.only(top: 2),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _productNetworkImage(collapsedImageSize, 10),
                ),
              ],
            );

      if (!includeQtyColumn) {
        return compactProductBlock;
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: compactProductBlock),
          const SizedBox(width: 8),
          qtyColumn,
        ],
      );
    }

    // Legacy non-compact row (unused by current [_buildOrderCard] call sites; Scan uses compact).
    const double scanRowImageSize = 50;
    final Widget scanProductRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _productNetworkImage(scanRowImageSize, 10),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _orderLineTitleWithOptionalNewBadge(
                description: product.description,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.12,
                ),
              ),
              if (productFlagChips.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 6, children: productFlagChips),
              ],
              _warehouseAvailabilityLinesWidget(
                context,
                product,
                padding: const EdgeInsets.only(top: 2),
              ),
            ],
          ),
        ),
      ],
    );

    if (!includeQtyColumn) {
      return scanProductRow;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: scanProductRow),
        const SizedBox(width: 8),
        qtyColumn,
      ],
    );
  }
}

/// Swipe-delete hint behind [Dismissible] — const so unchanged cards skip subtree work.
class _OrderLineCardDismissBackground extends StatelessWidget {
  const _OrderLineCardDismissBackground({this.compactLayout = true});

  final bool compactLayout;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      margin: EdgeInsets.symmetric(
        horizontal: 8,
        vertical: compactLayout ? 3 : 2,
      ),
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
    this.displayProduct,
    this.scanTabHighlightFlash = false,
    this.compactLayout = false,
    this.expandedOrdersCompact = false,
    this.restrictCardTapToProductArea = false,
    required this.lineHasDiscount,
    required this.discountedUnitPrice,
    required this.priceIndicator,
    required this.lineTotal,
    required this.onSwipeDeletePrompt,
    required this.onCardTap,
    required this.onDecrease,
    required this.onIncrease,
  });

  final Key dismissibleKey;
  final OrderLine line;
  final Product? displayProduct;
  final bool scanTabHighlightFlash;

  /// Denser card + line layout for Orders tab [ListView] and Scan tab [SliverList].
  final bool compactLayout;

  /// Expanded compact card: large top image, untruncated compact text.
  final bool expandedOrdersCompact;

  /// When true (compact lists), [onCardTap] applies only to the product block, not qty.
  final bool restrictCardTapToProductArea;
  final bool lineHasDiscount;
  final double discountedUnitPrice;
  final String? priceIndicator;
  final double lineTotal;
  final Future<void> Function() onSwipeDeletePrompt;
  final VoidCallback onCardTap;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode && _kScanRebuildInstrumentationEnabled) {
      _debugRebuildCount++;
      debugPrint('REBUILD_INSTRUMENT _OrderLineCard #$_debugRebuildCount');
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

    final EdgeInsets cardPadding = compactLayout
        ? const EdgeInsets.all(6)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 6);

    final Widget rowBody = restrictCardTapToProductArea
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: _kOrderLineCardBorderRadius,
                  onTap: onCardTap,
                  child: _OrderLineCardRow(
                    line: line,
                    displayProduct: displayProduct,
                    compactLayout: compactLayout,
                    expandedOrdersCompact: expandedOrdersCompact,
                    includeQtyColumn: false,
                    lineHasDiscount: lineHasDiscount,
                    discountedUnitPrice: discountedUnitPrice,
                    priceIndicator: priceIndicator,
                    lineTotal: lineTotal,
                    onDecrease: onDecrease,
                    onIncrease: onIncrease,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _OrderLineQtyColumn(
                line: line,
                lineTotal: lineTotal,
                onDecrease: onDecrease,
                onIncrease: onIncrease,
                compactLayout: compactLayout,
              ),
            ],
          )
        : InkWell(
            borderRadius: _kOrderLineCardBorderRadius,
            onTap: onCardTap,
            child: _OrderLineCardRow(
              line: line,
              displayProduct: displayProduct,
              compactLayout: compactLayout,
              expandedOrdersCompact: expandedOrdersCompact,
              includeQtyColumn: true,
              lineHasDiscount: lineHasDiscount,
              discountedUnitPrice: discountedUnitPrice,
              priceIndicator: priceIndicator,
              lineTotal: lineTotal,
              onDecrease: onDecrease,
              onIncrease: onIncrease,
            ),
          );

    return Dismissible(
      key: dismissibleKey,
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await onSwipeDeletePrompt();
        return false;
      },
      background: _OrderLineCardDismissBackground(compactLayout: compactLayout),
      child: Card(
        margin: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: compactLayout ? 3 : 2,
        ),
        shape: cardShape,
        child: RepaintBoundary(
          child: Padding(padding: cardPadding, child: rowBody),
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

  /// Dense order-tab actions (~42px tall) while keeping full-width labels readable.
  static final ButtonStyle _orderTabActionButtonStyle = FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
    minimumSize: const Size(double.infinity, 42),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                            const SizedBox(height: 2),
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
                            const SizedBox(height: 2),
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
                            const SizedBox(height: 2),
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
                    const Divider(height: 16),
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
          const SizedBox(height: 4),
          Text(
            'Order files: OneDrive → Import folder',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          FilledButton.icon(
            style: _orderTabActionButtonStyle,
            onPressed: loadingProducts
                ? null
                : () {
                    print('🔥 IMPORT ENTRY HIT 🔥');
                    print('[ImportOrderButton] import order started');
                    onImportOrder();
                  },
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Import Order (OneDrive → Import folder)'),
          ),
          const SizedBox(height: 4),
          FilledButton.icon(
            style: _orderTabActionButtonStyle,
            onPressed: loadingProducts ? null : () => onExportAllQuotes(),
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Export Order (Saved to OneDrive / Share)'),
          ),
          const SizedBox(height: 4),
          FilledButton.icon(
            style: _orderTabActionButtonStyle,
            onPressed: loadingProducts ? null : () => onExportCurrentQuote(),
            icon: const Icon(Icons.download_for_offline_outlined),
            label: const Text('Export Current Quote Only'),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: loadingProducts
                ? const Center(child: CircularProgressIndicator())
                : (activeTabIndex == 2 ? orderList : const SizedBox.shrink()),
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
    required this.onAddCustomer,
    required this.onWalkOrderEditor,
    required this.loadingProductsFromWeb,
    required this.loadingCustomersFromWeb,
    this.onBuildFullCatalogTestQuote,
    this.onExportFullCatalogExcel,
    this.exportingFullCatalogExcel = false,
    this.onExportMasterUpdateSheets,
    this.exportingMasterUpdateSheets = false,
    this.onBuildUpdatedMasterProductsSheet,
    this.buildingUpdatedMasterSheet = false,
  });

  final VoidCallback onLoadProducts;
  final VoidCallback onLoadCustomers;
  final Future<void> Function() onAddCustomer;
  final VoidCallback onWalkOrderEditor;
  final bool loadingProductsFromWeb;
  final bool loadingCustomersFromWeb;
  final Future<void> Function()? onBuildFullCatalogTestQuote;
  final Future<void> Function()? onExportFullCatalogExcel;
  final bool exportingFullCatalogExcel;
  final Future<void> Function()? onExportMasterUpdateSheets;
  final bool exportingMasterUpdateSheets;
  final Future<void> Function()? onBuildUpdatedMasterProductsSheet;
  final bool buildingUpdatedMasterSheet;

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
                  onPressed: loadingProductsFromWeb ? null : onLoadProducts,
                  child: Text(
                    loadingProductsFromWeb ? 'UPDATING...' : 'LOAD PRODUCTS',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: loadingCustomersFromWeb ? null : onLoadCustomers,
                  child: Text(
                    loadingCustomersFromWeb ? 'UPDATING...' : 'LOAD CUSTOMERS',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Select files from Downloads folder',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            'These are local working files (Downloads)',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () {
              onAddCustomer();
            },
            child: const Text('Add Customer'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onWalkOrderEditor,
            child: const Text('Walk Order Editor'),
          ),
          if (onBuildFullCatalogTestQuote != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                unawaited(onBuildFullCatalogTestQuote!());
              },
              child: const Text('Build Full Catalog Test Quote'),
            ),
          ],
          if (onExportFullCatalogExcel != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: exportingFullCatalogExcel
                  ? null
                  : () {
                      unawaited(onExportFullCatalogExcel!());
                    },
              child: Text(
                exportingFullCatalogExcel
                    ? 'EXPORTING…'
                    : 'Export Full Catalog Test Quote (Excel)',
              ),
            ),
          ],
          if (onExportMasterUpdateSheets != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: exportingMasterUpdateSheets
                  ? null
                  : () {
                      unawaited(onExportMasterUpdateSheets!());
                    },
              child: Text(
                exportingMasterUpdateSheets
                    ? 'EXPORTING…'
                    : 'Export Master Update Sheets',
              ),
            ),
          ],
          if (onBuildUpdatedMasterProductsSheet != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: buildingUpdatedMasterSheet
                  ? null
                  : () {
                      unawaited(onBuildUpdatedMasterProductsSheet!());
                    },
              child: Text(
                buildingUpdatedMasterSheet
                    ? 'BUILDING…'
                    : 'Build Updated Master Products Sheet',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CameraScannerPage extends StatefulWidget {
  final Future<_CameraScanOverlayUpdate?> Function(String) onDetect;

  const _CameraScannerPage({required this.onDetect});

  @override
  State<_CameraScannerPage> createState() => _CameraScannerPageState();
}

class _CameraScanOverlayUpdate {
  final String itemNumber;
  final int quantity;

  const _CameraScanOverlayUpdate({
    required this.itemNumber,
    required this.quantity,
  });
}

class _CameraScannerPageState extends State<_CameraScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  static const Duration _duplicateScanCooldown = Duration(milliseconds: 1200);
  String? _lastScannedValue;
  DateTime? _lastScannedAt;
  bool _torchEnabled = false;
  String _cameraOverlayText = 'Qty: 0';

  String _cameraScanQtyLabel() => _cameraOverlayText;

  void _updateCameraOverlayQtyForScanResult(_CameraScanOverlayUpdate result) {
    if (!mounted) return;
    setState(() {
      _cameraOverlayText = 'Qty: ${result.quantity}';
    });
  }

  Future<void> _toggleTorch() async {
    final state = _controller.value;
    if (!state.isRunning || state.torchState == TorchState.unavailable) {
      return;
    }
    await _controller.toggleTorch();
    if (!mounted) return;
    setState(() => _torchEnabled = !_torchEnabled);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue == null) continue;
      final raw = rawValue.trim();
      if (raw.isEmpty) continue;

      final now = DateTime.now();
      final isRecentDuplicate =
          _lastScannedValue == raw &&
          _lastScannedAt != null &&
          now.difference(_lastScannedAt!) < _duplicateScanCooldown;
      if (isRecentDuplicate) continue;

      _lastScannedValue = raw;
      _lastScannedAt = now;
      final overlayUpdate = await widget.onDetect(raw);
      if (mounted) {
        setState(() {});
      }
      if (overlayUpdate != null) {
        _updateCameraOverlayQtyForScanResult(overlayUpdate);
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan with Camera'),
        actions: [
          IconButton(
            icon: Icon(
              _torchEnabled ? Icons.flashlight_on : Icons.flashlight_off,
            ),
            tooltip: _torchEnabled
                ? 'Turn flashlight off'
                : 'Turn flashlight on',
            onPressed: () {
              _toggleTorch();
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _handleBarcode),
          Positioned(
            top: 12,
            right: 12,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _cameraScanQtyLabel(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Point camera at barcode',
                      style: TextStyle(color: Colors.white),
                    ),
                    if (_lastScannedValue != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Last scanned: $_lastScannedValue',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ],
                ),
              ),
            ),
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
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
                        style: TextStyle(fontSize: 14, color: onSurface),
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
            return Center(
              child: Text('Could not load archive: ${snapshot.error}'),
            );
          }
          final all = snapshot.data ?? [];
          final archived =
              all
                  .where((e) => e.status == QuoteLifecycleStatus.archived)
                  .toList()
                ..sort(_sortArchiveEntries);
          final confirmed =
              all
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

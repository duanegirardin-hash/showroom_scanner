/// Temporary trade-show quote-routing overrides (Glassware / Furniture / Incense).
///
/// Does **not** change Product Type, Category, or Sub-Category on the product.
/// Returns a routing bucket key/label only. Disable via config `enabled: false`.
library;

/// One trade-show routing bucket.
class TradeShowQuoteBucket {
  const TradeShowQuoteBucket({
    required this.bucketKey,
    required this.displayLabel,
  });

  final String bucketKey;
  final String displayLabel;
}

/// Parsed [assets/data/trade_show_quote_routing.json].
class TradeShowQuoteRoutingConfig {
  const TradeShowQuoteRoutingConfig({
    required this.enabled,
    required this.glasswareItemNumbers,
    required this.furnitureItemNumbers,
    required this.furnitureCategories,
    required this.furnitureSubCategory,
    required this.incenseSubCategory,
    required this.glassware,
    required this.furniture,
    required this.incense,
  });

  final bool enabled;
  final Set<String> glasswareItemNumbers;

  /// Explicit user-approved Furniture Item Numbers (route regardless of Product Type).
  final Set<String> furnitureItemNumbers;
  final Set<String> furnitureCategories;
  final String furnitureSubCategory;
  final String incenseSubCategory;
  final TradeShowQuoteBucket glassware;
  final TradeShowQuoteBucket furniture;
  final TradeShowQuoteBucket incense;

  static const TradeShowQuoteRoutingConfig disabled = TradeShowQuoteRoutingConfig(
    enabled: false,
    glasswareItemNumbers: <String>{},
    furnitureItemNumbers: <String>{},
    furnitureCategories: <String>{},
    furnitureSubCategory: '',
    incenseSubCategory: '',
    glassware: TradeShowQuoteBucket(
      bucketKey: 'glassware',
      displayLabel: 'GLASSWARE',
    ),
    furniture: TradeShowQuoteBucket(
      bucketKey: 'furniture',
      displayLabel: 'FURNITURE',
    ),
    incense: TradeShowQuoteBucket(
      bucketKey: 'incense',
      displayLabel: 'INCENSE',
    ),
  );

  /// All special buckets (for registration into the quote-bucket map).
  List<TradeShowQuoteBucket> get allBuckets => [glassware, furniture, incense];
}

/// Trim + collapse internal whitespace; keep punctuation for exact label compare.
String normalizeTradeShowField(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Case-insensitive field equality after [normalizeTradeShowField].
bool tradeShowFieldsEqual(String a, String b) {
  return normalizeTradeShowField(a).toLowerCase() ==
      normalizeTradeShowField(b).toLowerCase();
}

/// Accent-insensitive category compare so "Décor" and "Decor" can both match.
String _foldCategoryKey(String value) {
  final n = normalizeTradeShowField(value).toLowerCase();
  return n
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('à', 'a')
      .replaceAll('á', 'a');
}

bool _categoryMatches(String actual, Set<String> allowed) {
  final folded = _foldCategoryKey(actual);
  for (final candidate in allowed) {
    if (folded == _foldCategoryKey(candidate)) return true;
  }
  return false;
}

/// Normalize item numbers the same way as the scanner (`trim` + upper).
String normalizeTradeShowItemNumber(String value) => value.trim().toUpperCase();

/// True when Product Type is EVERYDAY (or blank / absent → treated as Everyday).
bool isEverydayOrAbsentProductType(String productType) {
  final t = productType.trim();
  if (t.isEmpty || t == '0') return true;
  return t.toUpperCase() == 'EVERYDAY';
}

Set<String> _parseItemNumberList(dynamic raw) {
  final out = <String>{};
  if (raw is! List) return out;
  for (final e in raw) {
    final n = normalizeTradeShowItemNumber(e.toString());
    if (n.isNotEmpty) out.add(n);
  }
  return out;
}

TradeShowQuoteRoutingConfig parseTradeShowQuoteRoutingConfig(
  Map<String, dynamic> root,
) {
  final enabled = root['enabled'] == true;
  final bucketsRaw = root['buckets'];
  final buckets = bucketsRaw is Map
      ? Map<String, dynamic>.from(bucketsRaw)
      : <String, dynamic>{};

  TradeShowQuoteBucket readBucket(String key, String fallbackKey, String label) {
    final raw = buckets[key];
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final bucketKey =
          (map['bucketKey'] as String?)?.trim().isNotEmpty == true
          ? (map['bucketKey'] as String).trim()
          : fallbackKey;
      final displayLabel =
          (map['displayLabel'] as String?)?.trim().isNotEmpty == true
          ? (map['displayLabel'] as String).trim()
          : label;
      return TradeShowQuoteBucket(
        bucketKey: bucketKey,
        displayLabel: displayLabel,
      );
    }
    return TradeShowQuoteBucket(bucketKey: fallbackKey, displayLabel: label);
  }

  final glassItems = _parseItemNumberList(root['glasswareItemNumbers']);

  final furnitureRaw = root['furniture'];
  final furnitureMap = furnitureRaw is Map
      ? Map<String, dynamic>.from(furnitureRaw)
      : <String, dynamic>{};
  final furnitureItems = _parseItemNumberList(furnitureMap['itemNumbers']);
  final categories = <String>{};
  final primary = (furnitureMap['category'] as String?)?.trim() ?? '';
  if (primary.isNotEmpty) categories.add(primary);
  final aliases = furnitureMap['categoryAliases'];
  if (aliases is List) {
    for (final a in aliases) {
      final s = a.toString().trim();
      if (s.isNotEmpty) categories.add(s);
    }
  }
  final furnitureSub =
      (furnitureMap['subCategory'] as String?)?.trim() ??
      'Furniture & Shelving';

  final incenseRaw = root['incense'];
  final incenseMap = incenseRaw is Map
      ? Map<String, dynamic>.from(incenseRaw)
      : <String, dynamic>{};
  final incenseSub =
      (incenseMap['subCategory'] as String?)?.trim() ?? 'Incense';

  return TradeShowQuoteRoutingConfig(
    enabled: enabled,
    glasswareItemNumbers: glassItems,
    furnitureItemNumbers: furnitureItems,
    furnitureCategories: categories,
    furnitureSubCategory: furnitureSub,
    incenseSubCategory: incenseSub,
    glassware: readBucket('glassware', 'glassware', 'GLASSWARE'),
    furniture: readBucket('furniture', 'furniture', 'FURNITURE'),
    incense: readBucket('incense', 'incense', 'INCENSE'),
  );
}

/// Which special rule matched (diagnostics / tests).
enum TradeShowRouteRule {
  none,
  glassware,
  furnitureExplicit,
  furnitureBroad,
  incense,
}

class TradeShowRouteDecision {
  const TradeShowRouteDecision({
    required this.rule,
    this.bucket,
    this.skippedNonEveryday = false,
  });

  final TradeShowRouteRule rule;
  final TradeShowQuoteBucket? bucket;

  /// True when broad furniture/incense fields matched but Product Type was not Everyday.
  final bool skippedNonEveryday;

  static const none = TradeShowRouteDecision(rule: TradeShowRouteRule.none);

  /// Canonical furniture bucket whether matched via explicit list or broad rule.
  bool get isFurniture =>
      rule == TradeShowRouteRule.furnitureExplicit ||
      rule == TradeShowRouteRule.furnitureBroad;
}

/// Resolve a trade-show override.
///
/// Precedence:
/// 1. Explicit Glassware item list
/// 2. Explicit Furniture item list (any Product Type)
/// 3. Everyday Furniture Category + Sub-Category
/// 4. Everyday Incense Sub-Category
/// 5. none (caller continues normal Product Type routing)
TradeShowRouteDecision resolveTradeShowQuoteRoute({
  required TradeShowQuoteRoutingConfig config,
  required String itemNumber,
  required String productType,
  required String category,
  required String subCategory,
}) {
  if (!config.enabled) return TradeShowRouteDecision.none;

  final item = normalizeTradeShowItemNumber(itemNumber);
  if (item.isNotEmpty && config.glasswareItemNumbers.contains(item)) {
    return TradeShowRouteDecision(
      rule: TradeShowRouteRule.glassware,
      bucket: config.glassware,
    );
  }

  if (item.isNotEmpty && config.furnitureItemNumbers.contains(item)) {
    // Explicit user-approved Furniture list — overrides even non-EVERYDAY types.
    return TradeShowRouteDecision(
      rule: TradeShowRouteRule.furnitureExplicit,
      bucket: config.furniture,
    );
  }

  final furnitureHit =
      _categoryMatches(category, config.furnitureCategories) &&
      tradeShowFieldsEqual(subCategory, config.furnitureSubCategory);
  if (furnitureHit) {
    if (!isEverydayOrAbsentProductType(productType)) {
      return const TradeShowRouteDecision(
        rule: TradeShowRouteRule.none,
        skippedNonEveryday: true,
      );
    }
    return TradeShowRouteDecision(
      rule: TradeShowRouteRule.furnitureBroad,
      bucket: config.furniture,
    );
  }

  if (tradeShowFieldsEqual(subCategory, config.incenseSubCategory)) {
    if (!isEverydayOrAbsentProductType(productType)) {
      return const TradeShowRouteDecision(
        rule: TradeShowRouteRule.none,
        skippedNonEveryday: true,
      );
    }
    return TradeShowRouteDecision(
      rule: TradeShowRouteRule.incense,
      bucket: config.incense,
    );
  }

  return TradeShowRouteDecision.none;
}

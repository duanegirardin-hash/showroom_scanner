/// Shared quote-bucket Product Type normalization and ECatalog seasonal membership.
/// Kept small and side-effect free so routing aliases can be regression-tested
/// without the full scanner UI.

String normalizeBucketLookupKey(String value) {
  var normalized = value.trim().toLowerCase();
  normalized = normalized.replaceAll(RegExp(r"[`´’']"), "'");
  normalized = normalized.replaceAll('&', ' and ');
  normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized;
}

/// One configured bucket from [assets/data/product_type_buckets.json].
class ProductTypeBucketMapping {
  final String bucketKey;
  final String displayLabel;

  const ProductTypeBucketMapping({
    required this.bucketKey,
    required this.displayLabel,
  });
}

/// Parses `{"mappings": { "RAW TYPE": { "bucketKey", "displayLabel" }, ... }}`
/// into a map keyed by [normalizeBucketLookupKey] of each raw type string.
Map<String, ProductTypeBucketMapping> parseProductTypeBucketMappings(
  Map<String, dynamic> root,
) {
  final out = <String, ProductTypeBucketMapping>{};
  final mappings = root['mappings'];
  if (mappings is! Map) return out;
  for (final entry in mappings.entries) {
    final rawKey = entry.key.toString().trim();
    final rawValue = entry.value;
    if (rawKey.isEmpty || rawValue is! Map) continue;
    final map = Map<String, dynamic>.from(rawValue);
    final bucketKey = (map['bucketKey'] as String?)?.trim() ?? '';
    final displayLabel = (map['displayLabel'] as String?)?.trim() ?? '';
    if (bucketKey.isEmpty || displayLabel.isEmpty) continue;
    out[normalizeBucketLookupKey(rawKey)] = ProductTypeBucketMapping(
      bucketKey: bucketKey,
      displayLabel: displayLabel,
    );
  }
  return out;
}

/// Resolves Product Type first, then Category, using the same order as the app.
/// Returns null when neither maps (caller may apply Pride / Everyday defaults).
ProductTypeBucketMapping? lookupProductTypeBucketMapping({
  required String productType,
  required String category,
  required Map<String, ProductTypeBucketMapping> byNormalizedRawType,
}) {
  final type = productType.trim();
  if (type.isNotEmpty && type != '0') {
    final hit = byNormalizedRawType[normalizeBucketLookupKey(type)];
    if (hit != null) return hit;
  }
  final cat = category.trim();
  if (cat.isNotEmpty) {
    final hit = byNormalizedRawType[normalizeBucketLookupKey(cat)];
    if (hit != null) return hit;
  }
  return null;
}

/// Product Type strings accepted by the ECatalog Seasonal merchandising chip.
/// Includes both legacy (`SUMMER *`) and live sheet (`SPRING/SUMMER - *`) labels.
const Set<String> kEcatalogSeasonalProductTypes = {
  'CALENDAR',
  'CANADA DAY',
  'PRIDE',
  'CHINESE NEW YEAR',
  'CHRISTMAS',
  'DIWALI',
  'EASTER',
  'FALL/WINTER ESSENTIALS',
  "FATHER'S DAY",
  'GRADUATION',
  'HALLOWEEN',
  'HANUKKAH',
  'HARVEST',
  "MOTHER'S DAY",
  'NEW YEARS',
  'SUMMER GENERAL',
  'SUMMER TOYS',
  'SPRING/SUMMER - GENERAL',
  'SPRING/SUMMER - TOYS',
  "ST PATRICK'S DAY",
  "VALENTINE'S DAY",
};

bool isEcatalogSeasonalProductType(String productType) =>
    kEcatalogSeasonalProductTypes.contains(productType.trim().toUpperCase());

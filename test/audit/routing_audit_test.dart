/// Investigation-only audit tests.
///
/// These tests exercise pure helpers already extracted from production
/// (`lib/quote_bucket_routing.dart`) and the bundled bucket JSON.
/// They do not require production-code changes.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/quote_bucket_routing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, ProductTypeBucketMapping> mappings;

  setUpAll(() async {
    final raw = await rootBundle.loadString(
      'assets/data/product_type_buckets.json',
    );
    mappings = parseProductTypeBucketMappings(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  });

  group('normalizeBucketLookupKey', () {
    test('trims and lowercases', () {
      expect(normalizeBucketLookupKey('  EVERYDAY  '), 'everyday');
    });

    test('unifies apostrophe variants', () {
      expect(
        normalizeBucketLookupKey("MOTHER'S DAY"),
        normalizeBucketLookupKey('MOTHER’S DAY'),
      );
    });

    test('collapses punctuation and hyphens to spaces', () {
      expect(
        normalizeBucketLookupKey('SPRING/SUMMER - GENERAL'),
        'spring summer general',
      );
    });
  });

  group('Product Type routing via bundled JSON', () {
    ProductTypeBucketMapping? lookup(String type, [String category = '']) =>
        lookupProductTypeBucketMapping(
          productType: type,
          category: category,
          byNormalizedRawType: mappings,
        );

    test('EVERYDAY → every_day', () {
      expect(lookup('EVERYDAY')?.bucketKey, 'every_day');
    });

    test('SUMMER GENERAL and SPRING/SUMMER - GENERAL share summer_general', () {
      expect(lookup('SUMMER GENERAL')?.bucketKey, 'summer_general');
      expect(lookup('SPRING/SUMMER - GENERAL')?.bucketKey, 'summer_general');
      expect(lookup('SUMMER GENERAL')?.displayLabel, 'SUMMER GENERAL');
      expect(lookup('SPRING/SUMMER - GENERAL')?.displayLabel, 'SUMMER GENERAL');
    });

    test('SUMMER TOYS and SPRING/SUMMER - TOYS share summer_toys', () {
      expect(lookup('SUMMER TOYS')?.bucketKey, 'summer_toys');
      expect(lookup('SPRING/SUMMER - TOYS')?.bucketKey, 'summer_toys');
    });

    test('Summer General and Summer Toys remain separate', () {
      expect(
        lookup('SUMMER GENERAL')?.bucketKey,
        isNot(lookup('SUMMER TOYS')?.bucketKey),
      );
      expect(
        lookup('SPRING/SUMMER - GENERAL')?.bucketKey,
        isNot(lookup('SPRING/SUMMER - TOYS')?.bucketKey),
      );
    });

    test('Halloween / Harvest / Mother\'s Day unchanged', () {
      expect(lookup('HALLOWEEN')?.bucketKey, 'halloween');
      expect(lookup('HARVEST')?.bucketKey, 'harvest');
      expect(lookup("MOTHER'S DAY")?.bucketKey, 'mothers_day');
    });

    test('St Patrick spellings share bucket', () {
      expect(lookup("ST PATRICK'S DAY")?.bucketKey, 'st_patricks_day');
      expect(lookup('ST PATRICKS DAY')?.bucketKey, 'st_patricks_day');
    });

    test('unknown Product Type with empty category returns null (Everyday caller)',
        () {
      expect(lookup('TOTALLY UNKNOWN TYPE XYZ'), isNull);
    });

    test('category fallback when Product Type empty', () {
      // Only succeeds if category string itself is a mapped raw key.
      expect(lookup('', 'HALLOWEEN')?.bucketKey, 'halloween');
    });
  });

  group('ECatalog Seasonal membership', () {
    test('includes both live and legacy Summer labels', () {
      expect(isEcatalogSeasonalProductType('SUMMER GENERAL'), isTrue);
      expect(isEcatalogSeasonalProductType('SUMMER TOYS'), isTrue);
      expect(isEcatalogSeasonalProductType('SPRING/SUMMER - GENERAL'), isTrue);
      expect(isEcatalogSeasonalProductType('SPRING/SUMMER - TOYS'), isTrue);
    });

    test('excludes Everyday; includes Halloween', () {
      expect(isEcatalogSeasonalProductType('EVERYDAY'), isFalse);
      expect(isEcatalogSeasonalProductType('HALLOWEEN'), isTrue);
    });
  });
}

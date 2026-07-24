import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/quote_bucket_routing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, ProductTypeBucketMapping> byNorm;

  setUpAll(() async {
    final raw = await rootBundle.loadString(
      'assets/data/product_type_buckets.json',
    );
    final decoded = jsonDecode(raw);
    expect(decoded, isA<Map>());
    byNorm = parseProductTypeBucketMappings(
      Map<String, dynamic>.from(decoded as Map),
    );
  });

  ProductTypeBucketMapping? resolve(
    String productType, {
    String category = '',
  }) {
    return lookupProductTypeBucketMapping(
      productType: productType,
      category: category,
      byNormalizedRawType: byNorm,
    );
  }

  group('Summer Product Type routing aliases', () {
    test('SPRING/SUMMER - GENERAL → summer_general', () {
      final hit = resolve('SPRING/SUMMER - GENERAL');
      expect(hit, isNotNull);
      expect(hit!.bucketKey, 'summer_general');
      expect(hit.displayLabel, 'SUMMER GENERAL');
    });

    test('SPRING/SUMMER - TOYS → summer_toys', () {
      final hit = resolve('SPRING/SUMMER - TOYS');
      expect(hit, isNotNull);
      expect(hit!.bucketKey, 'summer_toys');
      expect(hit.displayLabel, 'SUMMER TOYS');
    });

    test('SUMMER GENERAL still → summer_general', () {
      final hit = resolve('SUMMER GENERAL');
      expect(hit, isNotNull);
      expect(hit!.bucketKey, 'summer_general');
      expect(hit.displayLabel, 'SUMMER GENERAL');
    });

    test('SUMMER TOYS still → summer_toys', () {
      final hit = resolve('SUMMER TOYS');
      expect(hit, isNotNull);
      expect(hit!.bucketKey, 'summer_toys');
      expect(hit.displayLabel, 'SUMMER TOYS');
    });

    test('General and Toys remain separate buckets', () {
      final general = resolve('SPRING/SUMMER - GENERAL')!;
      final toys = resolve('SPRING/SUMMER - TOYS')!;
      expect(general.bucketKey, isNot(equals(toys.bucketKey)));
      expect(general.bucketKey, 'summer_general');
      expect(toys.bucketKey, 'summer_toys');
    });

    test('legacy and live General share the same bucket', () {
      expect(
        resolve('SUMMER GENERAL')!.bucketKey,
        resolve('SPRING/SUMMER - GENERAL')!.bucketKey,
      );
    });

    test('legacy and live Toys share the same bucket', () {
      expect(
        resolve('SUMMER TOYS')!.bucketKey,
        resolve('SPRING/SUMMER - TOYS')!.bucketKey,
      );
    });
  });

  group('Unchanged seasonal / everyday routing', () {
    test('HALLOWEEN → halloween', () {
      final hit = resolve('HALLOWEEN');
      expect(hit, isNotNull);
      expect(hit!.bucketKey, 'halloween');
    });

    test('HARVEST → harvest', () {
      final hit = resolve('HARVEST');
      expect(hit, isNotNull);
      expect(hit!.bucketKey, 'harvest');
    });

    test("MOTHER'S DAY → mothers_day", () {
      final hit = resolve("MOTHER'S DAY");
      expect(hit, isNotNull);
      expect(hit!.bucketKey, 'mothers_day');
    });

    test('EVERYDAY → every_day', () {
      final hit = resolve('EVERYDAY');
      expect(hit, isNotNull);
      expect(hit!.bucketKey, 'every_day');
    });
  });

  group('ECatalog Seasonal membership', () {
    test('includes live Summer Product Types', () {
      expect(isEcatalogSeasonalProductType('SPRING/SUMMER - GENERAL'), isTrue);
      expect(isEcatalogSeasonalProductType('SPRING/SUMMER - TOYS'), isTrue);
    });

    test('includes legacy Summer Product Types', () {
      expect(isEcatalogSeasonalProductType('SUMMER GENERAL'), isTrue);
      expect(isEcatalogSeasonalProductType('SUMMER TOYS'), isTrue);
    });

    test('includes other seasonal types and excludes Everyday', () {
      expect(isEcatalogSeasonalProductType('HALLOWEEN'), isTrue);
      expect(isEcatalogSeasonalProductType('HARVEST'), isTrue);
      expect(isEcatalogSeasonalProductType("MOTHER'S DAY"), isTrue);
      expect(isEcatalogSeasonalProductType('EVERYDAY'), isFalse);
    });
  });
}

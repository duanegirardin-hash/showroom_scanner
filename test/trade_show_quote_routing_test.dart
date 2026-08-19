import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/active_quote_continuation.dart';
import 'package:showroom_scanner/main.dart' show SavedQuoteInfo;
import 'package:showroom_scanner/quote_bucket_routing.dart';
import 'package:showroom_scanner/quote_routing_gate.dart';
import 'package:showroom_scanner/trade_show_quote_routing.dart';

import 'routing_harness.dart';

/// Canonical 64-item Glassware approved list (must match assets JSON).
const kApprovedGlasswareItemNumbers = <String>[
  '70209',
  '70478',
  '70479',
  '70480',
  '70481',
  '70735',
  '70736',
  '70737',
  '70738',
  '70739',
  '70740',
  '70741',
  '70742',
  '70773',
  '70774',
  '70775',
  '70776',
  '70777',
  '70778',
  '70779',
  '70984',
  '70985',
  '70986',
  '70987',
  '80171',
  '80172',
  '80173',
  '80174',
  '80495',
  '80496',
  '80630',
  '80631',
  '80632',
  '80633',
  '80634',
  '80774',
  '80775',
  '80792',
  '80793',
  '80794',
  '80795',
  '80797',
  '80798',
  '80799',
  '80800',
  '80802',
  '80826',
  '80827',
  '80828',
  '80829',
  '80830',
  '80831',
  '80884',
  '80885',
  '80889',
  '80890',
  '80891',
  '80892',
  '80893',
  '80894',
  '80895',
  '80896',
  '80897',
  '80898',
];

const kGlasswareAdditionsVs57 = <String>[
  '70985',
  '80174',
  '80631',
  '80634',
  '80826',
  '80892',
  '80897',
];

/// Canonical 40-item Furniture approved list from Furniture.xlsx.
const kApprovedFurnitureItemNumbers = <String>[
  '91815',
  '85160',
  '85164',
  '85101',
  '85176',
  '85102',
  '85140',
  '85005',
  '85184',
  '85204',
  '85136',
  '85112',
  '85206',
  '85177',
  '85207',
  '85108',
  '85131',
  '85133',
  '85134',
  '85132',
  '91811',
  '91812',
  '91813',
  '91814',
  '91808',
  '91809',
  '85105',
  '91802',
  '91803',
  '91804',
  '91805',
  '91806',
  '91807',
  '85109',
  '91817',
  '91818',
  '85019',
  '85017',
  '85018',
  '85020',
];

TradeShowQuoteRoutingConfig loadBundledTradeShowConfig() {
  final raw =
      File('assets/data/trade_show_quote_routing.json').readAsStringSync();
  return parseTradeShowQuoteRoutingConfig(
    Map<String, dynamic>.from(jsonDecode(raw) as Map),
  );
}

TradeShowQuoteRoutingConfig withTradeShowEnabled(
  TradeShowQuoteRoutingConfig config, {
  required bool enabled,
}) {
  return TradeShowQuoteRoutingConfig(
    enabled: enabled,
    glasswareItemNumbers: config.glasswareItemNumbers,
    furnitureItemNumbers: config.furnitureItemNumbers,
    furnitureCategories: config.furnitureCategories,
    furnitureSubCategory: config.furnitureSubCategory,
    incenseSubCategory: config.incenseSubCategory,
    glassware: config.glassware,
    furniture: config.furniture,
    incense: config.incense,
  );
}

TradeShowRouteDecision route(
  TradeShowQuoteRoutingConfig config, {
  required String item,
  String productType = 'EVERYDAY',
  String category = '',
  String subCategory = '',
}) {
  return resolveTradeShowQuoteRoute(
    config: config,
    itemNumber: item,
    productType: productType,
    category: category,
    subCategory: subCategory,
  );
}

String resolveFullBucketKey({
  required TradeShowQuoteRoutingConfig tradeShow,
  required Map<String, ProductTypeBucketMapping> byNorm,
  required String item,
  required String productType,
  String category = '',
  String subCategory = '',
}) {
  final special = resolveTradeShowQuoteRoute(
    config: tradeShow,
    itemNumber: item,
    productType: productType,
    category: category,
    subCategory: subCategory,
  );
  if (special.bucket != null) return special.bucket!.bucketKey;

  final mapped = lookupProductTypeBucketMapping(
    productType: productType,
    category: category,
    byNormalizedRawType: byNorm,
  );
  return mapped?.bucketKey ?? 'every_day';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TradeShowQuoteRoutingConfig bundled;
  late TradeShowQuoteRoutingConfig config;
  late Map<String, ProductTypeBucketMapping> byNorm;

  setUpAll(() async {
    bundled = loadBundledTradeShowConfig();
    config = withTradeShowEnabled(bundled, enabled: true);
    final bucketRaw = await rootBundle.loadString(
      'assets/data/product_type_buckets.json',
    );
    byNorm = parseProductTypeBucketMappings(
      Map<String, dynamic>.from(jsonDecode(bucketRaw) as Map),
    );
  });

  group('post-show: Glassware / Furniture / Incense use Product Type', () {
    test('bundled config is disabled; old bucket labels remain defined', () {
      expect(bundled.enabled, isFalse);
      expect(bundled.glassware.bucketKey, 'glassware');
      expect(bundled.furniture.bucketKey, 'furniture');
      expect(bundled.incense.bucketKey, 'incense');
      expect(bundled.glassware.displayLabel, 'GLASSWARE');
      expect(bundled.furniture.displayLabel, 'FURNITURE');
      expect(bundled.incense.displayLabel, 'INCENSE');
    });

    test('Glassware EVERYDAY routes to EVERYDAY', () {
      expect(route(bundled, item: '70209').rule, TradeShowRouteRule.none);
      expect(
        resolveFullBucketKey(
          tradeShow: bundled,
          byNorm: byNorm,
          item: '70209',
          productType: 'EVERYDAY',
        ),
        'every_day',
      );
    });

    test('Furniture EVERYDAY routes to EVERYDAY', () {
      expect(
        route(
          bundled,
          item: '91815',
          category: 'Decor & Giftware',
          subCategory: 'Furniture & Shelving',
        ).rule,
        TradeShowRouteRule.none,
      );
      expect(
        resolveFullBucketKey(
          tradeShow: bundled,
          byNorm: byNorm,
          item: '91815',
          productType: 'EVERYDAY',
          category: 'Decor & Giftware',
          subCategory: 'Furniture & Shelving',
        ),
        'every_day',
      );
    });

    test('Incense EVERYDAY routes to EVERYDAY', () {
      expect(
        route(bundled, item: 'INC-1', subCategory: 'Incense').rule,
        TradeShowRouteRule.none,
      );
      expect(
        resolveFullBucketKey(
          tradeShow: bundled,
          byNorm: byNorm,
          item: 'INC-1',
          productType: 'EVERYDAY',
          subCategory: 'Incense',
        ),
        'every_day',
      );
    });

    test('Everyday + Glassware + Furniture + Incense share EVERYDAY', () {
      const items = <({String item, String type, String cat, String sub})>[
        (item: 'REG-1', type: 'EVERYDAY', cat: 'Kitchenware', sub: 'Gadgets'),
        (item: '70209', type: 'EVERYDAY', cat: 'Glassware', sub: 'Drinkware'),
        (
          item: '91815',
          type: 'EVERYDAY',
          cat: 'Decor & Giftware',
          sub: 'Furniture & Shelving',
        ),
        (item: 'INC-1', type: 'EVERYDAY', cat: 'Candles & Incense', sub: 'Incense'),
      ];
      final keys = [
        for (final i in items)
          resolveFullBucketKey(
            tradeShow: bundled,
            byNorm: byNorm,
            item: i.item,
            productType: i.type,
            category: i.cat,
            subCategory: i.sub,
          ),
      ];
      expect(keys, everyElement('every_day'));
      expect(keys.toSet(), {'every_day'});
    });

    test('sub-categories no longer create special quote buckets', () {
      for (final id in kApprovedGlasswareItemNumbers) {
        expect(route(bundled, item: id).bucket, isNull, reason: id);
      }
      for (final id in kApprovedFurnitureItemNumbers) {
        expect(route(bundled, item: id).bucket, isNull, reason: id);
      }
      expect(route(bundled, item: 'X', subCategory: 'Incense').bucket, isNull);
    });

    test('non-EVERYDAY Product Types still follow Product Type', () {
      expect(
        resolveFullBucketKey(
          tradeShow: bundled,
          byNorm: byNorm,
          item: '70209',
          productType: 'SPRING/SUMMER - GENERAL',
        ),
        'summer_general',
      );
      expect(
        resolveFullBucketKey(
          tradeShow: bundled,
          byNorm: byNorm,
          item: '91815',
          productType: 'CHRISTMAS',
        ),
        'christmas',
      );
    });

    test('existing special quotes remain loadable by bucket key', () {
      expect(canonicalQuoteBucketKey('glassware'), 'glassware');
      expect(canonicalQuoteBucketKey('furniture'), 'furniture');
      expect(canonicalQuoteBucketKey('incense'), 'incense');
      for (final entry in [
        ('glassware', 'GLASSWARE'),
        ('furniture', 'FURNITURE'),
        ('incense', 'INCENSE'),
      ]) {
        final info = SavedQuoteInfo.fromJson({
          'id': 'quote_${entry.$1}',
          'name': '${entry.$2} QUOTE',
          'customerName': 'CUSTOMER ABC',
          'customerId': '302021',
          'quoteBucketKey': entry.$1,
          'quoteBucketLabel': entry.$2,
          'updatedAt': '2026-08-01T12:00:00.000',
        });
        expect(info.quoteBucketKey, entry.$1);
        expect(info.quoteBucketLabel, entry.$2);
        expect(canonicalQuoteBucketKey(info.quoteBucketKey), entry.$1);
      }
    });
  });

  group('trade-show config', () {
    test('bundled lists still include 64 glassware and 40 furniture IDs', () {
      expect(bundled.enabled, isFalse);
      expect(config.glasswareItemNumbers, hasLength(64));
      expect(
        config.glasswareItemNumbers,
        equals(
          kApprovedGlasswareItemNumbers.map((e) => e.toUpperCase()).toSet(),
        ),
      );
      expect(config.furnitureItemNumbers, hasLength(40));
      expect(
        config.furnitureItemNumbers,
        equals(
          kApprovedFurnitureItemNumbers.map((e) => e.toUpperCase()).toSet(),
        ),
      );
      expect(config.glassware.displayLabel, 'GLASSWARE');
      expect(config.furniture.displayLabel, 'FURNITURE');
      expect(config.incense.displayLabel, 'INCENSE');
      for (final id in kGlasswareAdditionsVs57) {
        expect(config.glasswareItemNumbers.contains(id), isTrue, reason: id);
      }
    });

    test('disabled config never overrides', () {
      final off = TradeShowQuoteRoutingConfig(
        enabled: false,
        glasswareItemNumbers: config.glasswareItemNumbers,
        furnitureItemNumbers: config.furnitureItemNumbers,
        furnitureCategories: config.furnitureCategories,
        furnitureSubCategory: config.furnitureSubCategory,
        incenseSubCategory: config.incenseSubCategory,
        glassware: config.glassware,
        furniture: config.furniture,
        incense: config.incense,
      );
      expect(route(off, item: '70209').rule, TradeShowRouteRule.none);
      expect(route(off, item: '91815').rule, TradeShowRouteRule.none);
      expect(
        route(
          off,
          item: 'X',
          category: 'Decor & Giftware',
          subCategory: 'Furniture & Shelving',
        ).rule,
        TradeShowRouteRule.none,
      );
      expect(
        route(off, item: 'Y', subCategory: 'Incense').rule,
        TradeShowRouteRule.none,
      );
    });
  });

  group('Glassware item-list routing', () {
    test('approved items and all 64 IDs → glassware', () {
      expect(route(config, item: '70209').rule, TradeShowRouteRule.glassware);
      expect(route(config, item: '80898').rule, TradeShowRouteRule.glassware);
      expect(route(config, item: '70985').rule, TradeShowRouteRule.glassware);
      for (final id in kApprovedGlasswareItemNumbers) {
        expect(
          route(config, item: id).bucket!.bucketKey,
          'glassware',
          reason: id,
        );
      }
    });

    test('non-listed similar item does not route to glassware', () {
      expect(route(config, item: '70208').rule, TradeShowRouteRule.none);
      expect(route(config, item: '80796').rule, TradeShowRouteRule.none);
    });
  });

  group('Furniture explicit + broad routing', () {
    test('all 40 explicit Furniture IDs → furniture', () {
      for (final id in kApprovedFurnitureItemNumbers) {
        final d = route(config, item: id);
        expect(d.isFurniture, isTrue, reason: id);
        expect(d.bucket!.bucketKey, 'furniture', reason: id);
        expect(d.rule, TradeShowRouteRule.furnitureExplicit, reason: id);
      }
    });

    test('explicit Furniture works for approved non-EVERYDAY item', () {
      final d = route(
        config,
        item: '85164',
        productType: 'FALL/WINTER ESSENTIALS',
        category: 'Decor & Giftware',
        subCategory: 'Furniture & Shelving',
      );
      expect(d.rule, TradeShowRouteRule.furnitureExplicit);
      expect(d.bucket!.bucketKey, 'furniture');
      expect(
        resolveFullBucketKey(
          tradeShow: config,
          byNorm: byNorm,
          item: '85164',
          productType: 'FALL/WINTER ESSENTIALS',
          category: 'Decor & Giftware',
          subCategory: 'Furniture & Shelving',
        ),
        'furniture',
      );
    });

    test('explicit Furniture SUMMER GENERAL item still → furniture', () {
      final d = route(
        config,
        item: '91818',
        productType: 'SUMMER GENERAL',
        category: 'Everyday Household',
        subCategory: 'Floor Mats',
      );
      expect(d.rule, TradeShowRouteRule.furnitureExplicit);
    });

    test('broad Decor + Furniture & Shelving Everyday → furniture', () {
      final d = route(
        config,
        item: 'BROAD-1',
        category: 'Decor & Giftware',
        subCategory: 'Furniture & Shelving',
      );
      expect(d.rule, TradeShowRouteRule.furnitureBroad);
    });

    test('Home Décor alias + Furniture & Shelving → furniture', () {
      expect(
        route(
          config,
          item: 'BROAD-2',
          category: 'Home Décor & Giftware',
          subCategory: 'Furniture & Shelving',
        ).rule,
        TradeShowRouteRule.furnitureBroad,
      );
    });

    test('broad Furniture rule remains EVERYDAY-only', () {
      final d = route(
        config,
        item: 'UNLISTED-SEASONAL',
        productType: 'CHRISTMAS',
        category: 'Decor & Giftware',
        subCategory: 'Furniture & Shelving',
      );
      expect(d.rule, TradeShowRouteRule.none);
      expect(d.skippedNonEveryday, isTrue);
      expect(
        resolveFullBucketKey(
          tradeShow: config,
          byNorm: byNorm,
          item: 'UNLISTED-SEASONAL',
          productType: 'CHRISTMAS',
          category: 'Decor & Giftware',
          subCategory: 'Furniture & Shelving',
        ),
        'christmas',
      );
    });

    test('wrong Category or Sub-Category does not trigger broad rule', () {
      expect(
        route(
          config,
          item: 'BAD-CAT',
          category: 'Kitchenware',
          subCategory: 'Furniture & Shelving',
        ).rule,
        TradeShowRouteRule.none,
      );
      expect(
        route(
          config,
          item: 'BAD-SUB',
          category: 'Decor & Giftware',
          subCategory: 'Frames',
        ).rule,
        TradeShowRouteRule.none,
      );
    });
  });

  group('Incense and normal Product Type fallback', () {
    test('Incense → incense', () {
      expect(
        route(config, item: 'INC-1', subCategory: 'Incense').rule,
        TradeShowRouteRule.incense,
      );
    });

    test('ordinary Everyday / Christmas / Summer Toys / Giftcraft unchanged', () {
      expect(
        resolveFullBucketKey(
          tradeShow: config,
          byNorm: byNorm,
          item: '99999',
          productType: 'EVERYDAY',
          category: 'Kitchenware',
          subCategory: 'Utensils',
        ),
        'every_day',
      );
      expect(
        resolveFullBucketKey(
          tradeShow: config,
          byNorm: byNorm,
          item: 'XMAS1',
          productType: 'CHRISTMAS',
        ),
        'christmas',
      );
      expect(
        resolveFullBucketKey(
          tradeShow: config,
          byNorm: byNorm,
          item: 'TOY1',
          productType: 'SUMMER TOYS',
        ),
        'summer_toys',
      );
      expect(
        resolveFullBucketKey(
          tradeShow: config,
          byNorm: byNorm,
          item: 'GC1',
          productType: 'GIFTCRAFT',
        ),
        'giftcraft',
      );
    });

    test('Glassware wins over Furniture explicit if overlap', () {
      // Synthetic: treat a glassware ID as also furniture-listed via custom config.
      final overlapConfig = TradeShowQuoteRoutingConfig(
        enabled: true,
        glasswareItemNumbers: {'70209'},
        furnitureItemNumbers: {'70209'},
        furnitureCategories: config.furnitureCategories,
        furnitureSubCategory: config.furnitureSubCategory,
        incenseSubCategory: config.incenseSubCategory,
        glassware: config.glassware,
        furniture: config.furniture,
        incense: config.incense,
      );
      expect(
        route(overlapConfig, item: '70209').rule,
        TradeShowRouteRule.glassware,
      );
    });

    test('canonical keys for new buckets collapse cleanly', () {
      expect(canonicalQuoteBucketKey('glassware'), 'glassware');
      expect(canonicalQuoteBucketKey('furniture'), 'furniture');
      expect(canonicalQuoteBucketKey('incense'), 'incense');
    });
  });

  group('Product Type / Category / Sub-Category unchanged', () {
    test('routing does not mutate product fields', () {
      var productType = 'FALL/WINTER ESSENTIALS';
      var category = 'Decor & Giftware';
      var subCategory = 'Furniture & Shelving';
      final before = (productType, category, subCategory);
      final d = route(
        config,
        item: '85164',
        productType: productType,
        category: category,
        subCategory: subCategory,
      );
      expect(d.isFurniture, isTrue);
      expect((productType, category, subCategory), before);
    });
  });

  group('bundled catalog dry validation', () {
    late List<Map<String, String>> catalog;
    late Map<String, Map<String, String>> byItem;

    setUpAll(() {
      final raw = File('assets/data/products.csv')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      final rows = const CsvToListConverter(
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(raw);
      expect(rows, isNotEmpty);
      final headers = rows.first.map((e) => e.toString().trim()).toList();
      int col(String name) => headers.indexOf(name);
      final iItem = col('Item Number');
      final iDesc = col('Description');
      final iType = col('Product Type');
      final iCat = col('Category');
      final iSub = col('Sub-Category');
      catalog = [
        for (final row in rows.skip(1))
          if (row.length > iSub)
            {
              'item': row[iItem].toString().trim().toUpperCase(),
              'description': row[iDesc].toString().trim(),
              'type': row[iType].toString().trim(),
              'category': row[iCat].toString().trim(),
              'subCategory': row[iSub].toString().trim(),
            },
      ];
      byItem = {
        for (final r in catalog)
          if (r['item']!.isNotEmpty) r['item']!: r,
      };
      expect(catalog, isNotEmpty);
    });

    test('Glassware dry validation', () {
      final missing = <String>[];
      final unexpectedTypes = <String, int>{};
      for (final id in kApprovedGlasswareItemNumbers) {
        final row = byItem[id];
        if (row == null) {
          missing.add(id);
          continue;
        }
        unexpectedTypes[row['type']!] =
            (unexpectedTypes[row['type']!] ?? 0) + 1;
        expect(
          route(
            config,
            item: id,
            productType: row['type']!,
            category: row['category']!,
            subCategory: row['subCategory']!,
          ).rule,
          TradeShowRouteRule.glassware,
        );
      }
      expect(kApprovedGlasswareItemNumbers.toSet(), hasLength(64));
      expect(missing, isEmpty);
      expect(unexpectedTypes.keys, ['EVERYDAY']);
      // ignore: avoid_print
      print(
        'DRY Glassware: configured=64 found=${64 - missing.length} '
        'missing=$missing types=$unexpectedTypes → glassware',
      );
    });

    test('Furniture dry validation + explicit non-EVERYDAY report', () {
      final explicitFound = <Map<String, String>>[];
      final explicitMissing = <String>[];
      for (final id in kApprovedFurnitureItemNumbers) {
        final row = byItem[id];
        if (row == null) {
          explicitMissing.add(id);
          continue;
        }
        explicitFound.add(row);
        expect(
          route(
            config,
            item: id,
            productType: row['type']!,
            category: row['category']!,
            subCategory: row['subCategory']!,
          ).isFurniture,
          isTrue,
          reason: id,
        );
      }
      expect(kApprovedFurnitureItemNumbers.toSet(), hasLength(40));
      expect(explicitMissing, isEmpty);

      // Category+Sub match without the explicit item list (broad rule only).
      final broadOnlyConfig = TradeShowQuoteRoutingConfig(
        enabled: true,
        glasswareItemNumbers: const {},
        furnitureItemNumbers: const {},
        furnitureCategories: config.furnitureCategories,
        furnitureSubCategory: config.furnitureSubCategory,
        incenseSubCategory: config.incenseSubCategory,
        glassware: config.glassware,
        furniture: config.furniture,
        incense: config.incense,
      );
      bool matchesBroadFields(Map<String, String> r) {
        return route(
              broadOnlyConfig,
              item: r['item']!,
              productType: 'EVERYDAY',
              category: r['category']!,
              subCategory: r['subCategory']!,
            ).rule ==
            TradeShowRouteRule.furnitureBroad;
      }

      final already = explicitFound.where(matchesBroadFields).length;
      final onlyExplicit =
          explicitFound.where((r) => !matchesBroadFields(r)).length;
      final nonEveryday = explicitFound
          .where((r) => r['type']!.toUpperCase() != 'EVERYDAY')
          .toList();

      final broadEveryday = catalog.where((r) {
        final d = route(
          config,
          item: r['item']!,
          productType: r['type']!,
          category: r['category']!,
          subCategory: r['subCategory']!,
        );
        return d.rule == TradeShowRouteRule.furnitureBroad;
      }).length;

      final furnitureRouted = <String>{};
      for (final r in catalog) {
        final d = route(
          config,
          item: r['item']!,
          productType: r['type']!,
          category: r['category']!,
          subCategory: r['subCategory']!,
        );
        if (d.isFurniture) furnitureRouted.add(r['item']!);
      }

      expect(already + onlyExplicit, 40);
      expect(furnitureRouted, hasLength(138));

      // ignore: avoid_print
      print(
        'DRY Furniture: explicit=40 found=${explicitFound.length} '
        'missing=$explicitMissing alreadyBroad=$already '
        'onlyExplicit=$onlyExplicit broadEveryday=$broadEveryday '
        'union=${furnitureRouted.length}',
      );
      for (final r in nonEveryday) {
        // ignore: avoid_print
        print(
          'EXPLICIT NON-EVERYDAY FURNITURE: ${r['item']} | ${r['description']} | '
          '${r['type']} | ${r['category']} | ${r['subCategory']} | '
          'Reason=EXPLICIT USER-APPROVED FURNITURE OVERRIDE',
        );
      }
      expect(nonEveryday, hasLength(2));
      expect(
        nonEveryday.map((r) => r['item']).toSet(),
        {'85164', '91818'},
      );
    });

    test('Incense dry validation', () {
      final incense = catalog
          .where((r) => tradeShowFieldsEqual(r['subCategory']!, 'Incense'))
          .toList();
      final typeCounts = <String, int>{};
      for (final r in incense) {
        typeCounts[r['type']!] = (typeCounts[r['type']!] ?? 0) + 1;
        expect(
          route(
            config,
            item: r['item']!,
            productType: r['type']!,
            category: r['category']!,
            subCategory: r['subCategory']!,
          ).rule,
          TradeShowRouteRule.incense,
        );
      }
      expect(incense, hasLength(71));
      // ignore: avoid_print
      print(
        'DRY Incense: count=${incense.length} types=$typeCounts → incense',
      );
    });

    test('overlaps and total affected', () {
      final glass = <String>{};
      final furn = <String>{};
      final inc = <String>{};
      for (final r in catalog) {
        final d = route(
          config,
          item: r['item']!,
          productType: r['type']!,
          category: r['category']!,
          subCategory: r['subCategory']!,
        );
        if (d.rule == TradeShowRouteRule.glassware) glass.add(r['item']!);
        if (d.isFurniture) furn.add(r['item']!);
        if (d.rule == TradeShowRouteRule.incense) inc.add(r['item']!);
      }
      expect(glass.intersection(furn), isEmpty);
      expect(glass.intersection(inc), isEmpty);
      expect(furn.intersection(inc), isEmpty);
      final total = glass.length + furn.length + inc.length;
      // ignore: avoid_print
      print(
        'DRY Overall: glass=${glass.length} furniture=${furn.length} '
        'incense=${inc.length} overlaps=none affected=$total',
      );
      expect(glass, hasLength(64));
      expect(furn, hasLength(138));
      expect(inc, hasLength(71));
      expect(total, 273);
    });
  });

  group('duplicate special-quote prevention (gated harness)', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('trade_show_quote_');
    });

    test('Everyday + Glassware + Furniture + Incense share one EVERYDAY quote',
        () async {
      final app = RoutingHarness(dir: dir, gate: QuoteRoutingGate());
      await app.scan('REG-1', 'every_day');
      await app.saveQuote();
      final id = app.currentQuoteId!;
      await app.scan('70209', 'every_day');
      await app.scan('91815', 'every_day');
      await app.scan('INC-1', 'every_day');
      expect(app.currentQuoteId, id);
      await app.saveQuote();
      final byBucket = await app.activeQuoteIdsByBucket();
      expect(byBucket['every_day']!.toSet(), {id});
      expect(byBucket['glassware'], isNull);
      expect(byBucket['furniture'], isNull);
      expect(byBucket['incense'], isNull);
    });


    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('repeated Glassware scans → one glassware quote', () async {
      final app = RoutingHarness(dir: dir, gate: QuoteRoutingGate());
      await app.scan('G-0', 'glassware');
      await app.saveQuote();
      final id = app.currentQuoteId!;
      for (var i = 1; i < 12; i++) {
        await app.scan('G-$i', 'glassware');
        expect(app.currentQuoteId, id);
      }
      await app.saveQuote();
      expect(
        (await app.activeQuoteIdsByBucket())['glassware']!.toSet(),
        hasLength(1),
      );
    });

    test('repeated Furniture scans → one furniture quote', () async {
      final app = RoutingHarness(dir: dir, gate: QuoteRoutingGate());
      await app.scan('F-0', 'furniture');
      await app.saveQuote();
      final id = app.currentQuoteId!;
      for (var i = 1; i < 10; i++) {
        await app.scan('F-$i', 'furniture');
        expect(app.currentQuoteId, id);
      }
      await app.saveQuote();
      expect(
        (await app.activeQuoteIdsByBucket())['furniture']!.toSet(),
        hasLength(1),
      );
    });

    test('repeated Incense scans → one incense quote', () async {
      final app = RoutingHarness(dir: dir, gate: QuoteRoutingGate());
      await app.scan('I-0', 'incense');
      await app.saveQuote();
      final id = app.currentQuoteId!;
      for (var i = 1; i < 10; i++) {
        await app.scan('I-$i', 'incense');
        expect(app.currentQuoteId, id);
      }
      await app.saveQuote();
      expect(
        (await app.activeQuoteIdsByBucket())['incense']!.toSet(),
        hasLength(1),
      );
    });

    test('mixed special routing does not create duplicate quotes', () async {
      final app = RoutingHarness(dir: dir, gate: QuoteRoutingGate());
      final buckets = [
        'glassware',
        'furniture',
        'incense',
        'every_day',
        'christmas',
      ];
      final firstId = <String, String>{};
      for (var i = 0; i < 80; i++) {
        final b = buckets[i % buckets.length];
        await app.scan('$b-$i', b);
        if (!firstId.containsKey(b)) {
          await app.saveQuote();
          firstId[b] = app.currentQuoteId!;
        } else {
          expect(app.currentQuoteId, firstId[b]);
        }
      }
      for (final b in buckets) {
        await app.ensureRoutingForProduct(b);
        if (app.orderLines.isNotEmpty) await app.saveQuote();
      }
      final byBucket = await app.activeQuoteIdsByBucket();
      for (final b in buckets) {
        expect(byBucket[b]!.toSet(), hasLength(1), reason: b);
      }
    });

    test('app restart reuses special quote IDs', () async {
      final app = RoutingHarness(dir: dir, gate: QuoteRoutingGate());
      await app.scan('G-1', 'glassware');
      await app.saveQuote();
      final glassId = app.currentQuoteId!;
      await app.scan('F-1', 'furniture');
      await app.saveQuote();
      final furnId = app.currentQuoteId!;
      await app.scan('I-1', 'incense');
      await app.saveQuote();
      final incId = app.currentQuoteId!;

      app.restart();
      await app.scan('G-2', 'glassware');
      expect(app.currentQuoteId, glassId);
      await app.scan('F-2', 'furniture');
      expect(app.currentQuoteId, furnId);
      await app.scan('I-2', 'incense');
      expect(app.currentQuoteId, incId);
    });

    test('one scan creates one line', () async {
      final app = RoutingHarness(dir: dir, gate: QuoteRoutingGate());
      await app.scan('85164', 'furniture');
      expect(app.orderLines, hasLength(1));
      await app.scan('85164', 'furniture');
      expect(app.orderLines, hasLength(1));
      expect(app.qtyOf('85164'), 2);
    });
  });
}

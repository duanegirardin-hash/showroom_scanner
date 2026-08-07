import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/active_quote_continuation.dart';
import 'package:showroom_scanner/quote_bucket_routing.dart';
import 'package:showroom_scanner/quote_routing_gate.dart';

/// Every raw Product Type spelling that must collapse onto one canonical bucket,
/// including invisible whitespace and Unicode punctuation variants.
///
/// Guards the "two quotes that both display Summer Toys" class of defect: if any
/// variant produced a different bucket key, routing would split into two quotes
/// for one customer and Product Type.
void main() {
  /// Invisible-whitespace / Unicode-punctuation mutations of [base].
  Map<String, String> variantsOf(String base) => {
    'exact': base,
    'lowercase': base.toLowerCase(),
    'uppercase': base.toUpperCase(),
    'leadingSpace': '   $base',
    'trailingSpace': '$base   ',
    'bothSpaces': '  $base  ',
    'leadingTab': '\t$base',
    'trailingTab': '$base\t',
    'leadingNbsp': '\u00A0$base',
    'trailingNbsp': '$base\u00A0',
    'internalNbsp': base.replaceAll(' ', '\u00A0'),
    'internalTab': base.replaceAll(' ', '\t'),
    'doubleSpaces': base.replaceAll(' ', '  '),
    'tripleSpaces': base.replaceAll(' ', '   '),
    'crlfWrapped': '\r\n$base\r\n',
    'crInternal': base.replaceAll(' ', '\r'),
    'lfInternal': base.replaceAll(' ', '\n'),
    'enDashForSpace': base.replaceAll(' ', '\u2013'),
    'emDashForSpace': base.replaceAll(' ', '\u2014'),
    'hyphenForSpace': base.replaceAll(' ', '-'),
    'slashForSpace': base.replaceAll(' ', '/'),
    'spacedHyphen': base.replaceAll(' ', ' - '),
    'spacedSlash': base.replaceAll(' ', ' / '),
    'zeroWidthLeading': '\u200B$base',
    'zeroWidthTrailing': '$base\u200B',
    'bomLeading': '\uFEFF$base',
    'mixedNoise': ' \u00A0\t$base\u200B \r\n',
  };

  /// Bucket keys the app routes to, as configured in product_type_buckets.json.
  const canonicalBuckets = <String>[
    'every_day',
    'giftcraft',
    'christmas',
    'harvest',
    'halloween',
    'summer_general',
    'summer_toys',
    'valentines_day',
    'easter',
    'fall_winter',
    'pride',
    'graduation',
    'calendar',
    'canada_day',
    'chinese_new_year',
    'diwali',
    'fathers_day',
    'hanukkah',
    'mothers_day',
    'new_years',
    'st_patricks_day',
  ];

  group('canonicalQuoteBucketKey is whitespace and Unicode stable', () {
    for (final bucket in canonicalBuckets) {
      test('$bucket collapses every variant to one key', () {
        final expected = canonicalQuoteBucketKey(bucket);
        variantsOf(bucket.replaceAll('_', ' ')).forEach((label, variant) {
          expect(
            canonicalQuoteBucketKey(variant),
            expected,
            reason: '$bucket / $label -> "${_cp(variant)}"',
          );
        });
      });
    }

    test('every canonical bucket is a fixed point', () {
      for (final bucket in canonicalBuckets) {
        expect(canonicalQuoteBucketKey(bucket), bucket);
        expect(
          canonicalQuoteBucketKey(canonicalQuoteBucketKey(bucket)),
          bucket,
          reason: 'normalization must be idempotent',
        );
      }
    });

    test('stray leading/trailing separators do not create a new bucket', () {
      for (final raw in [
        '_summer_toys_',
        '__summer_toys__',
        ' - summer toys - ',
        '/summer toys/',
        '\u2013summer toys\u2014',
        '\u200Bsummer_toys\u200B',
      ]) {
        expect(
          canonicalQuoteBucketKey(raw),
          'summer_toys',
          reason: 'raw "${_cp(raw)}" must not split the Summer Toys bucket',
        );
      }
    });

    test('blank-ish values fall back to the default Everyday bucket', () {
      for (final raw in ['', '   ', '\t', '\u00A0', '\r\n', '\u200B']) {
        expect(canonicalQuoteBucketKey(raw), 'every_day');
      }
    });

    test('distinct buckets never collide', () {
      final keys = canonicalBuckets.map(canonicalQuoteBucketKey).toSet();
      expect(keys, hasLength(canonicalBuckets.length));
    });
  });

  group('normalizeBucketLookupKey resolves every variant to one mapping', () {
    late Map<String, ProductTypeBucketMapping> mappings;

    setUpAll(() {
      mappings = parseProductTypeBucketMappings(
        Map<String, dynamic>.from(
          jsonDecode(
                File('assets/data/product_type_buckets.json').readAsStringSync(),
              )
              as Map,
        ),
      );
    });

    test('mapping table is non-empty and includes both Summer Toys aliases', () {
      expect(mappings, isNotEmpty);
      for (final alias in ['SUMMER TOYS', 'SPRING/SUMMER - TOYS']) {
        final hit = lookupProductTypeBucketMapping(
          productType: alias,
          category: '',
          byNormalizedRawType: mappings,
        );
        expect(hit, isNotNull, reason: '$alias must map');
        expect(hit!.bucketKey, 'summer_toys');
        expect(hit.displayLabel, 'SUMMER TOYS');
      }
    });

    test('all configured raw types survive whitespace/Unicode mutation', () {
      // Reverse the mapping to recover a representative raw label per key.
      for (final normalizedRaw in mappings.keys) {
        final expected = mappings[normalizedRaw]!.bucketKey;
        variantsOf(normalizedRaw).forEach((label, variant) {
          final hit = lookupProductTypeBucketMapping(
            productType: variant,
            category: '',
            byNormalizedRawType: mappings,
          );
          expect(
            hit?.bucketKey,
            expected,
            reason: '"$normalizedRaw" / $label -> "${_cp(variant)}"',
          );
        });
      }
    });

    test('every Summer Toys alias variant resolves to summer_toys', () {
      for (final alias in [
        'SUMMER TOYS',
        'summer toys',
        'Summer Toys',
        'SPRING/SUMMER - TOYS',
        'spring/summer - toys',
        'SPRING / SUMMER / TOYS',
        'SPRING\u00A0SUMMER\u00A0TOYS',
        'SPRING/SUMMER \u2013 TOYS',
        'SPRING/SUMMER \u2014 TOYS',
        '  SPRING/SUMMER  -  TOYS  ',
        '\tSUMMER TOYS\r\n',
      ]) {
        final hit = lookupProductTypeBucketMapping(
          productType: alias,
          category: '',
          byNormalizedRawType: mappings,
        );
        expect(
          hit?.bucketKey,
          'summer_toys',
          reason: 'alias "${_cp(alias)}" must reach summer_toys',
        );
        expect(
          canonicalQuoteBucketKey(hit!.bucketKey),
          'summer_toys',
          reason: 'canonical bucket must also be summer_toys',
        );
      }
    });

    test('en/em dash and NBSP behave exactly like hyphen and space', () {
      String n(String s) => normalizeBucketLookupKey(s);
      expect(n('SPRING/SUMMER - TOYS'), n('SPRING/SUMMER \u2013 TOYS'));
      expect(n('SPRING/SUMMER - TOYS'), n('SPRING/SUMMER \u2014 TOYS'));
      expect(n('SUMMER TOYS'), n('SUMMER\u00A0TOYS'));
      expect(n('SUMMER TOYS'), n('SUMMER\tTOYS'));
      expect(n('SUMMER TOYS'), n('SUMMER  TOYS'));
      expect(n('SUMMER TOYS'), n(' SUMMER TOYS '));
      expect(n('SUMMER TOYS'), n('summer toys'));
    });
  });

  group('routing gate key is whitespace and Unicode stable', () {
    test('all Summer Toys spellings produce one gate key', () {
      final expected = quoteRoutingGateKey(
        customerId: '302021',
        customerName: 'ABC',
        bucketKey: 'summer_toys',
      );
      for (final raw in [
        'summer_toys',
        'SUMMER TOYS',
        ' summer toys ',
        'summer  toys',
        'summer\u00A0toys',
        'summer\ttoys',
        'summer-toys',
        'summer\u2013toys',
        'summer\u2014toys',
        '_summer_toys_',
      ]) {
        expect(
          quoteRoutingGateKey(
            customerId: '302021',
            customerName: 'ABC',
            bucketKey: raw,
          ),
          expected,
          reason: 'gate key must not split on "${_cp(raw)}"',
        );
      }
    });

    test('customer id whitespace does not split the gate key', () {
      final expected = quoteRoutingGateKey(
        customerId: '302021',
        customerName: 'ABC',
        bucketKey: 'summer_toys',
      );
      for (final id in [' 302021', '302021 ', '  302021  ', '\t302021\r\n']) {
        expect(
          quoteRoutingGateKey(
            customerId: id,
            customerName: 'ABC',
            bucketKey: 'SUMMER TOYS',
          ),
          expected,
        );
      }
    });
  });

  group('catalog data has no invisible Product Type damage', () {
    Map<String, List<String>> rawTypes(String path) {
      final file = File(path);
      if (!file.existsSync()) return {};
      final rows = const CsvToListConverter(
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(file.readAsStringSync().replaceAll('\r\n', '\n'));
      if (rows.isEmpty) return {};
      final header = rows.first.map((c) => c.toString().trim()).toList();
      final typeIdx = header.indexOf('Product Type');
      final itemIdx = header.indexOf('Item Number');
      if (typeIdx < 0) return {};
      final out = <String, List<String>>{};
      for (final row in rows.skip(1)) {
        if (row.length <= typeIdx) continue;
        out
            .putIfAbsent(row[typeIdx].toString(), () => [])
            .add(row.length > itemIdx ? row[itemIdx].toString().trim() : '');
      }
      return out;
    }

    test('bundled products.csv Product Type column is clean', () {
      final byValue = rawTypes('assets/data/products.csv');
      expect(byValue, isNotEmpty);
      byValue.forEach((raw, items) {
        expect(
          raw,
          raw.trim(),
          reason: 'leading/trailing whitespace in "${_cp(raw)}" '
              '(e.g. item ${items.first})',
        );
        for (final bad in ['\u00A0', '\t', '\r', '\n', '\u2013', '\u2014', '\u200B', '\uFEFF']) {
          expect(
            raw.contains(bad),
            isFalse,
            reason: 'unexpected ${_cp(bad)} in "${_cp(raw)}" '
                '(e.g. item ${items.first})',
          );
        }
        expect(
          RegExp(r'  +').hasMatch(raw),
          isFalse,
          reason: 'repeated internal spaces in "${_cp(raw)}"',
        );
      });
    });

    test('every bundled Product Type maps to a configured bucket', () {
      final mappings = parseProductTypeBucketMappings(
        Map<String, dynamic>.from(
          jsonDecode(
                File('assets/data/product_type_buckets.json').readAsStringSync(),
              )
              as Map,
        ),
      );
      final unmapped = <String>[];
      rawTypes('assets/data/products.csv').forEach((raw, _) {
        if (raw.trim().isEmpty || raw.trim() == '0') return;
        final hit = lookupProductTypeBucketMapping(
          productType: raw,
          category: '',
          byNormalizedRawType: mappings,
        );
        if (hit == null) unmapped.add(raw);
      });
      expect(
        unmapped,
        isEmpty,
        reason: 'unmapped Product Types silently fall back to Everyday',
      );
    });

    test('bundled catalog has exactly one Summer Toys raw spelling', () {
      final mappings = parseProductTypeBucketMappings(
        Map<String, dynamic>.from(
          jsonDecode(
                File('assets/data/product_type_buckets.json').readAsStringSync(),
              )
              as Map,
        ),
      );
      final toySpellings = <String>{};
      rawTypes('assets/data/products.csv').forEach((raw, _) {
        final hit = lookupProductTypeBucketMapping(
          productType: raw,
          category: '',
          byNormalizedRawType: mappings,
        );
        if (hit?.bucketKey == 'summer_toys') toySpellings.add(raw);
      });
      expect(toySpellings, hasLength(1));
      // All spellings, however many, must share one canonical bucket.
      expect(
        toySpellings.map(canonicalQuoteBucketKey).toSet().length,
        lessThanOrEqualTo(1),
      );
    });
  });
}

String _cp(String raw) => raw.runes
    .map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}')
    .join(' ');

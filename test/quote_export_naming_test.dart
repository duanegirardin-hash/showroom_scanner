import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/quote_emun_csv.dart';

String _sanitizeExportSegment(String value) {
  var s = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  s = s
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '')
      .trim()
      .toUpperCase();
  return s.isEmpty ? 'QUOTE' : s;
}

String _exportBasenameType({
  required String quoteName,
  String? quoteBucketLabel,
  String? quoteBucketKey,
}) {
  final normalized = _sanitizeExportSegment(quoteName);
  final match = RegExp(r'^(.+)_(\d{4})_(\d{2})_(\d{2})_(\d{3})$').firstMatch(
    normalized,
  );
  final parsedType = match?.group(1) ?? normalized;
  final seq = match?.group(5) ?? '001';
  final resolved = resolveQuoteExportTypeCandidate(
    parsedQuoteType: parsedType,
    quoteBucketLabel: quoteBucketLabel,
    quoteBucketKey: quoteBucketKey,
  );
  final safeType = _sanitizeExportSegment(resolved);
  return '${safeType}_2026_08_28_$seq';
}

void main() {
  group('quoteExportTypeLooksBarcodeCorrupted', () {
    test('detects barcode-prefixed parsed types', () {
      expect(
        quoteExportTypeLooksBarcodeCorrupted('062823532588_GENERAL_QUOTE'),
        isTrue,
      );
      expect(quoteExportTypeLooksBarcodeCorrupted('062823532588'), isTrue);
    });

    test('does not flag legitimate seasonal quote types', () {
      expect(quoteExportTypeLooksBarcodeCorrupted('SUMMER_GENERAL_QUOTE'), isFalse);
      expect(quoteExportTypeLooksBarcodeCorrupted('SUMMER_TOYS_QUOTE'), isFalse);
      expect(quoteExportTypeLooksBarcodeCorrupted('EVERYDAY_QUOTE'), isFalse);
      expect(quoteExportTypeLooksBarcodeCorrupted('VALENTINE_S_DAY_QUOTE'), isFalse);
    });

    test('does not flag numbers elsewhere in the type', () {
      expect(quoteExportTypeLooksBarcodeCorrupted('CANADA_DAY_QUOTE'), isFalse);
      expect(quoteExportTypeLooksBarcodeCorrupted('TOYS_2024_QUOTE'), isFalse);
    });
  });

  group('resolveQuoteExportTypeCandidate', () {
    test('corrupted name falls back to quoteBucketLabel', () {
      expect(
        resolveQuoteExportTypeCandidate(
          parsedQuoteType: '062823532588_GENERAL_QUOTE',
          quoteBucketLabel: 'SUMMER GENERAL',
        ),
        'SUMMER GENERAL QUOTE',
      );
    });

    test('falls back to quoteBucketKey when label missing', () {
      expect(
        resolveQuoteExportTypeCandidate(
          parsedQuoteType: '062823532588_GENERAL_QUOTE',
          quoteBucketKey: 'summer_general',
        ),
        'SUMMER GENERAL QUOTE',
      );
    });

    test('good parsed type is unchanged', () {
      expect(
        resolveQuoteExportTypeCandidate(
          parsedQuoteType: 'SUMMER_GENERAL_QUOTE',
          quoteBucketLabel: 'SUMMER GENERAL',
        ),
        'SUMMER_GENERAL_QUOTE',
      );
      expect(
        resolveQuoteExportTypeCandidate(
          parsedQuoteType: 'SUMMER_TOYS_QUOTE',
          quoteBucketLabel: 'SUMMER TOYS',
        ),
        'SUMMER_TOYS_QUOTE',
      );
      expect(
        resolveQuoteExportTypeCandidate(
          parsedQuoteType: 'EVERYDAY_QUOTE',
          quoteBucketLabel: 'EVERYDAY',
        ),
        'EVERYDAY_QUOTE',
      );
    });

    test('empty parsed type uses bucket label', () {
      expect(
        resolveQuoteExportTypeCandidate(
          parsedQuoteType: '',
          quoteBucketLabel: 'CHRISTMAS',
        ),
        'CHRISTMAS QUOTE',
      );
    });
  });

  group('export basename type segment', () {
    test('corrupted stored name produces SUMMER_GENERAL_QUOTE segment', () {
      expect(
        _exportBasenameType(
          quoteName: '062823532588 GENERAL QUOTE_2026_08_28_001',
          quoteBucketLabel: 'SUMMER GENERAL',
        ),
        'SUMMER_GENERAL_QUOTE_2026_08_28_001',
      );
    });

    test('good SUMMER GENERAL name remains unchanged', () {
      expect(
        _exportBasenameType(
          quoteName: 'SUMMER GENERAL QUOTE_2026_08_28_001',
          quoteBucketLabel: 'SUMMER GENERAL',
        ),
        'SUMMER_GENERAL_QUOTE_2026_08_28_001',
      );
    });
  });

  group('PC transfer bracket wrap for corrupted quote', () {
    test('wraps corrected SUMMER_GENERAL_QUOTE for QuoteID 1787931361156', () {
      const exportBase =
          'SUMMER_GENERAL_QUOTE_2026_08_28_001_YOUR_STORE_W_MORE_505_RON_'
          '20260828_121548_660';
      final pc = buildPcTransferQuoteFilenameStem(
        quoteId: '1787931361156',
        exportBasenameWithoutExtension: exportBase,
      );
      expect(pc, startsWith('1787931361156_[SUMMER_GENERAL_QUOTE]'));
      expect(pc, isNot(contains('062823532588')));
    });
  });

  group('newlyInsertedBarcodeInQuoteName', () {
    const saved = 'SUMMER GENERAL QUOTE_2026_08_28_001';

    test('detects partial barcode replacement', () {
      expect(
        newlyInsertedBarcodeInQuoteName(
          '062823532588 GENERAL QUOTE_2026_08_28_001',
          saved,
        ),
        '062823532588',
      );
    });

    test('detects full-field barcode entry', () {
      expect(newlyInsertedBarcodeInQuoteName('062823532588', saved), '062823532588');
    });

    test('does not flag legitimate manual edits without new barcode runs', () {
      expect(
        newlyInsertedBarcodeInQuoteName(
          'SUMMER GENERAL QUOTE_2026_08_28_002',
          saved,
        ),
        isNull,
      );
      expect(
        newlyInsertedBarcodeInQuoteName(
          'MY CUSTOM SUMMER QUOTE_2026_08_28_001',
          saved,
        ),
        isNull,
      );
    });

    test('does not false-positive on date sequence digits alone', () {
      expect(
        newlyInsertedBarcodeInQuoteName(saved, 'NEW QUOTE'),
        isNull,
      );
    });

    test('saved unchanged when current matches saved', () {
      expect(newlyInsertedBarcodeInQuoteName(saved, saved), isNull);
    });
  });

  group('Send All mix: normal + corrupted quote filenames', () {
    test('each quote gets correct type segment', () {
      final names = <String, String>{
        'good_summer': _exportBasenameType(
          quoteName: 'SUMMER GENERAL QUOTE_2026_08_28_002',
          quoteBucketLabel: 'SUMMER GENERAL',
        ),
        'corrupted': _exportBasenameType(
          quoteName: '062823532588 GENERAL QUOTE_2026_08_28_001',
          quoteBucketLabel: 'SUMMER GENERAL',
        ),
        'toys': _exportBasenameType(
          quoteName: 'SUMMER TOYS QUOTE_2026_08_28_002',
          quoteBucketLabel: 'SUMMER TOYS',
        ),
        'everyday': _exportBasenameType(
          quoteName: 'EVERYDAY QUOTE_2026_08_28_001',
          quoteBucketLabel: 'EVERYDAY',
        ),
      };

      expect(names['good_summer'], 'SUMMER_GENERAL_QUOTE_2026_08_28_002');
      expect(names['corrupted'], 'SUMMER_GENERAL_QUOTE_2026_08_28_001');
      expect(names['toys'], 'SUMMER_TOYS_QUOTE_2026_08_28_002');
      expect(names['everyday'], 'EVERYDAY_QUOTE_2026_08_28_001');
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/active_quote_continuation.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('active_quote_continue_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Map<String, dynamic> row({
    required String id,
    required String customerId,
    required String bucket,
    required DateTime updatedAt,
    String status = 'active',
    String customerName = 'Customer',
  }) => {
    'id': id,
    'customerId': customerId,
    'customerName': customerName,
    'quoteBucketKey': bucket,
    'quoteStatus': status,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  Future<void> writePayload({
    required String id,
    required String bucket,
    required DateTime createdAt,
    required DateTime updatedAt,
    List<Map<String, dynamic>> lines = const [],
    Map<String, dynamic> extra = const {},
  }) {
    return File('${dir.path}/quote_$id.json').writeAsString(
      jsonEncode({
        'id': id,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'quoteBucketKey': bucket,
        'lines': lines,
        ...extra,
      }),
      flush: true,
    );
  }

  Future<ActiveQuoteContinuationResult> select({
    required List<Map<String, dynamic>> rows,
    String customerId = '302021',
    String customerName = 'Customer',
    String bucket = 'every_day',
    Set<String> excluded = const {},
  }) {
    return selectActiveQuoteForContinuation(
      quotesDirectory: dir,
      activeIndexRows: rows,
      excludedQuoteIds: excluded,
      customerId: customerId,
      customerName: customerName,
      bucketKey: bucket,
    );
  }

  group('persisted active quote selection', () {
    test('same-session and cold-restart lookup reuse the same id', () async {
      final updated = DateTime.utc(2026, 7, 1);
      final rows = [
        row(
          id: 'everyday-1',
          customerId: '302021',
          bucket: 'every_day',
          updatedAt: updated,
        ),
      ];
      await writePayload(
        id: 'everyday-1',
        bucket: 'every_day',
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: updated,
        lines: [
          {'itemNumber': 'A', 'quantity': 35, 'scans': 4, 'price': 0.585},
        ],
      );

      expect((await select(rows: rows)).selected?.id, 'everyday-1');
      // Recreate all lookup state to simulate a cold process restart.
      expect((await select(rows: List.of(rows))).selected?.id, 'everyday-1');
    });

    test('multiple Product Type buckets select independently', () async {
      final now = DateTime.utc(2026, 7, 1);
      final rows = [
        row(
          id: 'everyday',
          customerId: '302021',
          bucket: 'every_day',
          updatedAt: now,
        ),
        row(
          id: 'harvest',
          customerId: '302021',
          bucket: 'harvest',
          updatedAt: now,
        ),
      ];
      await writePayload(
        id: 'everyday',
        bucket: 'every_day',
        createdAt: now,
        updatedAt: now,
      );
      await writePayload(
        id: 'harvest',
        bucket: 'harvest',
        createdAt: now,
        updatedAt: now,
      );

      expect((await select(rows: rows)).selected?.id, 'everyday');
      expect(
        (await select(rows: rows, bucket: 'HARVEST')).selected?.id,
        'harvest',
      );
      expect((await select(rows: rows, bucket: 'CHRISTMAS')).selected, isNull);
    });

    test('different customers never cross-reuse', () async {
      final now = DateTime.utc(2026, 7, 1);
      final rows = [
        row(id: 'c1', customerId: '1', bucket: 'every_day', updatedAt: now),
        row(id: 'c2', customerId: '2', bucket: 'every_day', updatedAt: now),
      ];
      for (final id in ['c1', 'c2']) {
        await writePayload(
          id: id,
          bucket: 'every_day',
          createdAt: now,
          updatedAt: now,
        );
      }
      expect((await select(rows: rows, customerId: '2')).selected?.id, 'c2');
    });

    test('customer and bucket normalization avoids false duplicates', () async {
      final now = DateTime.utc(2026, 7, 1);
      final rows = [
        row(
          id: 'normalized',
          customerId: ' ABC ',
          customerName: ' ACME ',
          bucket: 'Fall/Winter',
          updatedAt: now,
        ),
      ];
      await writePayload(
        id: 'normalized',
        bucket: 'fall_winter',
        createdAt: now,
        updatedAt: now,
      );
      expect(
        (await select(
          rows: rows,
          customerId: 'abc',
          customerName: 'acme',
          bucket: ' FALL-WINTER ',
        )).selected?.id,
        'normalized',
      );
    });

    test(
      'multiple valid duplicates choose newest then id deterministically',
      () async {
        final older = DateTime.utc(2026, 7, 1);
        final newer = DateTime.utc(2026, 7, 2);
        final rows = [
          row(
            id: 'old',
            customerId: '302021',
            bucket: 'every_day',
            updatedAt: older,
          ),
          row(
            id: 'new-a',
            customerId: '302021',
            bucket: 'every_day',
            updatedAt: newer,
          ),
          row(
            id: 'new-z',
            customerId: '302021',
            bucket: 'every_day',
            updatedAt: newer,
          ),
        ];
        for (final entry in rows) {
          await writePayload(
            id: entry['id'] as String,
            bucket: 'every_day',
            createdAt: older,
            updatedAt: DateTime.parse(entry['updatedAt'] as String),
          );
        }
        final result = await select(rows: rows);
        expect(result.selected?.id, 'new-z');
        expect(result.validCandidateIds, ['new-z', 'new-a', 'old']);
        expect(rows, hasLength(3)); // Selection never merges or removes rows.
      },
    );

    test('newest payload updatedAt participates in duplicate choice', () async {
      final old = DateTime.utc(2026, 7, 1);
      final newest = DateTime.utc(2026, 7, 3);
      final rows = [
        row(
          id: 'payload-newest',
          customerId: '302021',
          bucket: 'every_day',
          updatedAt: old,
        ),
        row(
          id: 'index-newer',
          customerId: '302021',
          bucket: 'every_day',
          updatedAt: old.add(const Duration(days: 1)),
        ),
      ];
      await writePayload(
        id: 'payload-newest',
        bucket: 'every_day',
        createdAt: old,
        updatedAt: newest,
      );
      await writePayload(
        id: 'index-newer',
        bucket: 'every_day',
        createdAt: old,
        updatedAt: old,
      );
      expect((await select(rows: rows)).selected?.id, 'payload-newest');
    });

    test('missing and corrupt payloads are skipped safely', () async {
      final now = DateTime.utc(2026, 7, 1);
      final rows = [
        row(
          id: 'missing',
          customerId: '302021',
          bucket: 'every_day',
          updatedAt: now,
        ),
        row(
          id: 'corrupt',
          customerId: '302021',
          bucket: 'every_day',
          updatedAt: now,
        ),
        row(
          id: 'bad-lines',
          customerId: '302021',
          bucket: 'every_day',
          updatedAt: now,
        ),
        row(
          id: 'valid',
          customerId: '302021',
          bucket: 'every_day',
          updatedAt: now.subtract(const Duration(days: 1)),
        ),
      ];
      await File('${dir.path}/quote_corrupt.json').writeAsString('{not json');
      await File('${dir.path}/quote_bad-lines.json').writeAsString(
        jsonEncode({
          'id': 'bad-lines',
          'quoteBucketKey': 'every_day',
          'lines': [123],
        }),
      );
      await writePayload(
        id: 'valid',
        bucket: 'every_day',
        createdAt: now,
        updatedAt: now,
      );
      final result = await select(rows: rows);
      expect(result.selected?.id, 'valid');
      expect(result.missingPayloadIds, ['missing']);
      expect(result.corruptPayloadIds, ['corrupt', 'bad-lines']);
    });

    test('archived confirmed and deleted ids are not reused', () async {
      final now = DateTime.utc(2026, 7, 1);
      final rows = [
        row(
          id: 'archived',
          customerId: '302021',
          bucket: 'every_day',
          updatedAt: now,
          status: 'archived',
        ),
        row(
          id: 'confirmed',
          customerId: '302021',
          bucket: 'every_day',
          updatedAt: now,
          status: 'confirmed',
        ),
        row(
          id: 'deleted',
          customerId: '302021',
          bucket: 'every_day',
          updatedAt: now,
        ),
      ];
      for (final id in ['archived', 'confirmed', 'deleted']) {
        await writePayload(
          id: id,
          bucket: 'every_day',
          createdAt: now,
          updatedAt: now,
        );
      }
      expect(
        (await select(rows: rows, excluded: {'deleted'})).selected,
        isNull,
      );
    });

    test('restored active row becomes reusable', () async {
      final now = DateTime.utc(2026, 7, 1);
      final restored = row(
        id: 'restored',
        customerId: '302021',
        bucket: 'every_day',
        updatedAt: now,
      );
      await writePayload(
        id: 'restored',
        bucket: 'every_day',
        createdAt: now,
        updatedAt: now,
      );
      expect(
        (await select(rows: [restored], excluded: {'restored'})).selected,
        isNull,
      );
      expect((await select(rows: [restored])).selected?.id, 'restored');
    });

    test('blank index bucket falls back to valid payload bucket', () async {
      final now = DateTime.utc(2026, 7, 1);
      final rows = [
        row(id: 'legacy', customerId: '302021', bucket: '', updatedAt: now),
      ];
      await writePayload(
        id: 'legacy',
        bucket: 'Christmas',
        createdAt: now,
        updatedAt: now,
      );
      expect(
        (await select(rows: rows, bucket: 'christmas')).selected?.id,
        'legacy',
      );
    });
  });

  test(
    'coordinator serializes two rapid route/add/save transactions',
    () async {
      final coordinator = QuoteOperationCoordinator();
      var quoteCreations = 0;
      final lines = <String>[];
      String? currentId;

      Future<void> add(String item) {
        return coordinator.run(() async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          currentId ??= 'quote-${++quoteCreations}';
          lines.add(item);
        });
      }

      await Future.wait([add('A'), add('B')]);
      expect(currentId, 'quote-1');
      expect(quoteCreations, 1);
      expect(lines, ['A', 'B']);
    },
  );

  test('coordinator permits nested operations without deadlock', () async {
    final coordinator = QuoteOperationCoordinator();
    final values = <String>[];
    await coordinator.run(() async {
      values.add('outer');
      await coordinator.run(() async {
        values.add('inner');
      });
    });
    expect(values, ['outer', 'inner']);
  });

  test(
    'explicit Create Quote intent bypasses persisted continuation',
    () async {
      final now = DateTime.utc(2026, 7, 1);
      final rows = [
        row(
          id: 'existing',
          customerId: '302021',
          bucket: 'every_day',
          updatedAt: now,
        ),
      ];
      await writePayload(
        id: 'existing',
        bucket: 'every_day',
        createdAt: now,
        updatedAt: now,
      );

      final shouldLookup = shouldAttemptPersistedQuoteContinuation(
        currentQuoteId: null,
        hasWorkingLines: false,
        explicitFreshQuotePending: true,
      );
      expect(shouldLookup, isFalse);
      final selectedId = shouldLookup
          ? (await select(rows: rows)).selected?.id
          : 'fresh';
      expect(selectedId, 'fresh');
      expect(
        shouldAttemptPersistedQuoteContinuation(
          currentQuoteId: null,
          hasWorkingLines: false,
          explicitFreshQuotePending: false,
        ),
        isTrue,
      );
    },
  );

  test(
    'continued payload preserves lines, scans, price, notes and createdAt',
    () async {
      final createdAt = DateTime.utc(2026, 6, 1);
      final firstUpdate = DateTime.utc(2026, 7, 1);
      final secondUpdate = DateTime.utc(2026, 7, 2);
      await writePayload(
        id: 'preserve',
        bucket: 'every_day',
        createdAt: createdAt,
        updatedAt: firstUpdate,
        lines: [
          {
            'itemNumber': 'A',
            'quantity': 35,
            'scans': 4,
            'price': 0.585,
            'notes': 'keep me',
          },
        ],
        extra: {'quoteNotes': 'existing note'},
      );

      final file = File('${dir.path}/quote_preserve.json');
      final previous = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      final payload = mergeQuotePayloadForContinuationSave(
        previous: previous,
        generated: {
          'id': 'preserve',
          'createdAt': secondUpdate.toIso8601String(),
          'updatedAt': secondUpdate.toIso8601String(),
          'quoteBucketKey': 'every_day',
          'lines': [
            {
              'itemNumber': 'A',
              'quantity': 36,
              'scans': 5,
              'price': 9.99,
              'listPrice': 9.99,
            },
            {'itemNumber': 'B', 'quantity': 1, 'scans': 1, 'price': 2.50},
          ],
        },
      );
      await file.writeAsString(jsonEncode(payload), flush: true);

      final after = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      expect(after['createdAt'], createdAt.toIso8601String());
      expect(after['updatedAt'], secondUpdate.toIso8601String());
      expect(after['quoteNotes'], 'existing note');
      final afterLines = after['lines'] as List;
      expect(afterLines, hasLength(2));
      expect(afterLines.first['quantity'], 36);
      expect(afterLines.first['scans'], 5);
      expect(afterLines.first['price'], 0.585);
      expect(afterLines.first['notes'], 'keep me');

      // A second process restart still discovers the same updated quote.
      final result = await select(
        rows: [
          row(
            id: 'preserve',
            customerId: '302021',
            bucket: 'every_day',
            updatedAt: secondUpdate,
          ),
        ],
      );
      expect(result.selected?.id, 'preserve');
      expect(
        result.selected?.payload['createdAt'],
        createdAt.toIso8601String(),
      );
    },
  );
}

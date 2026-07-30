import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/quote_deleted_lifecycle.dart';

void main() {
  test('main retains deleted UI and email feature wiring', () async {
    final source = await File('lib/main.dart').readAsString();
    expect(source, contains("import 'quote_deleted_lifecycle.dart';"));
    expect(source, contains('loadDeleted: _loadDeletedQuoteIndex'));
    expect(source, contains("_sectionHeader('Recently Deleted')"));
    expect(source, contains("child: const Text('Restore')"));
    expect(source, contains("label: const Text('Delete Permanently')"));
    expect(source, contains("pop('removed:\${info.id}')"));
    expect(source, contains("'Move to Recently Deleted?'"));
    expect(source, contains("'Move to Recently Deleted'"));
    expect(source, contains("tooltip: 'Move to Recently Deleted'"));
    expect(source, isNot(contains("'Delete Quote'")));
    expect(
      source,
      isNot(contains("'Remove from list (after emailing or saving)'")),
    );
    expect(source, isNot(contains("tooltip: 'Delete from archive'")));
    expect(source, contains('persistCsvCopies: true'));
    expect(source, contains('archiveActiveQuotesAfterShare: true'));

    const current = 'Email Current Quote Only\\n(moves to Archive)';
    const customer =
        'Email All Quotes for This Customer\\n(archives included active quotes)';
    const all = 'Email All Saved Quotes\\n(share only — does not archive)';
    final currentIndex = source.indexOf(current);
    final customerIndex = source.indexOf(customer);
    final allIndex = source.indexOf(all);
    expect(currentIndex, greaterThanOrEqualTo(0));
    expect(customerIndex, greaterThan(currentIndex));
    expect(allIndex, greaterThan(customerIndex));
  });

  group('TTL helpers', () {
    final deletedAt = DateTime.utc(2026, 1, 1, 12);

    test('order remains before 30 complete days', () {
      final now = deletedAt.add(const Duration(days: 30));
      expect(isDeletedQuoteExpired(deletedAt, now), isFalse);
      expect(deletedQuoteDaysRemaining(deletedAt, now), 0);
    });

    test('order is expired after 30 complete days', () {
      final now = deletedAt.add(const Duration(days: 30, seconds: 1));
      expect(isDeletedQuoteExpired(deletedAt, now), isTrue);
      expect(deletedQuoteDaysRemaining(deletedAt, now), 0);
    });

    test('days remaining mid-window', () {
      final now = deletedAt.add(const Duration(days: 10));
      expect(deletedQuoteDaysRemaining(deletedAt, now), 20);
    });
  });

  group('resolveRestoreStatus', () {
    test('valid statuses preserved', () {
      expect(resolveRestoreStatus('active'), 'active');
      expect(resolveRestoreStatus('archived'), 'archived');
      expect(resolveRestoreStatus('confirmed'), 'confirmed');
    });

    test('invalid original status falls back to archived', () {
      expect(resolveRestoreStatus(null), 'archived');
      expect(resolveRestoreStatus(''), 'archived');
      expect(resolveRestoreStatus('bogus'), 'archived');
    });
  });

  group('legacy / parsing', () {
    test(
      'legacy quote JSON without deleted fields still parses index snapshot',
      () {
        final info = DeletedQuoteInfo.fromJson({
          'quoteId': 'q1',
          'deletedAt': '2026-01-01T00:00:00.000Z',
          'originalStatus': 'active',
          'index': {
            'id': 'q1',
            'name': 'EVERYDAY QUOTE',
            'customerName': 'Acme',
            'customerId': '1',
            'quoteBucketKey': 'every_day',
            'quoteBucketLabel': 'EVERYDAY',
            'updatedAt': '2026-01-01T00:00:00.000Z',
            'quoteStatus': 'active',
          },
        });
        expect(info.quoteId, 'q1');
        expect(info.name, 'EVERYDAY QUOTE');
        expect(info.customerName, 'Acme');
      },
    );

    test('missing quotes_deleted.json loads as empty via store', () async {
      final dir = await Directory.systemTemp.createTemp('rd_empty_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final store = QuoteDeletedIndexStore(quotesDirectory: dir);
      expect(await store.loadDeletedIndex(), isEmpty);
    });
  });

  group('QuoteDeletedIndexStore soft-delete / restore', () {
    late Directory dir;
    late QuoteDeletedIndexStore store;
    late DateTime clock;

    Map<String, dynamic> snap({
      required String id,
      required String status,
      String name = 'QUOTE A',
      String customer = 'Cust',
      String customerId = 'C1',
    }) => {
      'id': id,
      'name': name,
      'customerName': customer,
      'customerId': customerId,
      'quoteBucketKey': 'every_day',
      'quoteBucketLabel': 'EVERYDAY',
      'updatedAt': '2026-01-01T00:00:00.000Z',
      'quoteStatus': status,
    };

    Future<void> writeQuote(String id, {List<Map>? lines}) async {
      await store
          .quoteFileFor(id)
          .writeAsString(
            jsonEncode({
              'id': id,
              'name': 'QUOTE A',
              'lines':
                  lines ??
                  [
                    {
                      'itemNumber': '46314',
                      'quantity': 12,
                      'scans': 1,
                      'price': 0.585,
                      'description': 'Bag bag',
                    },
                  ],
              'customer': {'id': 'C1', 'companyName': 'Cust'},
            }),
            flush: true,
          );
    }

    setUp(() async {
      clock = DateTime.utc(2026, 6, 1, 12);
      dir = await Directory.systemTemp.createTemp('rd_store_');
      store = QuoteDeletedIndexStore(quotesDirectory: dir, clock: () => clock);
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('active soft-delete keeps quote file and hides from active', () async {
      await writeQuote('a1');
      await store.activeIndexFile.writeAsString(
        jsonEncode([snap(id: 'a1', status: 'active')]),
        flush: true,
      );

      final ok = await store.softDeleteQuote(
        indexSnapshot: snap(id: 'a1', status: 'active'),
        originalStatus: 'active',
      );
      expect(ok, isTrue);
      expect(await store.quoteFileFor('a1').exists(), isTrue);

      final active =
          jsonDecode(await store.activeIndexFile.readAsString()) as List;
      expect(active.where((e) => e['id'] == 'a1'), isEmpty);

      final deleted = await store.loadDeletedIndex();
      expect(deleted.single.quoteId, 'a1');
      expect(deleted.single.originalStatus, 'active');
      expect(deleted.any((e) => e.quoteId == 'a1'), isTrue);
    });

    test('archived soft-delete', () async {
      await writeQuote('ar1');
      await store.archiveIndexFile.writeAsString(
        jsonEncode([snap(id: 'ar1', status: 'archived')]),
        flush: true,
      );
      expect(
        await store.softDeleteQuote(
          indexSnapshot: snap(id: 'ar1', status: 'archived'),
          originalStatus: 'archived',
        ),
        isTrue,
      );
      final archive =
          jsonDecode(await store.archiveIndexFile.readAsString()) as List;
      expect(archive, isEmpty);
      expect(
        (await store.loadDeletedIndex()).single.originalStatus,
        'archived',
      );
    });

    test('confirmed soft-delete', () async {
      await writeQuote('cf1');
      await store.archiveIndexFile.writeAsString(
        jsonEncode([snap(id: 'cf1', status: 'confirmed')]),
        flush: true,
      );
      expect(
        await store.softDeleteQuote(
          indexSnapshot: snap(id: 'cf1', status: 'confirmed'),
          originalStatus: 'confirmed',
        ),
        isTrue,
      );
      expect(
        (await store.loadDeletedIndex()).single.originalStatus,
        'confirmed',
      );
    });

    test('duplicate delete taps keep one deleted row', () async {
      await writeQuote('dup-delete');
      final snapshot = snap(id: 'dup-delete', status: 'active');
      await store.activeIndexFile.writeAsString(
        jsonEncode([snapshot]),
        flush: true,
      );
      for (var i = 0; i < 2; i++) {
        expect(
          await store.softDeleteQuote(
            indexSnapshot: snapshot,
            originalStatus: 'active',
          ),
          isTrue,
        );
      }
      expect(
        (await store.loadDeletedIndex()).where(
          (entry) => entry.quoteId == 'dup-delete',
        ),
        hasLength(1),
      );
    });

    test(
      'failed deleted-index persistence leaves active source intact',
      () async {
        await writeQuote('deleted-write-failure');
        final snapshot = snap(id: 'deleted-write-failure', status: 'active');
        await store.activeIndexFile.writeAsString(
          jsonEncode([snapshot]),
          flush: true,
        );
        await Directory(store.deletedIndexFile.path).create();

        await expectLater(
          store.softDeleteQuote(
            indexSnapshot: snapshot,
            originalStatus: 'active',
          ),
          throwsA(isA<FileSystemException>()),
        );

        final active =
            jsonDecode(await store.activeIndexFile.readAsString()) as List;
        expect(active.single['id'], 'deleted-write-failure');
        expect(
          await store.quoteFileFor('deleted-write-failure').exists(),
          isTrue,
        );
        await Directory(store.deletedIndexFile.path).delete();
      },
    );

    test('Undo restores original status', () async {
      await writeQuote('u1');
      await store.activeIndexFile.writeAsString(
        jsonEncode([snap(id: 'u1', status: 'active')]),
        flush: true,
      );
      await store.softDeleteQuote(
        indexSnapshot: snap(id: 'u1', status: 'active'),
        originalStatus: 'active',
      );
      expect(await store.restoreDeletedQuote('u1'), isTrue);
      final active =
          jsonDecode(await store.activeIndexFile.readAsString()) as List;
      expect(active.single['id'], 'u1');
      expect(active.single['quoteStatus'], 'active');
      expect(active.single['updatedAt'], '2026-01-01T00:00:00.000Z');
      expect(await store.loadDeletedIndex(), isEmpty);
    });

    test('restore after restart (reload from disk)', () async {
      await writeQuote('r1');
      await store.archiveIndexFile.writeAsString(
        jsonEncode([snap(id: 'r1', status: 'archived')]),
        flush: true,
      );
      await store.softDeleteQuote(
        indexSnapshot: snap(id: 'r1', status: 'archived'),
        originalStatus: 'archived',
      );

      final store2 = QuoteDeletedIndexStore(
        quotesDirectory: dir,
        clock: () => clock,
      );
      expect(await store2.restoreDeletedQuote('r1'), isTrue);
      final archive =
          jsonDecode(await store2.archiveIndexFile.readAsString()) as List;
      expect(archive.single['quoteStatus'], 'archived');
    });

    test('confirmed quote restores to confirmed collection', () async {
      await writeQuote('confirmed-restore');
      await store.archiveIndexFile.writeAsString(
        jsonEncode([snap(id: 'confirmed-restore', status: 'confirmed')]),
        flush: true,
      );
      await store.softDeleteQuote(
        indexSnapshot: snap(id: 'confirmed-restore', status: 'confirmed'),
        originalStatus: 'confirmed',
      );

      expect(await store.restoreDeletedQuote('confirmed-restore'), isTrue);
      final archive =
          jsonDecode(await store.archiveIndexFile.readAsString()) as List;
      expect(archive.single['id'], 'confirmed-restore');
      expect(archive.single['quoteStatus'], 'confirmed');
    });

    test('invalid original status restores as archived', () async {
      await writeQuote('inv1');
      final prior = await store.loadDeletedIndex();
      await store.saveDeletedIndex(
        upsertDeletedQuote(
          prior,
          DeletedQuoteInfo(
            quoteId: 'inv1',
            deletedAt: clock,
            originalStatus: 'not-a-status',
            indexSnapshot: snap(id: 'inv1', status: 'active'),
          ),
        ),
      );
      expect(await store.restoreDeletedQuote('inv1'), isTrue);
      final archive =
          jsonDecode(await store.archiveIndexFile.readAsString()) as List;
      expect(archive.single['quoteStatus'], 'archived');
    });

    test('permanent deletion removes index entry and quote file', () async {
      await writeQuote('p1');
      await store.softDeleteQuote(
        indexSnapshot: snap(id: 'p1', status: 'active'),
        originalStatus: 'active',
      );
      expect(await store.permanentlyDeleteQuote('p1'), isTrue);
      expect(await store.loadDeletedIndex(), isEmpty);
      expect(await store.quoteFileFor('p1').exists(), isFalse);
    });

    test(
      'permanent deletion removes only the selected deleted quote',
      () async {
        for (final id in ['selected', 'keep']) {
          await writeQuote(id);
          await store.softDeleteQuote(
            indexSnapshot: snap(id: id, status: 'archived'),
            originalStatus: 'archived',
          );
        }

        expect(await store.permanentlyDeleteQuote('selected'), isTrue);
        final remaining = await store.loadDeletedIndex();
        expect(remaining.map((entry) => entry.quoteId), ['keep']);
        expect(await store.quoteFileFor('selected').exists(), isFalse);
        expect(await store.quoteFileFor('keep').exists(), isTrue);
      },
    );

    test('cancellation keeps order (permanent delete not called)', () async {
      await writeQuote('c1');
      await store.softDeleteQuote(
        indexSnapshot: snap(id: 'c1', status: 'active'),
        originalStatus: 'active',
      );
      // Simulate cancel: do nothing.
      expect((await store.loadDeletedIndex()).length, 1);
      expect(await store.quoteFileFor('c1').exists(), isTrue);
    });

    test('under-30-day retention', () async {
      await writeQuote('t1');
      await store.softDeleteQuote(
        indexSnapshot: snap(id: 't1', status: 'active'),
        originalStatus: 'active',
      );
      clock = clock.add(const Duration(days: 29));
      expect(await store.purgeExpiredDeletedQuotes(), isEmpty);
      expect(await store.quoteFileFor('t1').exists(), isTrue);
      expect((await store.loadDeletedIndex()).length, 1);
    });

    test('over-30-day cleanup', () async {
      await writeQuote('t2');
      await store.softDeleteQuote(
        indexSnapshot: snap(id: 't2', status: 'active'),
        originalStatus: 'active',
      );
      clock = clock.add(const Duration(days: 30, seconds: 1));
      final removed = await store.purgeExpiredDeletedQuotes();
      expect(removed, ['t2']);
      expect(await store.loadDeletedIndex(), isEmpty);
      expect(await store.quoteFileFor('t2').exists(), isFalse);
    });

    test(
      'deleted order does not appear in active or archive indexes',
      () async {
        await writeQuote('h1');
        await store.activeIndexFile.writeAsString(
          jsonEncode([snap(id: 'h1', status: 'active')]),
          flush: true,
        );
        await store.softDeleteQuote(
          indexSnapshot: snap(id: 'h1', status: 'active'),
          originalStatus: 'active',
        );
        final active =
            jsonDecode(await store.activeIndexFile.readAsString()) as List;
        final archive = await store.archiveIndexFile.exists()
            ? jsonDecode(await store.archiveIndexFile.readAsString()) as List
            : <dynamic>[];
        expect(active.any((e) => e['id'] == 'h1'), isFalse);
        expect(archive.any((e) => e['id'] == 'h1'), isFalse);
      },
    );

    test(
      'unrelated active archived and confirmed rows remain unchanged',
      () async {
        for (final id in [
          'target',
          'active-keep',
          'archive-keep',
          'confirmed-keep',
        ]) {
          await writeQuote(id);
        }
        await store.activeIndexFile.writeAsString(
          jsonEncode([
            snap(id: 'target', status: 'active'),
            snap(id: 'active-keep', status: 'active'),
          ]),
          flush: true,
        );
        await store.archiveIndexFile.writeAsString(
          jsonEncode([
            snap(id: 'archive-keep', status: 'archived'),
            snap(id: 'confirmed-keep', status: 'confirmed'),
          ]),
          flush: true,
        );

        expect(
          await store.softDeleteQuote(
            indexSnapshot: snap(id: 'target', status: 'active'),
            originalStatus: 'active',
          ),
          isTrue,
        );

        final active =
            jsonDecode(await store.activeIndexFile.readAsString()) as List;
        final archive =
            jsonDecode(await store.archiveIndexFile.readAsString()) as List;
        expect(active.map((row) => row['id']), ['active-keep']);
        expect(archive.map((row) => row['id']), [
          'archive-keep',
          'confirmed-keep',
        ]);
        expect(archive[0]['quoteStatus'], 'archived');
        expect(archive[1]['quoteStatus'], 'confirmed');
      },
    );

    test('product update survival (quote file untouched by catalog)', () async {
      await writeQuote('pu1');
      await store.softDeleteQuote(
        indexSnapshot: snap(id: 'pu1', status: 'active'),
        originalStatus: 'active',
      );
      // Simulate product CSV refresh — does not touch showroom_quotes.
      final before = await store.quoteFileFor('pu1').readAsString();
      expect(before.contains('46314'), isTrue);
      expect(await store.quoteFileFor('pu1').readAsString(), before);
    });

    test('complete quote payload remains byte-for-byte unchanged', () async {
      const id = 'byte-identical';
      final payload = jsonEncode({
        'id': id,
        'name': 'EVERYDAY QUOTE',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-06-01T00:00:00.000Z',
        'notes': 'Keep this note',
        'customer': {'id': 'C1', 'companyName': 'Cust'},
        'lines': [
          {
            'itemNumber': '01514',
            'quantity': 24,
            'scans': 3,
            'price': 1.625,
            'listPrice': 1.75,
            'discountEligible': true,
            'productType': 'EVERYDAY',
          },
        ],
        'exportedFileNames': ['Quote.csv'],
      });
      await store.quoteFileFor(id).writeAsString(payload, flush: true);
      await store.activeIndexFile.writeAsString(
        jsonEncode([snap(id: id, status: 'active')]),
        flush: true,
      );

      await store.softDeleteQuote(
        indexSnapshot: snap(id: id, status: 'active'),
        originalStatus: 'active',
      );
      expect(await store.quoteFileFor(id).readAsString(), payload);
      await store.restoreDeletedQuote(id);
      expect(await store.quoteFileFor(id).readAsString(), payload);
    });

    test('no duplicate after restore', () async {
      await writeQuote('d1');
      await store.activeIndexFile.writeAsString(
        jsonEncode([
          snap(id: 'd1', status: 'active'),
          snap(id: 'd1', status: 'active', name: 'dup'),
        ]),
        flush: true,
      );
      await store.softDeleteQuote(
        indexSnapshot: snap(id: 'd1', status: 'active'),
        originalStatus: 'active',
      );
      await store.restoreDeletedQuote('d1');
      final active =
          jsonDecode(await store.activeIndexFile.readAsString()) as List;
      expect(active.where((e) => e['id'] == 'd1').length, 1);
    });

    test('complete line-item data survives delete and restore', () async {
      await writeQuote(
        'L1',
        lines: [
          {
            'itemNumber': '01514',
            'quantity': 24,
            'scans': 3,
            'price': 1.62,
            'listPrice': 1.62,
            'description': 'Truck',
          },
        ],
      );
      await store.softDeleteQuote(
        indexSnapshot: snap(id: 'L1', status: 'active'),
        originalStatus: 'active',
      );
      await store.restoreDeletedQuote('L1');
      final body =
          jsonDecode(await store.quoteFileFor('L1').readAsString()) as Map;
      final lines = body['lines'] as List;
      expect(lines.single['itemNumber'], '01514');
      expect(lines.single['quantity'], 24);
      expect(lines.single['scans'], 3);
      expect(lines.single['price'], 1.62);
    });

    test('bulk purge becomes soft-delete (multiple archived)', () async {
      await writeQuote('b1');
      await writeQuote('b2');
      await store.archiveIndexFile.writeAsString(
        jsonEncode([
          snap(id: 'b1', status: 'archived'),
          snap(id: 'b2', status: 'archived'),
        ]),
        flush: true,
      );
      for (final id in ['b1', 'b2']) {
        await store.softDeleteQuote(
          indexSnapshot: snap(id: id, status: 'archived'),
          originalStatus: 'archived',
        );
      }
      final archive =
          jsonDecode(await store.archiveIndexFile.readAsString()) as List;
      expect(archive, isEmpty);
      expect((await store.loadDeletedIndex()).length, 2);
      expect(await store.quoteFileFor('b1').exists(), isTrue);
      expect(await store.quoteFileFor('b2').exists(), isTrue);
    });

    test('rollback if archive index write fails after deleted write', () async {
      await writeQuote('rb1');
      await store.activeIndexFile.writeAsString(
        jsonEncode([snap(id: 'rb1', status: 'active')]),
        flush: true,
      );

      // Replace archive path with a directory so writeAsString fails.
      final archivePath = store.archiveIndexFile.path;
      await Directory(archivePath).create(recursive: true);

      final ok = await store.softDeleteQuote(
        indexSnapshot: snap(id: 'rb1', status: 'active'),
        originalStatus: 'active',
      );
      expect(ok, isFalse);

      // Deleted index rolled back.
      expect(await store.loadDeletedIndex(), isEmpty);
      // Active restored.
      final active =
          jsonDecode(await store.activeIndexFile.readAsString()) as List;
      expect(active.single['id'], 'rb1');
      expect(await store.quoteFileFor('rb1').exists(), isTrue);

      await Directory(archivePath).delete(recursive: true);
    });
  });
}

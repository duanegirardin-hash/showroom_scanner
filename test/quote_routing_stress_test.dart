import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/quote_routing_gate.dart';

import 'routing_harness.dart';

/// Long mixed-type / HID-style stress coverage for the intermittent duplicate
/// Summer Toys defect. These are the automated stand-in for multi-session phone
/// HID testing; they do not close the defect on their own.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('quote_routing_stress_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  const buckets = <String>[
    'summer_toys',
    'every_day',
    'christmas',
    'halloween',
    'easter',
    'giftcraft',
    'summer_general',
  ];

  Future<void> assertNoDuplicateActiveQuotes(RoutingHarness app) async {
    final byBucket = await app.activeQuoteIdsByBucket();
    for (final entry in byBucket.entries) {
      expect(
        entry.value.toSet(),
        hasLength(1),
        reason:
            'bucket ${entry.key} has duplicate active ids: ${entry.value}',
      );
    }
    final files = await app.persistedQuoteFilesByBucket();
    for (final entry in files.entries) {
      expect(
        entry.value.toSet(),
        hasLength(lessThanOrEqualTo(1)),
        reason:
            'bucket ${entry.key} has duplicate quote files: ${entry.value}',
      );
    }
  }

  group('HID-style mixed-type stress (gated)', () {
    test('200 alternating scans keep one quote per Product Type', () async {
      final gate = QuoteRoutingGate();
      final app = RoutingHarness(dir: dir, gate: gate);
      final expectedItems = <String>{};
      String? summerToysId;

      for (var i = 0; i < 200; i++) {
        final bucket = buckets[i % buckets.length];
        final item = '$bucket-$i';
        expectedItems.add(item);
        await app.scan(item, bucket);
        if (bucket == 'summer_toys' && summerToysId == null) {
          await app.saveQuote();
          summerToysId = app.currentQuoteId;
        }
      }
      await app.saveQuote();

      await assertNoDuplicateActiveQuotes(app);
      expect(summerToysId, isNotNull);

      // Return to Summer Toys repeatedly — must reuse the original id.
      for (var r = 0; r < 25; r++) {
        await app.scan('toys-return-$r', 'summer_toys');
        expect(app.currentQuoteId, summerToysId);
      }
      await app.saveQuote();
      expect(app.currentQuoteId, summerToysId);

      // Interleave other types then return again.
      for (var i = 0; i < 40; i++) {
        final other = buckets[(i % (buckets.length - 1)) + 1];
        await app.scan('mix-$i', other);
        await app.scan('toys-late-$i', 'summer_toys');
        expect(app.currentQuoteId, summerToysId);
      }
      await app.saveQuote();
      await assertNoDuplicateActiveQuotes(app);

      // Sweep-save every bucket so every scanned line is on disk.
      for (final b in buckets) {
        await app.ensureRoutingForProduct(b);
        if (app.orderLines.isNotEmpty) await app.saveQuote();
      }
      final persisted = <String>{};
      for (final ids in (await app.persistedQuoteFilesByBucket()).values) {
        for (final id in ids) {
          final payload = await app.readPayload(id);
          for (final line in (payload!['lines'] as List)) {
            persisted.add((line as Map)['item'].toString());
          }
        }
      }
      expect(persisted, containsAll(expectedItems));
    });

    test('concurrent mixed-bucket bursts never mint a second quote', () async {
      final gate = QuoteRoutingGate();
      final app = RoutingHarness(dir: dir, gate: gate);

      await app.scan('toys-0', 'summer_toys');
      await app.saveQuote();
      final summerId = app.currentQuoteId!;

      for (var wave = 0; wave < 30; wave++) {
        await Future.wait([
          for (var i = 0; i < buckets.length; i++)
            app.scan('w${wave}_$i', buckets[i]),
        ]);
      }
      await app.saveQuote();
      await assertNoDuplicateActiveQuotes(app);

      await app.scan('toys-final', 'summer_toys');
      expect(app.currentQuoteId, summerId);
    });

    test('restart reuses Summer Toys id after long mixed session', () async {
      final gate = QuoteRoutingGate();
      final app = RoutingHarness(dir: dir, gate: gate);

      await app.scan('toys-a', 'summer_toys');
      await app.saveQuote();
      final summerId = app.currentQuoteId!;

      for (var i = 0; i < 80; i++) {
        await app.scan('b-$i', buckets[i % buckets.length]);
      }
      await app.saveQuote();

      // Simulate app restart: clear workspace, keep disk.
      app.orderLines.clear();
      app.currentQuoteId = null;
      app.activeBucketKey = 'every_day';

      final gate2 = QuoteRoutingGate();
      final restarted = RoutingHarness(dir: dir, gate: gate2)
        ..customerId = app.customerId
        ..customerName = app.customerName;

      await restarted.scan('toys-after-restart', 'summer_toys');
      expect(restarted.currentQuoteId, summerId);
      await assertNoDuplicateActiveQuotes(restarted);
    });
  });

  group('lifecycle persist race', () {
    test(
      'ungated lifecycle save racing route-away still duplicates (defect class)',
      () async {
        final app = RoutingHarness(dir: dir);
        await app.scan('toys-1', 'summer_toys');
        expect(app.currentQuoteId, isNull);

        // Lifecycle persist + routing switch away, both ungated.
        await Future.wait([
          app.persistWorkingQuote(throughGate: false),
          app.ensureRoutingForProduct('christmas'),
        ]);

        final byBucket = await app.persistedQuoteFilesByBucket();
        expect(
          byBucket['summer_toys'] ?? const <String>[],
          hasLength(greaterThan(1)),
          reason: 'ungated lifecycle+routing must still reproduce the race',
        );
      },
    );

    test(
      'lifecycle persist through gate cannot mint a second Summer Toys quote',
      () async {
        final gate = QuoteRoutingGate();
        final app = RoutingHarness(dir: dir, gate: gate);
        await app.scan('toys-1', 'summer_toys');
        expect(app.currentQuoteId, isNull);

        await Future.wait([
          app.persistWorkingQuote(throughGate: true),
          app.ensureRoutingForProduct('christmas'),
          app.ensureRoutingForProduct('every_day'),
          app.persistWorkingQuote(throughGate: true),
        ]);

        final byBucket = await app.persistedQuoteFilesByBucket();
        expect(byBucket['summer_toys'], hasLength(1));
        await assertNoDuplicateActiveQuotes(app);
      },
    );
  });

  group('route+add held under one gate', () {
    test('overlapping same-bucket scans retain every line', () async {
      final gate = QuoteRoutingGate();
      final app = RoutingHarness(dir: dir, gate: gate);

      await Future.wait([
        for (var i = 0; i < 20; i++) app.scan('toys-$i', 'summer_toys'),
      ]);
      await app.saveQuote();

      final files = await app.persistedQuoteFilesByBucket();
      expect(files['summer_toys'], hasLength(1));
      final id = files['summer_toys']!.single;
      final payload = await app.readPayload(id);
      final items = (payload!['lines'] as List)
          .map((l) => (l as Map)['item'].toString())
          .toSet();
      expect(items, {
        for (var i = 0; i < 20; i++) 'toys-$i',
      });
    });
  });
}

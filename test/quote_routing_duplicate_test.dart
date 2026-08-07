import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/active_quote_continuation.dart';
import 'package:showroom_scanner/quote_routing_gate.dart';

import 'routing_harness.dart';

/// Reproduces the production defect: a second active quote appears for a
/// customer + Product Type that already has one.
///
/// Root cause modelled here — routing is an unguarded check-then-act over one
/// shared workspace, and `_startNewQuote` persists nothing, so the quote id is
/// only minted later inside `_saveQuote`. Two overlapping entry paths both see
/// `currentQuoteId == null` and each mints its own id.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('quote_routing_dup_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('defect reproduction — unguarded routing (historical behaviour)', () {
    test(
      'unsaved SUMMER TOYS workspace + two concurrent routes away '
      'persists two SUMMER TOYS quotes',
      () async {
        final app = RoutingHarness(dir: dir);
        // Routed Summer Toys workspace that has never been saved: startNewQuote()
        // leaves currentQuoteId null and persists nothing.
        await app.scan('toys-1', 'summer_toys');
        expect(app.currentQuoteId, isNull);

        // Two entry paths route away at the same time (e.g. HID queue + camera,
        // or Quick Entry + search tap). Both observe currentQuoteId == null and
        // both mint a fresh id inside saveQuote().
        await Future.wait([
          app.ensureRoutingForProduct('christmas'),
          app.ensureRoutingForProduct('every_day'),
        ]);

        final byBucket = await app.persistedQuoteFilesByBucket();
        expect(
          byBucket['summer_toys'] ?? const <String>[],
          hasLength(greaterThan(1)),
          reason: 'unguarded routing must reproduce the duplicate defect',
        );
        expect(app.mintedIds.toSet(), hasLength(greaterThan(1)));
      },
    );

    test('the same race reproduces for CHRISTMAS (not Summer-specific)', () async {
      final app = RoutingHarness(dir: dir);
      await app.scan('xmas-1', 'christmas');

      await Future.wait([
        app.ensureRoutingForProduct('summer_toys'),
        app.ensureRoutingForProduct('every_day'),
      ]);

      final byBucket = await app.persistedQuoteFilesByBucket();
      expect(
        byBucket['christmas'] ?? const <String>[],
        hasLength(greaterThan(1)),
      );
    });

    test('the same race reproduces for HALLOWEEN and EASTER', () async {
      for (final bucket in ['halloween', 'easter']) {
        final scoped = await Directory.systemTemp.createTemp('dup_$bucket');
        try {
          final app = RoutingHarness(dir: scoped);
          await app.scan('$bucket-1', bucket);
          await Future.wait([
            app.ensureRoutingForProduct('christmas'),
            app.ensureRoutingForProduct('every_day'),
          ]);
          final byBucket = await app.persistedQuoteFilesByBucket();
          expect(
            byBucket[bucket] ?? const <String>[],
            hasLength(greaterThan(1)),
            reason: '$bucket must reproduce the same defect',
          );
        } finally {
          await scoped.delete(recursive: true);
        }
      }
    });

    test('two concurrent same-bucket scans lose a scanned line', () async {
      final app = RoutingHarness(dir: dir);
      await app.scan('everyday-1', 'every_day');
      await app.saveQuote();

      await Future.wait([
        app.scan('toys-1', 'summer_toys'),
        app.scan('toys-2', 'summer_toys'),
      ]);
      await app.saveQuote();

      final persisted = <String>[];
      for (final ids in (await app.persistedQuoteFilesByBucket()).values) {
        for (final id in ids) {
          final payload = await app.readPayload(id);
          persisted.addAll(
            (payload!['lines'] as List).map((l) => (l as Map)['item'].toString()),
          );
        }
      }
      // startNewQuote() clears the workspace, so an interleaved create discards
      // the line the other path had already added.
      expect(persisted, isNot(containsAll(['toys-1', 'toys-2'])));
    });
  });

  group('fixed — routing through QuoteRoutingGate', () {
    RoutingHarness gated() => RoutingHarness(dir: dir, gate: QuoteRoutingGate());

    test('unsaved workspace + two concurrent routes away keeps one quote', () async {
      final app = gated();
      await app.scan('toys-1', 'summer_toys');

      await Future.wait([
        app.ensureRoutingForProduct('christmas'),
        app.ensureRoutingForProduct('every_day'),
      ]);

      final byBucket = await app.persistedQuoteFilesByBucket();
      expect(byBucket['summer_toys'], hasLength(1));
      expect(app.mintedIds.toSet(), hasLength(1));
    });

    test('two concurrent same-bucket scans keep one quote and both lines', () async {
      final app = gated();
      await app.scan('everyday-1', 'every_day');
      await app.saveQuote();

      await Future.wait([
        app.scan('toys-1', 'summer_toys'),
        app.scan('toys-2', 'summer_toys'),
      ]);
      await app.saveQuote();

      final byBucket = await app.persistedQuoteFilesByBucket();
      expect(byBucket['summer_toys'], hasLength(1));
      expect(app.orderItems, containsAll(['toys-1', 'toys-2']));
    });

    test('every affected Product Type stays single under the same race', () async {
      for (final bucket in [
        'every_day',
        'giftcraft',
        'christmas',
        'harvest',
        'halloween',
        'summer_general',
        'summer_toys',
        'valentines',
        'easter',
      ]) {
        final scoped = await Directory.systemTemp.createTemp('fix_$bucket');
        try {
          final app = RoutingHarness(dir: scoped, gate: QuoteRoutingGate());
          await app.scan('$bucket-1', bucket);
          await Future.wait([
            app.ensureRoutingForProduct('fall_winter'),
            app.ensureRoutingForProduct('christmas'),
            app.ensureRoutingForProduct(bucket),
          ]);
          final byBucket = await app.persistedQuoteFilesByBucket();
          expect(
            byBucket[canonicalQuoteBucketKey(bucket)] ?? const <String>[],
            hasLength(lessThanOrEqualTo(1)),
            reason: '$bucket must never duplicate',
          );
        } finally {
          await scoped.delete(recursive: true);
        }
      }
    });
  });
}

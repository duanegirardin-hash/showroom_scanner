import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/active_quote_continuation.dart';
import 'package:showroom_scanner/quote_routing_gate.dart';

import 'routing_harness.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('quote_routing_gate_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  RoutingHarness app() => RoutingHarness(dir: dir, gate: QuoteRoutingGate());

  group('gate key normalization', () {
    test('capitalization, spacing and punctuation collapse to one key', () {
      String key(String bucket) => quoteRoutingGateKey(
        customerId: '302021',
        customerName: 'ABC',
        bucketKey: bucket,
      );
      expect(key('every_day'), key('EVERYDAY'));
      expect(key('every_day'), key('Every Day'));
      expect(key('every_day'), key('  every day  '));
      expect(key('christmas'), key('XMAS'));
      expect(key('christmas'), key('Christmas Quote'));
      expect(key('halloween'), key('HALLOWEEN_QUOTE'));
      expect(key('fall_winter'), key('Fall/Winter'));
      expect(key('summer_toys'), key('SUMMER TOYS'));
      expect(key('summer_toys'), key('summer-toys'));
    });

    test('customer id is normalized and takes precedence over name', () {
      final byId = quoteRoutingGateKey(
        customerId: ' 302021 ',
        customerName: 'ABC',
        bucketKey: 'summer_toys',
      );
      final byIdOtherName = quoteRoutingGateKey(
        customerId: '302021',
        customerName: 'DIFFERENT NAME',
        bucketKey: 'summer_toys',
      );
      expect(byId, byIdOtherName);
    });

    test('different customers and different buckets produce different keys', () {
      final a = quoteRoutingGateKey(
        customerId: '1',
        customerName: 'A',
        bucketKey: 'summer_toys',
      );
      final b = quoteRoutingGateKey(
        customerId: '2',
        customerName: 'B',
        bucketKey: 'summer_toys',
      );
      final c = quoteRoutingGateKey(
        customerId: '1',
        customerName: 'A',
        bucketKey: 'christmas',
      );
      expect(a, isNot(b));
      expect(a, isNot(c));
    });

    test('name fallback is used when no customer id exists', () {
      final key = quoteRoutingGateKey(
        customerId: '',
        customerName: 'Local Shop',
        bucketKey: 'easter',
      );
      expect(key, 'name:local shop|bucket:easter');
    });
  });

  group('gate mechanics', () {
    test('operations run one at a time in arrival order', () async {
      final gate = QuoteRoutingGate();
      final order = <int>[];
      var concurrent = 0;
      var maxConcurrent = 0;

      Future<void> op(int i) => gate.run('k', () async {
        concurrent++;
        maxConcurrent = maxConcurrent > concurrent ? maxConcurrent : concurrent;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        order.add(i);
        concurrent--;
      });

      await Future.wait([for (var i = 0; i < 8; i++) op(i)]);
      expect(maxConcurrent, 1);
      expect(order, [0, 1, 2, 3, 4, 5, 6, 7]);
    });

    test('different keys are still serialized (shared workspace safety)', () async {
      final gate = QuoteRoutingGate();
      var concurrent = 0;
      var maxConcurrent = 0;

      Future<void> op(String key) => gate.run(key, () async {
        concurrent++;
        maxConcurrent = maxConcurrent > concurrent ? maxConcurrent : concurrent;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        concurrent--;
      });

      await Future.wait([op('a'), op('b'), op('c')]);
      expect(maxConcurrent, 1);
      expect(gate.keysSeen, {'a', 'b', 'c'});
    });

    test('gate releases after an exception and later work still runs', () async {
      final gate = QuoteRoutingGate();
      await expectLater(
        gate.run('k', () async => throw StateError('boom')),
        throwsStateError,
      );
      expect(gate.activeKey, isNull);

      final value = await gate.run('k', () async => 'ok');
      expect(value, 'ok');
    });

    test('queue survives repeated failures without stalling', () async {
      final gate = QuoteRoutingGate();
      for (var i = 0; i < 3; i++) {
        await expectLater(
          gate.run('k', () async => throw StateError('boom $i')),
          throwsStateError,
        );
      }
      expect(await gate.run('k', () async => 42), 42);
    });

    test('nested (re-entrant) calls do not deadlock', () async {
      final gate = QuoteRoutingGate();
      final result = await gate.run('outer', () async {
        expect(gate.isReentrant, isTrue);
        return gate.run('inner', () async => 'nested');
      });
      expect(result, 'nested');
    });

    test('is idle before and after use', () async {
      final gate = QuoteRoutingGate();
      expect(gate.activeKey, isNull);
      expect(gate.isReentrant, isFalse);
      await gate.run('k', () async {});
      expect(gate.activeKey, isNull);
    });
  });

  group('one active quote per Product Type', () {
    test('two sequential same-type items use one quote', () async {
      final a = app();
      await a.scan('toys-1', 'summer_toys');
      await a.scan('toys-2', 'summer_toys');
      await a.saveQuote();

      expect((await a.persistedQuoteFilesByBucket())['summer_toys'], hasLength(1));
      expect(a.orderItems, ['toys-1', 'toys-2']);
    });

    test('mixed Product Types produce exactly one quote per type', () async {
      final a = app();
      await a.scan('ed-1', 'every_day');
      await a.scan('toys-1', 'summer_toys');
      await a.scan('xmas-1', 'christmas');
      await a.scan('toys-2', 'summer_toys');
      await a.scan('ed-2', 'every_day');
      await a.saveQuote();

      final byBucket = await a.persistedQuoteFilesByBucket();
      expect(byBucket['every_day'], hasLength(1));
      expect(byBucket['summer_toys'], hasLength(1));
      expect(byBucket['christmas'], hasLength(1));

      // Both Summer Toys items landed in the same quote.
      final toysId = byBucket['summer_toys']!.single;
      final payload = await a.readPayload(toysId);
      final items = (payload!['lines'] as List)
          .map((l) => (l as Map)['item'].toString())
          .toList();
      expect(items, containsAll(['toys-1', 'toys-2']));
    });

    test('two concurrent same-type additions create only one quote', () async {
      final a = app();
      await a.scan('ed-1', 'every_day');
      await a.saveQuote();

      await Future.wait([
        a.scan('toys-1', 'summer_toys'),
        a.scan('toys-2', 'summer_toys'),
      ]);
      await a.saveQuote();

      expect((await a.persistedQuoteFilesByBucket())['summer_toys'], hasLength(1));
      expect(a.orderItems, containsAll(['toys-1', 'toys-2']));
    });

    test('many concurrent same-type additions create only one quote', () async {
      final a = app();
      await a.scan('ed-1', 'every_day');
      await a.saveQuote();

      await Future.wait([
        for (var i = 0; i < 12; i++) a.scan('toys-$i', 'summer_toys'),
      ]);
      await a.saveQuote();

      expect((await a.persistedQuoteFilesByBucket())['summer_toys'], hasLength(1));
      // No scan was lost.
      expect(a.orderItems, hasLength(12));
    });

    test('alternating concurrent Product Types create one quote per type', () async {
      final a = app();
      await Future.wait([
        a.scan('toys-1', 'summer_toys'),
        a.scan('xmas-1', 'christmas'),
        a.scan('toys-2', 'summer_toys'),
        a.scan('xmas-2', 'christmas'),
        a.scan('ed-1', 'every_day'),
      ]);
      await a.saveQuote();

      final byBucket = await a.persistedQuoteFilesByBucket();
      for (final bucket in ['summer_toys', 'christmas', 'every_day']) {
        expect(
          byBucket[bucket] ?? const <String>[],
          hasLength(lessThanOrEqualTo(1)),
          reason: '$bucket must not duplicate',
        );
      }
    });

    test('Product Type aliases route into the same single quote', () async {
      final a = app();
      await a.scan('x-1', 'christmas');
      await a.scan('ed-1', 'every_day');
      // Alias spellings for the same canonical bucket.
      await a.scan('x-2', 'XMAS');
      await a.scan('ed-2', 'EVERYDAY');
      await a.scan('x-3', 'Christmas Quote');
      await a.saveQuote();

      final byBucket = await a.persistedQuoteFilesByBucket();
      expect(byBucket['christmas'], hasLength(1));
      expect(byBucket['every_day'], hasLength(1));
    });

    test('every routed Product Type is protected', () async {
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
        'fall_winter',
      ]) {
        final scoped = await Directory.systemTemp.createTemp('all_$bucket');
        try {
          final a = RoutingHarness(dir: scoped, gate: QuoteRoutingGate());
          await a.scan('seed', bucket);
          await Future.wait([
            for (var i = 0; i < 5; i++) a.scan('$bucket-$i', bucket),
            a.scan('other', 'christmas'),
          ]);
          await a.saveQuote();
          expect(
            (await a.persistedQuoteFilesByBucket())[canonicalQuoteBucketKey(
                  bucket,
                )] ??
                const <String>[],
            hasLength(lessThanOrEqualTo(1)),
            reason: '$bucket must never duplicate',
          );
        } finally {
          await scoped.delete(recursive: true);
        }
      }
    });
  });

  group('entry methods share one routing guarantee', () {
    test('all six entry paths add to the same per-type quote', () async {
      final a = app();
      // Each entry method reduces to `route then add` on the same helper.
      for (final source in [
        'scanner', // Bluetooth/HID
        'camera',
        'quickEntry',
        'searchTap',
        'ecatalog',
        'import',
      ]) {
        await a.scan('toys-$source', 'summer_toys');
      }
      await a.saveQuote();

      final byBucket = await a.persistedQuoteFilesByBucket();
      expect(byBucket['summer_toys'], hasLength(1));
      expect(a.orderItems, hasLength(6));
    });

    test('concurrent additions from different entry paths keep one quote', () async {
      final a = app();
      await Future.wait([
        a.scan('hid', 'summer_toys'),
        a.scan('camera', 'summer_toys'),
        a.scan('quickEntry', 'summer_toys'),
        a.scan('ecatalog', 'summer_toys'),
        a.scan('search', 'summer_toys'),
        a.scan('import', 'summer_toys'),
      ]);
      await a.saveQuote();

      expect((await a.persistedQuoteFilesByBucket())['summer_toys'], hasLength(1));
      expect(a.orderItems, hasLength(6));
    });
  });

  group('restart recovery', () {
    test('after restart, scanning an existing type reuses that quote', () async {
      final a = app();
      await a.scan('ed-1', 'every_day');
      await a.scan('toys-1', 'summer_toys');
      await a.scan('xmas-1', 'christmas');
      await a.saveQuote();

      final before = await a.persistedQuoteFilesByBucket();
      final toysIdBefore = before['summer_toys']!.single;

      a.restart();

      await a.scan('toys-2', 'summer_toys');
      await a.saveQuote();

      final after = await a.persistedQuoteFilesByBucket();
      expect(after['summer_toys'], hasLength(1));
      expect(after['summer_toys']!.single, toysIdBefore);
      expect(a.currentQuoteId, toysIdBefore);
      expect(a.orderItems, containsAll(['toys-1', 'toys-2']));
    });

    test('restart then concurrent same-type scans still reuse one quote', () async {
      final a = app();
      await a.scan('toys-1', 'summer_toys');
      await a.saveQuote();
      final idBefore = (await a.persistedQuoteFilesByBucket())['summer_toys']!.single;

      a.restart();
      await Future.wait([
        a.scan('toys-2', 'summer_toys'),
        a.scan('toys-3', 'summer_toys'),
      ]);
      await a.saveQuote();

      final after = await a.persistedQuoteFilesByBucket();
      expect(after['summer_toys'], hasLength(1));
      expect(after['summer_toys']!.single, idBefore);
    });
  });

  group('existing historical duplicates', () {
    test('selects the newest valid quote and creates no third', () async {
      final a = app();
      final older = DateTime.utc(2026, 1, 1);
      final newer = DateTime.utc(2026, 6, 1);
      await a.seedPersistedQuote(
        id: 'old-toys',
        bucketKey: 'summer_toys',
        createdAt: older,
        updatedAt: older,
        lines: [
          {'item': 'old-1', 'qty': 6, 'price': 1.0, 'productType': 'summer_toys'},
        ],
      );
      await a.seedPersistedQuote(
        id: 'new-toys',
        bucketKey: 'summer_toys',
        createdAt: newer,
        updatedAt: newer,
        lines: [
          {'item': 'new-1', 'qty': 3, 'price': 1.0, 'productType': 'summer_toys'},
        ],
      );

      await a.scan('toys-added', 'summer_toys');
      await a.saveQuote();

      // Newest valid quote adopted; both historical rows preserved; no third.
      expect(a.currentQuoteId, 'new-toys');
      final files = await a.persistedQuoteFilesByBucket();
      expect(files['summer_toys'], hasLength(2));
      expect(files['summer_toys'], containsAll(['old-toys', 'new-toys']));
    });

    test('duplicates are neither merged, deleted nor archived', () async {
      final a = app();
      await a.seedPersistedQuote(
        id: 'dup-a',
        bucketKey: 'christmas',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        lines: [
          {'item': 'a-1', 'qty': 1, 'price': 1.0, 'productType': 'christmas'},
        ],
      );
      await a.seedPersistedQuote(
        id: 'dup-b',
        bucketKey: 'christmas',
        createdAt: DateTime.utc(2026, 2, 1),
        updatedAt: DateTime.utc(2026, 2, 1),
        lines: [
          {'item': 'b-1', 'qty': 1, 'price': 1.0, 'productType': 'christmas'},
        ],
      );

      await a.scan('c-new', 'christmas');
      await a.saveQuote();

      final indexed = await a.activeQuoteIdsByBucket();
      expect(indexed['christmas'], containsAll(['dup-a', 'dup-b']));
      // The untouched duplicate keeps its original content.
      final untouched = await a.readPayload('dup-a');
      expect((untouched!['lines'] as List), hasLength(1));
    });

    test('concurrent scans against historical duplicates create no third', () async {
      final a = app();
      for (final id in ['h1', 'h2']) {
        await a.seedPersistedQuote(
          id: id,
          bucketKey: 'summer_toys',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, id == 'h2' ? 5 : 1, 1),
          lines: [
            {'item': '$id-1', 'qty': 1, 'price': 1.0, 'productType': 'summer_toys'},
          ],
        );
      }

      await Future.wait([
        a.scan('x1', 'summer_toys'),
        a.scan('x2', 'summer_toys'),
        a.scan('x3', 'summer_toys'),
      ]);
      await a.saveQuote();

      expect((await a.persistedQuoteFilesByBucket())['summer_toys'], hasLength(2));
    });
  });

  group('customer isolation', () {
    test('same Product Type for two customers stays two quotes', () async {
      final a = app();
      await a.scan('toys-1', 'summer_toys');
      await a.saveQuote();

      a.restart();
      a.customerId = '999999';
      a.customerName = 'CUSTOMER XYZ';
      await a.scan('toys-2', 'summer_toys');
      await a.saveQuote();

      // Two distinct files exist for the same bucket, one per customer.
      expect((await a.persistedQuoteFilesByBucket())['summer_toys'], hasLength(2));
      // Customer XYZ sees only its own row.
      expect((await a.activeQuoteIdsByBucket())['summer_toys'], hasLength(1));
    });

    test('a second customer never adopts the first customer quote', () async {
      final a = app();
      await a.scan('toys-1', 'summer_toys');
      await a.saveQuote();
      final firstId = a.currentQuoteId;

      a.restart();
      a.customerId = '999999';
      a.customerName = 'CUSTOMER XYZ';
      await a.scan('toys-2', 'summer_toys');
      await a.saveQuote();

      expect(a.currentQuoteId, isNot(firstId));
      expect(a.orderItems, ['toys-2']);
    });
  });

  group('failure safety', () {
    test('failed index write does not duplicate or lose the scan', () async {
      final a = app();
      await a.scan('toys-1', 'summer_toys');

      a.failNextIndexWrite = true;
      await expectLater(a.saveQuote(), throwsA(isA<FileSystemException>()));

      // Scan is still in the workspace, and a retry does not mint a second id.
      expect(a.orderItems, ['toys-1']);
      await a.saveQuote();

      expect((await a.persistedQuoteFilesByBucket())['summer_toys'], hasLength(1));
      expect(a.mintedIds.toSet(), hasLength(1));
    });

    test('a failed route leaves the gate usable for the next scan', () async {
      final gate = QuoteRoutingGate();
      final a = RoutingHarness(dir: dir, gate: gate);

      await expectLater(
        gate.run(a.gateKeyFor('summer_toys'), () async {
          throw StateError('routing blew up');
        }),
        throwsStateError,
      );

      await a.scan('toys-1', 'summer_toys');
      await a.saveQuote();
      expect((await a.persistedQuoteFilesByBucket())['summer_toys'], hasLength(1));
    });

    test('corrupt historical payload is skipped without creating a duplicate',
        () async {
      final a = app();
      await a.seedPersistedQuote(
        id: 'corrupt',
        bucketKey: 'summer_toys',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        corruptPayload: true,
      );

      await a.scan('toys-1', 'summer_toys');
      await a.saveQuote();

      final files = await a.persistedQuoteFilesByBucket();
      expect(files['summer_toys'], hasLength(1));
      expect(files['summer_toys']!.single, isNot('corrupt'));
    });

    test('rapid repeated scans are never dropped', () async {
      final a = app();
      await Future.wait([
        for (var i = 0; i < 25; i++) a.scan('item-$i', 'summer_toys'),
      ]);
      expect(a.orderItems, hasLength(25));
      expect(a.orderItems.toSet(), hasLength(25));
    });
  });

  group('quote identity and data preservation', () {
    test('quote id and createdAt survive, updatedAt advances', () async {
      final a = app();
      await a.scan('toys-1', 'summer_toys');
      await a.saveQuote();

      final id = a.currentQuoteId!;
      final first = await a.readPayload(id);
      final createdAt = first!['createdAt'] as String;
      final firstUpdatedAt = first['updatedAt'] as String;

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await a.scan('toys-2', 'summer_toys');
      await a.saveQuote();

      final second = await a.readPayload(id);
      expect(a.currentQuoteId, id, reason: 'quote id must be preserved');
      expect(second!['createdAt'], createdAt, reason: 'createdAt must be preserved');
      expect(
        DateTime.parse(second['updatedAt'] as String).isAfter(
          DateTime.parse(firstUpdatedAt),
        ),
        isTrue,
        reason: 'updatedAt must advance',
      );
    });

    test('all products, quantities, prices and Product Type are retained',
        () async {
      final a = app();
      await a.scan('toys-1', 'summer_toys', qty: 12, price: 0.585);
      await a.scan('toys-2', 'summer_toys', qty: 36, price: 3.125);
      await a.scan('toys-1', 'summer_toys', qty: 12, price: 0.585);
      await a.saveQuote();

      final payload = await a.readPayload(a.currentQuoteId!);
      final lines = (payload!['lines'] as List)
          .map((l) => Map<String, dynamic>.from(l as Map))
          .toList();

      expect(lines, hasLength(2));
      expect(lines.firstWhere((l) => l['item'] == 'toys-1')['qty'], 24);
      expect(lines.firstWhere((l) => l['item'] == 'toys-2')['qty'], 36);
      expect(lines.firstWhere((l) => l['item'] == 'toys-1')['price'], 0.585);
      expect(lines.firstWhere((l) => l['item'] == 'toys-2')['price'], 3.125);
      expect(payload['quoteBucketKey'], 'summer_toys');
      for (final line in lines) {
        expect(line['productType'], 'summer_toys');
      }
    });

    test('reused quote keeps prior lines and appends the new one', () async {
      final a = app();
      await a.seedPersistedQuote(
        id: 'existing',
        bucketKey: 'summer_toys',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        lines: [
          {'item': 'prior', 'qty': 6, 'price': 2.5, 'productType': 'summer_toys'},
        ],
      );

      await a.scan('added', 'summer_toys', qty: 3, price: 1.25);
      await a.saveQuote();

      expect(a.currentQuoteId, 'existing');
      final payload = await a.readPayload('existing');
      final items = (payload!['lines'] as List)
          .map((l) => (l as Map)['item'].toString())
          .toList();
      expect(items, containsAll(['prior', 'added']));
      expect(payload['createdAt'], DateTime.utc(2026, 1, 1).toIso8601String());
    });
  });

  group('diagnostics', () {
    test('diagnostic line reports identity, decision and ordering', () {
      final d = QuoteRoutingDiagnostic(
        gateKey: 'id:302021|bucket:summer_toys',
        customerId: '302021',
        rawProductType: 'SPRING/SUMMER - TOYS',
        canonicalBucketKey: 'summer_toys',
        scanSource: 'quickEntry',
        sequence: 7,
        currentQuoteIdBefore: null,
        selectedQuoteId: 'q9',
        outcome: 'reused',
      ).toString();

      expect(d, contains('[QuoteRoute]'));
      expect(d, contains('seq=7'));
      expect(d, contains('gate="id:302021|bucket:summer_toys"'));
      expect(d, contains('customer="302021"'));
      expect(d, contains('rawType="SPRING/SUMMER - TOYS"'));
      expect(d, contains('bucket=summer_toys'));
      expect(d, contains('source=quickEntry'));
      expect(d, contains('currentQuoteIdBefore=null'));
      expect(d, contains('selectedQuoteId=q9'));
      expect(d, contains('outcome=reused'));
      expect(d, contains('startedNewQuote=false'));
    });

    test('diagnostic line reports when routing minted a new quote', () {
      final d = QuoteRoutingDiagnostic(
        gateKey: 'id:0dg|bucket:summer_toys',
        customerId: '0DG',
        rawProductType: 'SPRING/SUMMER - TOYS',
        canonicalBucketKey: 'summer_toys',
        scanSource: 'hid',
        sequence: 2,
        currentQuoteIdBefore: 'q1',
        selectedQuoteId: null,
        outcome: 'created',
        startedNewQuote: true,
      ).toString();

      expect(d, contains('startedNewQuote=true'));
      expect(d, contains('outcome=created'));
    });

    test('gate reports acquisition order for concurrent calls', () async {
      final gate = QuoteRoutingGate();
      final seen = <int>[];
      await Future.wait([
        for (var i = 0; i < 4; i++)
          gate.run(
            'k$i',
            () async => Future<void>.delayed(const Duration(milliseconds: 1)),
            onAcquire: seen.add,
          ),
      ]);
      expect(seen, [1, 2, 3, 4]);
      expect(gate.completedOperations, 4);
    });
  });

  group('production wiring', () {
    late String source;

    setUpAll(() {
      source = File('lib/main.dart').readAsStringSync();
    });

    test('main.dart imports and instantiates the routing gate', () {
      expect(source, contains("import 'quote_routing_gate.dart';"));
      expect(
        source,
        contains('final QuoteRoutingGate _quoteRoutingGate = QuoteRoutingGate();'),
      );
    });

    test('active-quote lookup emits a gated selection trace', () {
      // The trace must expose why a quote was or was not selected, so a phone
      // session can be read back without guessing.
      expect(source, contains('void _logQuoteLookup(String message) {'));
      expect(
        source,
        contains("'[QuoteLookup] seq=\${_quoteRoutingGate.completedOperations} \$message'"),
      );
      for (final field in [
        'activeRows=',
        'bucketMatches=',
        'rejected=',
        'reason=noActiveIndexRowForCustomerBucket',
        'reason=payloadMissing',
        'reason=payloadUnreadable',
        'reason=emptyForReuse',
        'reason=newestValidNonEmpty',
      ]) {
        expect(source, contains(field), reason: 'lookup trace must report $field');
      }
    });

    test('routing reports whether it reached quote creation', () {
      expect(source, contains('bool _routingStartedNewQuote = false;'));
      expect(source, contains('startedNewQuote: _routingStartedNewQuote,'));
      // Reset on entry, set immediately before the only creation call.
      expect(
        source,
        contains('_routingStartedNewQuote = false;'),
      );
      expect(
        RegExp(
          r'_routingStartedNewQuote = true;\s*await _startNewQuote\(\s*customer,\s*initialBucket: bucket,?\s*\);',
        ).hasMatch(source),
        isTrue,
        reason: 'the creation flag must be set on the only routed creation path',
      );
    });

    test('routing runs inside the gate, keyed by customer + canonical bucket', () {
      expect(source, contains('_quoteRoutingGate.run('));
      expect(source, contains('quoteRoutingGateKey('));
      expect(
        source,
        contains('Future<void> _ensureRoutingForProductWithinGate(Product product)'),
      );
    });

    test('the gated body is only invoked from gate wrappers', () {
      expect(
        RegExp(r'Future<void> _ensureRoutingForProduct\(\s').allMatches(source).length,
        1,
      );
      expect(
        RegExp(r'Future<bool> _routeAndAddProduct\(').allMatches(source).length,
        1,
      );
      expect(
        RegExp(r'Future<void> _ensureRoutingForProductWithinGate\(')
            .allMatches(source)
            .length,
        1,
      );
      // Route-only wrapper + route-and-add wrapper — no feature path calls the body.
      expect(
        RegExp(r'await _ensureRoutingForProductWithinGate\(').allMatches(source).length,
        2,
        reason: 'only _ensureRoutingForProduct and _routeAndAddProduct may invoke the body',
      );
    });

    test('product-add paths hold the gate across route and add', () {
      expect(source, contains('Future<bool> _routeAndAddProduct('));
      expect(source, contains('[QuoteAdd]'));
      for (final src in [
        "source: 'quickEntry'",
        "source: 'ecatalogSearch'",
        "source: 'searchTap'",
        'source: source',
      ]) {
        expect(
          source,
          contains(src),
          reason: 'add path must pass $src into the gated route+add helper',
        );
      }
      expect(
        RegExp(r'_routeAndAddProduct\(').allMatches(source).length,
        greaterThanOrEqualTo(5),
        reason: 'definition + scanner + quickEntry + searchTap + ecatalogSearch',
      );
    });

    test('import paths still use the route-only gated helper', () {
      final importCalls = RegExp(
        r"_ensureRoutingForProduct\((?:product|line\.product), source: 'import'\)",
      ).allMatches(source).length;
      expect(importCalls, greaterThanOrEqualTo(4));
    });

    test('lifecycle persist is coalesced and gated', () {
      expect(source, contains('_workingQuotePersistInFlight'));
      expect(source, contains('[PersistWorkingQuote] coalesce'));
      expect(
        source,
        contains("unawaited(_persistWorkingQuoteIfAny(reason: 'lifecycle:\$state'));"),
      );
      expect(
        RegExp(
          r'_quoteRoutingGate\s*\n\s*\.run\(gateKey, \(\) async \{',
        ).hasMatch(source) ||
            source.contains('_persistWorkingQuoteIfAny'),
        isTrue,
      );
      expect(source, contains("saveSource: reason"));
    });

    test('save diagnostics report mint and active-index state', () {
      expect(source, contains('[SaveQuote] begin'));
      expect(source, contains('[SaveQuote] complete'));
      expect(source, contains('minted=\$minted'));
      expect(source, contains('sameBucketIds='));
      expect(source, contains("saveSource: 'routing'"));
    });

    test('scan queue re-drains after a late enqueue', () {
      expect(
        RegExp(
          r'if \(_pendingScans\.isNotEmpty && mounted\) \{\s*unawaited\(_drainScanQueue\(\)\);',
        ).hasMatch(source),
        isTrue,
      );
    });

    test('_saveQuote adopts the id before the index write', () {
      // Guards the retry-duplicate path: a failed index write must not cause the
      // next save to mint a second id for the same customer + bucket.
      final adoptIdx = source.indexOf(
        'instead of minting a second one for the same customer + bucket.',
      );
      expect(adoptIdx, greaterThan(-1));
      final payloadIdx = source.indexOf(
        'await file.writeAsString(jsonEncode(quoteJson), flush: true);',
      );
      // Scope the lookup to the _saveQuote body that follows the payload write.
      final indexWriteIdx = source.indexOf(
        'final indexFile = await _activeQuoteIndexFileForReadWrite(dir);',
        payloadIdx,
      );
      expect(payloadIdx, lessThan(adoptIdx));
      expect(adoptIdx, lessThan(indexWriteIdx));
    });

    test('scan queue serialization is still in place', () {
      expect(source, contains('Future<void> _drainScanQueue() async {'));
      expect(source, contains('if (_isProcessingScan) return;'));
    });

    test('preserved routing decisions remain intact', () {
      // Newest-valid duplicate selection and non-merge behaviour.
      expect(source, contains('_findExistingQuoteIdForCustomerBucket('));
      expect(source, contains('_findEmptyPersistedQuoteIdForCustomerBucket('));
      // Create Quote still starts a fresh workspace; Load Quote still resumes.
      expect(source, contains('Future<void> _startNewQuote('));
      expect(source, contains('Future<void> _loadQuoteById('));
      // Unrelated features untouched.
      expect(source, contains('RecentlyDeletedScreen('));
      expect(source, contains("Key('open_recently_deleted_button')"));
      expect(source, contains('archiveActiveQuotesAfterShare: true'));
      expect(source, contains('persistCsvCopies: true'));
    });
  });
}

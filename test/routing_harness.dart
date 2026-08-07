import 'dart:convert';
import 'dart:io';

import 'package:showroom_scanner/active_quote_continuation.dart';
import 'package:showroom_scanner/quote_routing_gate.dart';

/// Faithful model of the production quote-routing algorithm in `lib/main.dart`.
///
/// Mirrors, step for step and suspension point for suspension point:
///   * `_ensureRoutingForProduct`              (main.dart ~6007)
///   * `_findExistingQuoteIdForCustomerBucket` (main.dart ~5771)
///   * `_startNewQuote`                        (main.dart ~11103) — no persistence
///   * `_saveQuote`                            (main.dart ~13994) — mints the id
///   * `_loadQuoteById`                        (main.dart ~16687)
///
/// The model exists so the duplicate-quote race can be reproduced and regression
/// tested without booting the full scanner UI. [gate] is null to reproduce the
/// historical unguarded behaviour and set to exercise the fix.
class RoutingHarness {
  RoutingHarness({required this.dir, this.gate});

  final Directory dir;
  final QuoteRoutingGate? gate;

  String customerId = '302021';
  String customerName = 'CUSTOMER ABC';

  String activeBucketKey = 'every_day';
  String? currentQuoteId;

  /// Working order lines: `{item, qty, price, productType}`.
  final List<Map<String, dynamic>> orderLines = <Map<String, dynamic>>[];

  int _idSeed = 0;
  int created = 0;
  int reused = 0;
  final List<String> trace = <String>[];
  final List<String> mintedIds = <String>[];

  /// Set to throw inside the next [saveQuote] after the payload is written.
  bool failNextIndexWrite = false;

  List<String> get orderItems =>
      orderLines.map((l) => l['item'].toString()).toList();

  int qtyOf(String item) =>
      orderLines.firstWhere(
            (l) => l['item'] == item,
            orElse: () => const {'qty': 0},
          )['qty']
          as int;

  File get _indexFile => File('${dir.path}/quotes_active.json');

  Future<List<Map<String, dynamic>>> _loadIndex() async {
    if (!await _indexFile.exists()) return [];
    final decoded = jsonDecode(await _indexFile.readAsString());
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _writeIndex(List<Map<String, dynamic>> rows) =>
      _indexFile.writeAsString(jsonEncode(rows), flush: true);

  Future<Map<String, dynamic>?> readPayload(String id) async {
    final f = File('${dir.path}/quote_$id.json');
    if (!await f.exists()) return null;
    try {
      return Map<String, dynamic>.from(
        jsonDecode(await f.readAsString()) as Map,
      );
    } catch (_) {
      return null;
    }
  }

  /// Seeds a persisted active quote (historical data / restart fixtures).
  Future<void> seedPersistedQuote({
    required String id,
    required String bucketKey,
    required DateTime createdAt,
    required DateTime updatedAt,
    List<Map<String, dynamic>> lines = const [],
    String status = 'active',
    String? customerIdOverride,
    bool corruptPayload = false,
  }) async {
    final file = File('${dir.path}/quote_$id.json');
    if (corruptPayload) {
      await file.writeAsString('{not valid json', flush: true);
    } else {
      await file.writeAsString(
        jsonEncode({
          'id': id,
          'createdAt': createdAt.toUtc().toIso8601String(),
          'updatedAt': updatedAt.toUtc().toIso8601String(),
          'quoteBucketKey': canonicalQuoteBucketKey(bucketKey),
          'lines': lines,
        }),
        flush: true,
      );
    }
    final rows = await _loadIndex();
    rows.insert(0, {
      'id': id,
      'customerId': customerIdOverride ?? customerId,
      'customerName': customerName,
      'quoteBucketKey': canonicalQuoteBucketKey(bucketKey),
      'quoteStatus': status,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    });
    await _writeIndex(rows);
  }

  /// Mirrors `_findExistingQuoteIdForCustomerBucket`: index scan, per-row payload
  /// read, non-empty quotes preferred over empty starters, newest first.
  Future<String?> findExistingQuoteId(String bucketKey) async {
    final sought = canonicalQuoteBucketKey(bucketKey);
    final rows = await _loadIndex();
    final matches = <Map<String, dynamic>>[];
    for (final row in rows) {
      if ((row['quoteStatus'] ?? 'active') != 'active') continue;
      if (!persistedQuoteCustomerMatches(
        soughtCustomerId: customerId,
        soughtCustomerName: customerName,
        indexRow: row,
      )) {
        continue;
      }
      if (canonicalQuoteBucketKey((row['quoteBucketKey'] ?? '').toString()) !=
          sought) {
        continue;
      }
      matches.add(row);
    }
    if (matches.isEmpty) return null;

    matches.sort((a, b) {
      final au =
          DateTime.tryParse((a['updatedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final bu =
          DateTime.tryParse((b['updatedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final byUpdated = bu.compareTo(au);
      if (byUpdated != 0) return byUpdated;
      return b['id'].toString().compareTo(a['id'].toString());
    });

    for (final row in matches) {
      final id = row['id'].toString();
      final payload = await readPayload(id);
      if (payload != null && (payload['lines'] as List).isNotEmpty) return id;
    }
    for (final row in matches) {
      final id = row['id'].toString();
      final payload = await readPayload(id);
      if (payload != null && (payload['lines'] as List).isEmpty) return id;
    }
    return null;
  }

  /// Mirrors `_startNewQuote`: clears the workspace, drops the id, persists
  /// nothing. The quote only reaches disk on a later [saveQuote].
  Future<void> startNewQuote(String bucketKey) async {
    await Future<void>.delayed(Duration.zero);
    orderLines.clear();
    currentQuoteId = null;
    activeBucketKey = bucketKey;
    created++;
  }

  /// Mirrors `_loadQuoteById`.
  Future<void> loadQuoteById(String id) async {
    final payload = await readPayload(id);
    if (payload == null) return;
    orderLines
      ..clear()
      ..addAll(
        (payload['lines'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    currentQuoteId = id;
    activeBucketKey = (payload['quoteBucketKey'] ?? 'every_day').toString();
    reused++;
  }

  /// Mirrors `_saveQuote`: the id is minted here, not at creation time, and
  /// `createdAt` is preserved from any existing payload.
  Future<void> saveQuote() async {
    if (orderLines.isEmpty && currentQuoteId == null) return;
    final id = currentQuoteId ?? 'q${++_idSeed}';
    mintedIds.add(id);
    final now = DateTime.now().toUtc();
    final existing = await readPayload(id);
    await File('${dir.path}/quote_$id.json').writeAsString(
      jsonEncode({
        'id': id,
        'createdAt': existing?['createdAt'] ?? now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'quoteBucketKey': canonicalQuoteBucketKey(activeBucketKey),
        'lines': orderLines.map((l) => Map<String, dynamic>.from(l)).toList(),
      }),
      flush: true,
    );

    // Mirrors production: the id is adopted as soon as the payload exists, so a
    // failed index write retries against the same id instead of minting another.
    currentQuoteId = id;

    if (failNextIndexWrite) {
      failNextIndexWrite = false;
      throw const FileSystemException('index write failed');
    }

    final rows = await _loadIndex();
    rows.removeWhere((r) => r['id'].toString() == id);
    rows.insert(0, {
      'id': id,
      'customerId': customerId,
      'customerName': customerName,
      'quoteBucketKey': canonicalQuoteBucketKey(activeBucketKey),
      'quoteStatus': 'active',
      'updatedAt': now.toIso8601String(),
    });
    await _writeIndex(rows);
    currentQuoteId = id;
  }

  /// Mirrors the routed body of `_ensureRoutingForProduct`.
  Future<void> _routeBody(String bucketKey) async {
    final targetId = canonicalQuoteBucketKey(bucketKey);
    final activeId = canonicalQuoteBucketKey(activeBucketKey);
    trace.add('enter:$targetId');

    if (activeId == targetId) {
      if (currentQuoteId == null) {
        final existingId = await findExistingQuoteId(activeBucketKey);
        if (existingId != null) await loadQuoteById(existingId);
      }
      trace.add('alreadyOnBucket:$targetId');
      return;
    }

    if (orderLines.isNotEmpty) await saveQuote();

    final existingQuoteId = await findExistingQuoteId(bucketKey);
    if (existingQuoteId != null) {
      await loadQuoteById(existingQuoteId);
      trace.add('reused:$existingQuoteId');
      return;
    }

    await startNewQuote(bucketKey);
    trace.add('created:$targetId');
  }

  String gateKeyFor(String bucketKey) => quoteRoutingGateKey(
    customerId: customerId,
    customerName: customerName,
    bucketKey: bucketKey,
  );

  Future<void> ensureRoutingForProduct(String bucketKey) {
    final g = gate;
    if (g == null) return _routeBody(bucketKey);
    return g.run(gateKeyFor(bucketKey), () => _routeBody(bucketKey));
  }

  /// Mirrors the synchronous `_addProduct` that immediately follows routing.
  void addProduct(String item, {int qty = 1, double price = 1.0, String? productType}) {
    final existing = orderLines.indexWhere((l) => l['item'] == item);
    if (existing >= 0) {
      orderLines[existing]['qty'] = (orderLines[existing]['qty'] as int) + qty;
      return;
    }
    orderLines.add({
      'item': item,
      'qty': qty,
      'price': price,
      'productType': productType ?? activeBucketKey,
    });
  }

  /// One end-to-end add. When [gate] is set, routing *and* [_addProduct] share
  /// one acquisition — matching production [_routeAndAddProduct].
  Future<void> scan(
    String item,
    String bucketKey, {
    int qty = 1,
    double price = 1.0,
  }) async {
    final g = gate;
    if (g == null) {
      await ensureRoutingForProduct(bucketKey);
      addProduct(item, qty: qty, price: price, productType: bucketKey);
      return;
    }
    await g.run(gateKeyFor(bucketKey), () async {
      await _routeBody(bucketKey);
      addProduct(item, qty: qty, price: price, productType: bucketKey);
    });
  }

  /// Models [_persistWorkingQuoteIfAny]: an ungated (or optionally gated)
  /// background save that can fire while routing is in flight.
  Future<void> persistWorkingQuote({bool throughGate = false}) async {
    if (orderLines.isEmpty && currentQuoteId == null) return;
    if (!throughGate || gate == null) {
      await saveQuote();
      return;
    }
    await gate!.run(gateKeyFor(activeBucketKey), saveQuote);
  }

  /// Active index rows grouped by canonical bucket for this customer.
  Future<Map<String, List<String>>> activeQuoteIdsByBucket() async {
    final out = <String, List<String>>{};
    for (final row in await _loadIndex()) {
      if ((row['quoteStatus'] ?? 'active') != 'active') continue;
      if (!persistedQuoteCustomerMatches(
        soughtCustomerId: customerId,
        soughtCustomerName: customerName,
        indexRow: row,
      )) {
        continue;
      }
      final bucket = canonicalQuoteBucketKey(
        (row['quoteBucketKey'] ?? '').toString(),
      );
      out.putIfAbsent(bucket, () => []).add(row['id'].toString());
    }
    return out;
  }

  /// Every persisted quote *file* grouped by canonical bucket. Independent of
  /// index write ordering, so concurrency assertions are deterministic.
  Future<Map<String, List<String>>> persistedQuoteFilesByBucket() async {
    final out = <String, List<String>>{};
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('quote_') || !name.endsWith('.json')) continue;
      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(await entity.readAsString()) as Map,
        );
        final bucket = canonicalQuoteBucketKey(
          (payload['quoteBucketKey'] ?? '').toString(),
        );
        out.putIfAbsent(bucket, () => []).add(payload['id'].toString());
      } catch (_) {}
    }
    return out;
  }

  /// Simulates a cold restart: in-memory workspace is dropped, disk survives.
  void restart() {
    orderLines.clear();
    currentQuoteId = null;
    activeBucketKey = 'every_day';
    created = 0;
    reused = 0;
    trace.clear();
    mintedIds.clear();
  }
}

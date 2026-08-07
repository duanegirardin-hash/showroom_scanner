import 'dart:async';

import 'active_quote_continuation.dart' show canonicalQuoteBucketKey;

/// Stable gate identity for one customer + canonical Product Type bucket.
///
/// Customer id wins when present so renames cannot split a route; the company
/// name is the fallback for locally added customers without an id. The bucket is
/// reduced with [canonicalQuoteBucketKey] so display labels, capitalization,
/// spacing and punctuation aliases all collapse onto one key.
String quoteRoutingGateKey({
  required String customerId,
  required String customerName,
  required String bucketKey,
}) {
  final id = customerId.trim().toLowerCase();
  final name = customerName.trim().toLowerCase();
  final customer = id.isNotEmpty ? 'id:$id' : 'name:$name';
  return '$customer|bucket:${canonicalQuoteBucketKey(bucketKey)}';
}

/// One routing decision, for diagnostics only.
class QuoteRoutingDiagnostic {
  const QuoteRoutingDiagnostic({
    required this.gateKey,
    required this.customerId,
    required this.rawProductType,
    required this.canonicalBucketKey,
    required this.scanSource,
    required this.sequence,
    required this.currentQuoteIdBefore,
    required this.selectedQuoteId,
    required this.outcome,
    this.startedNewQuote = false,
  });

  final String gateKey;
  final String customerId;
  final String rawProductType;
  final String canonicalBucketKey;
  final String scanSource;

  /// Monotonic acquisition order, so concurrent calls can be ordered in a log.
  final int sequence;

  final String? currentQuoteIdBefore;
  final String? selectedQuoteId;

  /// `reused`, `created`, `alreadyOnBucket`, `noCustomer`, or `failed`.
  final String outcome;

  /// True when this route reached quote creation instead of reusing a quote.
  final bool startedNewQuote;

  @override
  String toString() =>
      '[QuoteRoute] seq=$sequence gate="$gateKey" '
      'customer="$customerId" rawType="$rawProductType" '
      'bucket=$canonicalBucketKey source=$scanSource '
      'currentQuoteIdBefore=${currentQuoteIdBefore ?? 'null'} '
      'selectedQuoteId=${selectedQuoteId ?? 'null'} '
      'startedNewQuote=$startedNewQuote '
      'outcome=$outcome';
}

/// Serializes quote route/create/load/save transactions.
///
/// Routing mutates one shared workspace (current quote id, active bucket, order
/// lines), so overlapping routes for *different* buckets corrupt each other just
/// as readily as two routes for the same bucket. The gate therefore runs a single
/// FIFO queue and uses the key for reuse bookkeeping and diagnostics rather than
/// for parallelism.
///
/// Guarantees:
///   * At most one routing operation runs at a time; queued work runs in arrival
///     order, so no scan is dropped.
///   * Re-entrant — an operation already inside the gate runs nested work inline
///     instead of deadlocking on itself.
///   * The queue always advances, including when an operation throws; the caller
///     still receives the error.
class QuoteRoutingGate {
  static final Object _zoneKey = Object();

  Future<void> _tail = Future<void>.value();
  int _sequence = 0;
  String? _activeKey;
  final Set<String> _keysSeen = <String>{};

  /// Key currently holding the gate, or null when idle.
  String? get activeKey => _activeKey;

  /// Acquisition count since construction (diagnostics/tests).
  int get completedOperations => _sequence;

  /// Distinct keys routed since construction (diagnostics/tests).
  Set<String> get keysSeen => Set<String>.unmodifiable(_keysSeen);

  /// True when the caller is already executing inside this gate.
  bool get isReentrant => Zone.current[_zoneKey] == this;

  /// Runs [operation] under the gate for [key].
  ///
  /// [onAcquire] receives the monotonic sequence number once the gate is held,
  /// which lets callers log the true ordering of concurrent requests.
  Future<T> run<T>(
    String key,
    Future<T> Function() operation, {
    void Function(int sequence)? onAcquire,
  }) {
    if (isReentrant) {
      onAcquire?.call(_sequence);
      return operation();
    }

    final completer = Completer<T>();
    _tail = _tail
        .then((_) async {
          final sequence = ++_sequence;
          _activeKey = key;
          _keysSeen.add(key);
          try {
            onAcquire?.call(sequence);
            final value = await runZoned(
              operation,
              zoneValues: <Object, Object>{_zoneKey: this},
            );
            if (!completer.isCompleted) completer.complete(value);
          } catch (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          } finally {
            // Always release, including on error, so later scans still route.
            _activeKey = null;
          }
        })
        .catchError((Object _) {
          // Errors are delivered through [completer]; keep the queue alive.
        });
    return completer.future;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Canonical identity used for persisted quote-bucket matching.
///
/// This mirrors the app's historical aliases while remaining independent of
/// display labels and Product Type assignment.
///
/// General string normalization is applied before alias matching so invisible
/// whitespace and Unicode punctuation cannot split a bucket: leading/trailing
/// whitespace is trimmed, and every run of non-alphanumeric characters — plain
/// spaces, non-breaking spaces (U+00A0), tabs, CR/LF, zero-width characters,
/// hyphens, en/em dashes and slashes — collapses to a single `_`. Stray leading
/// and trailing separators are then stripped, so `"_summer_toys_"`,
/// `"\u200Bsummer toys"` and `"SUMMER TOYS"` all yield `summer_toys`.
String canonicalQuoteBucketKey(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty ||
      value == 'every_day' ||
      value == 'everyday' ||
      value == 'every day' ||
      value.replaceAll('_', ' ').trim() == 'every day' ||
      value == 'everyday_quote' ||
      value == 'every day quote') {
    return 'every_day';
  }
  if (value == 'christmas' ||
      value == 'xmas' ||
      value == 'christmas_quote' ||
      value == 'christmas quote') {
    return 'christmas';
  }
  if (value == 'fall_winter' ||
      value == 'fall/winter' ||
      value == 'fall winter' ||
      value == 'fall-winter') {
    return 'fall_winter';
  }
  if (value == 'halloween' ||
      value == 'halloween_quote' ||
      value == 'halloween quote') {
    return 'halloween';
  }
  final collapsed = value
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  // Punctuation-only input (e.g. "---") collapses to nothing; treat it as blank.
  return collapsed.isEmpty ? 'every_day' : collapsed;
}

bool persistedQuoteCustomerMatches({
  required String soughtCustomerId,
  required String soughtCustomerName,
  required Map<String, dynamic> indexRow,
}) {
  final soughtId = soughtCustomerId.trim().toLowerCase();
  final rowId = (indexRow['customerId'] ?? '').toString().trim().toLowerCase();
  final soughtName = soughtCustomerName.trim().toLowerCase();
  final rowName = (indexRow['customerName'] ?? '')
      .toString()
      .trim()
      .toLowerCase();

  if (soughtId.isNotEmpty && rowId.isNotEmpty) return soughtId == rowId;
  return soughtName.isNotEmpty && soughtName == rowName;
}

bool shouldAttemptPersistedQuoteContinuation({
  required String? currentQuoteId,
  required bool hasWorkingLines,
  required bool explicitFreshQuotePending,
}) {
  return currentQuoteId == null &&
      !hasWorkingLines &&
      !explicitFreshQuotePending;
}

bool _payloadHasLoadableLineShape(Map<String, dynamic> payload) {
  for (final key in [
    'name',
    'createdAt',
    'updatedAt',
    'quoteBucketKey',
    'quoteBucketLabel',
  ]) {
    final value = payload[key];
    if (value != null && value is! String) return false;
  }

  final rawLines = payload['lines'] ?? payload['items'] ?? const <dynamic>[];
  if (rawLines is! List) return false;
  const stringFields = [
    'upc',
    'itemNumber',
    'description',
    'productType',
    'discountRaw',
    'netRaw',
    'psRaw',
    'category',
    'subCategory',
  ];
  const boolFields = [
    'discountEligible',
    'isNet',
    'isPs',
    'isNewRelease',
    'whse1InStock',
    'whse2InStock',
    'whse1OutOfStock',
    'whse2OutOfStock',
    'whse1ComingSoon',
    'whse2ComingSoon',
  ];
  for (final rawLine in rawLines) {
    if (rawLine is! Map) return false;
    final line = Map<String, dynamic>.from(rawLine);
    for (final key in stringFields) {
      final value = line[key];
      if (value != null && value is! String) return false;
    }
    for (final key in boolFields) {
      final value = line[key];
      if (value != null && value is! bool) return false;
    }
    for (final key in ['price', 'listPrice']) {
      final value = line[key];
      if (value != null && value is! num) return false;
    }
    final scans = line['scans'];
    if (scans != null && scans is! int) return false;
  }
  return true;
}

class ActiveQuoteContinuationCandidate {
  const ActiveQuoteContinuationCandidate({
    required this.id,
    required this.updatedAt,
    required this.payload,
  });

  final String id;
  final DateTime updatedAt;
  final Map<String, dynamic> payload;
}

class ActiveQuoteContinuationResult {
  const ActiveQuoteContinuationResult({
    required this.selected,
    required this.validCandidateIds,
    required this.missingPayloadIds,
    required this.corruptPayloadIds,
  });

  final ActiveQuoteContinuationCandidate? selected;
  final List<String> validCandidateIds;
  final List<String> missingPayloadIds;
  final List<String> corruptPayloadIds;
}

/// Selects a valid persisted active quote without mutating any index or payload.
///
/// Matching rows are validated by reading their payload. Multiple valid rows
/// are retained on disk; the newest index/payload timestamp wins, with quote id
/// as a stable descending tie-breaker.
Future<ActiveQuoteContinuationResult> selectActiveQuoteForContinuation({
  required Directory quotesDirectory,
  required Iterable<Map<String, dynamic>> activeIndexRows,
  required Set<String> excludedQuoteIds,
  required String customerId,
  required String customerName,
  required String bucketKey,
}) async {
  final soughtBucket = canonicalQuoteBucketKey(bucketKey);
  final valid = <ActiveQuoteContinuationCandidate>[];
  final missing = <String>[];
  final corrupt = <String>[];

  for (final row in activeIndexRows) {
    final id = (row['id'] ?? '').toString().trim();
    if (id.isEmpty || excludedQuoteIds.contains(id)) continue;
    final status = (row['quoteStatus'] ?? row['status'] ?? 'active')
        .toString()
        .trim()
        .toLowerCase();
    if (status != 'active') continue;
    if (!persistedQuoteCustomerMatches(
      soughtCustomerId: customerId,
      soughtCustomerName: customerName,
      indexRow: row,
    )) {
      continue;
    }

    final file = File('${quotesDirectory.path}/quote_$id.json');
    if (!await file.exists()) {
      missing.add(id);
      continue;
    }

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException('payload is not a map');
      payload = Map<String, dynamic>.from(decoded);
      if (!_payloadHasLoadableLineShape(payload)) {
        throw const FormatException('payload shape is not loadable');
      }
    } catch (_) {
      corrupt.add(id);
      continue;
    }

    final rowBucket = (row['quoteBucketKey'] ?? '').toString().trim();
    final payloadBucket = (payload['quoteBucketKey'] ?? '').toString().trim();
    final candidateBucket = canonicalQuoteBucketKey(
      rowBucket.isNotEmpty ? rowBucket : payloadBucket,
    );
    if (candidateBucket != soughtBucket) continue;

    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final rowUpdatedAt =
        DateTime.tryParse((row['updatedAt'] ?? '').toString()) ?? epoch;
    final payloadUpdatedAt =
        DateTime.tryParse((payload['updatedAt'] ?? '').toString()) ?? epoch;
    final updatedAt = rowUpdatedAt.isAfter(payloadUpdatedAt)
        ? rowUpdatedAt
        : payloadUpdatedAt;
    valid.add(
      ActiveQuoteContinuationCandidate(
        id: id,
        updatedAt: updatedAt,
        payload: payload,
      ),
    );
  }

  valid.sort((a, b) {
    final byUpdated = b.updatedAt.compareTo(a.updatedAt);
    if (byUpdated != 0) return byUpdated;
    return b.id.compareTo(a.id);
  });

  return ActiveQuoteContinuationResult(
    selected: valid.isEmpty ? null : valid.first,
    validCandidateIds: valid.map((candidate) => candidate.id).toList(),
    missingPayloadIds: missing,
    corruptPayloadIds: corrupt,
  );
}

/// Small FIFO coordinator for quote route/load/add/save transactions.
class QuoteOperationCoordinator {
  static final Object _zoneKey = Object();
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    if (Zone.current[_zoneKey] == this) return operation();
    final completer = Completer<T>();
    _tail = _tail
        .then((_) async {
          try {
            completer.complete(
              await runZoned(
                operation,
                zoneValues: <Object, Object>{_zoneKey: this},
              ),
            );
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .catchError((Object _) {
          // Individual callers receive their error through [completer]. Keep the
          // queue alive for subsequent quote operations.
        });
    return completer.future;
  }
}

String _persistedLineIdentity(Map<String, dynamic> line) {
  final upc = (line['upc'] ?? '').toString().trim();
  if (upc.isNotEmpty) return 'upc:$upc';
  final item = (line['itemNumber'] ?? '').toString().trim().toUpperCase();
  return 'item:$item';
}

/// Preserves the original quote timestamp and persisted line data while
/// applying current quantities/scans and newly added lines.
///
/// Existing `price`, `listPrice`, and optional `notes` values are retained for
/// existing lines. Unknown fields are also carried forward for compatibility.
Map<String, dynamic> mergeQuotePayloadForContinuationSave({
  required Map<String, dynamic> generated,
  required Map<String, dynamic>? previous,
}) {
  if (previous == null) return Map<String, dynamic>.from(generated);

  final priorLinesByIdentity = <String, Map<String, dynamic>>{};
  final rawPriorLines = previous['lines'] ?? previous['items'];
  if (rawPriorLines is List) {
    for (final rawLine in rawPriorLines.whereType<Map>()) {
      final line = Map<String, dynamic>.from(rawLine);
      final identity = _persistedLineIdentity(line);
      if (identity != 'item:') priorLinesByIdentity[identity] = line;
    }
  }

  final mergedLines = <Map<String, dynamic>>[];
  final rawGeneratedLines = generated['lines'];
  if (rawGeneratedLines is List) {
    for (final rawLine in rawGeneratedLines.whereType<Map>()) {
      final current = Map<String, dynamic>.from(rawLine);
      final prior = priorLinesByIdentity[_persistedLineIdentity(current)];
      if (prior == null) {
        mergedLines.add(current);
        continue;
      }
      final merged = <String, dynamic>{...prior, ...current};
      for (final protected in ['price', 'listPrice', 'notes']) {
        if (prior.containsKey(protected)) merged[protected] = prior[protected];
      }
      mergedLines.add(merged);
    }
  }

  final merged = <String, dynamic>{
    ...previous,
    ...generated,
    'lines': mergedLines,
  };
  final createdAt = previous['createdAt'];
  if (createdAt is String && createdAt.isNotEmpty) {
    merged['createdAt'] = createdAt;
  }
  return merged;
}

/// Recently Deleted quote index helpers (soft-delete / restore / TTL).
///
/// Keeps [quote_<id>.json] payloads untouched; only index rows move.
library;

import 'dart:convert';
import 'dart:io';

/// Retention window: an order remains until [deletedAt] + 30 days has passed.
const int kDeletedQuoteRetentionDays = 30;

/// True when the deleted record should be permanently removed.
/// Uses exclusive end: retained for the full 30-day period after [deletedAt].
bool isDeletedQuoteExpired(DateTime deletedAt, DateTime now) {
  final deadline = deletedAt.toUtc().add(
    const Duration(days: kDeletedQuoteRetentionDays),
  );
  return now.toUtc().isAfter(deadline);
}

/// Whole days remaining before expiry (0 on the final day while still retained).
int deletedQuoteDaysRemaining(DateTime deletedAt, DateTime now) {
  final deadline = deletedAt.toUtc().add(
    const Duration(days: kDeletedQuoteRetentionDays),
  );
  final secs = deadline.difference(now.toUtc()).inSeconds;
  if (secs <= 0) return 0;
  // Ceiling of remaining seconds into days, then clamp so day 0 means final day.
  final days = (secs + 86399) ~/ 86400;
  return days.clamp(0, kDeletedQuoteRetentionDays);
}

/// Maps stored original status to restore target; invalid → archived.
String resolveRestoreStatus(String? originalStatus) {
  switch ((originalStatus ?? '').trim().toLowerCase()) {
    case 'active':
      return 'active';
    case 'confirmed':
      return 'confirmed';
    case 'archived':
      return 'archived';
    default:
      return 'archived';
  }
}

/// One row in [quotes_deleted.json].
class DeletedQuoteInfo {
  DeletedQuoteInfo({
    required this.quoteId,
    required this.deletedAt,
    required this.originalStatus,
    required this.indexSnapshot,
  });

  final String quoteId;
  final DateTime deletedAt;

  /// `active` | `archived` | `confirmed` (or invalid → restore as archived).
  final String originalStatus;

  /// Full [SavedQuoteInfo]-compatible index map captured at delete time.
  final Map<String, dynamic> indexSnapshot;

  factory DeletedQuoteInfo.fromJson(Map<String, dynamic> json) {
    final id = (json['quoteId'] ?? json['id'] ?? json['index']?['id'] ?? '')
        .toString()
        .trim();
    final deletedAt =
        DateTime.tryParse(json['deletedAt'] as String? ?? '') ?? DateTime.now();
    final original =
        (json['originalStatus'] ?? json['original_status'] ?? 'archived')
            .toString();
    Map<String, dynamic> snap = {};
    final rawIndex = json['index'] ?? json['indexSnapshot'];
    if (rawIndex is Map) {
      snap = Map<String, dynamic>.from(rawIndex);
    } else {
      // Minimal snapshot from top-level fields if present.
      snap = Map<String, dynamic>.from(json)
        ..remove('quoteId')
        ..remove('deletedAt')
        ..remove('originalStatus')
        ..remove('original_status')
        ..remove('index')
        ..remove('indexSnapshot');
      if ((snap['id'] as String?)?.trim().isEmpty ?? true) {
        snap['id'] = id;
      }
    }
    if ((snap['id'] as String?)?.trim().isEmpty ?? true) {
      snap['id'] = id;
    }
    return DeletedQuoteInfo(
      quoteId: id,
      deletedAt: deletedAt,
      originalStatus: original,
      indexSnapshot: snap,
    );
  }

  Map<String, dynamic> toJson() => {
    'quoteId': quoteId,
    'deletedAt': deletedAt.toUtc().toIso8601String(),
    'originalStatus': originalStatus,
    'index': indexSnapshot,
  };

  String get customerName =>
      (indexSnapshot['customerName'] as String?)?.trim() ?? '';
  String get name => (indexSnapshot['name'] as String?)?.trim() ?? '';
}

List<DeletedQuoteInfo> parseDeletedQuoteIndexList(dynamic decoded) {
  if (decoded is! List) return [];
  final out = <DeletedQuoteInfo>[];
  for (final e in decoded) {
    if (e is! Map) continue;
    try {
      final info = DeletedQuoteInfo.fromJson(Map<String, dynamic>.from(e));
      if (info.quoteId.isEmpty) continue;
      out.add(info);
    } catch (_) {}
  }
  return out;
}

List<Map<String, dynamic>> encodeDeletedQuoteIndexList(
  List<DeletedQuoteInfo> entries,
) {
  return entries.map((e) => e.toJson()).toList();
}

/// Upsert by quoteId (newest delete wins).
List<DeletedQuoteInfo> upsertDeletedQuote(
  List<DeletedQuoteInfo> existing,
  DeletedQuoteInfo entry,
) {
  final out = existing.where((e) => e.quoteId != entry.quoteId).toList();
  out.insert(0, entry);
  return out;
}

List<DeletedQuoteInfo> removeDeletedQuoteById(
  List<DeletedQuoteInfo> existing,
  String quoteId,
) {
  return existing.where((e) => e.quoteId != quoteId).toList();
}

/// Split expired vs retained.
({List<DeletedQuoteInfo> retained, List<DeletedQuoteInfo> expired})
partitionExpiredDeletedQuotes({
  required List<DeletedQuoteInfo> entries,
  required DateTime now,
}) {
  final retained = <DeletedQuoteInfo>[];
  final expired = <DeletedQuoteInfo>[];
  for (final e in entries) {
    if (isDeletedQuoteExpired(e.deletedAt, now)) {
      expired.add(e);
    } else {
      retained.add(e);
    }
  }
  return (retained: retained, expired: expired);
}

/// Remove [quoteId] from a decoded index list (active or archive).
List<Map<String, dynamic>> removeIdFromIndexMaps(
  List<Map<String, dynamic>> list,
  String quoteId,
) {
  return list.where((e) => e['id']?.toString() != quoteId).toList();
}

/// Insert/replace index row at front; prevents duplicate ids.
List<Map<String, dynamic>> upsertIndexMapRow(
  List<Map<String, dynamic>> list,
  Map<String, dynamic> row,
) {
  final id = row['id']?.toString() ?? '';
  final out = id.isEmpty
      ? List<Map<String, dynamic>>.from(list)
      : list.where((e) => e['id']?.toString() != id).toList();
  out.insert(0, Map<String, dynamic>.from(row));
  return out;
}

/// File-backed deleted index with ordered write helpers for tests.
class QuoteDeletedIndexStore {
  QuoteDeletedIndexStore({
    required this.quotesDirectory,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Directory quotesDirectory;
  final DateTime Function() _clock;

  File get deletedIndexFile =>
      File('${quotesDirectory.path}/quotes_deleted.json');

  File quoteFileFor(String id) =>
      File('${quotesDirectory.path}/quote_$id.json');

  File get activeIndexFile =>
      File('${quotesDirectory.path}/quotes_active.json');

  File get archiveIndexFile =>
      File('${quotesDirectory.path}/quotes_archive.json');

  Future<List<DeletedQuoteInfo>> loadDeletedIndex() async {
    final file = deletedIndexFile;
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      return parseDeletedQuoteIndexList(decoded);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDeletedIndex(List<DeletedQuoteInfo> entries) async {
    final file = deletedIndexFile;
    await file.writeAsString(
      jsonEncode(encodeDeletedQuoteIndexList(entries)),
      flush: true,
    );
  }

  Future<List<Map<String, dynamic>>> _loadIndexMaps(File file) async {
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveIndexMaps(
    File file,
    List<Map<String, dynamic>> list,
  ) async {
    await file.writeAsString(jsonEncode(list), flush: true);
  }

  /// Soft-delete: write deleted index first, then strip active/archive.
  /// Rolls back deleted index if subsequent writes fail.
  Future<bool> softDeleteQuote({
    required Map<String, dynamic> indexSnapshot,
    required String originalStatus,
  }) async {
    final id = (indexSnapshot['id'] ?? '').toString().trim();
    if (id.isEmpty) return false;

    final priorDeleted = await loadDeletedIndex();
    final entry = DeletedQuoteInfo(
      quoteId: id,
      deletedAt: _clock().toUtc(),
      originalStatus: originalStatus,
      indexSnapshot: Map<String, dynamic>.from(indexSnapshot),
    );
    final nextDeleted = upsertDeletedQuote(priorDeleted, entry);

    await saveDeletedIndex(nextDeleted);

    final priorActive = await _loadIndexMaps(activeIndexFile);
    final priorArchive = await _loadIndexMaps(archiveIndexFile);

    try {
      await _saveIndexMaps(
        activeIndexFile,
        removeIdFromIndexMaps(priorActive, id),
      );
      await _saveIndexMaps(
        archiveIndexFile,
        removeIdFromIndexMaps(priorArchive, id),
      );
      return true;
    } catch (_) {
      await saveDeletedIndex(priorDeleted);
      try {
        await _saveIndexMaps(activeIndexFile, priorActive);
        await _saveIndexMaps(archiveIndexFile, priorArchive);
      } catch (_) {}
      return false;
    }
  }

  /// Restore from deleted index to active or archive based on [originalStatus].
  Future<bool> restoreDeletedQuote(String quoteId) async {
    final id = quoteId.trim();
    if (id.isEmpty) return false;
    if (!await quoteFileFor(id).exists()) return false;

    final deleted = await loadDeletedIndex();
    final idx = deleted.indexWhere((e) => e.quoteId == id);
    if (idx < 0) return false;
    final entry = deleted[idx];
    final priorDeleted = List<DeletedQuoteInfo>.from(deleted);

    final target = resolveRestoreStatus(entry.originalStatus);
    final row = Map<String, dynamic>.from(entry.indexSnapshot);
    row['id'] = id;
    row['quoteStatus'] = target;

    final nextDeleted = removeDeletedQuoteById(deleted, id);
    await saveDeletedIndex(nextDeleted);

    final priorActive = await _loadIndexMaps(activeIndexFile);
    final priorArchive = await _loadIndexMaps(archiveIndexFile);

    try {
      if (target == 'active') {
        await _saveIndexMaps(
          activeIndexFile,
          upsertIndexMapRow(priorActive, row),
        );
        // Ensure not also in archive.
        await _saveIndexMaps(
          archiveIndexFile,
          removeIdFromIndexMaps(priorArchive, id),
        );
      } else {
        await _saveIndexMaps(
          archiveIndexFile,
          upsertIndexMapRow(priorArchive, row),
        );
        await _saveIndexMaps(
          activeIndexFile,
          removeIdFromIndexMaps(priorActive, id),
        );
      }
      return true;
    } catch (_) {
      await saveDeletedIndex(priorDeleted);
      try {
        await _saveIndexMaps(activeIndexFile, priorActive);
        await _saveIndexMaps(archiveIndexFile, priorArchive);
      } catch (_) {}
      return false;
    }
  }

  /// Permanent delete: remove deleted index row + quote file.
  Future<bool> permanentlyDeleteQuote(String quoteId) async {
    final id = quoteId.trim();
    if (id.isEmpty) return false;
    final priorDeleted = await loadDeletedIndex();
    if (!priorDeleted.any((e) => e.quoteId == id)) return false;

    final next = removeDeletedQuoteById(priorDeleted, id);
    await saveDeletedIndex(next);

    final qf = quoteFileFor(id);
    if (await qf.exists()) {
      // Only delete file if not still referenced by active/archive.
      final active = await _loadIndexMaps(activeIndexFile);
      final archive = await _loadIndexMaps(archiveIndexFile);
      final stillIndexed =
          active.any((e) => e['id']?.toString() == id) ||
          archive.any((e) => e['id']?.toString() == id);
      if (!stillIndexed) {
        await qf.delete();
      }
    }
    return true;
  }

  /// Purge expired deleted quotes; returns expired ids removed.
  Future<List<String>> purgeExpiredDeletedQuotes() async {
    final deleted = await loadDeletedIndex();
    final part = partitionExpiredDeletedQuotes(entries: deleted, now: _clock());
    if (part.expired.isEmpty) return [];

    await saveDeletedIndex(part.retained);

    final removedIds = <String>[];
    final active = await _loadIndexMaps(activeIndexFile);
    final archive = await _loadIndexMaps(archiveIndexFile);
    final activeIds = active.map((e) => e['id']?.toString()).toSet();
    final archiveIds = archive.map((e) => e['id']?.toString()).toSet();

    for (final e in part.expired) {
      removedIds.add(e.quoteId);
      if (activeIds.contains(e.quoteId) || archiveIds.contains(e.quoteId)) {
        continue;
      }
      final qf = quoteFileFor(e.quoteId);
      if (await qf.exists()) {
        await qf.delete();
      }
    }
    return removedIds;
  }
}

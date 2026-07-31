/// Official customer catalog retention helpers (Load Customers cache).
///
/// Bundled assets are a seed/fallback. A successful Load Customers (or restored
/// cache from that load) is preferred and must not be overwritten by a later
/// assets parse.
library;

/// Filename under the app documents directory for the last successful
/// official Customer Masterlist CSV (from Load Customers).
const String kOfficialCustomersCacheFilename = 'customers_official_cache.csv';

/// Catalog provenance for the in-memory official customer list.
enum OfficialCustomersCatalogSource {
  none,
  bundledAssets,
  officialCache,
  liveSheet,
}

/// True when [candidate] must not replace an already-applied preferred catalog.
///
/// Preferred sources: live sheet and disk cache from a prior successful Load.
/// Bundled assets are the lowest-priority seed and must never wipe them.
bool shouldSkipOfficialCustomersCatalogApply({
  required OfficialCustomersCatalogSource current,
  required OfficialCustomersCatalogSource candidate,
}) {
  final currentIsPreferred =
      current == OfficialCustomersCatalogSource.liveSheet ||
      current == OfficialCustomersCatalogSource.officialCache;
  if (!currentIsPreferred) return false;
  return candidate == OfficialCustomersCatalogSource.bundledAssets;
}

/// Upsert customers by stable id (case-insensitive). First occurrence wins for
/// duplicate ids within [incoming]; existing rows with the same id are replaced
/// by the incoming row. Order: prior rows (minus replaced ids), then new ids.
List<T> upsertCustomersById<T>({
  required List<T> existing,
  required List<T> incoming,
  required String Function(T) idOf,
}) {
  final byKey = <String, T>{};
  final order = <String>[];

  void put(T customer, {required bool preferIncoming}) {
    final raw = idOf(customer).trim();
    if (raw.isEmpty) return;
    final key = raw.toLowerCase();
    if (!byKey.containsKey(key)) {
      order.add(key);
      byKey[key] = customer;
      return;
    }
    if (preferIncoming) {
      byKey[key] = customer;
    }
  }

  for (final c in existing) {
    put(c, preferIncoming: false);
  }
  for (final c in incoming) {
    put(c, preferIncoming: true);
  }

  return [for (final key in order) byKey[key]!];
}

/// Count of unique non-empty ids (case-insensitive).
int uniqueCustomerIdCount<T>(
  Iterable<T> customers, {
  required String Function(T) idOf,
}) {
  final keys = <String>{};
  for (final c in customers) {
    final id = idOf(c).trim();
    if (id.isEmpty) continue;
    keys.add(id.toLowerCase());
  }
  return keys.length;
}

/// Snackbar text after a successful official Load Customers.
/// Uses the official parsed count only — not the merged picker size.
String officialCustomersLoadedSnackBarMessage(int officialCount) {
  return '$officialCount customers loaded';
}

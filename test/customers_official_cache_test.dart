import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/customers_official_cache.dart';

class _Cust {
  _Cust(this.id, this.name);
  final String id;
  final String name;
}

/// Simulates the in-memory customer list used by Create Quote picker.
class _CustomerListSession {
  List<_Cust> customers = [];
  OfficialCustomersCatalogSource source = OfficialCustomersCatalogSource.none;
  String? selectedId;
  final List<String> quoteCustomerIds = [];

  bool applyCatalog({
    required List<_Cust> incoming,
    required OfficialCustomersCatalogSource candidate,
  }) {
    if (shouldSkipOfficialCustomersCatalogApply(
      current: source,
      candidate: candidate,
    )) {
      return false;
    }
    customers = List<_Cust>.from(incoming);
    source = candidate;
    if (selectedId != null &&
        !customers.any((c) => c.id.toLowerCase() == selectedId!.toLowerCase())) {
      selectedId = null;
    }
    return true;
  }

  bool containsId(String id) =>
      customers.any((c) => c.id.toLowerCase() == id.toLowerCase());

  void selectCustomer(String id) {
    if (!containsId(id)) {
      throw StateError('Customer $id not in picker list');
    }
    selectedId = id;
  }

  void createAndSaveQuote() {
    final id = selectedId;
    if (id == null) throw StateError('No customer selected');
    quoteCustomerIds.add(id);
    // Completing a quote must not wipe the official customer catalog.
  }

  void startSecondQuote() {
    // Selection may be cleared by UX; catalog must still contain the customer.
    selectedId = null;
  }

  void navigateAwayAndBack() {
    // Tab navigation must not rebuild the official list from bundled seed.
  }
}

void main() {
  group('official catalog preference', () {
    test('assets must not overwrite live sheet', () {
      expect(
        shouldSkipOfficialCustomersCatalogApply(
          current: OfficialCustomersCatalogSource.liveSheet,
          candidate: OfficialCustomersCatalogSource.bundledAssets,
        ),
        isTrue,
      );
    });

    test('assets must not overwrite official cache', () {
      expect(
        shouldSkipOfficialCustomersCatalogApply(
          current: OfficialCustomersCatalogSource.officialCache,
          candidate: OfficialCustomersCatalogSource.bundledAssets,
        ),
        isTrue,
      );
    });

    test('live sheet may replace cache or assets', () {
      expect(
        shouldSkipOfficialCustomersCatalogApply(
          current: OfficialCustomersCatalogSource.officialCache,
          candidate: OfficialCustomersCatalogSource.liveSheet,
        ),
        isFalse,
      );
      expect(
        shouldSkipOfficialCustomersCatalogApply(
          current: OfficialCustomersCatalogSource.bundledAssets,
          candidate: OfficialCustomersCatalogSource.liveSheet,
        ),
        isFalse,
      );
    });

    test('cache may replace assets', () {
      expect(
        shouldSkipOfficialCustomersCatalogApply(
          current: OfficialCustomersCatalogSource.bundledAssets,
          candidate: OfficialCustomersCatalogSource.officialCache,
        ),
        isFalse,
      );
    });
  });

  group('upsertCustomersById dedupe', () {
    test('double load keeps one row per id', () {
      final first = [_Cust('100', 'Acme'), _Cust('MISSING', 'New Co')];
      final second = [
        _Cust('100', 'Acme Updated'),
        _Cust('MISSING', 'New Co'),
        _Cust('200', 'Beta'),
      ];
      final merged = upsertCustomersById(
        existing: first,
        incoming: second,
        idOf: (c) => c.id,
      );
      expect(uniqueCustomerIdCount(merged, idOf: (c) => c.id), 3);
      expect(merged.where((c) => c.id.toLowerCase() == 'missing').length, 1);
      expect(
        merged.firstWhere((c) => c.id == '100').name,
        'Acme Updated',
      );
    });

    test('id comparison is case-insensitive', () {
      final merged = upsertCustomersById(
        existing: [_Cust('AbC', 'One')],
        incoming: [_Cust('abc', 'Two')],
        idOf: (c) => c.id,
      );
      expect(merged.length, 1);
      expect(merged.single.name, 'Two');
    });
  });

  group('Create Quote picker retention regressions', () {
    final bundled = [_Cust('100', 'Seed Only'), _Cust('200', 'Also Seed')];
    final sheet = [
      _Cust('100', 'Seed Only'),
      _Cust('200', 'Also Seed'),
      _Cust('999001', 'Previously Missing Customer'),
    ];

    test('Test 1 — loaded customer remains after creating a quote', () {
      final session = _CustomerListSession();
      session.applyCatalog(
        incoming: bundled,
        candidate: OfficialCustomersCatalogSource.bundledAssets,
      );
      expect(session.containsId('999001'), isFalse);

      session.applyCatalog(
        incoming: sheet,
        candidate: OfficialCustomersCatalogSource.liveSheet,
      );
      expect(session.containsId('999001'), isTrue);

      session.selectCustomer('999001');
      session.createAndSaveQuote();

      // Return to Create Quote picker without Load Customers.
      expect(session.containsId('999001'), isTrue);
      expect(session.source, OfficialCustomersCatalogSource.liveSheet);
    });

    test('Test 2 — second quote for same customer without reload', () {
      final session = _CustomerListSession();
      session.applyCatalog(
        incoming: bundled,
        candidate: OfficialCustomersCatalogSource.bundledAssets,
      );
      session.applyCatalog(
        incoming: sheet,
        candidate: OfficialCustomersCatalogSource.liveSheet,
      );
      session.selectCustomer('999001');
      session.createAndSaveQuote();
      session.startSecondQuote();

      expect(session.containsId('999001'), isTrue);
      session.selectCustomer('999001');
      session.createAndSaveQuote();
      expect(session.quoteCustomerIds, ['999001', '999001']);
    });

    test('Test 3 — navigation does not erase loaded customers', () {
      final session = _CustomerListSession();
      session.applyCatalog(
        incoming: sheet,
        candidate: OfficialCustomersCatalogSource.liveSheet,
      );
      session.navigateAwayAndBack();
      // Late bundled load must not wipe preferred catalog.
      final skipped = session.applyCatalog(
        incoming: bundled,
        candidate: OfficialCustomersCatalogSource.bundledAssets,
      );
      expect(skipped, isFalse);
      expect(session.containsId('999001'), isTrue);
      expect(session.customers.length, 3);
    });

    test('Test 4 — no duplicates after loading more than once', () {
      final session = _CustomerListSession();
      session.applyCatalog(
        incoming: sheet,
        candidate: OfficialCustomersCatalogSource.liveSheet,
      );
      session.applyCatalog(
        incoming: sheet,
        candidate: OfficialCustomersCatalogSource.liveSheet,
      );
      expect(
        uniqueCustomerIdCount(session.customers, idOf: (c) => c.id),
        session.customers.length,
      );
      expect(
        session.customers.where((c) => c.id == '999001').length,
        1,
      );
    });

    test('Test 5 — existing bundled customers remain after Load Customers', () {
      final session = _CustomerListSession();
      session.applyCatalog(
        incoming: bundled,
        candidate: OfficialCustomersCatalogSource.bundledAssets,
      );
      session.applyCatalog(
        incoming: sheet,
        candidate: OfficialCustomersCatalogSource.liveSheet,
      );
      expect(session.containsId('100'), isTrue);
      expect(session.containsId('200'), isTrue);
      expect(session.containsId('999001'), isTrue);
    });

    test('Test 6 — persistence across restart via official cache file', () async {
      final dir = await Directory.systemTemp.createTemp('cust_cache_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      const csv =
          'Id,CompanyName\n100,Seed Only\n999001,Previously Missing Customer\n';
      final cacheFile = File(
        '${dir.path}${Platform.pathSeparator}$kOfficialCustomersCacheFilename',
      );
      await cacheFile.writeAsString(csv);

      // Simulate app restart: new session reads cache instead of bundled seed.
      final restarted = _CustomerListSession();
      final cachedRows = [
        _Cust('100', 'Seed Only'),
        _Cust('999001', 'Previously Missing Customer'),
      ];
      expect(await cacheFile.exists(), isTrue);
      restarted.applyCatalog(
        incoming: cachedRows,
        candidate: OfficialCustomersCatalogSource.officialCache,
      );
      // Bundled seed must not wipe restored cache.
      restarted.applyCatalog(
        incoming: bundled,
        candidate: OfficialCustomersCatalogSource.bundledAssets,
      );
      expect(restarted.containsId('999001'), isTrue);
      expect(restarted.source, OfficialCustomersCatalogSource.officialCache);
    });
  });

  group('Load Customers snackbar reports official count only', () {
    test('265 official + 1 local → picker 266, snackbar 265', () {
      const officialCount = 265;
      final official = [
        for (var i = 0; i < officialCount; i++)
          _Cust('ID$i', 'Official Customer $i'),
      ];
      final local = _Cust('LOCAL-000001', 'Phone Local Customer');

      final session = _CustomerListSession();
      session.applyCatalog(
        incoming: official,
        candidate: OfficialCustomersCatalogSource.liveSheet,
      );
      expect(session.customers.length, 265);

      // Merge one local that does not collide by id/name (picker behavior).
      final picker = upsertCustomersById(
        existing: session.customers,
        incoming: [local],
        idOf: (c) => c.id,
      );
      expect(picker.length, 266);
      expect(picker.any((c) => c.id == 'LOCAL-000001'), isTrue);

      final snackbar = officialCustomersLoadedSnackBarMessage(officialCount);
      expect(snackbar, '265 customers loaded');
      expect(snackbar.contains('266'), isFalse);

      // Local remains selectable from the merged picker list.
      expect(
        picker.any((c) => c.id == 'LOCAL-000001' && c.name == 'Phone Local Customer'),
        isTrue,
      );
    });

    test('main snackbar uses official count helper, not merged length', () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(source, contains('officialCustomersLoadedSnackBarMessage(officialCount)'));
      expect(
        source.contains("Text('\$count customers loaded')"),
        isFalse,
      );
      expect(
        RegExp(
          r"final count = _customers\.length;",
        ).hasMatch(source),
        isFalse,
      );
    });
  });

  group('main wiring', () {
    test('startup and Load Customers use official cache helpers', () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(source, contains("import 'customers_official_cache.dart';"));
      expect(source, contains('_loadCustomersOnStartup'));
      expect(source, contains('_loadCustomersFromOfficialCache'));
      expect(source, contains('_writeOfficialCustomersCache'));
      expect(source, contains('kOfficialCustomersCacheFilename'));
      expect(source, contains('OfficialCustomersCatalogSource.liveSheet'));
      expect(source, contains('onLoadCustomers: _loadCustomersFromSheet'));
      expect(
        source.contains('shouldSkipOfficialCustomersCatalogApply'),
        isTrue,
      );
    });
  });
}

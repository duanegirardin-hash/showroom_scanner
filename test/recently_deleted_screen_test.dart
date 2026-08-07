import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/quote_deleted_lifecycle.dart';
import 'package:showroom_scanner/recently_deleted_screen.dart';

DeletedQuoteInfo _entry(String id, {String name = 'QUOTE'}) {
  return DeletedQuoteInfo(
    quoteId: id,
    deletedAt: DateTime.utc(2026, 8, 1),
    originalStatus: 'archived',
    indexSnapshot: {
      'id': id,
      'name': name,
      'customerName': 'Cust',
      'customerId': 'C1',
      'quoteBucketKey': 'every_day',
      'quoteBucketLabel': 'EVERYDAY',
      'updatedAt': '2026-08-01T00:00:00.000Z',
      'quoteStatus': 'archived',
    },
  );
}

void main() {
  test('clampScrollOffsetAfterRemoval keeps nearest valid offset', () {
    expect(
      clampScrollOffsetAfterRemoval(previousOffset: 400, maxScrollExtent: 350),
      350,
    );
    expect(
      clampScrollOffsetAfterRemoval(previousOffset: 120, maxScrollExtent: 500),
      120,
    );
    expect(
      clampScrollOffsetAfterRemoval(previousOffset: -10, maxScrollExtent: 50),
      0,
    );
  });

  testWidgets('Recently Deleted is a dedicated screen with empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecentlyDeletedScreen(
          loadDeleted: () async => <DeletedQuoteInfo>[],
          onView: (_) async {},
          onRestore: (_) async => true,
          onPermanentlyDelete: (_) async => true,
          onPermanentlyDeleteAll: (_) async =>
              const RecentlyDeletedBulkDeleteResult(succeeded: 0, failed: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recently Deleted'), findsWidgets);
    expect(find.byKey(const Key('recently_deleted_empty_state')), findsOneWidget);
    expect(find.byKey(const Key('delete_all_permanently_button')), findsOneWidget);
    expect(find.text('Delete All Permanently'), findsOneWidget);
    // Empty list disables bulk delete.
    final bulk = tester.widget<OutlinedButton>(
      find.byKey(const Key('delete_all_permanently_button')),
    );
    expect(bulk.onPressed, isNull);
  });

  testWidgets(
    'single permanent delete stays on screen and preserves scroll offset',
    (tester) async {
      final entries = List<DeletedQuoteInfo>.generate(
        20,
        (i) => _entry('q$i', name: 'QUOTE $i'),
      );
      var loadCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: RecentlyDeletedScreen(
            loadDeleted: () async {
              loadCount++;
              return List<DeletedQuoteInfo>.from(entries);
            },
            onView: (_) async {},
            onRestore: (_) async => true,
            onPermanentlyDelete: (info) async {
              entries.removeWhere((e) => e.quoteId == info.quoteId);
              return true;
            },
            onPermanentlyDeleteAll: (_) async =>
                const RecentlyDeletedBulkDeleteResult(succeeded: 0, failed: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<RecentlyDeletedScreenState>(
        find.byType(RecentlyDeletedScreen),
      );
      // Scroll away from the top before deleting.
      state.scrollController.jumpTo(280);
      await tester.pumpAndSettle();
      final before = state.scrollController.offset;
      expect(before, greaterThan(0));

      await tester.tap(find.text('Delete Permanently').at(0));
      await tester.pumpAndSettle();

      // Still on the dedicated screen — not popped back to Archive.
      expect(find.byType(RecentlyDeletedScreen), findsOneWidget);
      expect(find.byKey(const Key('open_recently_deleted_button')), findsNothing);
      expect(loadCount, greaterThanOrEqualTo(2));

      final after = state.scrollController.offset;
      expect(after, greaterThan(0));
      expect(
        (after - before).abs(),
        lessThanOrEqualTo(before),
        reason: 'scroll should remain near the prior offset, not jump to 0',
      );
      expect(after, isNot(0));
    },
  );

  testWidgets('empty state appears after last permanent delete', (tester) async {
    var entries = <DeletedQuoteInfo>[_entry('only')];
    await tester.pumpWidget(
      MaterialApp(
        home: RecentlyDeletedScreen(
          loadDeleted: () async => List<DeletedQuoteInfo>.from(entries),
          onView: (_) async {},
          onRestore: (_) async => true,
          onPermanentlyDelete: (info) async {
            entries = entries.where((e) => e.quoteId != info.quoteId).toList();
            return true;
          },
          onPermanentlyDeleteAll: (_) async =>
              const RecentlyDeletedBulkDeleteResult(succeeded: 0, failed: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recently_deleted_empty_state')), findsNothing);

    await tester.tap(find.text('Delete Permanently'));
    await tester.pumpAndSettle();

    expect(find.byType(RecentlyDeletedScreen), findsOneWidget);
    expect(find.byKey(const Key('recently_deleted_empty_state')), findsOneWidget);
  });

  testWidgets('Delete All Permanently cancel leaves entries untouched', (
    tester,
  ) async {
    final entries = [_entry('a'), _entry('b')];
    var bulkCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RecentlyDeletedScreen(
          loadDeleted: () async => List<DeletedQuoteInfo>.from(entries),
          onView: (_) async {},
          onRestore: (_) async => true,
          onPermanentlyDelete: (_) async => true,
          onPermanentlyDeleteAll: (list) async {
            bulkCalls++;
            return RecentlyDeletedBulkDeleteResult(
              succeeded: list.length,
              failed: 0,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete_all_permanently_button')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Permanently delete all 2 recently deleted'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(bulkCalls, 0);
    expect(find.text('QUOTE'), findsNWidgets(2));
  });

  testWidgets('Delete All Permanently confirms with exact count and deletes', (
    tester,
  ) async {
    var entries = [_entry('a', name: 'A'), _entry('b', name: 'B'), _entry('c', name: 'C')];
    RecentlyDeletedBulkDeleteResult? seen;
    await tester.pumpWidget(
      MaterialApp(
        home: RecentlyDeletedScreen(
          loadDeleted: () async => List<DeletedQuoteInfo>.from(entries),
          onView: (_) async {},
          onRestore: (_) async => true,
          onPermanentlyDelete: (_) async => true,
          onPermanentlyDeleteAll: (list) async {
            seen = RecentlyDeletedBulkDeleteResult(
              succeeded: list.length,
              failed: 0,
            );
            entries = [];
            return seen!;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete_all_permanently_button')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Permanently delete all 3 recently deleted'),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(TextButton, 'Delete All Permanently'),
    );
    await tester.pumpAndSettle();

    expect(seen?.succeeded, 3);
    expect(seen?.failed, 0);
    expect(find.byKey(const Key('recently_deleted_empty_state')), findsOneWidget);
    expect(find.byType(RecentlyDeletedScreen), findsOneWidget);
  });

  testWidgets('partial bulk failure keeps failed rows visible', (tester) async {
    var entries = [_entry('ok', name: 'OK'), _entry('bad', name: 'BAD')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentlyDeletedScreen(
            loadDeleted: () async => List<DeletedQuoteInfo>.from(entries),
            onView: (_) async {},
            onRestore: (_) async => true,
            onPermanentlyDelete: (_) async => true,
            onPermanentlyDeleteAll: (list) async {
              var succeeded = 0;
              var failed = 0;
              for (final e in list) {
                if (e.quoteId == 'ok') {
                  entries.removeWhere((x) => x.quoteId == 'ok');
                  succeeded++;
                } else {
                  failed++;
                }
              }
              return RecentlyDeletedBulkDeleteResult(
                succeeded: succeeded,
                failed: failed,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete_all_permanently_button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(TextButton, 'Delete All Permanently'),
    );
    await tester.pumpAndSettle();

    expect(find.text('BAD'), findsOneWidget);
    expect(find.text('OK'), findsNothing);
    expect(
      find.textContaining('Permanently deleted 1 of 2'),
      findsOneWidget,
    );
  });
}

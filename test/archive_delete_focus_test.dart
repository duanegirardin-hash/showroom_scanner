import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/archive_delete_focus.dart';
import 'package:showroom_scanner/quote_deleted_lifecycle.dart';
import 'package:showroom_scanner/recently_deleted_screen.dart';

DeletedQuoteInfo _entry(String id) {
  return DeletedQuoteInfo(
    quoteId: id,
    deletedAt: DateTime.utc(2026, 8, 1),
    originalStatus: 'archived',
    indexSnapshot: {
      'id': id,
      'name': 'QUOTE',
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
  testWidgets('Recently Deleted has no autofocus TextField', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecentlyDeletedScreen(
          loadDeleted: () async => [_entry('a')],
          onView: (_) async {},
          onRestore: (_) async => true,
          onPermanentlyDelete: (_) async => true,
          onPermanentlyDeleteAll: (_) async =>
              const RecentlyDeletedBulkDeleteResult(succeeded: 0, failed: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.autofocus, isFalse);
    }
  });

  testWidgets('bulk delete button label is DELETE ALL QUOTES PERMANENTLY', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecentlyDeletedScreen(
          loadDeleted: () async => [_entry('a')],
          onView: (_) async {},
          onRestore: (_) async => true,
          onPermanentlyDelete: (_) async => true,
          onPermanentlyDeleteAll: (_) async =>
              const RecentlyDeletedBulkDeleteResult(succeeded: 0, failed: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(kDeleteAllQuotesPermanentlyButtonLabel), findsOneWidget);
    expect(find.text('Delete All Permanently'), findsNothing);
  });

  testWidgets('delete confirmation dialog has no TextField', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecentlyDeletedScreen(
          loadDeleted: () async => [_entry('a'), _entry('b')],
          onView: (_) async {},
          onRestore: (_) async => true,
          onPermanentlyDelete: (_) async => true,
          onPermanentlyDeleteAll: (_) async =>
              const RecentlyDeletedBulkDeleteResult(succeeded: 0, failed: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete_all_permanently_button')));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Delete All Permanently?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('archive search field keeps focus only when user taps it', (
    tester,
  ) async {
    final archiveSearchFocus = FocusNode();
    addTearDown(archiveSearchFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                key: const Key('archive_search_field'),
                focusNode: archiveSearchFocus,
                decoration: const InputDecoration(labelText: 'Search archive'),
              ),
              ElevatedButton(
                onPressed: () {
                  releaseArchiveDeleteWorkflowFocus(
                    extraNodes: [archiveSearchFocus],
                  );
                  showDialog<void>(
                    context: tester.element(find.byType(ElevatedButton)),
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Permanently?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Delete'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(archiveSearchFocus.hasFocus, isFalse);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(archiveSearchFocus.hasFocus, isFalse);

    await tester.tap(find.byKey(const Key('archive_search_field')));
    await tester.pumpAndSettle();
    expect(archiveSearchFocus.hasFocus, isTrue);
  });

  testWidgets('single permanent delete does not leave search field focused', (
    tester,
  ) async {
    final archiveSearchFocus = FocusNode();
    addTearDown(archiveSearchFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                focusNode: archiveSearchFocus,
                decoration: const InputDecoration(labelText: 'Search archive'),
              ),
              Expanded(
                child: RecentlyDeletedScreen(
                  loadDeleted: () async => [_entry('only')],
                  onView: (_) async {},
                  onRestore: (_) async => true,
                  onPermanentlyDelete: (_) async {
                    releaseArchiveDeleteWorkflowFocus(
                      extraNodes: [archiveSearchFocus],
                    );
                    return true;
                  },
                  onPermanentlyDeleteAll: (_) async =>
                      const RecentlyDeletedBulkDeleteResult(
                        succeeded: 0,
                        failed: 0,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    archiveSearchFocus.requestFocus();
    await tester.pumpAndSettle();
    expect(archiveSearchFocus.hasFocus, isTrue);

    await tester.tap(find.text('Delete Permanently'));
    await tester.pumpAndSettle();

    expect(archiveSearchFocus.hasFocus, isFalse);
  });

  test('releaseArchiveDeleteWorkflowFocus clears extra nodes', () {
    final node = FocusNode();
    addTearDown(node.dispose);
    // No widget tree — ensure unfocus is safe on detached nodes.
    releaseArchiveDeleteWorkflowFocus(extraNodes: [node]);
    expect(node.hasFocus, isFalse);
  });
}

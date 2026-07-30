import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:showroom_scanner/customer_quote_email.dart';
import 'package:showroom_scanner/main.dart' as app;

class _QuoteRef {
  const _QuoteRef(this.id, this.customerId);

  final String id;
  final String customerId;
}

class _ArchiveQuoteRef {
  const _ArchiveQuoteRef({
    required this.id,
    required this.status,
    required this.payload,
  });

  final String id;
  final String status;
  final Map<String, Object?> payload;

  _ArchiveQuoteRef archived() =>
      _ArchiveQuoteRef(id: id, status: 'archived', payload: payload);
}

void main() {
  test(
    'email chooser retains exact explanatory notes and button order',
    () async {
      final source = await File('lib/main.dart').readAsString();
      const current = 'Email Current Quote Only\\n(moves to Archive)';
      const customer =
          'Email All Quotes for This Customer\\n(archives included active quotes)';
      const all = 'Email All Saved Quotes\\n(share only — does not archive)';

      final currentIndex = source.indexOf(current);
      final customerIndex = source.indexOf(customer);
      final allIndex = source.indexOf(all);
      expect(currentIndex, greaterThanOrEqualTo(0));
      expect(customerIndex, greaterThan(currentIndex));
      expect(allIndex, greaterThan(customerIndex));
    },
  );

  test(
    'main keeps customer persistence and body-free multi-share wiring',
    () async {
      final source = await File('lib/main.dart').readAsString();
      expect(source, contains("import 'customer_quote_email.dart';"));
      expect(source, contains('persistCsvCopies: true'));
      expect(source, contains('persistCsvCopy: persistCsvCopies'));
      expect(source, contains('persistCustomerEmailCsvCopy('));
      expect(
        source,
        contains('launchCustomerMultiFileShare<ShareResult, XFile>'),
      );
      expect(
        source,
        isNot(contains("text: textParts.join('\\n\\n---\\n\\n')")),
      );
      expect(source, contains('Documents/Showroom_Sync/Exported orders'));
      expect(source, contains('archiveActiveQuotesAfterShare: true'));
      expect(source, contains('bool archiveActiveQuotesAfterShare = false'));
      expect(source, contains('onlyQuoteId: true'));
    },
  );

  test('selection includes active and archived quotes in existing order', () {
    final active = [
      const _QuoteRef('active-1', 'customer-a'),
      const _QuoteRef('other-active', 'customer-b'),
      const _QuoteRef('active-2', 'customer-a'),
    ];
    final archived = [
      const _QuoteRef('archive-1', 'customer-a'),
      const _QuoteRef('other-archive', 'customer-b'),
      const _QuoteRef('archive-2', 'customer-a'),
    ];

    final selected = customerEmailQuoteSelection<_QuoteRef>(
      activeQuotes: active,
      archivedQuotes: archived,
      belongsToCustomer: (quote) => quote.customerId == 'customer-a',
    );

    expect(selected.map((quote) => quote.id), [
      'active-1',
      'active-2',
      'archive-1',
      'archive-2',
    ]);
  });

  test('selection supports ten or more quotes for one customer', () {
    final active = List.generate(
      6,
      (index) => _QuoteRef('active-$index', 'customer-a'),
    );
    final archived = List.generate(
      6,
      (index) => _QuoteRef('archive-$index', 'customer-a'),
    );
    final selected = customerEmailQuoteSelection<_QuoteRef>(
      activeQuotes: active,
      archivedQuotes: archived,
      belongsToCustomer: (quote) => quote.customerId == 'customer-a',
    );
    expect(selected, hasLength(12));
  });

  group('archive after successful share launch', () {
    const unchangedPayload = <String, Object?>{
      'customer': "Low's Family Foods",
      'products': 'A,B',
      'quantities': '2,4',
      'scanCounts': '1,3',
      'prices': '1.2345,9.8765',
      'productType': 'EVERYDAY',
      'createdAt': '2026-07-01T10:00:00.000',
      'updatedAt': '2026-07-30T10:00:00.000',
      'filename': 'Quote_EVERYDAY.csv',
    };

    test('current quote moves only after successful launch', () async {
      var active = [
        const _ArchiveQuoteRef(
          id: 'current',
          status: 'active',
          payload: unchangedPayload,
        ),
      ];
      var archived = <_ArchiveQuoteRef>[];

      await launchEmailShareThenArchive<String>(
        launch: () async => 'launched',
        didLaunch: (result) => result == 'launched',
        archive: () async {
          final transition = customerEmailArchiveTransition<_ArchiveQuoteRef>(
            activeQuotes: active,
            archivedQuotes: archived,
            sharedActiveQuoteIds: const ['current'],
            idOf: (quote) => quote.id,
            asArchived: (quote) => quote.archived(),
          );
          active = transition.activeQuotes;
          archived = transition.archivedQuotes;
        },
      );

      expect(active, isEmpty);
      expect(archived.single.status, 'archived');
      expect(identical(archived.single.payload, unchangedPayload), isTrue);
    });

    test(
      'customer share moves active quotes and preserves existing archive',
      () {
        final existingArchive = const _ArchiveQuoteRef(
          id: 'already-archived',
          status: 'archived',
          payload: {'existing': true},
        );
        final transition = customerEmailArchiveTransition<_ArchiveQuoteRef>(
          activeQuotes: const [
            _ArchiveQuoteRef(
              id: 'active-1',
              status: 'active',
              payload: unchangedPayload,
            ),
            _ArchiveQuoteRef(
              id: 'active-2',
              status: 'active',
              payload: unchangedPayload,
            ),
            _ArchiveQuoteRef(
              id: 'other-active',
              status: 'active',
              payload: unchangedPayload,
            ),
          ],
          archivedQuotes: [existingArchive, existingArchive],
          sharedActiveQuoteIds: const ['active-1', 'active-2'],
          idOf: (quote) => quote.id,
          asArchived: (quote) => quote.archived(),
        );

        expect(transition.activeQuotes.map((quote) => quote.id), [
          'other-active',
        ]);
        expect(transition.archivedQuotes.map((quote) => quote.id).toSet(), {
          'active-1',
          'active-2',
          'already-archived',
        });
        expect(
          transition.archivedQuotes
              .where((quote) => quote.id == 'already-archived')
              .single,
          same(existingArchive),
        );
        expect(transition.archivedQuotes, hasLength(3));
      },
    );

    test('unavailable or failed share launch does not archive', () async {
      var archiveCalls = 0;
      final unavailable = await launchEmailShareThenArchive<String>(
        launch: () async => 'unavailable',
        didLaunch: (result) => result != 'unavailable',
        archive: () async => archiveCalls++,
      );
      expect(unavailable, 'unavailable');
      expect(archiveCalls, 0);

      await expectLater(
        launchEmailShareThenArchive<String>(
          launch: () async => throw StateError('launch failed'),
          didLaunch: (_) => true,
          archive: () async => archiveCalls++,
        ),
        throwsStateError,
      );
      expect(archiveCalls, 0);
    });

    test(
      'attachment generation failure occurs before archive callback',
      () async {
        var archiveCalls = 0;

        Future<void> prepareAndShare(
          Future<void> Function() generateAttachments,
        ) async {
          await generateAttachments();
          await launchEmailShareThenArchive<void>(
            launch: () async {},
            didLaunch: (_) => true,
            archive: () async => archiveCalls++,
          );
        }

        await expectLater(
          prepareAndShare(
            () async =>
                throw const FormatException('attachment generation failed'),
          ),
          throwsFormatException,
        );
        expect(archiveCalls, 0);
      },
    );
  });

  group('permanent customer CSV copies', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('customer_email_exports_');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('customer folder sanitization preserves valid punctuation', () {
      expect(
        app.sanitizeCustomerExportFolderName("Low's Family Foods"),
        "Low's Family Foods",
      );
      expect(
        app.sanitizeCustomerExportFolderName('Smith & Sons Market'),
        'Smith & Sons Market',
      );
      expect(
        app.sanitizeCustomerExportFolderName('North/South Foods'),
        'North_South Foods',
      );
    });

    test('one quote is copied under the exact customer folder', () async {
      final root = Directory('${temp.path}/Showroom_Sync/Exported orders');
      final result = await persistCustomerEmailCsvCopy(
        quoteId: 'one',
        customerDisplayName: "Low's Family Foods",
        customerFolderName: "Low's Family Foods",
        filename: 'Quote_ONE.csv',
        csvText: 'item,qty\nA,1',
        save:
            ({
              required customerDisplayName,
              required filename,
              required csvText,
            }) => app.writeOrderExportCsvUnderDesignatedBase(
              exportBasePath: root.path,
              customerDisplayName: customerDisplayName,
              filename: filename,
              csvText: csvText,
            ),
      );

      expect(result.succeeded, isTrue);
      expect(
        p.normalize(result.file!.path),
        contains(
          p.join('Showroom_Sync', 'Exported orders', "Low's Family Foods"),
        ),
      );
      expect(await result.file!.readAsString(), 'item,qty\nA,1');
    });

    test(
      'ten or more copies persist while temporary share files remain selected',
      () async {
        final root = Directory('${temp.path}/Showroom_Sync/Exported orders');
        final temporaryAttachments = <String>[];
        for (var index = 0; index < 12; index++) {
          final temporary = File('${temp.path}/temp_quote_$index.csv');
          await temporary.writeAsString('temporary-$index');
          temporaryAttachments.add(temporary.path);

          final result = await persistCustomerEmailCsvCopy(
            quoteId: 'quote-$index',
            customerDisplayName: 'Smith & Sons Market',
            customerFolderName: 'Smith & Sons Market',
            filename: 'Quote_$index.csv',
            csvText: 'permanent-$index',
            save:
                ({
                  required customerDisplayName,
                  required filename,
                  required csvText,
                }) => app.writeOrderExportCsvUnderDesignatedBase(
                  exportBasePath: root.path,
                  customerDisplayName: customerDisplayName,
                  filename: filename,
                  csvText: csvText,
                ),
          );
          expect(result.succeeded, isTrue);
        }

        final customerDir = Directory('${root.path}/Smith & Sons Market');
        expect(customerDir.listSync().whereType<File>(), hasLength(12));

        List<String>? launchedAttachments;
        String? launchedSubject;
        final result = await launchCustomerMultiFileShare<String, String>(
          attachments: temporaryAttachments,
          subject: 'Quotes (12) — Smith & Sons Market',
          launch: (attachments, subject) async {
            launchedAttachments = attachments;
            launchedSubject = subject;
            return 'dismissed';
          },
        );
        expect(launchedAttachments, temporaryAttachments);
        expect(launchedSubject, 'Quotes (12) — Smith & Sons Market');
        expect(result, 'dismissed');
        for (final path in temporaryAttachments) {
          expect(await File(path).exists(), isTrue);
        }
      },
    );

    test('duplicate filenames use the established numeric suffix', () async {
      final root = Directory('${temp.path}/Showroom_Sync/Exported orders');

      Future<File> save({
        required String customerDisplayName,
        required String filename,
        required String csvText,
      }) {
        return app.writeOrderExportCsvUnderDesignatedBase(
          exportBasePath: root.path,
          customerDisplayName: customerDisplayName,
          filename: filename,
          csvText: csvText,
        );
      }

      final first = await persistCustomerEmailCsvCopy(
        quoteId: 'first',
        customerDisplayName: 'Customer Name',
        customerFolderName: 'Customer Name',
        filename: 'Quote.csv',
        csvText: 'first',
        save: save,
      );
      final second = await persistCustomerEmailCsvCopy(
        quoteId: 'second',
        customerDisplayName: 'Customer Name',
        customerFolderName: 'Customer Name',
        filename: 'Quote.csv',
        csvText: 'second',
        save: save,
      );

      expect(first.file?.path, endsWith('Quote.csv'));
      expect(second.file?.path, endsWith('Quote_2.csv'));
      expect(await first.file!.readAsString(), 'first');
      expect(await second.file!.readAsString(), 'second');
    });

    test(
      'permanent save failure does not remove temporary attachment',
      () async {
        final temporary = File('${temp.path}/temporary.csv');
        await temporary.writeAsString('temporary attachment');

        final result = await persistCustomerEmailCsvCopy(
          quoteId: 'failure',
          customerDisplayName: 'Customer Name',
          customerFolderName: 'Customer Name',
          filename: 'Quote.csv',
          csvText: 'permanent copy',
          save:
              ({
                required customerDisplayName,
                required filename,
                required csvText,
              }) async {
                throw const FileSystemException(
                  'Simulated permanent save failure',
                );
              },
        );

        expect(result.succeeded, isFalse);
        expect(result.error, isA<FileSystemException>());
        expect(await temporary.exists(), isTrue);
        expect(await temporary.readAsString(), 'temporary attachment');
      },
    );
  });

  group('root email operation UI', () {
    late GlobalKey<NavigatorState> navigatorKey;
    late GlobalKey<ScaffoldMessengerState> messengerKey;
    late CustomerEmailOperationGate gate;

    setUp(() {
      navigatorKey = GlobalKey<NavigatorState>();
      messengerKey = GlobalKey<ScaffoldMessengerState>();
      gate = CustomerEmailOperationGate();
    });

    Future<void> pumpHarness(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: messengerKey,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) => const AlertDialog(
                      title: Text('Load Quote'),
                      content: Text('Modal panel'),
                    ),
                  );
                },
                child: const Text('Open Load Quote'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Load Quote'));
      await tester.pumpAndSettle();
      expect(find.text('Load Quote'), findsOneWidget);
    }

    testWidgets('closes Load Quote panel before preparing email', (
      tester,
    ) async {
      await pumpHarness(tester);
      final sendCompleter = Completer<void>();

      unawaited(
        runCustomerQuoteEmailFromModal(
          gate: gate,
          rootNavigatorKey: navigatorKey,
          rootScaffoldMessengerKey: messengerKey,
          prepare: () async =>
              (quoteCount: 10, send: () => sendCompleter.future),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Load Quote'), findsNothing);
      expect(find.text('Preparing 10 quotes for email…'), findsOneWidget);

      sendCompleter.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('no email application error uses root dialog', (tester) async {
      await pumpHarness(tester);

      unawaited(
        runCustomerQuoteEmailFromModal(
          gate: gate,
          rootNavigatorKey: navigatorKey,
          rootScaffoldMessengerKey: messengerKey,
          prepare: () async => (
            quoteCount: 10,
            send: () async {
              throw StateError('No email or sharing application is available.');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Load Quote'), findsNothing);
      expect(find.text('Unable to email quotes'), findsOneWidget);
      expect(
        find.textContaining('No email or sharing application is available.'),
        findsOneWidget,
      );
    });

    testWidgets('export-generation exception shows complete root error', (
      tester,
    ) async {
      await pumpHarness(tester);

      unawaited(
        runCustomerQuoteEmailFromModal(
          gate: gate,
          rootNavigatorKey: navigatorKey,
          rootScaffoldMessengerKey: messengerKey,
          prepare: () async {
            throw const FormatException(
              'Quote quote-bad could not generate CSV attachment.',
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Load Quote'), findsNothing);
      expect(find.text('Unable to email quotes'), findsOneWidget);
      expect(
        find.textContaining(
          'Quote quote-bad could not generate CSV attachment.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('rapid double invocation starts only one operation', (
      tester,
    ) async {
      await pumpHarness(tester);
      final sendCompleter = Completer<void>();
      var launches = 0;

      Future<({int quoteCount, Future<void> Function() send})> prepare() async {
        launches++;
        return (quoteCount: 10, send: () => sendCompleter.future);
      }

      final first = runCustomerQuoteEmailFromModal(
        gate: gate,
        rootNavigatorKey: navigatorKey,
        rootScaffoldMessengerKey: messengerKey,
        prepare: prepare,
      );
      final second = runCustomerQuoteEmailFromModal(
        gate: gate,
        rootNavigatorKey: navigatorKey,
        rootScaffoldMessengerKey: messengerKey,
        prepare: prepare,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(await second, isFalse);
      expect(launches, 1);

      sendCompleter.complete();
      expect(await first, isTrue);
      await tester.pumpAndSettle();
    });
  });
}

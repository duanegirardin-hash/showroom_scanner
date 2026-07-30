import 'dart:io';

import 'package:flutter/material.dart';

/// Keeps the existing order within each source: active quotes first, followed
/// by archived quotes, with unrelated customers removed.
List<T> customerEmailQuoteSelection<T>({
  required Iterable<T> activeQuotes,
  required Iterable<T> archivedQuotes,
  required bool Function(T quote) belongsToCustomer,
}) {
  return <T>[
    ...activeQuotes.where(belongsToCustomer),
    ...archivedQuotes.where(belongsToCustomer),
  ];
}

class CustomerEmailArchiveTransition<T> {
  const CustomerEmailArchiveTransition({
    required this.activeQuotes,
    required this.archivedQuotes,
    required this.movedQuotes,
  });

  final List<T> activeQuotes;
  final List<T> archivedQuotes;
  final List<T> movedQuotes;
}

/// Moves only requested active IDs, preserves existing archived entries, and
/// guarantees one archived row per ID.
CustomerEmailArchiveTransition<T> customerEmailArchiveTransition<T>({
  required Iterable<T> activeQuotes,
  required Iterable<T> archivedQuotes,
  required Iterable<String> sharedActiveQuoteIds,
  required String Function(T quote) idOf,
  required T Function(T quote) asArchived,
}) {
  final targetIds = sharedActiveQuoteIds.where((id) => id.isNotEmpty).toSet();
  final remainingActive = <T>[];
  final moved = <T>[];
  for (final quote in activeQuotes) {
    if (targetIds.contains(idOf(quote))) {
      moved.add(quote);
    } else {
      remainingActive.add(quote);
    }
  }

  final archiveIds = <String>{};
  final existingArchive = <T>[];
  for (final quote in archivedQuotes) {
    if (archiveIds.add(idOf(quote))) existingArchive.add(quote);
  }
  final newlyArchived = <T>[];
  for (final quote in moved) {
    if (archiveIds.add(idOf(quote))) newlyArchived.add(asArchived(quote));
  }

  return CustomerEmailArchiveTransition<T>(
    activeQuotes: remainingActive,
    archivedQuotes: <T>[...newlyArchived.reversed, ...existingArchive],
    movedQuotes: moved,
  );
}

class CustomerEmailCsvPersistenceResult {
  const CustomerEmailCsvPersistenceResult._({
    required this.file,
    required this.error,
  });

  factory CustomerEmailCsvPersistenceResult.saved(File file) =>
      CustomerEmailCsvPersistenceResult._(file: file, error: null);

  factory CustomerEmailCsvPersistenceResult.failed(Object error) =>
      CustomerEmailCsvPersistenceResult._(file: null, error: error);

  final File? file;
  final Object? error;

  bool get succeeded => file != null;
}

Future<CustomerEmailCsvPersistenceResult> persistCustomerEmailCsvCopy({
  required String quoteId,
  required String customerDisplayName,
  required String customerFolderName,
  required String filename,
  required String csvText,
  required Future<File> Function({
    required String customerDisplayName,
    required String filename,
    required String csvText,
  })
  save,
}) async {
  debugPrint(
    '[EmailPersist] START quoteId=$quoteId '
    'customerFolder="$customerFolderName" filename="$filename"',
  );
  try {
    final file = await save(
      customerDisplayName: customerDisplayName,
      filename: filename,
      csvText: csvText,
    );
    debugPrint(
      '[EmailPersist] SAVED quoteId=$quoteId '
      'customerFolder="$customerFolderName" path=${file.path}',
    );
    return CustomerEmailCsvPersistenceResult.saved(file);
  } catch (error, stackTrace) {
    debugPrint(
      '[EmailPersist] FAILED quoteId=$quoteId '
      'customerFolder="$customerFolderName" filename="$filename": '
      '$error\n$stackTrace',
    );
    return CustomerEmailCsvPersistenceResult.failed(error);
  }
}

/// Deliberately has no email-body argument. Android ACTION_SEND_MULTIPLE in
/// share_plus 10.1.4 must receive files and subject without EXTRA_TEXT.
Future<R> launchCustomerMultiFileShare<R, T>({
  required List<T> attachments,
  required String subject,
  required Future<R> Function(List<T> attachments, String subject) launch,
}) {
  return launch(attachments, subject);
}

/// Runs archive persistence only after the platform share call returns a result
/// that proves the share sheet launched. A thrown launch error or an
/// unavailable result leaves active quotes untouched.
Future<R> launchEmailShareThenArchive<R>({
  required Future<R> Function() launch,
  required bool Function(R result) didLaunch,
  required Future<void> Function() archive,
}) async {
  final result = await launch();
  if (didLaunch(result)) {
    await archive();
  }
  return result;
}

class CustomerEmailOperationGate {
  bool _busy = false;

  bool get isBusy => _busy;

  Future<bool> run(Future<void> Function() operation) async {
    if (_busy) return false;
    _busy = true;
    try {
      await operation();
      return true;
    } finally {
      _busy = false;
    }
  }
}

/// Closes the current modal route, then performs email preparation using only
/// root-screen navigation and messaging state.
///
/// Returns false when another email operation is already running.
Future<bool> runCustomerQuoteEmailFromModal({
  required CustomerEmailOperationGate gate,
  required GlobalKey<NavigatorState> rootNavigatorKey,
  required GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey,
  required Future<({int quoteCount, Future<void> Function() send})> Function()
  prepare,
}) {
  return gate.run(() async {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) {
      throw StateError('Root navigator is not available.');
    }

    // This entry point is invoked only after choosing Email All from the Load
    // Quote route, so the current root route is the modal that must be closed.
    navigator.pop();
    // Wait for the dialog route's reverse animation so preparation and any
    // subsequent share/error UI begin from the root screen.
    await Future<void>.delayed(const Duration(milliseconds: 250));

    ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? progress;
    try {
      final prepared = await prepare();
      final messenger = rootScaffoldMessengerKey.currentState;
      progress = messenger?.showSnackBar(
        SnackBar(
          content: Text('Preparing ${prepared.quoteCount} quotes for email…'),
          duration: const Duration(minutes: 5),
        ),
      );
      await prepared.send();
    } catch (error, stackTrace) {
      debugPrint('[EmailShare] customer email failed: $error\n$stackTrace');
      progress?.close();
      rootScaffoldMessengerKey.currentState?.hideCurrentSnackBar();

      final rootContext = rootNavigatorKey.currentContext;
      if (rootContext == null) {
        debugPrint(
          '[EmailShare] could not display error dialog: '
          'root navigator context unavailable',
        );
        return;
      }
      await showDialog<void>(
        context: rootContext,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Unable to email quotes'),
          content: SingleChildScrollView(
            child: SelectableText('Could not email quotes:\n\n$error'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      progress?.close();
    }
  });
}

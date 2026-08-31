/// Dedicated Recently Deleted list screen (Archive entry point).
///
/// Soft-delete / restore / permanent-delete lifecycle stays in the host app and
/// [QuoteDeletedIndexStore]; this widget only presents the list, confirms
/// destructive actions, and preserves scroll across single-row removals.
library;

import 'package:flutter/material.dart';

import 'archive_delete_focus.dart';
import 'quote_deleted_lifecycle.dart';

/// Result of a bulk permanent-delete attempt.
class RecentlyDeletedBulkDeleteResult {
  const RecentlyDeletedBulkDeleteResult({
    required this.succeeded,
    required this.failed,
  });

  final int succeeded;
  final int failed;

  int get attempted => succeeded + failed;
}

/// Clamps a prior scroll offset after the list shortens.
@visibleForTesting
double clampScrollOffsetAfterRemoval({
  required double previousOffset,
  required double maxScrollExtent,
}) {
  if (maxScrollExtent < 0) return 0;
  if (previousOffset < 0) return 0;
  return previousOffset.clamp(0.0, maxScrollExtent);
}

/// Full-screen Recently Deleted view.
class RecentlyDeletedScreen extends StatefulWidget {
  const RecentlyDeletedScreen({
    super.key,
    required this.loadDeleted,
    required this.onView,
    required this.onRestore,
    required this.onPermanentlyDelete,
    required this.onPermanentlyDeleteAll,
  });

  final Future<List<DeletedQuoteInfo>> Function() loadDeleted;
  final Future<void> Function(DeletedQuoteInfo info) onView;

  /// Returns true when restore persistence succeeded.
  final Future<bool> Function(DeletedQuoteInfo info) onRestore;

  /// Shows confirmation, permanently deletes one entry, returns true on success.
  final Future<bool> Function(DeletedQuoteInfo info) onPermanentlyDelete;

  /// Permanently deletes every entry in [entries] using the host's safe path.
  final Future<RecentlyDeletedBulkDeleteResult> Function(
    List<DeletedQuoteInfo> entries,
  )
  onPermanentlyDeleteAll;

  @override
  State<RecentlyDeletedScreen> createState() => RecentlyDeletedScreenState();
}

@visibleForTesting
class RecentlyDeletedScreenState extends State<RecentlyDeletedScreen> {
  final ScrollController scrollController = ScrollController();
  final Set<String> _busyIds = <String>{};
  List<DeletedQuoteInfo>? _entries;
  Object? _loadError;
  bool _loading = true;
  bool _bulkInProgress = false;

  @override
  void initState() {
    super.initState();
    _reload(preserveScroll: false);
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _reload({required bool preserveScroll}) async {
    final priorOffset = preserveScroll && scrollController.hasClients
        ? scrollController.offset
        : null;
    try {
      final list = await widget.loadDeleted();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loadError = null;
        _loading = false;
      });
      if (priorOffset != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !scrollController.hasClients) return;
          final next = clampScrollOffsetAfterRemoval(
            previousOffset: priorOffset,
            maxScrollExtent: scrollController.position.maxScrollExtent,
          );
          scrollController.jumpTo(next);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _runRowAction(
    DeletedQuoteInfo info,
    Future<bool> Function() action, {
    required bool preserveScroll,
  }) async {
    if (_busyIds.contains(info.quoteId) || _bulkInProgress) return;
    releaseArchiveDeleteWorkflowFocus();
    setState(() => _busyIds.add(info.quoteId));
    try {
      final ok = await action();
      if (!mounted) return;
      if (ok) {
        await _reload(preserveScroll: preserveScroll);
      }
    } finally {
      if (mounted) {
        setState(() => _busyIds.remove(info.quoteId));
      }
    }
  }

  Future<void> _confirmAndDeleteAll() async {
    final entries = List<DeletedQuoteInfo>.from(_entries ?? const []);
    if (entries.isEmpty || _bulkInProgress) return;
    final n = entries.length;
    releaseArchiveDeleteWorkflowFocus();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete All Permanently?'),
        content: Text(
          'Permanently delete all $n recently deleted '
          'quote${n == 1 ? '' : 's'}?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete All Permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _bulkInProgress = true);
    RecentlyDeletedBulkDeleteResult result;
    try {
      result = await widget.onPermanentlyDeleteAll(entries);
    } finally {
      if (mounted) setState(() => _bulkInProgress = false);
    }
    if (!mounted) return;
    await _reload(preserveScroll: false);

    final messenger = ScaffoldMessenger.of(context);
    if (result.failed == 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.succeeded == 1
                ? '1 order permanently deleted'
                : '${result.succeeded} orders permanently deleted',
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Permanently deleted ${result.succeeded} of ${result.attempted}. '
            '${result.failed} could not be deleted.',
          ),
        ),
      );
    }
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }

  Widget _buildCard(DeletedQuoteInfo info) {
    final busy = _busyIds.contains(info.quoteId) || _bulkInProgress;
    final days = deletedQuoteDaysRemaining(info.deletedAt, DateTime.now());
    final expiryText = days == 0
        ? 'Expires today'
        : '$days day${days == 1 ? '' : 's'} remaining';
    final original = resolveRestoreStatus(info.originalStatus);
    return Card(
      key: ValueKey<String>('deleted-card-${info.quoteId}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.customerName.isEmpty
                            ? '(No customer)'
                            : info.customerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.name.isEmpty ? '(Unnamed quote)' : info.name,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Originally: $original',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        'Deleted: ${info.deletedAt.toLocal()} · $expiryText',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.delete_outline, color: Colors.redAccent),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : () => widget.onView(info),
                  child: const Text('View'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _runRowAction(
                          info,
                          () => widget.onRestore(info),
                          preserveScroll: true,
                        ),
                  child: const Text('Restore'),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _runRowAction(
                          info,
                          () => widget.onPermanentlyDelete(info),
                          preserveScroll: true,
                        ),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Delete Permanently'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recently Deleted'),
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Text('Could not load Recently Deleted: $_loadError'),
              )
            : RefreshIndicator(
                onRefresh: () => _reload(preserveScroll: false),
                child: CustomScrollView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: const Key('delete_all_permanently_button'),
                            onPressed:
                                _bulkInProgress ||
                                    entries == null ||
                                    entries.isEmpty
                                ? null
                                : _confirmAndDeleteAll,
                            icon: const Icon(Icons.delete_forever),
                            label: const Text(
                              kDeleteAllQuotesPermanentlyButtonLabel,
                              textAlign: TextAlign.center,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _sectionHeader('Recently Deleted'),
                    ),
                    if (entries == null || entries.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No recently deleted quotes.\n'
                              'Deleted orders appear here for 30 days.',
                              textAlign: TextAlign.center,
                              key: Key('recently_deleted_empty_state'),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          return _buildCard(entries[index]);
                        }, childCount: entries.length),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
      ),
    );
  }
}

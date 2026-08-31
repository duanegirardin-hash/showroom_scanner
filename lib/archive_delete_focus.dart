/// Focus/keyboard helpers for Archive and Recently Deleted delete workflows.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Archive tab bulk permanent-delete button label (Recently Deleted screen).
const String kDeleteAllQuotesPermanentlyButtonLabel =
    'DELETE ALL QUOTES PERMANENTLY';

/// Drops text-input focus and hides the soft keyboard before/after Archive
/// delete confirmations so repeated deletes are not interrupted.
///
/// Pass any app-owned [FocusNode]s that may still be registered globally
/// (Load Quote search, Scan quick entry, etc.) even when their widgets are
/// not mounted on the Archive tab.
void releaseArchiveDeleteWorkflowFocus({
  Iterable<FocusNode> extraNodes = const [],
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  for (final node in extraNodes) {
    if (node.hasFocus) {
      node.unfocus();
    }
  }
  SystemChannels.textInput.invokeMethod('TextInput.hide');
}

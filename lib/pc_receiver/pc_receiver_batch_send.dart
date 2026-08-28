import 'pc_receiver_client.dart';
import 'pc_receiver_pairing.dart';
import '../quote_emun_csv.dart';

/// One quote eligible for PC transfer in a batch send.
class PcReceiverQuoteSendTarget {
  const PcReceiverQuoteSendTarget({
    required this.quoteId,
    required this.quoteName,
    required this.customerId,
    required this.customerName,
    required this.loadQuoteJson,
  });

  final String quoteId;
  final String quoteName;
  final String customerId;
  final String customerName;
  final Future<Map<String, dynamic>?> Function() loadQuoteJson;
}

/// Outcome for one quote in a batch PC transfer.
class PcReceiverBatchItemOutcome {
  const PcReceiverBatchItemOutcome({
    required this.quoteId,
    required this.quoteName,
    required this.result,
  });

  final String quoteId;
  final String quoteName;
  final PcSendResult result;
}

/// Aggregated results after sending multiple quotes to the PC Receiver.
class PcReceiverBatchSendSummary {
  const PcReceiverBatchSendSummary({
    required this.total,
    required this.outcomes,
  });

  final int total;
  final List<PcReceiverBatchItemOutcome> outcomes;

  int get sentCount =>
      outcomes.where((o) => o.result.kind == PcSendKind.sent).length;

  int get alreadyOnPcCount =>
      outcomes.where((o) => o.result.kind == PcSendKind.alreadyOnPc).length;

  int get failedCount => outcomes
      .where(
        (o) =>
            o.result.kind != PcSendKind.sent &&
            o.result.kind != PcSendKind.alreadyOnPc,
      )
      .length;
}

Future<PcSendResult> sendPreparedQuoteToPcReceiver({
  required PcReceiverClient client,
  required PcReceiverPairing pairing,
  required String quoteId,
  required String quoteName,
  required String customerId,
  required String customerName,
  required Map<String, dynamic> data,
  required String Function(Map<String, dynamic> data) formatCsv,
  String Function(Map<String, dynamic> data)? buildTransferFilename,
}) async {
  final csv = formatCsv(data);
  final builtTransferName = buildTransferFilename?.call(data).trim() ?? '';
  final meta = quoteTransferMetadata(
    data,
    fallbackCustomerId: customerId,
    fallbackCustomerName: customerName,
    fallbackQuoteName: quoteName,
  );
  final transferQuoteName = resolvePcTransferQuoteName(
    data,
    buildTransferFilename: buildTransferFilename,
    fallbackCustomerId: customerId,
    fallbackCustomerName: customerName,
    fallbackQuoteName: quoteName,
  );
  return client.sendQuote(
    pairing: pairing,
    quoteId: meta.quoteId.isNotEmpty ? meta.quoteId : quoteId,
    customerId: meta.customerId,
    customerName: meta.customerName,
    quoteName: transferQuoteName,
    csvText: csv,
  );
}

Future<PcReceiverBatchSendSummary> runPcReceiverBatchSend({
  required PcReceiverClient client,
  required PcReceiverPairing pairing,
  required List<PcReceiverQuoteSendTarget> targets,
  required String Function(Map<String, dynamic> data) formatCsv,
  String Function(Map<String, dynamic> data)? buildTransferFilename,
}) async {
  final outcomes = <PcReceiverBatchItemOutcome>[];
  for (final target in targets) {
    final data = await target.loadQuoteJson();
    if (data == null) {
      outcomes.add(
        PcReceiverBatchItemOutcome(
          quoteId: target.quoteId,
          quoteName: target.quoteName,
          result: const PcSendResult(
            kind: PcSendKind.failed,
            title: 'COULD NOT SEND',
            body: 'This quote could not be read.',
          ),
        ),
      );
      continue;
    }

    final result = await sendPreparedQuoteToPcReceiver(
      client: client,
      pairing: pairing,
      quoteId: target.quoteId,
      quoteName: target.quoteName,
      customerId: target.customerId,
      customerName: target.customerName,
      data: data,
      formatCsv: formatCsv,
      buildTransferFilename: buildTransferFilename,
    );
    outcomes.add(
      PcReceiverBatchItemOutcome(
        quoteId: target.quoteId,
        quoteName: target.quoteName,
        result: result,
      ),
    );
  }
  return PcReceiverBatchSendSummary(total: targets.length, outcomes: outcomes);
}

String formatPcReceiverBatchSummaryBody(PcReceiverBatchSendSummary summary) {
  final lines = <String>[
    if (summary.total == 1)
      '1 quote processed'
    else
      '${summary.total} quotes processed',
    if (summary.sentCount == 1)
      '1 sent successfully'
    else
      '${summary.sentCount} sent successfully',
    if (summary.alreadyOnPcCount == 1)
      '1 already on PC'
    else
      '${summary.alreadyOnPcCount} already on PC',
    if (summary.failedCount == 1)
      '1 failed'
    else
      '${summary.failedCount} failed',
  ];

  final failed = summary.outcomes
      .where(
        (o) =>
            o.result.kind != PcSendKind.sent &&
            o.result.kind != PcSendKind.alreadyOnPc,
      )
      .toList();
  if (failed.isNotEmpty) {
    lines.add('');
    lines.add('Could not send:');
    for (final item in failed) {
      final label = item.quoteName.trim().isNotEmpty
          ? item.quoteName.trim()
          : item.quoteId;
      lines.add(label);
    }
  }
  return lines.join('\n');
}

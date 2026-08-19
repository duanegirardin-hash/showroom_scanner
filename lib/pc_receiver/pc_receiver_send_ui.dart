import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'pc_receiver_client.dart';
import 'pc_receiver_pairing.dart';
import 'pc_receiver_store.dart';
import '../quote_emun_csv.dart';

enum PcReceiverNotFoundChoice { tryAgain, pairChange, cancel }

enum PcReceiverSendChoice { send, changePc, cancel }

Future<void> showPcReceiverSendFlow({
  required BuildContext context,
  required String quoteId,
  required String quoteName,
  required String customerId,
  required String customerName,
  required Future<Map<String, dynamic>?> Function() loadQuoteJson,
  required String Function(Map<String, dynamic> data) formatCsv,
  PcReceiverStore? store,
  PcReceiverClient? client,
}) async {
  final pairStore = store ?? PcReceiverStore();
  final httpClient = client ?? PcReceiverClient();
  var pairing = await pairStore.load();

  while (context.mounted) {
    if (pairing == null) {
      final startPair = await showDialog<bool>(
        context: context,
        builder: (ctx) => const PcReceiverNoPairDialog(),
      );
      if (startPair != true || !context.mounted) return;
      pairing = await showPcReceiverPairDialog(
        context: context,
        store: pairStore,
      );
      continue;
    }

    final ping = await httpClient.ping(pairing);
    if (!context.mounted) return;

    if (ping.kind == PcSendKind.pcNotFound ||
        ping.kind == PcSendKind.unauthorized ||
        ping.kind == PcSendKind.notReady) {
      final choice = await showDialog<PcReceiverNotFoundChoice>(
        context: context,
        builder: (ctx) => PcReceiverNotFoundDialog(result: ping),
      );
      if (!context.mounted) return;
      if (choice == PcReceiverNotFoundChoice.tryAgain) {
        continue;
      }
      if (choice == PcReceiverNotFoundChoice.pairChange) {
        final next = await showPcReceiverPairDialog(
          context: context,
          store: pairStore,
          existing: pairing,
        );
        if (next != null) pairing = next;
        continue;
      }
      return;
    }

    final sendChoice = await showDialog<PcReceiverSendChoice>(
      context: context,
      builder: (ctx) => PcReceiverSendConfirmDialog(
        pairing: pairing!,
        quoteName: quoteName,
        customerName: customerName,
      ),
    );
    if (!context.mounted) return;
    if (sendChoice == PcReceiverSendChoice.changePc) {
      final next = await showPcReceiverPairDialog(
        context: context,
        store: pairStore,
        existing: pairing,
      );
      if (next != null) pairing = next;
      continue;
    }
    if (sendChoice != PcReceiverSendChoice.send) return;

    final data = await loadQuoteJson();
    if (!context.mounted) return;
    if (data == null) {
      await _showResult(
        context,
        const PcSendResult(
          kind: PcSendKind.failed,
          title: 'COULD NOT SEND',
          body: 'This quote could not be read.',
        ),
      );
      return;
    }

    final csv = formatCsv(data);
    final meta = quoteTransferMetadata(
      data,
      fallbackCustomerId: customerId,
      fallbackCustomerName: customerName,
    );
    final result = await httpClient.sendQuote(
      pairing: pairing,
      quoteId: meta.quoteId.isNotEmpty ? meta.quoteId : quoteId,
      customerId: meta.customerId,
      customerName: meta.customerName,
      csvText: csv,
    );
    if (!context.mounted) return;
    await _showResult(context, result);
    return;
  }
}

class PcReceiverNoPairDialog extends StatelessWidget {
  const PcReceiverNoPairDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('NO PC PAIRED'),
      content: const Text('Pair this phone with the PC Receiver first.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('PAIR WITH PC'),
        ),
      ],
    );
  }
}

class PcReceiverNotFoundDialog extends StatelessWidget {
  const PcReceiverNotFoundDialog({super.key, required this.result});

  final PcSendResult result;

  @override
  Widget build(BuildContext context) {
    final body = result.kind == PcSendKind.pcNotFound
        ? 'Make sure the PC Receiver is running and both devices are on\nthe same Wi-Fi network.'
        : result.body;
    return AlertDialog(
      title: Text(result.title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, PcReceiverNotFoundChoice.cancel),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, PcReceiverNotFoundChoice.tryAgain),
          child: const Text('TRY AGAIN'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, PcReceiverNotFoundChoice.pairChange),
          child: const Text('PAIR / CHANGE PC'),
        ),
      ],
    );
  }
}

class PcReceiverSendConfirmDialog extends StatelessWidget {
  const PcReceiverSendConfirmDialog({
    super.key,
    required this.pairing,
    required this.quoteName,
    required this.customerName,
  });

  final PcReceiverPairing pairing;
  final String quoteName;
  final String customerName;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('SEND TO PC'),
      content: Text(
        [
          'PC Receiver',
          pairing.displaySummary,
          '',
          customerName.isEmpty ? quoteName : customerName,
          if (quoteName.isNotEmpty) quoteName,
          '',
          'Sends this quote only. Does not archive or email.',
        ].join('\n'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, PcReceiverSendChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, PcReceiverSendChoice.changePc),
          child: const Text('CHANGE PAIRED PC'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, PcReceiverSendChoice.send),
          child: const Text('SEND TO PC'),
        ),
      ],
    );
  }
}

Future<void> _showResult(BuildContext context, PcSendResult result) {
  debugPrint('[PcReceiver] ${result.kind} ${result.technicalLog}');
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(result.title),
      content: Text(result.body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<PcReceiverPairing?> showPcReceiverPairDialog({
  required BuildContext context,
  required PcReceiverStore store,
  PcReceiverPairing? existing,
}) {
  return showDialog<PcReceiverPairing>(
    context: context,
    builder: (ctx) => _PairPcDialog(store: store, existing: existing),
  );
}

class _PairPcDialog extends StatefulWidget {
  const _PairPcDialog({required this.store, this.existing});

  final PcReceiverStore store;
  final PcReceiverPairing? existing;

  @override
  State<_PairPcDialog> createState() => _PairPcDialogState();
}

class _PairPcDialogState extends State<_PairPcDialog> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _token;
  PcReceiverPairing? _ready;
  var _showManual = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ready = widget.existing;
    _host = TextEditingController(text: widget.existing?.host ?? '');
    _port = TextEditingController(
      text: '${widget.existing?.port ?? PcReceiverPairing.defaultPort}',
    );
    _token = TextEditingController(text: widget.existing?.token ?? '');
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  void _applyPairing(PcReceiverPairing parsed) {
    _host.text = parsed.host;
    _port.text = '${parsed.port}';
    _token.text = parsed.token;
    setState(() {
      _ready = parsed;
      _error = null;
    });
  }

  Future<void> _scan() async {
    final parsed = await Navigator.of(context).push<PcReceiverPairing>(
      MaterialPageRoute(builder: (_) => const _PairQrScanPage()),
    );
    if (parsed == null || !mounted) return;
    _applyPairing(parsed);
  }

  Future<void> _save() async {
    final fromScan = _ready;
    final parsed =
        fromScan ??
        PcReceiverPairing.tryParseFields(
          host: _host.text,
          port: int.tryParse(_port.text.trim()) ?? -1,
          token: _token.text,
          pcName: widget.existing?.pcName ?? '',
        );
    if (parsed == null) {
      setState(
        () => _error =
            'Scan the PC Receiver QR code, or enter the address and port.',
      );
      return;
    }
    await widget.store.save(parsed);
    if (!mounted) return;
    Navigator.pop(context, parsed);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    return AlertDialog(
      title: const Text('PAIR WITH PC'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'On the PC Receiver tap PAIR PHONE so the QR code is showing, then scan it.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('SCAN QR CODE'),
            ),
            if (ready != null) ...[
              const SizedBox(height: 16),
              Text(
                'PC Receiver',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(ready.displaySummary),
              const SizedBox(height: 4),
              const Text('Pairing code received.'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _showManual = !_showManual),
              child: Text(
                _showManual
                    ? 'Hide manual entry'
                    : 'Enter details manually instead',
              ),
            ),
            if (_showManual) ...[
              TextField(
                controller: _host,
                decoration: const InputDecoration(
                  labelText: 'PC address',
                  hintText: '192.168.x.x',
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _ready = null),
              ),
              TextField(
                controller: _port,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() => _ready = null),
              ),
              TextField(
                controller: _token,
                decoration: const InputDecoration(labelText: 'Pairing token'),
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                onChanged: (_) => setState(() => _ready = null),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('SAVE')),
      ],
    );
  }
}

class _PairQrScanPage extends StatefulWidget {
  const _PairQrScanPage();

  @override
  State<_PairQrScanPage> createState() => _PairQrScanPageState();
}

class _PairQrScanPageState extends State<_PairQrScanPage> {
  var _handled = false;
  String? _hint;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final v = barcode.rawValue;
      if (v == null || v.isEmpty) continue;
      final parsed = PcReceiverPairing.tryParse(v);
      if (parsed == null) {
        setState(() {
          _hint =
              'That is not a PC Receiver pairing QR. Point at the PAIR PHONE window.';
        });
        continue;
      }
      _handled = true;
      Navigator.pop(context, parsed);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SCAN QR CODE')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _hint ?? 'Point the camera at the PC Receiver QR code.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

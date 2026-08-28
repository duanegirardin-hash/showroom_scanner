import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showroom_scanner/pc_receiver/pc_receiver_client.dart';
import 'package:showroom_scanner/pc_receiver/pc_receiver_pairing.dart';
import 'package:showroom_scanner/pc_receiver/pc_receiver_send_ui.dart';
import 'package:showroom_scanner/pc_receiver/pc_receiver_store.dart';

void main() {
  const token = 'phase3-test-token-32chars-ok';

  PcReceiverPairing pairing({String host = '192.168.1.20'}) =>
      PcReceiverPairing.tryParseFields(
        host: host,
        port: 17855,
        token: token,
        pcName: 'TEST-PC',
      )!;

  Future<T?> pumpDialog<T>(
    WidgetTester tester,
    Widget dialog,
  ) async {
    T? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                result = await showDialog<T>(
                  context: context,
                  builder: (_) => dialog,
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('no PC paired offers PAIR WITH PC', (tester) async {
    await pumpDialog<bool>(tester, const PcReceiverNoPairDialog());
    expect(find.text('NO PC PAIRED'), findsOneWidget);
    expect(find.text('PAIR WITH PC'), findsOneWidget);
    expect(find.text('CANCEL'), findsOneWidget);
    await tester.tap(find.text('PAIR WITH PC'));
    await tester.pumpAndSettle();
  });

  testWidgets('SEND TO PC mode dialog offers current and all customer options', (
    tester,
  ) async {
    await pumpDialog<PcReceiverSendMode>(
      tester,
      const PcReceiverSendModeDialog(),
    );
    expect(find.text('SEND TO PC'), findsOneWidget);
    expect(find.text('Send Current Quote to PC'), findsOneWidget);
    expect(
      find.text('Send All Current Quotes for This Customer to PC'),
      findsOneWidget,
    );
    await tester.tap(find.text('Send Current Quote to PC'));
    await tester.pumpAndSettle();
  });

  testWidgets('send all confirm dialog shows quote count', (tester) async {
    await pumpDialog<PcReceiverSendChoice>(
      tester,
      PcReceiverSendAllConfirmDialog(
        pairing: pairing(),
        customerName: "PETER & PAUL'S BASKETS & GIFTS",
        quoteCount: 4,
      ),
    );
    expect(find.textContaining('4 current quotes'), findsOneWidget);
    expect(find.textContaining("PETER & PAUL'S BASKETS & GIFTS"), findsOneWidget);
    expect(find.text('SEND TO PC'), findsWidgets);
  });

  testWidgets('reachable PC shows SEND TO PC and CHANGE PAIRED PC', (
    tester,
  ) async {
    await pumpDialog<PcReceiverSendChoice>(
      tester,
      PcReceiverSendConfirmDialog(
        pairing: pairing(),
        quoteName: 'EVERYDAY QUOTE',
        customerName: 'DUANE GIRARDIN',
      ),
    );
    expect(find.text('SEND TO PC'), findsWidgets);
    expect(find.text('CHANGE PAIRED PC'), findsOneWidget);
    expect(find.textContaining('192.168.1.20:17855'), findsOneWidget);
    await tester.tap(find.text('CHANGE PAIRED PC'));
    await tester.pumpAndSettle();
  });

  testWidgets('unreachable PC offers TRY AGAIN, PAIR / CHANGE PC, CANCEL', (
    tester,
  ) async {
    late PcReceiverNotFoundChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                choice = await showDialog<PcReceiverNotFoundChoice>(
                  context: context,
                  builder: (_) => PcReceiverNotFoundDialog(
                    result: const PcSendResult(
                      kind: PcSendKind.pcNotFound,
                      title: 'PC NOT FOUND',
                      body: 'unused',
                    ),
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('PC NOT FOUND'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(find.text('PAIR / CHANGE PC'), findsOneWidget);
    expect(find.text('CANCEL'), findsOneWidget);
    expect(find.text('OK'), findsNothing);
    await tester.tap(find.text('PAIR / CHANGE PC'));
    await tester.pumpAndSettle();
    expect(choice, PcReceiverNotFoundChoice.pairChange);
  });

  testWidgets('PAIR WITH PC screen has SCAN QR CODE', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox.shrink(),
        ),
      ),
    );
    final ctx = tester.element(find.byType(SizedBox));
    final future = showPcReceiverPairDialog(
      context: ctx,
      store: PcReceiverStoreForTest(),
    );
    await tester.pumpAndSettle();
    expect(find.text('PAIR WITH PC'), findsOneWidget);
    expect(find.text('SCAN QR CODE'), findsOneWidget);
    expect(find.text('Enter details manually instead'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await future, isNull);
  });

  test('quote remains unchanged on pairing-only PcSendResult', () {
    const r = PcSendResult(
      kind: PcSendKind.pcNotFound,
      title: 'PC NOT FOUND',
      body: 'Make sure the PC Receiver is running',
    );
    expect(r.quoteUnchanged, isTrue);
  });
}

class PcReceiverStoreForTest extends PcReceiverStore {
  PcReceiverStoreForTest() : super(documentsOverride: () {
    throw UnsupportedError('pairing dialog cancel must not persist');
  });
}

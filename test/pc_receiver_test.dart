import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:showroom_scanner/pc_receiver/pc_receiver_client.dart';
import 'package:showroom_scanner/pc_receiver/pc_receiver_pairing.dart';
import 'package:showroom_scanner/pc_receiver/pc_receiver_store.dart';
import 'package:showroom_scanner/quote_emun_csv.dart';

void main() {
  const token = 'phase3-test-token-32chars-ok';

  PcReceiverPairing pairing() => PcReceiverPairing.tryParseFields(
    host: '192.168.1.20',
    port: 17855,
    token: token,
    pcName: 'TEST-PC',
  )!;

  group('pairing', () {
    test('parses versioned URI', () {
      final p = pairing();
      final again = PcReceiverPairing.tryParse(p.toPairingUri());
      expect(again?.host, '192.168.1.20');
      expect(again?.port, 17855);
      expect(again?.token, token);
    });

    test('parses PC Receiver QR URI including encoded PC name', () {
      const raw =
          'showroomscanner-pc://pair?v=1&host=192.168.1.20&port=17855'
          '&token=phase3-test-token-32chars-ok&name=Duane%27s+PC';
      final parsed = PcReceiverPairing.tryParse(raw);
      expect(parsed, isNotNull);
      expect(parsed!.host, '192.168.1.20');
      expect(parsed.port, 17855);
      expect(parsed.token, token);
      expect(parsed.pcName, "Duane's PC");
      expect(parsed.displaySummary.contains(token), isFalse);
      expect(parsed.displaySummary, contains('192.168.1.20:17855'));
    });

    test('rejects ordinary product barcodes', () {
      expect(PcReceiverPairing.tryParse('062823204669'), isNull);
      expect(PcReceiverPairing.tryParse('https://example.com'), isNull);
    });

    test('parses JSON payload', () {
      final raw = jsonEncode(pairing().toJson());
      final again = PcReceiverPairing.tryParse(raw);
      expect(again?.host, '192.168.1.20');
      expect(again?.token, token);
    });

    test('rejects destination path in payload', () {
      expect(
        PcReceiverPairing.tryParseMap({
          'host': '192.168.1.20',
          'port': 17855,
          'token': token,
          'destination_folder': r'C:\Windows',
        }),
        isNull,
      );
    });

    test('rejects short token and missing pairing', () {
      expect(
        PcReceiverPairing.tryParseFields(
          host: '192.168.1.20',
          port: 17855,
          token: 'short',
        ),
        isNull,
      );
    });

    test('store round-trip', () async {
      final dir = Directory.systemTemp.createTempSync('pcpair');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final store = PcReceiverStore(documentsOverride: () => dir);
      expect(await store.load(), isNull);
      await store.save(pairing());
      final loaded = await store.load();
      expect(loaded?.host, '192.168.1.20');
      expect(loaded?.token, token);
      await store.clear();
      expect(await store.load(), isNull);
    });

    test('save replaces old address only after save; cancel leaves old pairing', () async {
      final dir = Directory.systemTemp.createTempSync('pcpair2');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final store = PcReceiverStore(documentsOverride: () => dir);
      await store.save(pairing());
      expect((await store.load())?.host, '192.168.1.20');

      final replacement = PcReceiverPairing.tryParseFields(
        host: '172.20.10.5',
        port: 17855,
        token: 'replacement-token-32chars-ok!!',
        pcName: 'HOTSPOT-PC',
      )!;
      // Cancel path: never call save.
      expect((await store.load())?.host, '192.168.1.20');
      expect((await store.load())?.token, token);

      await store.save(replacement);
      final loaded = await store.load();
      expect(loaded?.host, '172.20.10.5');
      expect(loaded?.token, 'replacement-token-32chars-ok!!');
    });
  });

  group('CSV Item,Quantity', () {
    test('matches compact EMUN export', () {
      final csv = formatQuoteAsEmunCsv({
        'id': '1786661863097',
        'customer': {'id': '0DG', 'companyName': 'DUANE GIRARDIN'},
        'lines': [
          {'itemNumber': '20466', 'quantity': 12, 'price': 1.1},
        ],
      });
      expect(csv, 'Item,Quantity\n20466,12');
      expect(csv.contains('price'), isFalse);
      expect(csv.contains('DUANE'), isFalse);
    });

    test('metadata stays outside CSV', () {
      final meta = quoteTransferMetadata({
        'id': '1786661863097',
        'customer': {'id': '0DG', 'companyName': 'DUANE GIRARDIN'},
        'lines': [
          {'itemNumber': '20466', 'quantity': 12},
        ],
      });
      expect(meta.quoteId, '1786661863097');
      expect(meta.customerId, '0DG');
      expect(meta.customerName, 'DUANE GIRARDIN');
    });
  });

  group('client', () {
    test('missing pairing', () async {
      final client = PcReceiverClient(httpClient: MockClient((_) async {
        fail('should not call network');
      }));
      final r = await client.sendQuote(
        pairing: null,
        quoteId: '1',
        customerId: '0DG',
        customerName: 'DUANE GIRARDIN',
        csvText: 'Item,Quantity\n20466,12',
      );
      expect(r.kind, PcSendKind.notPaired);
      expect(r.quoteUnchanged, isTrue);
    });

    test('invalid token', () async {
      final client = PcReceiverClient(
        httpClient: MockClient((req) async {
          expect(req.headers['x-showroom-pair-token'], token);
          return http.Response('{"overall":"failed","code":"unauthorized"}', 401);
        }),
      );
      final r = await client.sendQuote(
        pairing: pairing(),
        quoteId: '1',
        customerId: '0DG',
        customerName: 'DUANE GIRARDIN',
        csvText: 'Item,Quantity\n20466,12',
      );
      expect(r.kind, PcSendKind.unauthorized);
      expect(r.quoteUnchanged, isTrue);
    });

    test('receiver unreachable', () async {
      final client = PcReceiverClient(
        httpClient: MockClient((_) async {
          throw const SocketException('connection refused');
        }),
      );
      final r = await client.sendQuote(
        pairing: pairing(),
        quoteId: '1',
        customerId: '0DG',
        customerName: 'DUANE GIRARDIN',
        csvText: 'Item,Quantity\n20466,12',
      );
      expect(r.kind, PcSendKind.pcNotFound);
      expect(r.title, 'PC NOT FOUND');
      expect(r.quoteUnchanged, isTrue);
    });

    test('successful acknowledgement', () async {
      final client = PcReceiverClient(
        httpClient: MockClient((req) async {
          expect(req.url.path, '/ingest');
          final body = jsonDecode(req.body) as Map;
          expect(body['quote_id'], '1786661863097');
          expect((body['csv_text'] as String).startsWith('Item,Quantity'), isTrue);
          return http.Response(
            jsonEncode({
              'overall': 'received',
              'received': 1,
              'duplicate': 0,
              'failed': 0,
              'results': [
                {
                  'status': 'received',
                  'code': 'ok',
                  'quote_id': '1786661863097',
                },
              ],
            }),
            200,
          );
        }),
      );
      final r = await client.sendQuote(
        pairing: pairing(),
        quoteId: '1786661863097',
        customerId: '0DG',
        customerName: 'DUANE GIRARDIN',
        csvText: 'Item,Quantity\n20466,12',
      );
      expect(r.kind, PcSendKind.sent);
      expect(r.title, 'SENT TO PC');
      expect(r.quoteUnchanged, isTrue);
    });

    test('duplicate acknowledgement', () async {
      final client = PcReceiverClient(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'overall': 'received',
              'received': 0,
              'duplicate': 1,
              'failed': 0,
              'results': [
                {
                  'status': 'duplicate',
                  'code': 'already_received',
                },
              ],
            }),
            200,
          ),
        ),
      );
      final r = await client.sendQuote(
        pairing: pairing(),
        quoteId: '1786661863097',
        customerId: '0DG',
        customerName: 'DUANE GIRARDIN',
        csvText: 'Item,Quantity\n20466,12',
      );
      expect(r.kind, PcSendKind.alreadyOnPc);
      expect(r.title, 'ALREADY ON PC');
    });

    test('invalid receiver response', () async {
      final client = PcReceiverClient(
        httpClient: MockClient((_) async => http.Response('not-json', 200)),
      );
      final r = await client.sendQuote(
        pairing: pairing(),
        quoteId: '1',
        customerId: '0DG',
        customerName: 'DUANE GIRARDIN',
        csvText: 'Item,Quantity\n20466,12',
      );
      expect(r.kind, PcSendKind.failed);
      expect(r.quoteUnchanged, isTrue);
    });

    test('timeout', () async {
      final client = PcReceiverClient(
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('{}', 200);
        }),
      );
      final r = await client.sendQuote(
        pairing: pairing(),
        quoteId: '1',
        customerId: '0DG',
        customerName: 'DUANE GIRARDIN',
        csvText: 'Item,Quantity\n20466,12',
      );
      expect(r.kind, PcSendKind.pcNotFound);
      expect(r.quoteUnchanged, isTrue);
    });
  });
}

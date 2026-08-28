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
        'name': 'EVERYDAY QUOTE_2026_08_27_003',
        'customer': {'id': '0DG', 'companyName': 'DUANE GIRARDIN'},
        'lines': [
          {'itemNumber': '20466', 'quantity': 12},
        ],
      });
      expect(meta.quoteId, '1786661863097');
      expect(meta.customerId, '0DG');
      expect(meta.customerName, 'DUANE GIRARDIN');
      expect(meta.quoteName, 'EVERYDAY QUOTE_2026_08_27_003');
    });

    test('quote name falls back when JSON name is empty', () {
      final meta = quoteTransferMetadata(
        {'id': '1', 'customer': {'id': '0DG', 'companyName': 'DUANE GIRARDIN'}},
        fallbackQuoteName: 'FALLBACK QUOTE NAME',
      );
      expect(meta.quoteName, 'FALLBACK QUOTE NAME');
    });

    test('wrapQuoteTypeForPcTransferBasename brackets quote type generically', () {
      expect(
        wrapQuoteTypeForPcTransferBasename(
          'EVERYDAY_QUOTE_2026_08_27_001_PETER_PAUL_S_BASKETS_GIFTS_'
          '20260827_175033_025',
        ),
        '[EVERYDAY_QUOTE]_2026_08_27_001_PETER_PAUL_S_BASKETS_GIFTS_'
        '20260827_175033_025',
      );
      expect(
        wrapQuoteTypeForPcTransferBasename(
          'CHRISTMAS_QUOTE_2026_12_25_002_BIG_DOLLAR_20261225_120000_000',
        ),
        '[CHRISTMAS_QUOTE]_2026_12_25_002_BIG_DOLLAR_20261225_120000_000',
      );
      expect(
        wrapQuoteTypeForPcTransferBasename(
          'EASTER_QUOTE_2026_04_20_001_DUANE_GIRARDIN_20260420_090000_000',
        ),
        '[EASTER_QUOTE]_2026_04_20_001_DUANE_GIRARDIN_20260420_090000_000',
      );
    });

    test('buildPcTransferQuoteFilenameStem brackets quote type for PC transfer', () {
      const exportBase =
          'EVERYDAY_QUOTE_2026_08_27_001_WM_LIQUIDATION_1536448_ONTARIO_INC_'
          '20260827_173514_362';
      const expected =
          '1787866440577_[EVERYDAY_QUOTE]_2026_08_27_001_WM_LIQUIDATION_'
          '1536448_ONTARIO_INC_20260827_173514_362';
      expect(
        buildPcTransferQuoteFilenameStem(
          quoteId: '1787866440577',
          exportBasenameWithoutExtension: exportBase,
        ),
        expected,
      );
    });

    test('resolvePcTransferQuoteName prefers export-style builder', () {
      const fullName =
          '1787866440577_[EVERYDAY_QUOTE]_2026_08_27_001_WM_LIQUIDATION_'
          '1536448_ONTARIO_INC_20260827_173514_362';
      final resolved = resolvePcTransferQuoteName(
        {
          'id': '1787866440577',
          'name': 'EVERYDAY QUOTE_2026_08_27_001',
          'customer': {
            'id': '200667',
            'companyName': 'WM LIQUIDATION / 1536448 ONTARIO INC.',
          },
        },
        buildTransferFilename: (_) => fullName,
      );
      expect(resolved, fullName);
    });

    test('resolvePcTransferQuoteName falls back to stored quote name', () {
      final resolved = resolvePcTransferQuoteName(
        {
          'id': '1787866440577',
          'name': 'EVERYDAY QUOTE_2026_08_27_001',
        },
      );
      expect(resolved, 'EVERYDAY QUOTE_2026_08_27_001');
    });

    test('barcode-corrupted name resolves to bucket label for PC bracket type', () {
      final parsedType = resolveQuoteExportTypeCandidate(
        parsedQuoteType: '062823532588_GENERAL_QUOTE',
        quoteBucketLabel: 'SUMMER GENERAL',
      );
      expect(parsedType, 'SUMMER GENERAL QUOTE');
      const exportBase =
          'SUMMER_GENERAL_QUOTE_2026_08_28_001_YOUR_STORE_W_MORE_505_RON_'
          '20260828_121548_660';
      final pc = buildPcTransferQuoteFilenameStem(
        quoteId: '1787931361156',
        exportBasenameWithoutExtension: exportBase,
      );
      expect(pc, contains('[SUMMER_GENERAL_QUOTE]'));
      expect(wrapQuoteTypeForPcTransferBasename(exportBase), startsWith('[SUMMER_GENERAL_QUOTE]'));
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
        quoteName: 'EVERYDAY QUOTE_2026_08_27_003',
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
        quoteName: 'EVERYDAY QUOTE_2026_08_27_003',
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
        quoteName: 'EVERYDAY QUOTE_2026_08_27_003',
        csvText: 'Item,Quantity\n20466,12',
      );
      expect(r.kind, PcSendKind.pcNotFound);
      expect(r.title, 'PC NOT FOUND');
      expect(r.quoteUnchanged, isTrue);
    });

    test('successful acknowledgement sends full export-style quote_name', () async {
      const quoteName =
          '1787866440577_[EVERYDAY_QUOTE]_2026_08_27_001_WM_LIQUIDATION_'
          '1536448_ONTARIO_INC_20260827_173514_362';
      final client = PcReceiverClient(
        httpClient: MockClient((req) async {
          expect(req.url.path, '/ingest');
          final body = jsonDecode(req.body) as Map;
          expect(body['quote_id'], '1787866440577');
          expect(body['customer_id'], '200667');
          expect(body['customer_name'], contains('WM LIQUIDATION'));
          expect(body['quote_name'], quoteName);
          expect((body['csv_text'] as String).startsWith('Item,Quantity'), isTrue);
          expect((body['csv_text'] as String).contains('WM LIQUIDATION'), isFalse);
          expect((body['csv_text'] as String).contains(quoteName), isFalse);
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
                  'quote_id': '1787866440577',
                },
              ],
            }),
            200,
          );
        }),
      );
      final r = await client.sendQuote(
        pairing: pairing(),
        quoteId: '1787866440577',
        customerId: '200667',
        customerName: 'WM LIQUIDATION _ 1536448 ONTARIO INC',
        quoteName: quoteName,
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
        quoteName: 'EVERYDAY QUOTE_2026_08_27_003',
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
        quoteName: 'EVERYDAY QUOTE_2026_08_27_003',
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
        quoteName: 'EVERYDAY QUOTE_2026_08_27_003',
        csvText: 'Item,Quantity\n20466,12',
      );
      expect(r.kind, PcSendKind.pcNotFound);
      expect(r.quoteUnchanged, isTrue);
    });
  });
}

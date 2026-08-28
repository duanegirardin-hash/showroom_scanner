import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:showroom_scanner/pc_receiver/pc_receiver_batch_send.dart';
import 'package:showroom_scanner/pc_receiver/pc_receiver_client.dart';
import 'package:showroom_scanner/pc_receiver/pc_receiver_pairing.dart';
import 'package:showroom_scanner/quote_emun_csv.dart';

void main() {
  const token = 'phase3-test-token-32chars-ok';

  PcReceiverPairing pairing() => PcReceiverPairing.tryParseFields(
    host: '192.168.1.20',
    port: 17855,
    token: token,
    pcName: 'TEST-PC',
  )!;

  Map<String, dynamic> sampleQuote({
    required String id,
    required String name,
    required String customerId,
    required String customerName,
    String bucketKey = 'everyday',
  }) {
    return {
      'id': id,
      'name': name,
      'quoteBucketKey': bucketKey,
      'customer': {
        'id': customerId,
        'companyName': customerName,
      },
      'lines': [
        {'itemNumber': '20466', 'quantity': 12},
      ],
    };
  }

  String formatCsv(Map<String, dynamic> data) => formatQuoteAsEmunCsv(data);

  String buildTransferFilename(Map<String, dynamic> data) {
    return buildPcTransferQuoteFilenameStem(
      quoteId: (data['id'] as String?) ?? '',
      exportBasenameWithoutExtension:
          '${(data['name'] as String?) ?? ''}_PETER_PAUL_S_BASKETS_GIFTS_20260827_175033_025',
    );
  }

  group('formatPcReceiverBatchSummaryBody', () {
    test('reports sent, duplicate, and failed counts', () {
      final body = formatPcReceiverBatchSummaryBody(
        PcReceiverBatchSendSummary(
          total: 4,
          outcomes: [
            PcReceiverBatchItemOutcome(
              quoteId: '1',
              quoteName: 'EVERYDAY QUOTE',
              result: const PcSendResult(
                kind: PcSendKind.sent,
                title: 'SENT TO PC',
                body: 'ok',
              ),
            ),
            PcReceiverBatchItemOutcome(
              quoteId: '2',
              quoteName: 'CHRISTMAS QUOTE',
              result: const PcSendResult(
                kind: PcSendKind.sent,
                title: 'SENT TO PC',
                body: 'ok',
              ),
            ),
            PcReceiverBatchItemOutcome(
              quoteId: '3',
              quoteName: 'EASTER QUOTE',
              result: const PcSendResult(
                kind: PcSendKind.sent,
                title: 'SENT TO PC',
                body: 'ok',
              ),
            ),
            PcReceiverBatchItemOutcome(
              quoteId: '4',
              quoteName: 'TOYS QUOTE',
              result: const PcSendResult(
                kind: PcSendKind.alreadyOnPc,
                title: 'ALREADY ON PC',
                body: 'duplicate',
              ),
            ),
          ],
        ),
      );
      expect(body, contains('4 quotes processed'));
      expect(body, contains('3 sent successfully'));
      expect(body, contains('1 already on PC'));
      expect(body, contains('0 failed'));
    });

    test('lists failed quote names', () {
      final body = formatPcReceiverBatchSummaryBody(
        PcReceiverBatchSendSummary(
          total: 2,
          outcomes: [
            PcReceiverBatchItemOutcome(
              quoteId: '1',
              quoteName: 'EVERYDAY QUOTE',
              result: const PcSendResult(
                kind: PcSendKind.sent,
                title: 'SENT TO PC',
                body: 'ok',
              ),
            ),
            PcReceiverBatchItemOutcome(
              quoteId: '2',
              quoteName: 'CHRISTMAS QUOTE',
              result: const PcSendResult(
                kind: PcSendKind.failed,
                title: 'COULD NOT SEND',
                body: 'failed',
              ),
            ),
          ],
        ),
      );
      expect(body, contains('1 failed'));
      expect(body, contains('Could not send:'));
      expect(body, contains('CHRISTMAS QUOTE'));
    });
  });

  group('runPcReceiverBatchSend', () {
    test('sends each quote in a separate request with its own QuoteID', () async {
      final sentIds = <String>[];
      final payloads = <Map<String, dynamic>>[];
      final client = PcReceiverClient(
        httpClient: MockClient((req) async {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          payloads.add(body);
          sentIds.add(body['quote_id'] as String);
          return http.Response(
            jsonEncode({
              'overall': 'received',
              'received': 1,
              'duplicate': 0,
              'failed': 0,
              'results': [
                {'status': 'received', 'code': 'ok', 'quote_id': body['quote_id']},
              ],
            }),
            200,
          );
        }),
      );

      final quotes = [
        sampleQuote(
          id: '1001',
          name: 'EVERYDAY QUOTE_2026_08_27_001',
          customerId: '300622',
          customerName: "PETER & PAUL'S BASKETS & GIFTS",
        ),
        sampleQuote(
          id: '1002',
          name: 'CHRISTMAS QUOTE_2026_08_27_001',
          customerId: '300622',
          customerName: "PETER & PAUL'S BASKETS & GIFTS",
          bucketKey: 'christmas',
        ),
      ];

      final summary = await runPcReceiverBatchSend(
        client: client,
        pairing: pairing(),
        targets: [
          for (final q in quotes)
            PcReceiverQuoteSendTarget(
              quoteId: q['id'] as String,
              quoteName: q['name'] as String,
              customerId: '300622',
              customerName: "PETER & PAUL'S BASKETS & GIFTS",
              loadQuoteJson: () async => q,
            ),
        ],
        formatCsv: formatCsv,
        buildTransferFilename: buildTransferFilename,
      );

      expect(sentIds, ['1001', '1002']);
      expect(payloads.length, 2);
      expect(summary.sentCount, 2);
      expect(summary.failedCount, 0);
    });

    test('CSV remains Item,Quantity only with quote_name in payload', () async {
      Map<String, dynamic>? lastBody;
      final client = PcReceiverClient(
        httpClient: MockClient((req) async {
          lastBody = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'overall': 'received',
              'received': 1,
              'duplicate': 0,
              'failed': 0,
              'results': [
                {'status': 'received', 'code': 'ok'},
              ],
            }),
            200,
          );
        }),
      );

      final data = sampleQuote(
        id: '1787867433025',
        name: 'EVERYDAY_QUOTE_2026_08_27_001',
        customerId: '300622',
        customerName: "PETER & PAUL'S BASKETS & GIFTS",
      );

      await runPcReceiverBatchSend(
        client: client,
        pairing: pairing(),
        targets: [
          PcReceiverQuoteSendTarget(
            quoteId: '1787867433025',
            quoteName: 'EVERYDAY_QUOTE_2026_08_27_001',
            customerId: '300622',
            customerName: "PETER & PAUL'S BASKETS & GIFTS",
            loadQuoteJson: () async => data,
          ),
        ],
        formatCsv: formatCsv,
        buildTransferFilename: buildTransferFilename,
      );

      final csv = lastBody!['csv_text'] as String;
      expect(csv.split('\n').first, 'Item,Quantity');
      expect(csv.contains('PETER'), isFalse);
      expect(csv.contains('1787867433025'), isFalse);
      final quoteName = lastBody!['quote_name'] as String;
      expect(quoteName, contains('[EVERYDAY_QUOTE]'));
      expect(quoteName, contains('1787867433025'));
    });

    test('duplicate on one quote does not block the rest', () async {
      final client = PcReceiverClient(
        httpClient: MockClient((req) async {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final id = body['quote_id'] as String;
          if (id == 'dup') {
            return http.Response(
              jsonEncode({
                'overall': 'received',
                'received': 0,
                'duplicate': 1,
                'failed': 0,
                'results': [
                  {'status': 'duplicate', 'code': 'already_received'},
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'overall': 'received',
              'received': 1,
              'duplicate': 0,
              'failed': 0,
              'results': [
                {'status': 'received', 'code': 'ok'},
              ],
            }),
            200,
          );
        }),
      );

      final summary = await runPcReceiverBatchSend(
        client: client,
        pairing: pairing(),
        targets: [
          PcReceiverQuoteSendTarget(
            quoteId: 'dup',
            quoteName: 'DUPLICATE QUOTE',
            customerId: '300622',
            customerName: 'CUSTOMER',
            loadQuoteJson: () async => sampleQuote(
              id: 'dup',
              name: 'DUPLICATE QUOTE',
              customerId: '300622',
              customerName: 'CUSTOMER',
            ),
          ),
          PcReceiverQuoteSendTarget(
            quoteId: 'ok',
            quoteName: 'OK QUOTE',
            customerId: '300622',
            customerName: 'CUSTOMER',
            loadQuoteJson: () async => sampleQuote(
              id: 'ok',
              name: 'OK QUOTE',
              customerId: '300622',
              customerName: 'CUSTOMER',
            ),
          ),
        ],
        formatCsv: formatCsv,
      );

      expect(summary.total, 2);
      expect(summary.alreadyOnPcCount, 1);
      expect(summary.sentCount, 1);
      expect(summary.failedCount, 0);
    });

    test('one failed quote does not stop remaining quotes', () async {
      final sent = <String>[];
      final client = PcReceiverClient(
        httpClient: MockClient((req) async {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final id = body['quote_id'] as String;
          sent.add(id);
          if (id == 'bad') {
            return http.Response('not-json', 200);
          }
          return http.Response(
            jsonEncode({
              'overall': 'received',
              'received': 1,
              'duplicate': 0,
              'failed': 0,
              'results': [
                {'status': 'received', 'code': 'ok'},
              ],
            }),
            200,
          );
        }),
      );

      final summary = await runPcReceiverBatchSend(
        client: client,
        pairing: pairing(),
        targets: [
          PcReceiverQuoteSendTarget(
            quoteId: 'bad',
            quoteName: 'BAD QUOTE',
            customerId: '300622',
            customerName: 'CUSTOMER',
            loadQuoteJson: () async => sampleQuote(
              id: 'bad',
              name: 'BAD QUOTE',
              customerId: '300622',
              customerName: 'CUSTOMER',
            ),
          ),
          PcReceiverQuoteSendTarget(
            quoteId: 'good',
            quoteName: 'GOOD QUOTE',
            customerId: '300622',
            customerName: 'CUSTOMER',
            loadQuoteJson: () async => sampleQuote(
              id: 'good',
              name: 'GOOD QUOTE',
              customerId: '300622',
              customerName: 'CUSTOMER',
            ),
          ),
        ],
        formatCsv: formatCsv,
      );

      expect(sent, ['bad', 'good']);
      expect(summary.sentCount, 1);
      expect(summary.failedCount, 1);
    });

    test('unreadable quote counts as failed and continues', () async {
      final client = PcReceiverClient(
        httpClient: MockClient((req) async {
          return http.Response(
            jsonEncode({
              'overall': 'received',
              'received': 1,
              'duplicate': 0,
              'failed': 0,
              'results': [
                {'status': 'received', 'code': 'ok'},
              ],
            }),
            200,
          );
        }),
      );

      final summary = await runPcReceiverBatchSend(
        client: client,
        pairing: pairing(),
        targets: [
          PcReceiverQuoteSendTarget(
            quoteId: 'missing',
            quoteName: 'MISSING QUOTE',
            customerId: '300622',
            customerName: 'CUSTOMER',
            loadQuoteJson: () async => null,
          ),
          PcReceiverQuoteSendTarget(
            quoteId: 'present',
            quoteName: 'PRESENT QUOTE',
            customerId: '300622',
            customerName: 'CUSTOMER',
            loadQuoteJson: () async => sampleQuote(
              id: 'present',
              name: 'PRESENT QUOTE',
              customerId: '300622',
              customerName: 'CUSTOMER',
            ),
          ),
        ],
        formatCsv: formatCsv,
      );

      expect(summary.failedCount, 1);
      expect(summary.sentCount, 1);
    });
  });

  group('customer quote selection (active index rows)', () {
    bool sameLogicalCustomer({
      required String customerIdA,
      required String customerNameA,
      required String customerIdB,
      required String customerNameB,
    }) {
      final idA = customerIdA.trim();
      final idB = customerIdB.trim();
      final nameA = customerNameA.trim().toLowerCase();
      final nameB = customerNameB.trim().toLowerCase();
      if (idA.isNotEmpty && idB.isNotEmpty) {
        return idA.toLowerCase() == idB.toLowerCase();
      }
      if (idA.isNotEmpty && idB.isEmpty) {
        return nameB.isNotEmpty && nameB == nameA;
      }
      if (idA.isEmpty && idB.isNotEmpty) {
        return nameA.isNotEmpty && nameA == nameB;
      }
      return nameA.isNotEmpty && nameA == nameB;
    }

    List<_TestQuoteRow> activeRowsForCustomer(
      List<_TestQuoteRow> activeIndexRows,
      String customerId,
      String customerName,
    ) {
      return activeIndexRows
          .where(
            (q) => sameLogicalCustomer(
              customerIdA: customerId,
              customerNameA: customerName,
              customerIdB: q.customerId,
              customerNameB: q.customerName,
            ),
          )
          .toList();
    }

    test('includes only active rows for the selected customer', () {
      final active = [
        _TestQuoteRow(id: '1', customerId: '300622', customerName: 'PETER'),
        _TestQuoteRow(id: '2', customerId: '300622', customerName: 'PETER'),
        _TestQuoteRow(id: '3', customerId: '999', customerName: 'OTHER'),
      ];
      final selected = activeRowsForCustomer(active, '300622', 'PETER');
      expect(selected.map((q) => q.id), ['1', '2']);
    });

    test('excludes archived confirmed and deleted by using active index only', () {
      final activeIndexOnly = [
        _TestQuoteRow(id: 'active', customerId: '300622', customerName: 'PETER'),
      ];
      final archivedOrDeleted = [
        _TestQuoteRow(id: 'archived', customerId: '300622', customerName: 'PETER'),
        _TestQuoteRow(id: 'confirmed', customerId: '300622', customerName: 'PETER'),
        _TestQuoteRow(id: 'deleted', customerId: '300622', customerName: 'PETER'),
      ];
      final selected = activeRowsForCustomer(activeIndexOnly, '300622', 'PETER');
      expect(selected.map((q) => q.id), ['active']);
      expect(archivedOrDeleted.every((q) => !selected.contains(q)), isTrue);
    });
  });
}

class _TestQuoteRow {
  _TestQuoteRow({
    required this.id,
    required this.customerId,
    required this.customerName,
  });

  final String id;
  final String customerId;
  final String customerName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TestQuoteRow &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

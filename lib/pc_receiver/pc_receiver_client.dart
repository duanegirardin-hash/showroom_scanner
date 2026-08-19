import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'pc_receiver_pairing.dart';

enum PcSendKind { sent, alreadyOnPc, pcNotFound, notPaired, unauthorized, notReady, failed }

class PcSendResult {
  const PcSendResult({
    required this.kind,
    required this.title,
    required this.body,
    this.technicalLog = '',
    this.quoteUnchanged = true,
  });

  final PcSendKind kind;
  final String title;
  final String body;
  final String technicalLog;
  final bool quoteUnchanged;

  bool get isSuccess =>
      kind == PcSendKind.sent || kind == PcSendKind.alreadyOnPc;
}

class PcReceiverClient {
  PcReceiverClient({http.Client? httpClient, Duration? timeout})
    : _http = httpClient ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 8);

  final http.Client _http;
  final Duration _timeout;

  Future<PcSendResult> ping(PcReceiverPairing? pairing) async {
    if (pairing == null) {
      return const PcSendResult(
        kind: PcSendKind.notPaired,
        title: 'NO PC PAIRED',
        body: 'Pair this phone with the PC Receiver first.',
      );
    }
    try {
      final resp = await _http
          .get(
            pairing.pingUri,
            headers: {
              'X-Showroom-Device': 'Showroom Scanner',
              ...pairing.authHeaders,
            },
          )
          .timeout(_timeout);
      return _mapPing(resp);
    } on TimeoutException catch (e) {
      return _notFound('timeout: $e');
    } on SocketException catch (e) {
      return _notFound('socket: $e');
    } on http.ClientException catch (e) {
      return _notFound('client: $e');
    } catch (e) {
      return _notFound('error: $e');
    }
  }

  Future<PcSendResult> sendQuote({
    required PcReceiverPairing? pairing,
    required String quoteId,
    required String customerId,
    required String customerName,
    required String csvText,
  }) async {
    if (pairing == null) {
      return const PcSendResult(
        kind: PcSendKind.notPaired,
        title: 'NO PC PAIRED',
        body: 'Pair this phone with the PC Receiver first.',
      );
    }
    if (!csvText.startsWith('Item,Quantity')) {
      return const PcSendResult(
        kind: PcSendKind.failed,
        title: 'COULD NOT SEND',
        body: 'Quote CSV is not in Item,Quantity format.',
        technicalLog: 'csv_header_mismatch',
      );
    }

    final payload = {
      'quote_id': quoteId,
      'customer_id': customerId,
      'customer_name': customerName,
      'csv_text': csvText,
    };

    try {
      final resp = await _http
          .post(
            pairing.ingestUri,
            headers: {
              'Content-Type': 'application/json',
              'X-Showroom-Device': 'Showroom Scanner',
              ...pairing.authHeaders,
            },
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      return _mapIngest(resp, customerName);
    } on TimeoutException catch (e) {
      return _notFound('timeout: $e');
    } on SocketException catch (e) {
      return _notFound('socket: $e');
    } on http.ClientException catch (e) {
      return _notFound('client: $e');
    } catch (e) {
      return _notFound('error: $e');
    }
  }

  PcSendResult _mapPing(http.Response resp) {
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      return const PcSendResult(
        kind: PcSendKind.unauthorized,
        title: 'NOT PAIRED WITH THIS PC',
        body: 'The pairing code does not match. Pair this phone again.',
        technicalLog: 'unauthorized ping',
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return _notFound('http ${resp.statusCode}');
    }
    try {
      final map = jsonDecode(resp.body);
      if (map is Map && map['ok'] == true) {
        final ready = map['ready'] != false;
        if (!ready) {
          return const PcSendResult(
            kind: PcSendKind.notReady,
            title: 'PC IS NOT READY',
            body: 'Choose a destination folder on the PC Receiver, then try again.',
          );
        }
        return const PcSendResult(
          kind: PcSendKind.sent,
          title: 'PC RECEIVER',
          body: 'Connected',
        );
      }
    } catch (e) {
      return PcSendResult(
        kind: PcSendKind.failed,
        title: 'COULD NOT SEND',
        body: 'The PC sent a response this app could not read.',
        technicalLog: 'invalid ping json: $e',
      );
    }
    return const PcSendResult(
      kind: PcSendKind.failed,
      title: 'COULD NOT SEND',
      body: 'The PC sent a response this app could not read.',
      technicalLog: 'invalid ping body',
    );
  }

  PcSendResult _mapIngest(http.Response resp, String customerName) {
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      return const PcSendResult(
        kind: PcSendKind.unauthorized,
        title: 'NOT PAIRED WITH THIS PC',
        body: 'The pairing code does not match. Pair this phone again.',
        technicalLog: 'unauthorized ingest',
      );
    }
    if (resp.statusCode == 0) {
      return _notFound('http 0');
    }
    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) {
        map = Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return _notFound('http ${resp.statusCode} invalid json $e');
      }
      return PcSendResult(
        kind: PcSendKind.failed,
        title: 'COULD NOT SEND',
        body: 'The PC sent a response this app could not read.',
        technicalLog: 'invalid ingest json: $e body=${resp.body}',
      );
    }
    if (map == null) {
      return _notFound('http ${resp.statusCode} empty');
    }

    final results = map['results'];
    Map<String, dynamic>? first;
    if (results is List && results.isNotEmpty && results.first is Map) {
      first = Map<String, dynamic>.from(results.first as Map);
    }

    final status = (first?['status'] as String?) ?? (map['status'] as String?);
    final code = (first?['code'] as String?) ?? (map['code'] as String?);

    if (status == 'received' || code == 'ok') {
      final name = customerName.trim().isEmpty ? 'Customer' : customerName.trim();
      return PcSendResult(
        kind: PcSendKind.sent,
        title: 'SENT TO PC',
        body: '$name\n1 quote saved\n\nPC acknowledged receipt.',
      );
    }
    if (status == 'duplicate' || code == 'already_received') {
      return const PcSendResult(
        kind: PcSendKind.alreadyOnPc,
        title: 'ALREADY ON PC',
        body: 'This quote was previously received.',
      );
    }
    if (code == 'destination_unavailable') {
      return const PcSendResult(
        kind: PcSendKind.notReady,
        title: 'PC IS NOT READY',
        body: 'Choose a destination folder on the PC Receiver, then try again.',
        technicalLog: 'destination_unavailable',
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (map['overall'] == 'failed' && (code == 'unauthorized')) {
        return const PcSendResult(
          kind: PcSendKind.unauthorized,
          title: 'NOT PAIRED WITH THIS PC',
          body: 'The pairing code does not match. Pair this phone again.',
        );
      }
      return _notFound('http ${resp.statusCode} ${resp.body}');
    }
    return PcSendResult(
      kind: PcSendKind.failed,
      title: 'COULD NOT SEND',
      body: 'The PC could not save this quote.',
      technicalLog: resp.body,
    );
  }

  PcSendResult _notFound(String log) {
    return PcSendResult(
      kind: PcSendKind.pcNotFound,
      title: 'PC NOT FOUND',
      body:
          'Make sure the PC Receiver is running\nand both devices are on the same Wi-Fi.',
      technicalLog: log,
    );
  }
}

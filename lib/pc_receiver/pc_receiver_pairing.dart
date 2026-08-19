/// Pairing payload between Showroom Scanner and the PC Receiver.
/// Versioned. Contains no EMUN credentials and no Windows paths.
library;

import 'dart:convert';

class PcReceiverPairing {
  static const protocolVersion = 1;
  static const kind = 'showroomscanner.pc.pair';
  static const defaultPort = 17855;
  static const headerName = 'X-Showroom-Pair-Token';

  const PcReceiverPairing({
    required this.host,
    required this.port,
    required this.token,
    this.pcName = '',
    this.protocol = protocolVersion,
  });

  final String host;
  final int port;
  final String token;
  final String pcName;
  final int protocol;

  Uri get ingestUri =>
      Uri(scheme: 'http', host: host, port: port, path: '/ingest');

  Uri get pingUri => Uri(scheme: 'http', host: host, port: port, path: '/ping');

  Map<String, String> get authHeaders => {headerName: token};

  /// User-visible pairing summary. Never includes the token.
  String get displaySummary {
    final name = pcName.trim();
    if (name.isNotEmpty) {
      return '$name\n$host:$port';
    }
    return '$host:$port';
  }

  Map<String, dynamic> toJson() => {
    'v': protocol,
    'kind': kind,
    'host': host,
    'port': port,
    'token': token,
    if (pcName.isNotEmpty) 'name': pcName,
  };

  String toPairingUri() {
    return Uri(
      scheme: 'showroomscanner-pc',
      host: 'pair',
      queryParameters: {
        'v': '$protocol',
        'host': host,
        'port': '$port',
        'token': token,
        if (pcName.isNotEmpty) 'name': pcName,
      },
    ).toString();
  }

  static PcReceiverPairing? tryParse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map) return null;
        return tryParseMap(Map<String, dynamic>.from(decoded));
      } catch (_) {
        return null;
      }
    }
    final uri = Uri.tryParse(text);
    if (uri != null &&
        (uri.scheme == 'showroomscanner-pc' || uri.scheme == 'showroomscanner')) {
      final host = uri.queryParameters['host'] ?? '';
      final port =
          int.tryParse(uri.queryParameters['port'] ?? '') ?? defaultPort;
      final token = uri.queryParameters['token'] ?? '';
      final name = uri.queryParameters['name'] ?? '';
      final v = int.tryParse(uri.queryParameters['v'] ?? '') ?? protocolVersion;
      return tryParseFields(host: host, port: port, token: token, pcName: name, protocol: v);
    }
    return null;
  }

  static PcReceiverPairing? tryParseMap(Map<String, dynamic> map) {
    if (map.containsKey('destination') ||
        map.containsKey('destination_folder') ||
        map.containsKey('path')) {
      return null;
    }
    final kindValue = (map['kind'] as String?)?.trim();
    if (kindValue != null &&
        kindValue.isNotEmpty &&
        kindValue != kind) {
      return null;
    }
    final host = (map['host'] as String?)?.trim() ?? '';
    final portRaw = map['port'];
    final port = portRaw is int
        ? portRaw
        : int.tryParse('$portRaw') ?? defaultPort;
    final token = (map['token'] as String?)?.trim() ?? '';
    final name = (map['name'] as String?)?.trim() ??
        (map['pc_name'] as String?)?.trim() ??
        '';
    final vRaw = map['v'] ?? map['protocol'];
    final v = vRaw is int ? vRaw : int.tryParse('$vRaw') ?? protocolVersion;
    return tryParseFields(
      host: host,
      port: port,
      token: token,
      pcName: name,
      protocol: v,
    );
  }

  static PcReceiverPairing? tryParseFields({
    required String host,
    required int port,
    required String token,
    String pcName = '',
    int protocol = protocolVersion,
  }) {
    final h = host.trim();
    final t = token.trim();
    if (!_looksLikeHost(h)) return null;
    if (port < 1 || port > 65535) return null;
    if (t.length < 16) return null;
    if (protocol != protocolVersion) return null;
    return PcReceiverPairing(
      host: h,
      port: port,
      token: t,
      pcName: pcName.trim(),
      protocol: protocol,
    );
  }

  static bool _looksLikeHost(String host) {
    if (host.isEmpty || host.length > 253) return false;
    if (host.contains('/') || host.contains('\\') || host.contains(' ')) {
      return false;
    }
    final ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (ipv4.hasMatch(host)) {
      final parts = host.split('.').map(int.parse).toList();
      return parts.every((n) => n >= 0 && n <= 255);
    }
    // Hostname (Phase 3 mainly uses IPv4; hostname allowed for later mDNS).
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$').hasMatch(host) ||
        RegExp(r'^[A-Za-z0-9]$').hasMatch(host);
  }
}

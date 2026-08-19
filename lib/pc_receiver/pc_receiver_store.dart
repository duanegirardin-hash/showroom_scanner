import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'pc_receiver_pairing.dart';

class PcReceiverStore {
  PcReceiverStore({Directory? Function()? documentsOverride})
    : _documentsOverride = documentsOverride;

  final Directory? Function()? _documentsOverride;
  static const fileName = 'pc_receiver_pair.json';

  Future<File> _file() async {
    final dir = _documentsOverride?.call() ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, fileName));
  }

  Future<PcReceiverPairing?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final map = jsonDecode(await file.readAsString());
      if (map is! Map) return null;
      return PcReceiverPairing.tryParseMap(Map<String, dynamic>.from(map));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PcReceiverPairing pairing) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(pairing.toJson()), flush: true);
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }
}

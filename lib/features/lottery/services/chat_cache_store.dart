import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 聊天缓存落盘：优先 app support 目录下的文件，目录不可用（测试/个别平台）时退回
/// SharedPreferences。旧版本只写 SharedPreferences，读文件不存在时迁移一次。
class ChatCacheStore {
  ChatCacheStore._();

  static const _prefPrefix = 'flyroom_chat_cache_';

  static Directory? _dir;
  static bool _dirUnavailable = false;

  static Future<File?> _file(String roomId) async {
    if (_dirUnavailable) return null;
    try {
      final dir = _dir ??= Directory(
        '${(await getApplicationSupportDirectory()).path}/chat_cache',
      );
      if (!await dir.exists()) await dir.create(recursive: true);
      final safe = roomId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      return File('${dir.path}/$safe.json');
    } catch (_) {
      _dirUnavailable = true;
      return null;
    }
  }

  /// [migrated] true：读到的是旧 SharedPreferences 数据且已迁出，调用方应尽快重写到文件。
  static Future<({String? payload, bool migrated})> read(String roomId) async {
    final file = await _file(roomId);
    if (file != null) {
      try {
        if (await file.exists()) {
          return (payload: await file.readAsString(), migrated: false);
        }
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString('$_prefPrefix$roomId');
    if (legacy != null && file != null) {
      await prefs.remove('$_prefPrefix$roomId');
      return (payload: legacy, migrated: true);
    }
    return (payload: legacy, migrated: false);
  }

  static Future<void> write(String roomId, String payload) async {
    final file = await _file(roomId);
    if (file != null) {
      try {
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(payload, flush: true);
        await tmp.rename(file.path);
        return;
      } catch (_) {
        // 落文件失败就退回 prefs
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefPrefix$roomId', payload);
  }

  static Future<void> delete(String roomId) async {
    final file = await _file(roomId);
    if (file != null) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefPrefix$roomId');
  }
}

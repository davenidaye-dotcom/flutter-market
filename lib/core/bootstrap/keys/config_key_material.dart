import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'cfg_aes_a.dart';
import 'cfg_aes_b.dart';
import 'cfg_aes_c.dart';
import 'cfg_aes_d.dart';
import 'cfg_mac_a.dart';
import 'cfg_mac_b.dart';
import 'cfg_mac_c.dart';
import 'cfg_mac_d.dart';

/// 配置加解密密钥材料（打散重组；最终经 SHA256）。
/// [kid] 为配置信封版本：日常轮换 API 验签密钥不改这里；
/// 仅当「解 OSS 的根密钥」泄露需要发版时，再在 App 增加 kid=2 碎片。
class ConfigKeyMaterial {
  ConfigKeyMaterial._();

  static final Map<String, List<int>> _aesCache = {};
  static final Map<String, List<int>> _macCache = {};

  /// 当前包支持的配置根密钥版本（发版时可追加 '2'）
  static const supportedKids = ['1'];

  static List<int> aesKeyBytes([String kid = '1']) {
    final k = kid.trim().isEmpty ? '1' : kid.trim();
    final cached = _aesCache[k];
    if (cached != null) return cached;
    final pass = _passphraseFor(k, aes: true);
    return _aesCache[k] = sha256.convert(utf8.encode(pass)).bytes;
  }

  static List<int> macKeyBytes([String kid = '1']) {
    final k = kid.trim().isEmpty ? '1' : kid.trim();
    final cached = _macCache[k];
    if (cached != null) return cached;
    final pass = _passphraseFor(k, aes: false);
    return _macCache[k] = sha256.convert(utf8.encode(pass)).bytes;
  }

  static String _passphraseFor(String kid, {required bool aes}) {
    assert(() {
      if (aes) {
        cfgAesDecoyA();
        cfgAesDecoyB();
        cfgAesDecoyC();
        cfgAesDecoyD();
      } else {
        cfgMacDecoyA();
        cfgMacDecoyB();
        cfgMacDecoyC();
        cfgMacDecoyD();
      }
      return true;
    }());
    // kid=1：现有四片；未来 kid=2 可换另一组碎片文件
    if (kid != '1') {
      throw StateError('config root kid=$kid not in this app build');
    }
    final parts = aes
        ? [cfgAesPieceA(), cfgAesPieceB(), cfgAesPieceC(), cfgAesPieceD()]
        : [cfgMacPieceA(), cfgMacPieceB(), cfgMacPieceC(), cfgMacPieceD()];
    const order = [2, 0, 3, 1];
    return order.map((i) => parts[i]).join();
  }
}

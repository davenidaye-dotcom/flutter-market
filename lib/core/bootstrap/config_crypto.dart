import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

import 'keys/config_key_material.dart';

/// OSS 下发的线路配置明文
class EndpointConfig {
  const EndpointConfig({
    required this.version,
    required this.env,
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    this.ts,
    this.signKid,
    this.signSecret,
    this.cfgKid = '1',
  });

  final int version;
  final String env;
  final String apiBaseUrl;
  final String wsBaseUrl;
  final int? ts;

  /// API 验签密钥版本（热轮换，无需重打包）
  final String? signKid;
  final String? signSecret;

  /// 配置信封根密钥版本（极少换，换则要发版）
  final String cfgKid;

  factory EndpointConfig.fromJson(Map<String, dynamic> json, {String cfgKid = '1'}) {
    final api = (json['apiBaseUrl'] ?? json['api'] ?? '').toString().trim();
    final ws = (json['wsBaseUrl'] ?? json['ws'] ?? '').toString().trim();
    if (api.isEmpty || ws.isEmpty) {
      throw const FormatException('endpoint config missing api/ws');
    }
    final signKid = (json['signKid'] ?? json['sign_kid'] ?? '').toString().trim();
    final signSecret =
        (json['signSecret'] ?? json['sign_secret'] ?? '').toString().trim();
    return EndpointConfig(
      version: int.tryParse('${json['v'] ?? json['version'] ?? 1}') ?? 1,
      env: (json['env'] ?? '').toString(),
      apiBaseUrl: api.replaceAll(RegExp(r'/+$'), ''),
      wsBaseUrl: ws.replaceAll(RegExp(r'/+$'), ''),
      ts: int.tryParse('${json['ts'] ?? ''}'),
      signKid: signKid.isEmpty ? null : signKid,
      signSecret: signSecret.isEmpty ? null : signSecret,
      cfgKid: cfgKid,
    );
  }

  Map<String, dynamic> toJson() => {
        'v': version,
        'env': env,
        'apiBaseUrl': apiBaseUrl,
        'wsBaseUrl': wsBaseUrl,
        if (ts != null) 'ts': ts,
        if (signKid != null && signKid!.isNotEmpty) 'signKid': signKid,
        if (signSecret != null && signSecret!.isNotEmpty) 'signSecret': signSecret,
      };

  bool get hasSignCredential =>
      signKid != null &&
      signKid!.isNotEmpty &&
      signSecret != null &&
      signSecret!.isNotEmpty;
}

/// 文件格式：
/// - 旧：`FRCFG1|<ivB64>|<cipherB64>|<macB64>`（cfgKid=1）
/// - 新：`FRCFG2|<cfgKid>|<ivB64>|<cipherB64>|<macB64>`
class ConfigCrypto {
  ConfigCrypto._();

  static const prefixV1 = 'FRCFG1';
  static const prefixV2 = 'FRCFG2';

  static String encryptToFrcfg(EndpointConfig config, {String cfgKid = '1'}) {
    final plain = jsonEncode(config.toJson());
    final key = enc.Key(Uint8List.fromList(ConfigKeyMaterial.aesKeyBytes(cfgKid)));
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final cipher = encrypter.encrypt(plain, iv: iv);
    final ivB64 = iv.base64;
    final cipherB64 = cipher.base64;
    final macB64 = _macB64(cfgKid, ivB64, cipherB64, legacyV1: false);
    return '$prefixV2|$cfgKid|$ivB64|$cipherB64|$macB64';
  }

  static EndpointConfig decryptFrcfg(String raw) {
    final text = raw.trim();
    final parts = text.split('|');
    late final String cfgKid;
    late final String ivB64;
    late final String cipherB64;
    late final String macB64;
    late final String expectMac;
    if (parts.length == 4 && parts[0] == prefixV1) {
      cfgKid = '1';
      ivB64 = parts[1];
      cipherB64 = parts[2];
      macB64 = parts[3];
      expectMac = _macB64(cfgKid, ivB64, cipherB64, legacyV1: true);
    } else if (parts.length == 5 && parts[0] == prefixV2) {
      cfgKid = parts[1].trim();
      ivB64 = parts[2];
      cipherB64 = parts[3];
      macB64 = parts[4];
      expectMac = _macB64(cfgKid, ivB64, cipherB64, legacyV1: false);
    } else {
      throw const FormatException('invalid frcfg header');
    }
    if (!ConfigKeyMaterial.supportedKids.contains(cfgKid)) {
      throw FormatException('unsupported cfgKid=$cfgKid');
    }
    if (!_slowEq(expectMac, macB64)) {
      throw const FormatException('frcfg mac mismatch');
    }
    final key = enc.Key(Uint8List.fromList(ConfigKeyMaterial.aesKeyBytes(cfgKid)));
    final iv = enc.IV.fromBase64(ivB64);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final plain = encrypter.decrypt64(cipherB64, iv: iv);
    final map = jsonDecode(plain);
    if (map is! Map) {
      throw const FormatException('frcfg payload not object');
    }
    return EndpointConfig.fromJson(Map<String, dynamic>.from(map), cfgKid: cfgKid);
  }

  static String _macB64(
    String cfgKid,
    String ivB64,
    String cipherB64, {
    required bool legacyV1,
  }) {
    final hmac = Hmac(sha256, ConfigKeyMaterial.macKeyBytes(cfgKid));
    final payload = legacyV1 ? '$ivB64|$cipherB64' : '$cfgKid|$ivB64|$cipherB64';
    final dig = hmac.convert(utf8.encode(payload));
    return base64Encode(dig.bytes);
  }

  static bool _slowEq(String a, String b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return r == 0;
  }
}

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'sign_credential_store.dart';
import 'sign_shard_a.dart';
import 'sign_shard_b.dart';
import 'sign_shard_c.dart';
import 'sign_shard_d.dart';

/// App API HMAC 签名（与后端 ApiSignFilter 约定一致）。
///
/// 密钥来源优先级：
/// 1. OSS 下发的 signSecret + signKid（可热轮换，无需重打包）
/// 2. 包内打散重组（kid=1 兜底）
class ApiRequestSigner {
  ApiRequestSigner._();

  static final _rng = Random.secure();
  static String? _bakedSecret;

  /// 打散顺序：C + A + D + B（诱饵函数永不调用进拼接）
  static String materializeBakedSecret() {
    if (_bakedSecret != null) return _bakedSecret!;
    assert(() {
      frSignDecoyA();
      frSignDecoyB();
      frSignDecoyC();
      frSignDecoyD();
      return true;
    }());
    final parts = <String>[
      frSignPieceA(),
      frSignPieceB(),
      frSignPieceC(),
      frSignPieceD(),
    ];
    const order = <int>[2, 0, 3, 1];
    final buf = StringBuffer();
    for (final i in order) {
      buf.write(parts[i]);
    }
    return _bakedSecret = buf.toString();
  }

  static (String kid, String secret) _activeCredential() {
    final store = SignCredentialStore.instance;
    if (store.hasRemote) {
      return (store.kid, store.remoteSecret!);
    }
    return (SignCredentialStore.bakedKid, materializeBakedSecret());
  }

  /// 写入 Dio 请求头：X-FR-Client / Kid / Ts / Nonce / Sign
  static void attach(RequestOptions options) {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _nonce();
    final path = options.uri.path;
    final query = _canonicalQuery(options.uri.queryParametersAll);
    final bodyHash = sha256.convert(_bodyBytes(options)).toString();
    final method = options.method.toUpperCase();
    final canonical = 'v1\n$method\n$path\n$query\n$ts\n$nonce\n$bodyHash';
    final cred = _activeCredential();
    final sign =
        Hmac(sha256, utf8.encode(cred.$2)).convert(utf8.encode(canonical)).toString();

    options.headers['X-FR-Client'] = 'APP';
    options.headers['X-FR-Kid'] = cred.$1;
    options.headers['X-FR-Ts'] = ts;
    options.headers['X-FR-Nonce'] = nonce;
    options.headers['X-FR-Sign'] = sign;
  }

  static List<int> _bodyBytes(RequestOptions options) {
    final data = options.data;
    if (data == null) return const [];
    if (data is List<int>) return data;
    if (data is FormData) {
      return const [];
    }
    if (data is String) return utf8.encode(data);
    return utf8.encode(jsonEncode(data));
  }

  static String _canonicalQuery(Map<String, List<String>> params) {
    if (params.isEmpty) return '';
    final keys = params.keys.toList()..sort();
    final parts = <String>[];
    for (final k in keys) {
      final vals = List<String>.from(params[k] ?? const [])..sort();
      for (final v in vals) {
        parts.add('$k=$v');
      }
    }
    return parts.join('&');
  }

  static String _nonce() {
    final ms = DateTime.now().microsecondsSinceEpoch;
    final r = _rng.nextInt(1 << 32).toRadixString(16);
    return '${ms.toRadixString(16)}$r';
  }
}

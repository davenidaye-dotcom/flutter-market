import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/env/env_config.dart';
import '../network/api_client.dart';
import '../security/sign_credential_store.dart';
import 'bootstrap_seeds.dart';
import 'config_crypto.dart';

/// 启动时从 OSS/CDN 拉加密线路 → 解密 → 应用到 [EnvConfig]。
/// 失败则用本地缓存，再不行用包内内置地址（保证开发可跑）。
class RemoteEndpointBootstrap {
  RemoteEndpointBootstrap._();
  static final RemoteEndpointBootstrap instance = RemoteEndpointBootstrap._();

  static const _cacheKey = 'flyroom_endpoint_frcfg_cache';
  static const _assetPath = 'assets/bootstrap/endpoint.frcfg';

  bool ready = false;
  String source = 'none';
  EndpointConfig? current;

  /// [perUrlTimeout] 单地址超时；[budget] 远程总预算，避免串行拖死启动。
  Future<void> ensureReady({
    Duration perUrlTimeout = const Duration(seconds: 2),
    Duration budget = const Duration(seconds: 3),
  }) async {
    if (ready) return;

    // 1) 远程 CDN/OSS（并行 + 总超时）
    final remote = await _tryRemote(perUrlTimeout, budget: budget);
    if (remote != null) {
      await _apply(remote.$1, source: 'oss', cacheRaw: true, raw: remote.$2);
      return;
    }

    // 2) 本地缓存
    final cached = await _tryCache();
    if (cached != null) {
      await _apply(cached, source: 'cache', cacheRaw: false);
      return;
    }

    // 3) 包内资产（可选预置加密文件）
    final asset = await _tryAsset();
    if (asset != null) {
      await _apply(asset, source: 'asset', cacheRaw: false);
      return;
    }

    // 4) 内置明文兜底
    final fallback = EndpointConfig(
      version: 1,
      env: EnvConfig.environment.key,
      apiBaseUrl: EnvConfig.builtinApiBaseUrl,
      wsBaseUrl: EnvConfig.builtinWsBaseUrl,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    await _apply(fallback, source: 'builtin', cacheRaw: false);
  }

  Future<(EndpointConfig, String)?> _tryRemote(
    Duration perUrlTimeout, {
    required Duration budget,
  }) async {
    final urls = BootstrapSeeds.urlsForEnv(EnvConfig.environment.key);
    if (urls.isEmpty) return null;

    final dio = Dio(
      BaseOptions(
        connectTimeout: perUrlTimeout,
        receiveTimeout: perUrlTimeout,
        responseType: ResponseType.plain,
        validateStatus: (c) => c != null && c >= 200 && c < 300,
      ),
    );

    final completer = Completer<(EndpointConfig, String)?>();
    var pending = urls.length;

    for (final url in urls) {
      () async {
        try {
          final res = await dio.get<String>(url);
          final raw = (res.data ?? '').trim();
          if (raw.isEmpty) throw StateError('empty');
          final cfg = ConfigCrypto.decryptFrcfg(raw);
          if (!_envOk(cfg)) throw StateError('env mismatch');
          if (!completer.isCompleted) {
            completer.complete((cfg, raw));
          }
        } catch (e) {
          debugPrint('[bootstrap] miss $url → $e');
          pending--;
          if (pending <= 0 && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      }();
    }

    try {
      return await completer.future.timeout(budget, onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  Future<EndpointConfig?> _tryCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final cfg = ConfigCrypto.decryptFrcfg(raw);
      if (!_envOk(cfg)) return null;
      return cfg;
    } catch (e) {
      debugPrint('[bootstrap] cache fail → $e');
      return null;
    }
  }

  Future<EndpointConfig?> _tryAsset() async {
    try {
      final raw = (await rootBundle.loadString(_assetPath)).trim();
      if (raw.isEmpty) return null;
      final cfg = ConfigCrypto.decryptFrcfg(raw);
      if (!_envOk(cfg)) return null;
      return cfg;
    } catch (_) {
      return null;
    }
  }

  bool _envOk(EndpointConfig cfg) {
    // 必须带 env，且与当前 APP_ENV 一致，避免错环境配置落库
    if (cfg.env.isEmpty) return false;
    return cfg.env == EnvConfig.environment.key;
  }

  Future<void> _apply(
    EndpointConfig cfg, {
    required String source,
    required bool cacheRaw,
    String? raw,
  }) async {
    EnvConfig.applyEndpoint(apiBaseUrl: cfg.apiBaseUrl, wsBaseUrl: cfg.wsBaseUrl);
    ApiClient.instance.syncBaseUrl();
    if (cfg.hasSignCredential) {
      SignCredentialStore.instance.applyRemote(
        kid: cfg.signKid!,
        secret: cfg.signSecret!,
      );
    } else {
      SignCredentialStore.instance.clearRemote();
    }
    current = cfg;
    this.source = source;
    ready = true;
    if (cacheRaw && raw != null && raw.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, raw);
    }
    debugPrint(
      '[bootstrap] source=$source api=${cfg.apiBaseUrl} ws=${cfg.wsBaseUrl} '
      'signKid=${cfg.signKid ?? SignCredentialStore.bakedKid}',
    );
  }

  /// 验签连续失败时可清缓存，强制下次走 OSS/asset
  Future<void> invalidateCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    ready = false;
    current = null;
    source = 'none';
  }
}

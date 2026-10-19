import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/env/env_config.dart';
import '../network/api_client.dart';
import '../network/auth_api_client.dart';
import '../security/sign_credential_store.dart';
import '../security/vpn_guard.dart';
import 'bootstrap_seeds.dart';
import 'config_crypto.dart';

/// 启动时从 OSS/CDN 拉加密线路 → 解密 → 应用到 [EnvConfig]。
/// 生产包一直停在启动页重试，拉到 OSS 才进 App。开发/测试拉不到时用内置测试地址。
class RemoteEndpointBootstrap {
  RemoteEndpointBootstrap._();
  static final RemoteEndpointBootstrap instance = RemoteEndpointBootstrap._();

  static const _cacheKey = 'flyroom_endpoint_frcfg_cache';
  static const _retryGap = Duration(seconds: 1);

  bool ready = false;
  String source = 'none';
  EndpointConfig? current;

  /// [perUrlTimeout] 单地址超时；[budget] 每一轮的总预算。
  Future<void> ensureReady({
    Duration perUrlTimeout = const Duration(seconds: 6),
    Duration budget = const Duration(seconds: 8),
  }) async {
    if (ready) return;

    while (true) {
      final remote = await _tryRemote(perUrlTimeout, budget: budget);
      if (remote != null) {
        await _apply(remote.$1, source: 'oss', cacheRaw: true, raw: remote.$2);
        return;
      }
      if (EnvConfig.environment != AppEnvironment.pro) break;
      debugPrint('[bootstrap] oss unavailable, retry');
      await Future<void>.delayed(_retryGap);
    }

    final fallback = EndpointConfig(
      version: 1,
      env: EnvConfig.environment.key,
      apiBaseUrl: EnvConfig.builtinApiBaseUrl,
      wsBaseUrl: EnvConfig.builtinWsBaseUrl,
      authBaseUrl: EnvConfig.builtinAuthBaseUrl,
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
    // 有 VPN 时不连 OSS。开发/测试回退内置地址，生产不发业务请求。
    if (await VpnGuard.active()) return null;

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
    EnvConfig.applyEndpoint(
      apiBaseUrl: cfg.apiBaseUrl,
      wsBaseUrl: cfg.wsBaseUrl,
      authBaseUrl: cfg.authBaseUrl,
    );
    ApiClient.instance.syncBaseUrl();
    AuthApiClient.instance.syncBaseUrl();
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
      '[bootstrap] source=$source api=${cfg.apiBaseUrl} auth=${cfg.authBaseUrl ?? cfg.apiBaseUrl} '
      'ws=${cfg.wsBaseUrl} '
      'signKid=${cfg.signKid ?? SignCredentialStore.bakedKid}',
    );
  }

  /// 验签连续失败时可清缓存，下次启动重新拉 OSS
  Future<void> invalidateCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    ready = false;
    current = null;
    source = 'none';
  }
}

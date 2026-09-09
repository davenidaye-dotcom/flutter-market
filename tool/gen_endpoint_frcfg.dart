// ignore_for_file: avoid_print
/// 生成上传到 OSS 的加密线路文件（含可热轮换的 API 验签密钥）。
///
/// ```bash
/// dart run tool/gen_endpoint_frcfg.dart \
///   --env=dev \
///   --api=http://207.148.105.182/api/v1 \
///   --ws=ws://207.148.105.182/ws/v1 \
///   --sign-kid=1 \
///   --sign-secret='eT4uY8nBFr9kQx2m6cH1jR5!P7vL0sW#'
/// ```
///
/// 轮换到 kid=2（无需重打包 App）：
/// 1. 后端 application.yml secrets 同时保留 "1" 与 "2"
/// 2. 本工具用 --sign-kid=2 --sign-secret=新密钥 重新生成并上传 OSS
/// 3. 观察无旧流量后，后端删掉 secrets."1"
import 'dart:io';

import 'package:letou_app/config/env/env_config.dart';
import 'package:letou_app/core/bootstrap/config_crypto.dart';
import 'package:letou_app/core/security/api_request_signer.dart';

void main(List<String> args) {
  var env = EnvConfig.environment.key;
  var api = EnvConfig.builtinApiBaseUrl;
  var ws = EnvConfig.builtinWsBaseUrl;
  var signKid = '1';
  var signSecret = ApiRequestSigner.materializeBakedSecret();
  var cfgKid = '1';
  for (final a in args) {
    if (a.startsWith('--env=')) env = a.substring(6);
    if (a.startsWith('--api=')) api = a.substring(6);
    if (a.startsWith('--ws=')) ws = a.substring(5);
    if (a.startsWith('--sign-kid=')) signKid = a.substring(11);
    if (a.startsWith('--sign-secret=')) signSecret = a.substring(14);
    if (a.startsWith('--cfg-kid=')) cfgKid = a.substring(10);
  }
  final cfg = EndpointConfig(
    version: 1,
    env: env,
    apiBaseUrl: api,
    wsBaseUrl: ws,
    ts: DateTime.now().millisecondsSinceEpoch,
    signKid: signKid,
    signSecret: signSecret,
    cfgKid: cfgKid,
  );
  final blob = ConfigCrypto.encryptToFrcfg(cfg, cfgKid: cfgKid);
  final dir = Directory('tool/out');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final file = File('tool/out/endpoint.$env.frcfg');
  file.writeAsStringSync(blob);
  final assetDir = Directory('assets/bootstrap');
  if (!assetDir.existsSync()) assetDir.createSync(recursive: true);
  File('assets/bootstrap/endpoint.frcfg').writeAsStringSync(blob);
  print('wrote ${file.path}');
  print('wrote assets/bootstrap/endpoint.frcfg');
  print('env=$env api=$api ws=$ws');
  print('signKid=$signKid cfgKid=$cfgKid');
  print('upload → OSS flyroom/$env/endpoint.frcfg');
  print('backend must contain secrets."$signKid" = same sign-secret');
}

/// 包内写死的「引导 CDN/OSS」地址（不是业务 API）。
/// 可换成你们真实 OSS 公有读路径；额外可用 --dart-define=BOOTSTRAP_URL=...
class BootstrapSeeds {
  BootstrapSeeds._();

  /// 可选运行时覆盖（调试/灰度）
  static const defineUrl = String.fromEnvironment('BOOTSTRAP_URL', defaultValue: '');

  static const _proBuild =
      String.fromEnvironment('APP_ENV', defaultValue: 'dev') == 'pro';

  /// 按环境拼路径后缀。正式包不带这些地址。
  static List<String> urlsForEnv(String envKey) {
    final out = <String>[];
    if (defineUrl.trim().isNotEmpty) {
      out.add(defineUrl.trim());
    }
    if (_proBuild || envKey == 'pro') return out;
    const objectName = 'endpoint.frcfg';
    // 反转存放，运行时翻回，避免明文一眼搜到完整 OSS
    final seeds = <String>[
      // 主：请改成你们真实 bucket
      _rev('http://oss.cloudflare888.com/flyroom/$envKey/$objectName'),
      // 备
      _rev('https://fr-cfg-backup.oss-ap-southeast-1.aliyuncs.com/flyroom/$envKey/$objectName'),
      // 第三跳（可换成 Cloudflare R2 / 自建 CDN）
      _rev('https://cdn.fr-endpoint.net/flyroom/$envKey/$objectName'),
    ];
    for (final s in seeds) {
      out.add(_rev(s));
    }
    return out;
  }

  static String _rev(String s) => String.fromCharCodes(s.codeUnits.reversed);
}

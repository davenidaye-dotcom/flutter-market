/// 本地预设头像：后台只存编码（如 av01），App 映射到 assets。
abstract final class AvatarCatalog {
  static const int count = 58;
  static const String codePrefix = 'av';

  /// av01 … av58
  static String codeAt(int index) {
    final n = index + 1;
    return '$codePrefix${n.toString().padLeft(2, '0')}';
  }

  static List<String> get allCodes =>
      List.generate(count, codeAt, growable: false);

  static String? assetOf(String? codeOrUrl) {
    final code = normalizeCode(codeOrUrl);
    if (code == null) return null;
    final n = int.parse(code.substring(2));
    return 'assets/avatars/avatar_${n.toString().padLeft(2, '0')}.png';
  }

  /// 合法编码返回标准 avNN；http(s) URL / 空 / 非法 → null（本地图不可用）
  static String? normalizeCode(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return null;
    final m = RegExp(r'^(?:av)?(\d{1,2})$', caseSensitive: false).firstMatch(s);
    if (m == null) return null;
    final n = int.tryParse(m.group(1)!);
    if (n == null || n < 1 || n > count) return null;
    return '$codePrefix${n.toString().padLeft(2, '0')}';
  }

  static bool isPresetCode(String? raw) => normalizeCode(raw) != null;
}

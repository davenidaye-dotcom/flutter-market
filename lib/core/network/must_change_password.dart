/// 房主尚未改密时，业务接口返回这句话。App 据此回到改密页。
class MustChangePassword {
  MustChangePassword._();

  static const message = '请先修改密码';

  static void Function()? handler;
  static bool _busy = false;

  static void consider(dynamic data) {
    if (handler == null || _busy || data is! Map) return;
    final code = data['code'];
    final n = code is int ? code : int.tryParse('$code');
    if (n == null || n == 200) return;
    if (data['msg']?.toString() != message) return;
    _busy = true;
    try {
      handler?.call();
    } finally {
      _busy = false;
    }
  }
}

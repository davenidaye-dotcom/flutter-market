/// 写操作防抖 + 在途锁 + 幂等键（requestId）。
///
/// - 防抖：短时间内重复点击直接忽略
/// - 在途锁：请求未返回前禁止再次提交
/// - 幂等：同一次用户意图复用同一 [requestId]；网络失败可重试用原键；
///   成功或明确业务失败后清空，下次主动操作生成新键
class SubmitGuard {
  SubmitGuard({this.debounce = const Duration(milliseconds: 800)});

  final Duration debounce;

  bool _busy = false;
  DateTime? _lastStartAt;
  String? _requestId;
  static int _seq = 0;

  bool get isBusy => _busy;

  String? get currentRequestId => _requestId;

  /// 开始一次提交。返回 null 表示应忽略本次点击。
  String? tryBegin() {
    if (_busy) return null;
    final now = DateTime.now();
    if (_lastStartAt != null && now.difference(_lastStartAt!) < debounce) {
      return null;
    }
    _busy = true;
    _lastStartAt = now;
    _requestId ??= _newRequestId();
    return _requestId;
  }

  /// [success] true：清空幂等键（下次是新意图）
  /// [keepForRetry] true：网络类失败，保留 requestId 供重试
  void end({required bool success, bool keepForRetry = false}) {
    _busy = false;
    if (success || !keepForRetry) {
      _requestId = null;
    }
  }

  void reset() {
    _busy = false;
    _requestId = null;
    _lastStartAt = null;
  }

  /// 包装一次异步写操作。被防抖/在途拦截时返回 null。
  Future<T?> run<T>(
    Future<T> Function(String requestId) action, {
    bool Function(Object error)? isRetryable,
  }) async {
    final id = tryBegin();
    if (id == null) return null;
    try {
      final result = await action(id);
      end(success: true);
      return result;
    } catch (e) {
      final retryable = isRetryable?.call(e) ?? isNetworkRetryable(e);
      end(success: false, keepForRetry: retryable);
      rethrow;
    }
  }

  static bool isNetworkRetryable(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('timeout') ||
        msg.contains('timed out') ||
        msg.contains('network') ||
        msg.contains('连接') ||
        msg.contains('超时') ||
        msg.contains('socket') ||
        msg.contains('connection');
  }

  static String _newRequestId() {
    final ms = DateTime.now().microsecondsSinceEpoch;
    _seq = (_seq + 1) & 0xffff;
    return 'req_${ms.toRadixString(36)}_$_seq';
  }
}

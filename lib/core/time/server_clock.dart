/// 服务器时钟。
///
/// 倒计时、封盘、开奖都是「服务器给的绝对时刻 − 当前时刻」。当前时刻如果取手机墙钟，
/// 两部手机时钟差几秒，倒计时就差几秒。这里改成：用服务器随包下发的 `serverNowMs` 校准，
/// 之后用单调计时器（Stopwatch）往前走——既和服务器对齐，也不受用户中途改手机时间影响。
///
/// 估算方法：每个样本 = `serverNowMs + 单程延迟 − 本机单调时间`。网络延迟只会让样本偏小，
/// 所以在最近窗口内取最大值，就是延迟最小那一次，最接近真实的服务器时间。
class ServerClock {
  ServerClock._();

  /// 只用来在没有任何样本时回落到手机时间，并作为单调计时器基准。
  static final Stopwatch _mono = Stopwatch()..start();

  /// 样本保留时长。再长会把本机计时器与服务器时钟的微小漂移累积进来。
  static const _window = Duration(seconds: 60);
  static const _maxSamples = 64;

  static final List<_Sample> _samples = <_Sample>[];
  static int? _offsetMs;

  /// 当前对齐用的偏移（服务器时间 − 单调时间），未校准时为 null。
  static int? get offsetMs => _offsetMs;

  static bool get calibrated => _offsetMs != null;

  /// 服务器当前时间。没校准过时退回手机时间。
  static DateTime now() {
    final off = _offsetMs;
    if (off == null) return DateTime.now();
    return DateTime.fromMillisecondsSinceEpoch(
      _mono.elapsedMilliseconds + off,
    );
  }

  static int nowMs() => now().millisecondsSinceEpoch;

  /// 本机时钟领先服务器的毫秒数（正数=手机快）。仅用于排查。
  static int? get phoneAheadMs {
    final off = _offsetMs;
    if (off == null) return null;
    return DateTime.now().millisecondsSinceEpoch -
        (_mono.elapsedMilliseconds + off);
  }

  /// 记一个样本。
  ///
  /// [serverNowMs] 服务器写出这一帧时的时间戳；[latencyMs] 已知的单程延迟（HTTP 可取 RTT/2，
  /// WS 不知道就传 0）。
  static void observe(int? serverNowMs, {int latencyMs = 0}) {
    if (serverNowMs == null || serverNowMs <= 0) return;
    final at = _mono.elapsedMilliseconds;
    final sample = serverNowMs + latencyMs - at;
    _samples.add(_Sample(at, sample));
    final cutoff = at - _window.inMilliseconds;
    _samples.removeWhere((s) => s.at < cutoff);
    while (_samples.length > _maxSamples) {
      _samples.removeAt(0);
    }
    var best = _samples.first.offset;
    for (final s in _samples) {
      if (s.offset > best) best = s.offset;
    }
    _offsetMs = best;
  }

  /// 登出/切服务器时清掉，避免带着上一个环境的偏移。
  static void reset() {
    _samples.clear();
    _offsetMs = null;
  }
}

class _Sample {
  const _Sample(this.at, this.offset);
  final int at;
  final int offset;
}

import 'dart:async';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/lottery_repository.dart';

/// 业务码：优先 [ApiException.bizCode]，其次从文案里认已知码。
String? betErrorCode(Object e) {
  if (e is! ApiException) return null;
  final biz = e.bizCode;
  if (biz != null && biz.isNotEmpty) return biz;
  for (final c in _knownCodes) {
    if (e.message.contains(c)) return c;
  }
  return null;
}

const _knownCodes = [
  'BET_REQ_NOT_FOUND',
  'BET_BUSY',
  'BET_TOO_FAST',
  'BET_PENDING',
  'SEALED',
];

/// 玩家可读的下注错误；服务端文案为空或只是码本身时才用本地文案。
String betErrorMessage(ApiException e) {
  final code = betErrorCode(e);
  final msg = e.message.trim();
  if (msg.isNotEmpty && msg != code) return msg;
  return switch (code) {
    'BET_BUSY' => '当前下注人数较多，请稍后重试',
    'BET_TOO_FAST' => '操作太快了，请稍后再试',
    'BET_PENDING' => '上一笔注单处理中，请稍候',
    'SEALED' => '已封盘',
    _ => msg,
  };
}

/// 一次用户下注的传输状态机：WS 优先（等 BET_ACK ≤3s）→ HTTP 兜底（同一 reqId）→
/// HTTP 网络错误后按 reqId 轮询。WS 与 HTTP 谁先返回用谁，另一路结果丢弃。
class BetExecutor {
  BetExecutor({
    required this.wsAvailable,
    required this.sendWs,
    required this.poll,
    this.ackTimeout = const Duration(seconds: 3),
    this.pollDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 3),
    ],
    this.busyRetryDelay = const Duration(milliseconds: 300),
  });

  /// WS 已连接且服务端宣告了 BET 能力。
  final bool Function() wsAvailable;

  /// 发出 `{action:BET, data:body}`；返回 false 表示没发出去。
  final bool Function(String reqId, Map<String, dynamic> body) sendWs;
  final Future<BetSubmitResult?> Function(String reqId) poll;
  final Duration ackTimeout;
  final List<Duration> pollDelays;
  final Duration busyRetryDelay;

  final Map<String, _Attempt> _attempts = {};

  /// 同一 reqId 重复调用（重试）合并成同一次在途请求。
  /// [http] 是同一 reqId 的 `POST /member/bets`（带 Idempotency-Key）。
  Future<BetSubmitResult> submit(
    String reqId,
    Map<String, dynamic> wsBody,
    Future<BetSubmitResult> Function() http,
  ) {
    final existing = _attempts[reqId];
    if (existing != null) return existing.done.future;
    final attempt = _Attempt(http);
    _attempts[reqId] = attempt;
    unawaited(_run(reqId, wsBody, attempt).whenComplete(() {
      _attempts.remove(reqId);
    }));
    return attempt.done.future;
  }

  /// WS 事件 BET_ACK 的 data。
  void onAck(Map<String, dynamic> data) {
    final reqId = '${data['reqId'] ?? ''}';
    final attempt = _attempts[reqId];
    if (attempt == null || attempt.done.isCompleted) return;
    if (data['ok'] == true) {
      attempt.complete(BetSubmitResult.fromMap(data));
      return;
    }
    final code = data['code']?.toString();
    // BET_BUSY：改走 HTTP 重试一次（同 reqId）；HTTP 已在路上则等它。
    if (code == 'BET_BUSY') {
      attempt.startHttp?.call();
      return;
    }
    attempt.fail(ApiException(
      message: '${data['message'] ?? data['msg'] ?? '下注失败'}',
      bizCode: code,
    ));
  }

  Future<void> _run(
    String reqId,
    Map<String, dynamic> wsBody,
    _Attempt attempt,
  ) async {
    Timer? timer;
    var httpStarted = false;
    void startHttp() {
      if (httpStarted || attempt.done.isCompleted) return;
      httpStarted = true;
      timer?.cancel();
      unawaited(() async {
        try {
          attempt.complete(await _httpWithPoll(reqId, attempt));
        } catch (e) {
          attempt.fail(e);
        }
      }());
    }

    attempt.startHttp = startHttp;
    if (wsAvailable() && sendWs(reqId, wsBody)) {
      timer = Timer(ackTimeout, startHttp);
    } else {
      startHttp();
    }
    try {
      await attempt.done.future;
    } catch (_) {
      // 错误由 submit 的调用方从 future 拿
    } finally {
      timer?.cancel();
      attempt.startHttp = null;
    }
  }

  Future<BetSubmitResult> _httpWithPoll(String reqId, _Attempt attempt) async {
    var busyRetried = false;
    while (true) {
      try {
        return await attempt.http();
      } on ApiException catch (e) {
        if (!e.isNetwork) {
          if (betErrorCode(e) == 'BET_BUSY' && !busyRetried) {
            busyRetried = true;
            await Future<void>.delayed(busyRetryDelay);
            if (attempt.done.isCompleted) rethrow;
            continue;
          }
          rethrow;
        }
        return _pollAfterNetworkError(reqId, e, attempt);
      }
    }
  }

  Future<BetSubmitResult> _pollAfterNetworkError(
    String reqId,
    ApiException original,
    _Attempt attempt,
  ) async {
    for (final delay in pollDelays) {
      await Future<void>.delayed(delay);
      if (attempt.done.isCompleted) throw original;
      try {
        final r = await poll(reqId);
        if (r != null) return r;
      } on ApiException catch (e) {
        if (betErrorCode(e) == 'BET_REQ_NOT_FOUND' || e.code == 404) {
          throw original;
        }
      }
    }
    throw original;
  }
}

class _Attempt {
  _Attempt(this.http);

  final Future<BetSubmitResult> Function() http;
  final done = Completer<BetSubmitResult>();
  void Function()? startHttp;

  void complete(BetSubmitResult r) {
    if (!done.isCompleted) done.complete(r);
  }

  void fail(Object e) {
    if (!done.isCompleted) done.completeError(e);
  }
}

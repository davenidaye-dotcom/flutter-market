import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/core/network/api_exception.dart';
import 'package:letou_app/data/repositories/lottery_repository.dart';
import 'package:letou_app/features/lottery/services/bet_executor.dart';

const _ms = Duration(milliseconds: 10);

BetSubmitResult _ok(String id) => BetSubmitResult(orderIds: [id], content: 'c');

void main() {
  late List<String> sent;
  late int httpCalls;
  late int pollCalls;

  BetExecutor build({
    bool ws = true,
    required Future<BetSubmitResult> Function() http,
    Future<BetSubmitResult?> Function(String)? poll,
  }) {
    return BetExecutor(
      wsAvailable: () => ws,
      sendWs: (reqId, body) {
        sent.add(reqId);
        return true;
      },
      poll: (id) {
        pollCalls++;
        return (poll ?? (_) async => null)(id);
      },
      ackTimeout: const Duration(milliseconds: 60),
      pollDelays: const [_ms, _ms, _ms],
      busyRetryDelay: _ms,
    );
  }

  setUp(() {
    sent = [];
    httpCalls = 0;
    pollCalls = 0;
  });

  test('WS 有 BET_ACK：不走 HTTP', () async {
    final ex = build(http: () async {
      httpCalls++;
      return _ok('http');
    });
    final f = ex.submit('r1', {'x': 1}, () async {
      httpCalls++;
      return _ok('http');
    });
    ex.onAck({'reqId': 'r1', 'ok': true, 'orderId': '77'});
    final r = await f;
    expect(r.orderIds, ['77']);
    expect(sent, ['r1']);
    expect(httpCalls, 0);
  });

  test('3s 内无 ACK：同一 reqId 走 HTTP；HTTP 先返回则之后的 ACK 被忽略', () async {
    final ex = build(http: () async => _ok('x'));
    final f = ex.submit('r2', {}, () async {
      httpCalls++;
      return _ok('http');
    });
    final r = await f;
    ex.onAck({'reqId': 'r2', 'ok': true, 'orderId': 'late'});
    expect(r.orderIds, ['http']);
    expect(httpCalls, 1);
  });

  test('HTTP 在途时 ACK 先到：采用 ACK，HTTP 结果丢弃', () async {
    final ex = build(http: () async => _ok('x'));
    final f = ex.submit('r2b', {}, () async {
      httpCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      return _ok('http');
    });
    await Future<void>.delayed(const Duration(milliseconds: 70));
    ex.onAck({'reqId': 'r2b', 'ok': true, 'orderId': 'ack'});
    expect((await f).orderIds, ['ack']);
    expect(httpCalls, 1);
  });

  test('WS 不可用：直接 HTTP，不发 WS', () async {
    final ex = build(ws: false, http: () async => _ok('x'));
    final r = await ex.submit('r3', {}, () async => _ok('http'));
    expect(r.orderIds, ['http']);
    expect(sent, isEmpty);
  });

  test('ACK ok=false 业务错误：直接报错，不回退 HTTP', () async {
    final ex = build(http: () async => _ok('x'));
    final f = ex.submit('r4', {}, () async {
      httpCalls++;
      return _ok('http');
    });
    ex.onAck({'reqId': 'r4', 'ok': false, 'code': 'SEALED', 'message': '已封盘'});
    await expectLater(
      f,
      throwsA(isA<ApiException>()
          .having((e) => e.bizCode, 'bizCode', 'SEALED')
          .having((e) => e.message, 'message', '已封盘')),
    );
    expect(httpCalls, 0);
  });

  test('ACK BET_BUSY：改走 HTTP 重试一次（同 reqId）', () async {
    final ex = build(http: () async => _ok('x'));
    final f = ex.submit('r5', {}, () async {
      httpCalls++;
      return _ok('http');
    });
    ex.onAck({'reqId': 'r5', 'ok': false, 'code': 'BET_BUSY'});
    expect((await f).orderIds, ['http']);
    expect(httpCalls, 1);
  });

  test('HTTP 业务错误不重试、不轮询', () async {
    final ex = build(ws: false, http: () async => _ok('x'));
    final f = ex.submit('r6', {}, () async {
      httpCalls++;
      throw const ApiException(message: '余额不足', bizCode: 'BALANCE_NOT_ENOUGH');
    });
    await expectLater(f, throwsA(isA<ApiException>()));
    expect(httpCalls, 1);
    expect(pollCalls, 0);
  });

  test('HTTP BET_BUSY 只重试一次', () async {
    final ex = build(ws: false, http: () async => _ok('x'));
    final f = ex.submit('r7', {}, () async {
      httpCalls++;
      throw const ApiException(message: 'busy', bizCode: 'BET_BUSY');
    });
    await expectLater(f, throwsA(isA<ApiException>()));
    expect(httpCalls, 2);
  });

  test('HTTP 网络错误：按 reqId 轮询，PENDING 后 DONE 即成功', () async {
    var n = 0;
    final ex = build(
      ws: false,
      http: () async => _ok('x'),
      poll: (_) async => ++n < 3 ? null : _ok('polled'),
    );
    final r = await ex.submit('r8', {}, () async {
      httpCalls++;
      throw const ApiException(message: '系统维护中', isNetwork: true);
    });
    expect(r.orderIds, ['polled']);
    expect(httpCalls, 1);
    expect(pollCalls, 3);
  });

  test('轮询 BET_REQ_NOT_FOUND：立即按原网络错误失败', () async {
    final ex = build(
      ws: false,
      http: () async => _ok('x'),
      poll: (_) async =>
          throw const ApiException(message: 'x', bizCode: 'BET_REQ_NOT_FOUND'),
    );
    final f = ex.submit('r9', {}, () async {
      throw const ApiException(message: '系统维护中', isNetwork: true);
    });
    await expectLater(
      f,
      throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true)),
    );
    expect(pollCalls, 1);
  });

  test('轮询用尽仍 PENDING：失败', () async {
    final ex = build(ws: false, http: () async => _ok('x'));
    final f = ex.submit('r10', {}, () async {
      throw const ApiException(message: '系统维护中', isNetwork: true);
    });
    await expectLater(f, throwsA(isA<ApiException>()));
    expect(pollCalls, 3);
  });

  test('同一 reqId 重试合并成一次在途请求', () async {
    final ex = build(ws: false, http: () async => _ok('x'));
    final c = Completer<BetSubmitResult>();
    final f1 = ex.submit('r11', {}, () {
      httpCalls++;
      return c.future;
    });
    final f2 = ex.submit('r11', {}, () {
      httpCalls++;
      return c.future;
    });
    c.complete(_ok('one'));
    expect((await f1).orderIds, ['one']);
    expect((await f2).orderIds, ['one']);
    expect(httpCalls, 1);
  });

  test('betErrorMessage：文案为空或只是错误码时用本地提示', () {
    expect(
      betErrorMessage(const ApiException(message: 'BET_BUSY', bizCode: 'BET_BUSY')),
      isNot('BET_BUSY'),
    );
    expect(
      betErrorMessage(const ApiException(message: '余额不足', bizCode: 'X')),
      '余额不足',
    );
  });
}

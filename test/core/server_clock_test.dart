import 'package:flutter_test/flutter_test.dart';
import 'package:letou_app/core/time/server_clock.dart';

void main() {
  setUp(ServerClock.reset);

  test('未校准时退回手机时间', () {
    expect(ServerClock.calibrated, isFalse);
    final d = ServerClock.now().difference(DateTime.now()).inMilliseconds.abs();
    expect(d, lessThan(50));
  });

  test('手机时钟快 3 秒：校准后 now() 对齐服务器而不是手机', () {
    final phoneNow = DateTime.now().millisecondsSinceEpoch;
    final serverNow = phoneNow - 3000; // 服务器比手机慢 3 秒
    ServerClock.observe(serverNow);

    final skew = ServerClock.now().millisecondsSinceEpoch - serverNow;
    expect(skew.abs(), lessThan(100));
    expect(ServerClock.phoneAheadMs!, inInclusiveRange(2900, 3200));
  });

  test('两部手机时钟不同，收到同一服务器时间后算出的 now() 一致', () {
    final base = DateTime.now().millisecondsSinceEpoch;
    ServerClock.observe(base + 10000); // 手机 A：慢了 10 秒
    final a = ServerClock.now().millisecondsSinceEpoch;
    ServerClock.reset();
    ServerClock.observe(base - 2000); // 手机 B：快了 2 秒
    final b = ServerClock.now().millisecondsSinceEpoch;
    // 同一时刻不同的服务器时间（相差 12 秒）仅用于验证偏移独立；
    // 同一服务器时刻下两者应一致：
    ServerClock.reset();
    ServerClock.observe(base);
    final c = ServerClock.now().millisecondsSinceEpoch;
    ServerClock.reset();
    ServerClock.observe(base);
    final d = ServerClock.now().millisecondsSinceEpoch;
    expect((c - d).abs(), lessThan(50));
    expect((a - b - 12000).abs(), lessThan(50));
  });

  test('窗口内取延迟最小的样本（偏移最大）', () {
    final base = DateTime.now().millisecondsSinceEpoch;
    ServerClock.observe(base - 400); // 一次慢包：看起来服务器落后 400ms
    ServerClock.observe(base - 40); // 一次快包
    final err = ServerClock.now().millisecondsSinceEpoch - base;
    expect(err.abs(), lessThan(100)); // 采纳快包，不是慢包
  });

  test('无效时间戳被忽略', () {
    ServerClock.observe(null);
    ServerClock.observe(0);
    ServerClock.observe(-5);
    expect(ServerClock.calibrated, isFalse);
  });

  test('8 秒 RTT 不能把时钟拨快超过 1 秒', () {
    final base = DateTime.now().millisecondsSinceEpoch;
    ServerClock.observe(base);
    final before = ServerClock.offsetMs;
    ServerClock.observe(base, latencyMs: 8000);
    expect(ServerClock.offsetMs, before);
    final skew = ServerClock.now().millisecondsSinceEpoch - base;
    expect(skew.abs(), lessThan(1000));
  });

  test('过期的偏快样本在没有新包时也会清掉，只留最新一条', () {
    ServerClock.debugElapsedMs = 0;
    ServerClock.observe(5000000 + 800); // 偏快的一条
    ServerClock.debugElapsedMs = 30 * 1000;
    ServerClock.observe(5000000 + 30 * 1000); // 准的一条
    expect(ServerClock.offsetMs, 5000000 + 800);
    ServerClock.debugElapsedMs = 61 * 1000;
    ServerClock.now();
    expect(ServerClock.offsetMs, 5000000);
    // 再过很久也不退回手机时间，沿用最新那条
    ServerClock.debugElapsedMs = 600 * 1000;
    ServerClock.now();
    expect(ServerClock.calibrated, isTrue);
    expect(ServerClock.offsetMs, 5000000);
  });
}

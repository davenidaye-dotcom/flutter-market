import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/member_repository.dart';
import '../../data/repositories/owner_repository.dart';

/// 开奖、封盘按彩种各一个开关，关着就不响。消息只在收到对方客服消息时响一声。
/// 每次登录回到默认：开奖关、封盘关、消息开。
class BgmPrompt {
  BgmPrompt._();

  static const _prefKey = 'flyroom_bgm_prefs_v2';
  static const _drawAsset = 'sounds/coin.wav';
  static const _sealAsset = 'sounds/wood.wav';
  static const _messageAsset = 'sounds/ding.wav';

  static final AudioPlayer _player = AudioPlayer();
  static final Queue<_Cue> _queue = Queue<_Cue>();
  static final LinkedHashSet<String> _played = LinkedHashSet<String>();
  static final Map<String, _Flag> _games = {};
  static bool messageOn = true;
  static int _messageHeld = 0;
  /// 底栏正停在「在线客服」。房主的会话列表、某条私聊，和玩家的客服对话，都是这一栏。
  static bool _shellOnCs = false;
  static bool _ready = false;
  static bool _playing = false;
  static bool _hooked = false;
  static int _playGen = 0;
  static int _expectComplete = 0;
  static DateTime _ignoreCompleteUntil = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void> _tail = Future<void>.value();

  static bool drawOn(String gameType) =>
      _games[_key(gameType)]?.draw ?? false;

  static bool sealOn(String gameType) =>
      _games[_key(gameType)]?.seal ?? false;

  static Future<void> loadLocal() => _serial(_readLocal);

  static Future<void> refreshPlayer() => loadLocal();

  static Future<void> refreshHost() => loadLocal();

  static Future<void> setMessage(bool value, {required bool host}) {
    return _serial(() async {
      final prev = messageOn;
      messageOn = value;
      if (!value) {
        _queue.removeWhere((cue) => cue.kind == 'MESSAGE');
      }
      await _persist();
      try {
        await _push(host: host);
      } catch (e) {
        messageOn = prev;
        await _persist();
        rethrow;
      }
    });
  }

  static Future<void> setGame(
    String gameType, {
    bool? draw,
    bool? seal,
    required bool host,
  }) {
    return _serial(() async {
      final key = _key(gameType);
      final prev = Map<String, _Flag>.from(_games);
      final cur = _games[key] ?? const _Flag();
      final next = _Flag(draw: draw ?? cur.draw, seal: seal ?? cur.seal);
      if (!next.draw && !next.seal) {
        _games.remove(key);
      } else {
        _games[key] = next;
      }
      if (draw == false) {
        _queue.removeWhere((cue) => cue.kind == 'DRAW' && cue.gameType == key);
      }
      if (seal == false) {
        _queue.removeWhere((cue) => cue.kind == 'SEAL' && cue.gameType == key);
      }
      await _persist();
      try {
        await _push(host: host);
      } catch (e) {
        _games
          ..clear()
          ..addAll(prev);
        await _persist();
        rethrow;
      }
    });
  }

  /// 登录成功后回到默认。不把上次打开的开奖、封盘带回来。消息重新打开。
  static Future<void> resetForLogin({required bool host, required bool player}) {
    return _serial(() async {
      messageOn = true;
      _games.clear();
      _queue.clear();
      // 上一轮提示音若没收到结束回调，锁会一直占着，换账号登录后也全部没声。
      _playGen++;
      _playing = false;
      await _persist();
      if (!host && !player) return;
      try {
        await _push(host: host, ignoreUnauthorized: true);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('BgmPrompt.resetForLogin failed: $e');
        }
      }
    });
  }

  static void playSeal(String roomId, String gameType, String issue) {
    final key = _key(gameType);
    final issueNo = issue.trim();
    if (key.isEmpty || issueNo.isEmpty || !sealOn(key)) return;
    _enqueue(_Cue(_sealAsset, 'SEAL', key), '$roomId|$key|$issueNo|SEAL');
  }

  static void playDraw(String roomId, String gameType, String issue) {
    final key = _key(gameType);
    final issueNo = issue.trim();
    if (key.isEmpty || issueNo.isEmpty || !drawOn(key)) return;
    _enqueue(_Cue(_drawAsset, 'DRAW', key), '$roomId|$key|$issueNo|DRAW');
  }

  /// 底栏切到在线客服时由壳层记下。列表和私聊都算这一栏。
  static void setShellOnCs(bool value) {
    _shellOnCs = value;
  }

  static bool get _csQuiet => _shellOnCs || _messageHeld > 0;

  /// 从别的页面盖出来的客服页按住。人离开再放开，下一声才响。
  static void holdMessage() => _messageHeld++;

  static void releaseMessage() {
    if (_messageHeld > 0) _messageHeld--;
  }

  static void playMessage(String id) {
    if (!messageOn || _csQuiet) return;
    final token = id.trim();
    if (token.isEmpty) return;
    _enqueue(_Cue(_messageAsset, 'MESSAGE', ''), 'MSG|$token');
  }

  static Future<void> _readLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      messageOn = true;
      _games.clear();
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      messageOn = decoded['message'] != false;
      final rawGames = decoded['games'];
      if (rawGames is! Map) return;
      rawGames.forEach((key, value) {
        if (value is! Map) return;
        final draw = value['draw'] == true;
        final seal = value['seal'] == true;
        if (!draw && !seal) return;
        _games[_key('$key')] = _Flag(draw: draw, seal: seal);
      });
    } catch (_) {}
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final body = <String, Object>{
        'message': messageOn,
        'games': {
          for (final entry in _games.entries)
            entry.key: {'draw': entry.value.draw, 'seal': entry.value.seal},
        },
      };
      await prefs.setString(_prefKey, jsonEncode(body));
    } catch (_) {}
  }

  static Future<void> _push({required bool host, bool ignoreUnauthorized = false}) {
    final payload = <String, Map<String, bool>>{
      for (final entry in _games.entries)
        entry.key: {'draw': entry.value.draw, 'seal': entry.value.seal},
    };
    if (host) {
      return OwnerRepository().updateBgm(
        message: messageOn,
        games: payload,
        ignoreUnauthorized: ignoreUnauthorized,
      );
    }
    return MemberRepository().updateBgm(
      message: messageOn,
      games: payload,
      ignoreUnauthorized: ignoreUnauthorized,
    );
  }

  static void _enqueue(_Cue cue, String dedupeKey) {
    final issueNo = dedupeKey.trim();
    if (issueNo.isEmpty) return;
    if (!_allowed(cue)) return;
    if (!_played.add(issueNo)) return;
    while (_played.length > 240) {
      _played.remove(_played.first);
    }
    _queue.add(cue);
    unawaited(_pump());
  }

  static bool _allowed(_Cue cue) {
    if (cue.kind == 'MESSAGE') return messageOn && !_csQuiet;
    if (cue.kind == 'SEAL') return sealOn(cue.gameType);
    if (cue.kind == 'DRAW') return drawOn(cue.gameType);
    return false;
  }

  static void _finish(int gen) {
    if (gen != _playGen || !_playing) return;
    _playing = false;
    unawaited(_pump());
  }

  static Future<void> _pump() async {
    if (_playing || _queue.isEmpty) return;
    final cue = _queue.removeFirst();
    if (!_allowed(cue)) {
      if (_queue.isNotEmpty) unawaited(_pump());
      return;
    }
    _playing = true;
    final gen = ++_playGen;
    // 短提示音经常不回调 onPlayerComplete。不在这里放开，后面的客服消息会一直没声。
    unawaited(Future<void>.delayed(const Duration(milliseconds: 1500), () {
      _finish(gen);
    }));
    try {
      await _ensure();
      if (gen != _playGen) return;
      // stop() 自己也会触发 complete，不能把它当成这一声结束。
      _ignoreCompleteUntil = DateTime.now().add(const Duration(milliseconds: 280));
      try {
        await _player.stop();
      } catch (_) {}
      if (gen != _playGen || !_allowed(cue)) {
        _finish(gen);
        return;
      }
      _expectComplete = gen;
      await _player.play(AssetSource(cue.asset));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BgmPrompt.play failed: $e');
      }
      _finish(gen);
    }
  }

  static Future<void> _ensure() async {
    if (!_hooked) {
      _hooked = true;
      _player.onPlayerComplete.listen((_) {
        if (DateTime.now().isBefore(_ignoreCompleteUntil)) return;
        _finish(_expectComplete);
      });
    }
    if (_ready) return;
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setVolume(1);
    _ready = true;
  }

  static Future<void> _serial(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  static String _key(String gameType) => gameType.trim().toUpperCase();
}

class _Flag {
  const _Flag({this.draw = false, this.seal = false});

  final bool draw;
  final bool seal;
}

class _Cue {
  const _Cue(this.asset, this.kind, this.gameType);

  final String asset;
  final String kind;
  final String gameType;
}

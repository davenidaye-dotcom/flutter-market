import 'dart:async';
import 'dart:collection';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/member_repository.dart';
import '../../data/repositories/owner_repository.dart';

/// 封盘、开奖各一声。开关跟账号走，关了就不再响。
class BgmPrompt {
  BgmPrompt._();

  static const _prefKey = 'flyroom_bgm_enabled';
  static const _sealAsset = 'sounds/seal.wav';
  static const _drawAsset = 'sounds/draw.wav';

  static final AudioPlayer _player = AudioPlayer();
  static final Queue<String> _queue = Queue<String>();
  static final LinkedHashSet<String> _played = LinkedHashSet<String>();
  static bool enabled = true;
  static bool _ready = false;
  static bool _playing = false;
  static bool _hooked = false;
  static bool _ignoreComplete = false;

  static Future<void> loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(_prefKey) ?? true;
    } catch (_) {}
  }

  static Future<void> setEnabled(bool value) async {
    enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
    if (!value) {
      _queue.clear();
      try {
        await _player.stop();
      } catch (_) {}
      _playing = false;
    }
  }

  static Future<void> refreshPlayer() => _refresh(host: false);

  static Future<void> refreshHost() => _refresh(host: true);

  static Future<void> _refresh({required bool host}) async {
    await loadLocal();
    try {
      final on = host
          ? await OwnerRepository().getBgmEnabled()
          : await MemberRepository().getBgmEnabled();
      await setEnabled(on);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BgmPrompt.refresh failed: $e');
      }
    }
  }

  static void playSeal(String roomId, String gameType, String issue) {
    _enqueue(_sealAsset, roomId, gameType, issue, 'SEAL');
  }

  static void playDraw(String roomId, String gameType, String issue) {
    _enqueue(_drawAsset, roomId, gameType, issue, 'DRAW');
  }

  static void _enqueue(
    String asset,
    String roomId,
    String gameType,
    String issue,
    String kind,
  ) {
    if (!enabled) return;
    final issueNo = issue.trim();
    if (issueNo.isEmpty || gameType.trim().isEmpty) return;
    final key = '$roomId|$gameType|$issueNo|$kind';
    if (!_played.add(key)) return;
    while (_played.length > 240) {
      _played.remove(_played.first);
    }
    _queue.add(asset);
    unawaited(_pump());
  }

  static Future<void> _pump() async {
    if (_playing || _queue.isEmpty || !enabled) return;
    _playing = true;
    final asset = _queue.removeFirst();
    try {
      await _ensure();
      _ignoreComplete = true;
      await _player.stop();
      _ignoreComplete = false;
      if (!enabled) {
        _playing = false;
        return;
      }
      await _player.play(AssetSource(asset));
    } catch (e) {
      _playing = false;
      if (kDebugMode) {
        debugPrint('BgmPrompt.play failed: $e');
      }
      if (_queue.isNotEmpty && enabled) {
        unawaited(_pump());
      }
    }
  }

  static Future<void> _ensure() async {
    if (!_hooked) {
      _hooked = true;
      _player.onPlayerComplete.listen((_) {
        if (_ignoreComplete) return;
        _playing = false;
        unawaited(_pump());
      });
    }
    if (_ready) return;
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setVolume(1);
    _ready = true;
  }
}

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 房主审核提醒提示音：弹窗出现时播放一次。
class HostAuditAlertSound {
  HostAuditAlertSound._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _ready = false;

  static Future<void> _ensure() async {
    if (_ready) return;
    await _player.setReleaseMode(ReleaseMode.release);
    await _player.setVolume(1.0);
    _ready = true;
  }

  static Future<void> playOnce() async {
    try {
      await _ensure();
      await _player.stop();
      await _player.play(AssetSource('sounds/audit_notice.wav'));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('HostAuditAlertSound.playOnce failed: $e');
      }
    }
  }
}

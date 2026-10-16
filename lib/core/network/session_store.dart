import 'package:shared_preferences/shared_preferences.dart';

import 'client_cert_store.dart';

/// In-memory + persisted auth/room session for Dio interceptors.
class SessionStore {
  SessionStore._();
  static final SessionStore instance = SessionStore._();

  static const _kToken = 'flyroom_access_token';
  static const _kRoomId = 'flyroom_room_id';
  static const _kRoomCode = 'flyroom_room_code';
  static const _kRoomName = 'flyroom_room_name';
  static const _kOwnerNickname = 'flyroom_owner_nickname';
  static const _kBetConfirm = 'flyroom_bet_confirm';
  static const _kShowQuick = 'flyroom_show_quick';

  String? accessToken;
  /// 每次开始一次新的密码登录或清会话时递增。在途的快登不能再写入 token。
  int epoch = 0;
  String? roomId;
  String? roomCode;
  String? roomName;
  String? ownerNickname;
  bool betConfirm = false;
  /// 房主「显示快捷」。关则聊天页不显示盘口入口。默认开。
  bool showQuick = true;

  bool get hasToken => accessToken != null && accessToken!.isNotEmpty;

  /// token / 房间 / 清会话串行写，避免后完成的旧登录把新 token 写回磁盘。
  Future<void> _queue = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// 作废还没写完的登录（快登、上一次密码登录）。
  int bumpEpoch() => ++epoch;

  /// 大厅顶栏：房主昵称 → 房间名。
  String get hallTitle {
    final nick = ownerNickname?.trim() ?? '';
    if (nick.isNotEmpty) return nick;
    return roomName?.trim() ?? '';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString(_kToken);
    roomId = prefs.getString(_kRoomId);
    roomCode = prefs.getString(_kRoomCode);
    roomName = prefs.getString(_kRoomName);
    ownerNickname = prefs.getString(_kOwnerNickname);
    betConfirm = prefs.getBool(_kBetConfirm) ?? false;
    showQuick = prefs.getBool(_kShowQuick) ?? true;
  }

  /// [epoch] 与当前代际不一致时不写入，避免快登覆盖刚完成的密码登录。
  Future<bool> setToken(String? token, {int? epoch}) {
    return _serial(() => _setToken(token, epoch: epoch));
  }

  Future<bool> _setToken(String? token, {int? epoch}) async {
    if (epoch != null && this.epoch != epoch) return false;
    final captured = this.epoch;
    accessToken = token;
    final prefs = await SharedPreferences.getInstance();
    if (this.epoch != captured) {
      if (accessToken == token) accessToken = null;
      return false;
    }
    if (token == null || token.isEmpty) {
      await prefs.remove(_kToken);
    } else {
      await prefs.setString(_kToken, token);
    }
    if (this.epoch != captured || accessToken != token) {
      final now = accessToken;
      if (now == null || now.isEmpty) {
        await prefs.remove(_kToken);
      } else {
        await prefs.setString(_kToken, now);
      }
      return false;
    }
    return true;
  }

  Future<void> setRoom({
    String? roomId,
    String? roomCode,
    String? roomName,
    String? ownerNickname,
    bool? betConfirm,
    bool? showQuick,
    int? epoch,
  }) {
    return _serial(() => _setRoom(
          roomId: roomId,
          roomCode: roomCode,
          roomName: roomName,
          ownerNickname: ownerNickname,
          betConfirm: betConfirm,
          showQuick: showQuick,
          epoch: epoch,
        ));
  }

  Future<void> _setRoom({
    String? roomId,
    String? roomCode,
    String? roomName,
    String? ownerNickname,
    bool? betConfirm,
    bool? showQuick,
    int? epoch,
  }) async {
    if (epoch != null && this.epoch != epoch) return;
    final captured = this.epoch;
    this.roomId = roomId;
    this.roomCode = roomCode;
    if (roomName != null) this.roomName = roomName;
    if (ownerNickname != null) this.ownerNickname = ownerNickname;
    if (betConfirm != null) this.betConfirm = betConfirm;
    if (showQuick != null) this.showQuick = showQuick;
    final prefs = await SharedPreferences.getInstance();
    if (this.epoch != captured) return;
    if (roomId == null || roomId.isEmpty) {
      await prefs.remove(_kRoomId);
    } else {
      await prefs.setString(_kRoomId, roomId);
    }
    if (roomCode == null || roomCode.isEmpty) {
      await prefs.remove(_kRoomCode);
    } else {
      await prefs.setString(_kRoomCode, roomCode);
    }
    final name = this.roomName?.trim() ?? '';
    if (name.isEmpty) {
      await prefs.remove(_kRoomName);
    } else {
      await prefs.setString(_kRoomName, name);
    }
    final nick = this.ownerNickname?.trim() ?? '';
    if (nick.isEmpty) {
      await prefs.remove(_kOwnerNickname);
    } else {
      await prefs.setString(_kOwnerNickname, nick);
    }
    if (betConfirm != null) {
      await prefs.setBool(_kBetConfirm, betConfirm);
    }
    if (showQuick != null) {
      await prefs.setBool(_kShowQuick, showQuick);
    }
  }

  Future<void> setShowQuick(bool value) async {
    showQuick = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowQuick, value);
  }

  Future<void> setBetConfirm(bool value) async {
    betConfirm = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBetConfirm, value);
  }

  /// 这次登录写入的 token 还在，但代际已经被更新的登录占走。只撤这张 token，不再拨代际。
  Future<void> dropToken(String token) {
    return _serial(() => _dropToken(token));
  }

  Future<void> _dropToken(String token) async {
    if (token.isEmpty || accessToken != token) return;
    accessToken = null;
    final prefs = await SharedPreferences.getInstance();
    if (accessToken != null) return;
    await prefs.remove(_kToken);
  }

  Future<void> clear() {
    epoch++;
    accessToken = null;
    roomId = null;
    roomCode = null;
    roomName = null;
    ownerNickname = null;
    betConfirm = false;
    showQuick = true;
    return _serial(_clearPersisted);
  }

  Future<void> _clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final token = accessToken;
    if (token != null && token.isNotEmpty) {
      await prefs.setString(_kToken, token);
      return;
    }
    await prefs.remove(_kToken);
    await prefs.remove(_kRoomId);
    await prefs.remove(_kRoomCode);
    await prefs.remove(_kRoomName);
    await prefs.remove(_kOwnerNickname);
    await prefs.remove(_kBetConfirm);
    await prefs.remove(_kShowQuick);
    ClientCertStore.instance.clear();
  }
}

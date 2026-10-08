import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/models/chat_message_model.dart';

/// 重复通道：聊天键盘 vs 盘面，禁止互相覆盖。
enum BetRepeatChannel {
  chat,
  market;

  String get keyPart => name;
}

/// 「重复」：按房间+彩种+账号+通道存上一笔成功指令。
class BetRepeatStore {
  BetRepeatStore._();

  static const _prefPrefix = 'flyroom_bet_repeat_v2_';
  static final Map<String, String> _memory = {};

  static String _key(
    String roomId,
    String gameId,
    String accountId,
    BetRepeatChannel channel,
  ) =>
      '$roomId|$gameId|$accountId|${channel.keyPart}';

  static Future<void> save({
    required String roomId,
    required String gameId,
    required String accountId,
    required BetRepeatChannel channel,
    required String command,
  }) async {
    final text = command.trim();
    if (text.isEmpty || !isRepeatableBetContent(text)) return;
    if (accountId.isEmpty) return;
    final key = _key(roomId, gameId, accountId, channel);
    _memory[key] = text;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefPrefix$key', text);
  }

  static Future<String?> read({
    required String roomId,
    required String gameId,
    required String accountId,
    required BetRepeatChannel channel,
  }) async {
    if (accountId.isEmpty) return null;
    final key = _key(roomId, gameId, accountId, channel);
    final cached = _memory[key];
    if (cached != null && cached.isNotEmpty) return cached;
    final prefs = await SharedPreferences.getInstance();
    final disk = prefs.getString('$_prefPrefix$key');
    if (disk != null && disk.isNotEmpty) {
      _memory[key] = disk;
      return disk;
    }
    return null;
  }

  static Future<bool> has({
    required String roomId,
    required String gameId,
    required String accountId,
    required BetRepeatChannel channel,
  }) async {
    final v = await read(
      roomId: roomId,
      gameId: gameId,
      accountId: accountId,
      channel: channel,
    );
    return v != null && v.isNotEmpty;
  }
}

/// 未发送的下注草稿（进聊天页恢复输入框）。
class BetDraftStore {
  BetDraftStore._();

  static const _prefPrefix = 'flyroom_bet_draft_';
  static final Map<String, String> _memory = {};

  static String _key(String roomId, String gameId, String accountId) =>
      '$roomId|$gameId|$accountId';

  static Future<void> save({
    required String roomId,
    required String gameId,
    required String accountId,
    required String draft,
  }) async {
    if (accountId.isEmpty) return;
    final key = _key(roomId, gameId, accountId);
    final text = draft;
    _memory[key] = text;
    final prefs = await SharedPreferences.getInstance();
    if (text.trim().isEmpty) {
      await prefs.remove('$_prefPrefix$key');
      return;
    }
    await prefs.setString('$_prefPrefix$key', text);
  }

  static Future<String?> read({
    required String roomId,
    required String gameId,
    required String accountId,
  }) async {
    if (accountId.isEmpty) return null;
    final key = _key(roomId, gameId, accountId);
    final cached = _memory[key];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final disk = prefs.getString('$_prefPrefix$key');
    if (disk != null) _memory[key] = disk;
    return disk;
  }

  static Future<void> clear({
    required String roomId,
    required String gameId,
    required String accountId,
  }) async {
    if (accountId.isEmpty) return;
    final key = _key(roomId, gameId, accountId);
    _memory.remove(key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefPrefix$key');
  }
}

bool isRepeatableBetContent(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return false;
  if (text == '取消' || text == '重复' || text == '梭哈') return false;
  if (text.contains('封盘线') || text.contains('停止战斗')) return false;
  if (text.contains('距离封盘') || text.contains('中奖名单')) return false;
  if (text.contains('中奖列表核对') || text.contains('中奖金额')) return false;
  if (text.contains('竞猜列表核对') || text.contains('下注总金额')) return false;
  if (text.contains('已开奖')) return false;
  if (RegExp(r'第\d+期开奖').hasMatch(text)) return false;
  return true;
}

bool isUserBetChatMessage(ChatMessageModel message) {
  if (message.type != ChatMessageType.text) return false;
  if (message.isAdmin) return false;
  return isRepeatableBetContent(message.content);
}

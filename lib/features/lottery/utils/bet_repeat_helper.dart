import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/models/chat_message_model.dart';
import '../../../data/models/user_model.dart';

/// 聊天「重复」：回填上一笔成功下注指令，排除系统/开奖/封盘文案。
class BetRepeatStore {
  BetRepeatStore._();

  static const _prefPrefix = 'flyroom_bet_repeat_';
  static final Map<String, String> _memory = {};

  static String _key(String roomId, String gameId, String accountId) =>
      '$roomId|$gameId|$accountId';

  static Future<void> save({
    required String roomId,
    required String gameId,
    required String accountId,
    required String command,
  }) async {
    final text = command.trim();
    if (text.isEmpty || !isRepeatableBetContent(text)) return;
    if (accountId.isEmpty) return;
    final key = _key(roomId, gameId, accountId);
    _memory[key] = text;
    final prefs = await SharedPreferences.getInstance();
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
    if (cached != null && cached.isNotEmpty) return cached;
    final prefs = await SharedPreferences.getInstance();
    final disk = prefs.getString('$_prefPrefix$key');
    if (disk != null && disk.isNotEmpty) {
      _memory[key] = disk;
      return disk;
    }
    return null;
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

String? findRepeatableFromMessages(
  List<ChatMessageModel> messages,
  UserModel? user,
) {
  final selfNames = <String>{'我'};
  if (user != null) {
    if (user.nickname.isNotEmpty) selfNames.add(user.nickname);
    if (user.username.isNotEmpty) selfNames.add(user.username);
  }
  for (var i = messages.length - 1; i >= 0; i--) {
    final m = messages[i];
    if (!isUserBetChatMessage(m)) continue;
    if (!selfNames.contains(m.sender)) continue;
    return m.content.trim();
  }
  return null;
}

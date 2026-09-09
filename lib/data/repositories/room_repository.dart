import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/session_store.dart';
import '../models/room_model.dart';

class RoomRepository {
  RoomRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<RoomModel> verifyRoom(String roomCode) async {
    final data = await _client.get(
      '/member/rooms/verify',
      query: {'roomCode': roomCode},
    );
    if (data is! Map) {
      throw const ApiException(message: '房间校验失败');
    }
    final map = Map<String, dynamic>.from(data);
    final exists = map['exists'] == true;
    if (!exists) {
      final reason = map['reason']?.toString();
      throw ApiException(
        message: reason?.isNotEmpty == true
            ? _reasonMessage(reason!)
            : '房间不存在或不可进入',
      );
    }
    return RoomModel(
      id: map['roomCode']?.toString() ?? roomCode,
      name: map['roomName']?.toString() ?? '',
      thumbnailUrl: map['coverUrl']?.toString(),
      numericId: map['roomId']?.toString(),
      enterMode: map['enterMode']?.toString() ?? map['enter_mode']?.toString(),
      hasEnterPassword: map['hasEnterPassword'] == true ||
          map['needEnterPassword'] == true,
      status: map['status']?.toString(),
      betConfirm: map['betConfirm'] == true || map['betConfirm'] == 1,
    );
  }

  Future<RoomModel> enterRoom(String roomCode, {String? enterPassword}) async {
    final data = await _client.post(
      '/member/rooms/enter',
      data: {
        'roomCode': roomCode,
        if (enterPassword != null && enterPassword.isNotEmpty)
          'enterPassword': enterPassword,
      },
    );
    if (data is! Map) {
      throw const ApiException(message: '进房失败');
    }
    final map = Map<String, dynamic>.from(data);
    final code = map['roomCode']?.toString() ?? roomCode;
    final roomId = map['roomId']?.toString();
    await SessionStore.instance.setRoom(
      roomId: roomId,
      roomCode: code,
      betConfirm: map['betConfirm'] == true || map['betConfirm'] == 1,
    );
    return RoomModel(
      id: code,
      name: map['roomName']?.toString() ?? '',
      thumbnailUrl: map['coverUrl']?.toString(),
      numericId: roomId,
      betConfirm: map['betConfirm'] == true || map['betConfirm'] == 1,
    );
  }

  Future<List<RoomModel>> getHistoryRooms({int limit = 20}) async {
    final data = await _client.get(
      '/member/rooms/history',
      query: {'limit': limit},
    );
    if (data is! List) return const [];
    return data.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return RoomModel(
        id: m['roomCode']?.toString() ?? '',
        name: m['roomName']?.toString() ?? '',
        thumbnailUrl: m['coverUrl']?.toString(),
        numericId: m['roomId']?.toString(),
      );
    }).where((r) => r.id.isNotEmpty).toList();
  }

  Future<List<AnnouncementModel>> getAnnouncements(String roomId) async {
    final _ = roomId;
    try {
      final data = await _client.get('/member/notices');
      if (data is! List) return const [];
      return data.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        final content = m['content']?.toString() ?? '';
        final created = m['startAt']?.toString() ?? '';
        return AnnouncementModel(
          id: '${m['noticeId'] ?? m['id'] ?? ''}',
          title: m['scope']?.toString() ?? '',
          content: content,
          createdAt: DateTime.tryParse(created) ?? DateTime.now(),
        );
      }).where((a) => a.content.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  static String _reasonMessage(String reason) {
    switch (reason.toUpperCase()) {
      case 'ROOM_NOT_FOUND':
        return '房间不存在';
      case 'ROOM_DISABLED':
        return '房间已停用';
      default:
        return reason;
    }
  }
}

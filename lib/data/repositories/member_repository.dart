import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';

/// Member profile / CS / redpacks / room intro.
class MemberRepository {
  MemberRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<Map<String, dynamic>> getProfile() async {
    final data = await _client.get('/member/profile');
    return _asMap(data);
  }

  Future<void> updateNickname(String nickname) async {
    await _client.put('/member/profile/nickname', data: {'nickname': nickname});
  }

  Future<void> updateAvatar(String avatarCode) async {
    await _client.put('/member/profile/avatar', data: {'avatarUrl': avatarCode});
  }

  Future<bool> getBgmEnabled() async {
    final data = await _client.get('/member/profile');
    if (data is! Map) return true;
    return data['bgmEnabled'] != false;
  }

  Future<void> updateBgm(bool enabled) async {
    await _client.put('/member/profile/bgm', data: {'enabled': enabled});
  }

  Future<List<Map<String, dynamic>>> getRedpacks({String status = 'AVAILABLE'}) async {
    final data = await _client.get('/member/redpacks', query: {'status': status});
    return _asMapList(data);
  }

  Future<Map<String, dynamic>> claimRedpack(String redpackId) async {
    final data = await _client.post('/member/redpacks/$redpackId/claim');
    return _asMap(data);
  }

  Future<List<Map<String, dynamic>>> getCsMessages({
    String? beforeId,
    int limit = 50,
  }) async {
    final data = await _client.get('/member/cs/messages', query: {
      if (beforeId != null) 'beforeId': beforeId,
      'limit': limit,
    });
    return _asMapList(data);
  }

  Future<Map<String, dynamic>> sendCsMessage(
    String content, {
    String msgType = 'TEXT',
    String? mediaId,
    String? refType,
    String? refId,
  }) async {
    final data = await _client.post('/member/cs/messages', data: {
      if (content.isNotEmpty) 'content': content,
      'msgType': msgType,
      if (mediaId != null && mediaId.isNotEmpty) 'mediaId': mediaId,
      if (refType != null && refType.isNotEmpty) 'refType': refType,
      if (refId != null && refId.isNotEmpty) 'refId': refId,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> uploadCsMedia(String path, {String? filename}) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: filename),
    });
    final data = await _client.post('/member/cs/media', data: form);
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getCsRef(String refType, String refId) async {
    final data = await _client.get('/member/cs/refs/$refType/$refId');
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getRoomIntro({required String gameType}) async {
    final data = await _client.get('/member/rooms/intro', query: {
      'gameType': gameType,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> getAgentInfo({
    String? startDate,
    String? endDate,
  }) async {
    final data = await _client.get('/member/agent-info', query: {
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> submitEnterApplication({
    required String roomCode,
    String? remark,
  }) async {
    final data = await _client.post('/member/rooms/enter-applications', data: {
      'roomCode': roomCode,
      if (remark != null && remark.isNotEmpty) 'remark': remark,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>?> getPendingEnterApplication(String roomCode) async {
    final data = await _client.get(
      '/member/rooms/enter-applications/pending',
      query: {'roomCode': roomCode},
    );
    if (data == null) return null;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<List<Map<String, dynamic>>> getNotices() async {
    final data = await _client.get('/member/notices');
    return _asMapList(data);
  }

  Future<Map<String, dynamic>> getRoomAnnouncement() async {
    final data = await _client.get('/member/rooms/announcement');
    return _asMap(data);
  }
}

Map<String, dynamic> _asMap(dynamic data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return {};
}

List<Map<String, dynamic>> _asMapList(dynamic data) {
  if (data is! List) return const [];
  return data
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

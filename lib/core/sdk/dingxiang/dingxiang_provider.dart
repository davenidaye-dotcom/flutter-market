import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dingxiang_service.dart';

final dingxiangServiceProvider = Provider<DingxiangService>((ref) {
  final service = DingxiangPlaceholderService();
  ref.onDispose(service.dispose);
  return service;
});

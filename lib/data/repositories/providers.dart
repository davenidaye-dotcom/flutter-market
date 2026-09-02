import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'agent_repository.dart';
import 'auth_repository.dart';
import 'lottery_repository.dart';
import 'member_repository.dart';
import 'owner_repository.dart';
import 'room_repository.dart';
import 'wallet_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  return RoomRepository();
});

final lotteryRepositoryProvider = Provider<LotteryRepository>((ref) {
  return LotteryRepository();
});

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  return WalletRepository();
});

final memberRepositoryProvider = Provider<MemberRepository>((ref) {
  return MemberRepository();
});

final agentRepositoryProvider = Provider<AgentRepository>((ref) {
  return AgentRepository();
});

final ownerRepositoryProvider = Provider<OwnerRepository>((ref) {
  return OwnerRepository();
});

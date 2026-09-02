import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../config/router/route_paths.dart';
import '../../../core/network/session_store.dart';
import '../../../config/theme/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/models/room_model.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/glossy_button.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/input_dialog.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../auth/providers/auth_session_provider.dart';
import '../../lottery/providers/lottery_live_provider.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  String _roomCode = '';
  bool _loading = false;
  List<RoomModel> _history = [];
  bool _historyLoading = false;

  @override
  void initState() {
    super.initState();
    _roomCode = SessionStore.instance.roomCode ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() => _historyLoading = true);
    try {
      final list = await ref.read(roomRepositoryProvider).getHistoryRooms();
      if (!mounted) return;
      setState(() {
        _history = list;
        _historyLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _history = [];
        _historyLoading = false;
      });
    }
  }

  String _errMsg(Object e) {
    if (e is ApiException) return e.message;
    final s = e.toString();
    if (s.startsWith('ApiException: ')) return s.substring(14);
    if (s.startsWith('Exception: ')) return s.substring(11);
    return s;
  }

  Future<String?> _askEnterPassword() async {
    final pwd = await showTextInputDialog(
      context: context,
      title: '进房密码',
      hint: '请输入进房密码',
      obscure: true,
    );
    if (pwd == null) return null;
    if (pwd.isEmpty) {
      AppToast.info('请输入进房密码');
      return null;
    }
    return pwd;
  }

  Future<void> _handleAuditRoom(String roomCode, String roomName) async {
    final memberRepo = ref.read(memberRepositoryProvider);
    try {
      final pending = await memberRepo.getPendingEnterApplication(roomCode);
      if (!mounted) return;
      if (pending != null && pending.isNotEmpty) {
        final status = (pending['status'] ?? 'PENDING').toString();
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('进房审核中'),
            content: Text(
              '房间「${roomName.isEmpty ? roomCode : roomName}」需审核进入。\n'
              '当前申请状态：$status\n请等待房主审核通过后再进入。',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
            ],
          ),
        );
        return;
      }
    } catch (_) {
      // 无待审或接口异常时继续尝试提交
    }

    final remarkCtrl = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('申请进入房间'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('房间「${roomName.isEmpty ? roomCode : roomName}」需要房主审核后才能进入。'),
            SizedBox(height: 12.h),
            EmulatorSafeTextField(
              controller: remarkCtrl,
              decoration: const InputDecoration(hintText: '申请说明（可选）'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('提交申请')),
        ],
      ),
    );
    final remark = remarkCtrl.text.trim();
    remarkCtrl.dispose();
    if (submit != true || !mounted) return;

    try {
      await memberRepo.submitEnterApplication(
        roomCode: roomCode,
        remark: remark.isEmpty ? null : remark,
      );
      if (!mounted) return;
      AppToast.success('进房申请已提交，请等待房主审核');
    } on ApiException catch (e) {
      // DIRECT 房误调申请时后端会拒绝 — 回退直接进房
      if (e.message.contains('无需进房申请')) {
        await _doEnter(roomCode);
        return;
      }
      AppToast.error(e.message);
    } catch (e) {
      AppToast.error(_errMsg(e));
    }
  }

  Future<void> _doEnter(String roomCode, {String? enterPassword}) async {
    final room = await ref.read(roomRepositoryProvider).enterRoom(
          roomCode,
          enterPassword: enterPassword,
        );
    ref.read(authSessionProvider.notifier).bindRoomCode(room.roomCode);
    final live = ref.read(roomLotteryLiveProvider(room.roomCode).notifier);
    await live.ensureLoaded();
    if (!mounted) return;
    context.push(RoutePaths.roomLottery(room.roomCode));
  }

  Future<void> _enterRoom([String? code]) async {
    final roomCode = (code ?? _roomCode).trim();
    if (roomCode.length < 6) {
      AppToast.info('请输入6位房间号');
      return;
    }
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final verified = await ref.read(roomRepositoryProvider).verifyRoom(roomCode);
      if (!mounted) return;

      if (verified.requiresEnterAudit) {
        await _handleAuditRoom(verified.roomCode, verified.name);
        return;
      }

      String? password;
      if (verified.hasEnterPassword) {
        password = await _askEnterPassword();
        if (password == null) return;
      }

      await _doEnter(verified.roomCode, enterPassword: password);
    } on ApiException catch (e) {
      // 校验未返回 enterMode 时，enter 可能直接报需审核
      if (e.message.contains('审核') || e.message.contains('申请')) {
        await _handleAuditRoom(roomCode, '');
        return;
      }
      if (e.message.contains('密码')) {
        final password = await _askEnterPassword();
        if (password == null) return;
        try {
          await _doEnter(roomCode, enterPassword: password);
        } catch (e2) {
          AppToast.error(_errMsg(e2));
        }
        return;
      }
      AppToast.error(e.message);
    } catch (e) {
      AppToast.error(_errMsg(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authSessionProvider.select((s) => s.user));
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadHistory,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 12.h),
                  const AppLogoHeader(),
                  SizedBox(height: 20.h),
                  _ProfileCard(
                    nickname: user?.nickname ?? '未登录',
                    username: user?.username ?? '',
                    loading: _loading,
                    initialRoomCode: _roomCode,
                    onSettings: () => context.push(RoutePaths.personalSettings),
                    onLogout: () async {
                      await ref.read(authSessionProvider.notifier).logout();
                      if (context.mounted) context.go(RoutePaths.login);
                    },
                    onRoomCodeChanged: (v) => _roomCode = v,
                    onEnterRoom: _enterRoom,
                  ),
                  SizedBox(height: 40.h),
                  Text(
                    '历史房间:',
                    style: TextStyle(
                      fontSize: 15.sp,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  if (_historyLoading)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.h),
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  else
                    _HistoryGrid(
                      rooms: _history,
                      onTap: (r) => _enterRoom(r.roomCode),
                    ),
                  SizedBox(height: 40.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatefulWidget {
  const _ProfileCard({
    required this.nickname,
    required this.username,
    required this.onSettings,
    required this.onLogout,
    required this.onRoomCodeChanged,
    required this.onEnterRoom,
    required this.loading,
    this.initialRoomCode = '',
  });

  final String nickname;
  final String username;
  final String initialRoomCode;
  final VoidCallback onSettings;
  final VoidCallback onLogout;
  final ValueChanged<String> onRoomCodeChanged;
  final Future<void> Function([String? code]) onEnterRoom;
  final bool loading;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  late final TextEditingController _roomCodeCtrl;

  @override
  void initState() {
    super.initState();
    _roomCodeCtrl = TextEditingController(text: widget.initialRoomCode);
    _roomCodeCtrl.addListener(() {
      widget.onRoomCodeChanged(_roomCodeCtrl.text);
    });
  }

  @override
  void dispose() {
    _roomCodeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(20.w, 20.w, 20.w, 40.h),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(22.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28.r,
                    backgroundColor: AppColors.primaryLight,
                    child: Icon(Icons.person, color: Colors.white, size: 32.sp),
                  ),
                  SizedBox(width: 12.w),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.nickname,
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        widget.username,
                        style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              Row(
                children: [
                  Expanded(
                    child: _ActionBtn(
                      label: '个人设置',
                      icon: Icons.hexagon_outlined,
                      color: AppColors.accentBrownDark,
                      onTap: widget.onSettings,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: _ActionBtn(
                      label: '安全退出',
                      icon: Icons.power_settings_new,
                      color: const Color(0xFF8FA9E0),
                      onTap: widget.onLogout,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              Text('房间号', style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary)),
              SizedBox(height: 12.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: EmulatorSafeTextField(
                  controller: _roomCodeCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 6,
                    color: AppColors.textPrimary,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '请输入6位房间号',
                    hintStyle: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.textHint,
                      letterSpacing: 0,
                      fontWeight: FontWeight.normal,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onSubmitted: (v) {
                    if (v.length == 6) widget.onEnterRoom(v);
                  },
                ),
              ),
              SizedBox(height: 8.h),
            ],
          ),
        ),
        Positioned(
          bottom: -18.h,
          left: 28.w,
          right: 28.w,
          child: GlossyButton(
            text: '进入房间',
            onPressed: widget.loading ? null : () => widget.onEnterRoom(),
            loading: widget.loading,
            height: 48.h,
          ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22.r),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16.sp),
            SizedBox(width: 4.w),
            Text(label, style: TextStyle(color: Colors.white, fontSize: 13.sp)),
          ],
        ),
      ),
    );
  }
}

class _HistoryGrid extends StatelessWidget {
  const _HistoryGrid({required this.rooms, required this.onTap});

  final List<RoomModel> rooms;
  final ValueChanged<RoomModel> onTap;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) {
      return Text('暂无历史房间', style: TextStyle(fontSize: 13.sp, color: AppColors.textHint));
    }
    return Wrap(
      spacing: 16.w,
      runSpacing: 12.h,
      children: rooms.map((r) {
        return GestureDetector(
          onTap: () => onTap(r),
          child: SizedBox(
            width: 80.w,
            child: Column(
              children: [
                Container(
                  width: 72.w,
                  height: 72.w,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8.r),
                    color: AppColors.primaryLight.withValues(alpha: 0.2),
                  ),
                  child: Icon(Icons.landscape, color: AppColors.primary, size: 32.sp),
                ),
                SizedBox(height: 4.h),
                Text(r.roomCode, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

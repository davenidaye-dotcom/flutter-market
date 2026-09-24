import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../profile/pages/change_password_page.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';
import 'fly_balance_page.dart';
import 'fly_bind_page.dart';
import 'fly_logs_page.dart';
import 'fly_odds_page.dart';
import 'fly_report_page.dart';

/// 飞单管理：账号、快捷操作、按彩种开关和赔率。
class FlyHubPage extends ConsumerStatefulWidget {
  const FlyHubPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<FlyHubPage> createState() => _FlyHubPageState();
}

class _FlyHubPageState extends ConsumerState<FlyHubPage> {
  Map<String, dynamic> _status = {};
  Map<String, dynamic> _credit = {};
  List<Map<String, dynamic>> _games = [];
  bool _loading = true;
  bool _busy = false;

  bool get _bound => _status['bound'] == true;

  bool get _flightOn => _status['flightEnabled'] == true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final status = await repo.getFeipanStatus();
      Map<String, dynamic> credit = {};
      if (status['bound'] == true) {
        try {
          credit = await repo.getFeipanCredit();
        } catch (e) {
          if (mounted) AppToast.error(e.toString());
        }
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _credit = credit;
        _games = _gamesOf(status['games']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  List<Map<String, dynamic>> _gamesOf(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }

  void _needBind() {
    AppToast.info('请先绑定代理会员');
  }

  Future<void> _setMaster(bool enabled) async {
    if (!_bound) {
      _needBind();
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(ownerRepositoryProvider).updateFeipanFlightSwitch(
            flightEnabled: enabled,
          );
      if (!mounted) return;
      setState(() => _status = {..._status, 'flightEnabled': enabled});
      AppToast.success(enabled ? '飞单已开启' : '飞单已关闭');
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setGame(String gameType, bool enabled) async {
    if (!_bound) {
      _needBind();
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(ownerRepositoryProvider).updateFeipanFlightSwitch(
            gameType: gameType,
            gameEnabled: enabled,
          );
      if (!mounted) return;
      setState(() {
        _games = [
          for (final g in _games)
            if ('${g['gameType']}' == gameType)
              {...g, 'enabled': enabled}
            else
              g,
        ];
      });
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unbind() async {
    final ok = await hostConfirm(
      context,
      title: '解除绑定',
      message: '确认解绑？解绑后房间下注将不再飞出。',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(ownerRepositoryProvider).unbindFeipan();
      AppToast.success('已解绑');
      await _load();
    } catch (e) {
      AppToast.error(e.toString());
    }
  }

  Future<void> _openBind() async {
    await pushHostPage(context, FlyBindPage(roomId: widget.roomId));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final name = '${_status['username'] ?? ''}'.trim();
    final balance = _bound
        ? hostNumStr(_credit['available'], fraction: 2)
        : '—';
    return HostSubPageScaffold(
      title: '飞单管理',
      body: _loading
          ? const AppPageLoading()
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                _accountCard(name.isEmpty ? '未绑定' : name, balance),
                SizedBox(height: 16.h),
                _sectionTitle('快捷操作'),
                SizedBox(height: 8.h),
                _actionGrid(),
                SizedBox(height: 16.h),
                _sectionTitle('游戏飞单配置'),
                SizedBox(height: 8.h),
                if (_games.isEmpty)
                  HostWhiteCard(
                    child: Text(
                      '暂无彩种',
                      style: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                    ),
                  )
                else
                  for (var i = 0; i < _games.length; i++) ...[
                    if (i > 0) SizedBox(height: 8.h),
                    _gameCard(_games[i]),
                  ],
              ],
            ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 15.sp,
        fontWeight: FontWeight.w600,
        color: AppColors.navBlue,
      ),
    );
  }

  Widget _accountCard(String name, String balance) {
    return HostWhiteCard(
      padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 12.h),
      child: Column(
        children: [
          Row(
            children: [
              _iconBubble(Icons.account_circle_outlined, const Color(0xFF5B8DEF)),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      _bound ? '已绑定代理会员' : '尚未绑定代理会员',
                      style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F6FB),
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: Text(
                  '余额 $balance',
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: _entryTile(
                  icon: Icons.receipt_long_outlined,
                  color: const Color(0xFF5B8DEF),
                  title: '额度变更',
                  page: FlyBalancePage(roomId: widget.roomId),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _entryTile(
                  icon: Icons.history,
                  color: const Color(0xFF7E8BA3),
                  title: '操作日志',
                  page: FlyLogsPage(roomId: widget.roomId),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _entryTile({
    required IconData icon,
    required Color color,
    required String title,
    required Widget page,
  }) {
    return Material(
      color: const Color(0xFFF7F9FC),
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: () => pushHostPage(context, page),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20.sp),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(title, style: TextStyle(fontSize: 14.sp)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionTile(
                icon: Icons.lock_outline,
                color: const Color(0xFF8B7CFF),
                label: '修改密码',
                onTap: () => pushHostPage(context, const ChangePasswordPage()),
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: _actionTile(
                icon: Icons.bar_chart,
                color: const Color(0xFFFF9F43),
                label: '飞单报表',
                onTap: () => pushHostPage(
                  context,
                  FlyReportPage(roomId: widget.roomId),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
        Row(
          children: [
            Expanded(
              child: _actionTile(
                icon: Icons.play_circle_outline,
                color: const Color(0xFF4C9AFF),
                label: '开启全部飞单',
                highlighted: _bound && _flightOn,
                onTap: () => _setMaster(true),
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: _actionTile(
                icon: Icons.pause_circle_outline,
                color: const Color(0xFFFF6B6B),
                label: '关闭全部飞单',
                highlighted: _bound && !_flightOn,
                onTap: () => _setMaster(false),
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
        _actionTile(
          icon: _bound ? Icons.link_off : Icons.link,
          color: _bound ? const Color(0xFFFF6B6B) : const Color(0xFF5B8DEF),
          label: _bound ? '解除绑定' : '绑定代理会员',
          onTap: _bound ? _unbind : _openBind,
        ),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
    bool highlighted = false,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: _busy ? null : onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
          child: Row(
            children: [
              _iconBubble(icon, color),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 18.sp, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gameCard(Map<String, dynamic> game) {
    final type = '${game['gameType'] ?? ''}';
    final name = '${game['gameName'] ?? type}';
    final on = game['enabled'] == true;
    return HostWhiteCard(
      padding: EdgeInsets.fromLTRB(12.w, 12.h, 8.w, 8.h),
      child: Column(
        children: [
          Row(
            children: [
              _iconBubble(Icons.casino_outlined, const Color(0xFF5B8DEF)),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
                    Text(
                      type,
                      style: TextStyle(fontSize: 11.sp, color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _bound && on,
                onChanged: !_bound || _busy ? null : (v) => _setGame(type, v),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                if (!_bound) {
                  _needBind();
                  return;
                }
                pushHostPage(
                  context,
                  FlyOddsPage(
                    roomId: widget.roomId,
                    gameType: type,
                    gameName: name,
                  ),
                );
              },
              icon: Icon(Icons.tune, size: 16.sp, color: AppColors.navBlue),
              label: Text('设置', style: TextStyle(fontSize: 13.sp, color: AppColors.navBlue)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBubble(IconData icon, Color color) {
    return Container(
      width: 32.w,
      height: 32.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Icon(icon, color: color, size: 18.sp),
    );
  }
}

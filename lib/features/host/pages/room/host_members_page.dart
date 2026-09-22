import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';
import 'host_member_detail_page.dart';
import 'host_robot_create_page.dart';
import 'host_robot_settings_page.dart';

/// 房间成员 — 统计卡片 + Tab + 搜索 + 卡片列表
/// Tab：全部 / 在线 / 机器人(气氛号) / 试玩号
class HostMembersPage extends ConsumerStatefulWidget {
  const HostMembersPage({
    super.key,
    required this.roomId,
    this.initialFilter = 0,
  });
  final String roomId;
  /// 0全部 1在线 2机器人 3试玩号
  final int initialFilter;

  @override
  ConsumerState<HostMembersPage> createState() => _HostMembersPageState();
}

class _HostMembersPageState extends ConsumerState<HostMembersPage> {
  static const _tabs = ['全部', '在线', '机器人', '试玩号'];

  late int _filter;
  final _search = TextEditingController();
  List<HostMember> _rows = [];
  bool _loading = true;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter.clamp(0, _tabs.length - 1);
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _memberType => switch (_filter) {
        1 => 'ONLINE',
        2 => 'ROBOT',
        3 => 'FAKE',
        _ => 'ALL',
      };

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final kw = _search.text.trim();
      // 顶部四块统计永远用「全部」summary；机器人 Tab 列表走 atmosphere
      final statsFuture = repo.getMembers(memberType: 'ALL', pageSize: 1);
      final listFuture = _filter == 2
          ? repo.getAtmosphereList(keyword: kw, pageSize: 100)
          : repo.getMembers(keyword: kw, memberType: _memberType, pageSize: 100);
      final results = await Future.wait([listFuture, statsFuture]);
      if (!mounted) return;
      final data = results[0];
      final statsData = results[1];
      final summary = statsData['summary'];
      setState(() {
        _rows = hostRowsOf(data).map(hostMemberFromMap).toList();
        _stats = summary is Map
            ? Map<String, dynamic>.from(summary)
            : (data['summary'] is Map
                ? Map<String, dynamic>.from(data['summary'] as Map)
                : <String, dynamic>{});
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Future<void> _createRobots() async {
    await pushHostPage(
      context,
      HostRobotCreatePage(roomId: widget.roomId),
    );
    if (!mounted) return;
    setState(() => _filter = 2);
    await _load();
  }

  bool _isTrialLike(HostMember m) =>
      m.isTrial ||
      m.roleLabel.contains('假人') ||
      m.roleLabel.contains('试玩');

  String _badge(HostMember m) {
    if (m.isMood) return m.disabled ? '已停用' : '启用中';
    if (_isTrialLike(m)) return '试玩号';
    if (m.isAgent) return '代理';
    if (m.disabled) {
      final label = m.statusLabel;
      if (label.contains('假人')) return '试玩号';
      return label;
    }
    return '会员';
  }

  Color _badgeFg(HostMember m) {
    if (m.isMood) {
      return m.disabled ? const Color(0xFF757575) : const Color(0xFF2E7D32);
    }
    if (_isTrialLike(m)) return const Color(0xFFC62828);
    if (m.disabled) return const Color(0xFF757575);
    return const Color(0xFF616161);
  }

  Color _badgeBg(HostMember m) {
    if (m.isMood) {
      return m.disabled ? const Color(0xFFEEEEEE) : const Color(0xFFE8F5E9);
    }
    if (_isTrialLike(m)) return const Color(0xFFFFEBEE);
    if (m.disabled) return const Color(0xFFEEEEEE);
    return const Color(0xFFF0F0F0);
  }

  @override
  Widget build(BuildContext context) {
    final blue = AppColors.navBlue;
    return HostSubPageScaffold(
      title: '房间成员',
      trailing: TextButton(
        onPressed: _createRobots,
        child: Text('新增', style: TextStyle(fontSize: 15.sp, color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
            child: _StatsGrid(stats: _stats),
          ),
          SizedBox(height: 12.h),
          // Tab：全部 / 在线 / 机器人 / 试玩号
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Container(
              height: 40.h,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (_filter == i) return;
                          setState(() => _filter = i);
                          _load();
                        },
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _filter == i ? blue : Colors.transparent,
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Text(
                            _tabs[i],
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w600,
                              color: _filter == i ? Colors.white : const Color(0xFF333333),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: 12.h),
          // 搜索
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40.h,
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    alignment: Alignment.center,
                    child: EmulatorSafeTextField(
                      controller: _search,
                      textAlign: TextAlign.left,
                      onSubmitted: (_) => _load(),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: '请输入玩家昵称或备注',
                        hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                GestureDetector(
                  onTap: _load,
                  child: Container(
                    width: 40.w,
                    height: 40.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: blue,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Icon(Icons.search, color: Colors.white, size: 22.sp),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          Expanded(
            child: _loading
                ? const AppPageLoading()
                : _rows.isEmpty
                    ? Center(
                        child: Text('暂无数据', style: TextStyle(fontSize: 14.sp, color: AppColors.textHint)),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                        itemCount: _rows.length + 1,
                        separatorBuilder: (_, i) =>
                            i == _rows.length - 1 ? const SizedBox.shrink() : SizedBox(height: 10.h),
                        itemBuilder: (_, i) {
                          if (i == _rows.length) {
                            return Padding(
                              padding: EdgeInsets.only(top: 12.h, bottom: 8.h),
                              child: Center(
                                child: Text(
                                  '没有更多了，共 ${_rows.length} 条',
                                  style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                                ),
                              ),
                            );
                          }
                          final m = _rows[i];
                          return _MemberCard(
                            member: m,
                            badge: _badge(m),
                            badgeFg: _badgeFg(m),
                            badgeBg: _badgeBg(m),
                            onTap: () async {
                              if (m.isMood) {
                                await pushHostPage(
                                  context,
                                  HostRobotSettingsPage(
                                    roomId: widget.roomId,
                                    accountId: m.id,
                                  ),
                                );
                              } else {
                                await pushHostPage(
                                  context,
                                  HostMemberDetailPage(
                                    roomId: widget.roomId,
                                    memberId: m.id,
                                  ),
                                );
                              }
                              if (mounted) await _load();
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.receipt_long_outlined, '总流水', hostNumStr(stats['totalTurnover'] ?? stats['turnover'], fraction: 2)),
      (Icons.balance_outlined, '总输赢', hostNumStr(stats['totalWinLoss'] ?? stats['winLoss'], fraction: 2)),
      (Icons.water_drop_outlined, '彩票回水', hostNumStr(stats['totalRebate'] ?? stats['rebate'], fraction: 2)),
      (Icons.paid_outlined, '真实玩家总积分', hostNumStr(stats['realPlayerPoints'] ?? stats['totalBalance'], fraction: 2)),
    ];
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _StatCard(icon: items[0].$1, label: items[0].$2, value: items[0].$3)),
            SizedBox(width: 10.w),
            Expanded(child: _StatCard(icon: items[1].$1, label: items[1].$2, value: items[1].$3)),
          ],
        ),
        SizedBox(height: 10.h),
        Row(
          children: [
            Expanded(child: _StatCard(icon: items[2].$1, label: items[2].$2, value: items[2].$3)),
            SizedBox(width: 10.w),
            Expanded(child: _StatCard(icon: items[3].$1, label: items[3].$2, value: items[3].$3)),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16.sp, color: const Color(0xFF9E9E9E)),
              SizedBox(width: 4.w),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.navBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.badge,
    required this.badgeFg,
    required this.badgeBg,
    required this.onTap,
  });

  final HostMember member;
  final String badge;
  final Color badgeFg;
  final Color badgeBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nick = member.nickname.isNotEmpty ? member.nickname : member.username;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
          child: Row(
            children: [
              UserAvatar(codeOrUrl: member.avatar, radius: 22.r),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nick,
                      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: const Color(0xFF222222)),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'ID: ${member.id}',
                      style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Text(badge, style: TextStyle(fontSize: 11.sp, color: badgeFg)),
                  ),
                  if (!member.isMood) ...[
                    SizedBox(height: 6.h),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 14.sp, color: AppColors.textSecondary),
                        SizedBox(width: 2.w),
                        Text(
                          '余额 ${hostNumStr(member.points, fraction: 2)}',
                          style: TextStyle(fontSize: 12.sp, color: const Color(0xFF333333)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              SizedBox(width: 4.w),
              Icon(Icons.chevron_right, color: const Color(0xFFBDBDBD), size: 22.sp),
            ],
          ),
        ),
      ),
    );
  }
}

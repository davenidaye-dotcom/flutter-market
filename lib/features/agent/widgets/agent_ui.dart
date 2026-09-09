import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../config/env/env_config.dart';
import '../../../config/router/route_paths.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../auth/providers/auth_session_provider.dart';

/// 顶栏余额：GET /agent/credits/account
/// 文档字段：header.displayId / header.balance / header.subordinateBalance
///           + available / totalCredit / occupied
final agentHeaderProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final account = await ref.read(agentRepositoryProvider).getCreditAccount();
  final header = account['header'] is Map
      ? Map<String, dynamic>.from(account['header'] as Map)
      : <String, dynamic>{};
  // 严格按 V1.3：顶栏读 header.*；额度读顶层 available/totalCredit/occupied
  final available = account['available'];
  return {
    'displayId': header['displayId']?.toString() ?? '',
    'balance': header['balance'] ?? 0,
    'subordinateBalance': header['subordinateBalance'] ?? 0,
    'totalCredit': account['totalCredit'],
    'occupied': account['occupied'],
    'available': available,
  };
});

/// Game tab options from lottery/info PROFILE
final agentGameOptionsProvider = FutureProvider<List<Map<String, String>>>((ref) async {
  final data = await ref.read(agentRepositoryProvider).getLotteryInfo(scene: 'PROFILE');
  final games = data['games'];
  if (games is! List) return const [];
  return [
    for (final g in games)
      if (g is Map)
        {
          'type': (g['type'] ?? '').toString(),
          'typeName': (g['typeName'] ?? g['type'] ?? '').toString(),
        },
  ].where((e) => e['type']!.isNotEmpty).toList();
});

/// Game names from lottery/info PROFILE
final agentGamesProvider = FutureProvider<List<String>>((ref) async {
  final options = await ref.watch(agentGameOptionsProvider.future);
  return options.map((e) => e['typeName'] ?? e['type'] ?? '').where((e) => e.isNotEmpty).toList();
});

/// 账户状态枚举 → 中文
String agentAccountStatusLabel(String? status) {
  switch (status?.toUpperCase()) {
    case 'NORMAL':
      return '正常';
    case 'LOCKED':
      return '锁定';
    case 'FROZEN':
      return '冻结';
    case 'DISABLED':
      return '禁用';
    default:
      return status?.isNotEmpty == true ? status! : '—';
  }
}

/// 账户类型 → 中文（优先后端 accountTypeName）
String agentAccountTypeLabel(Map<String, dynamic> row) {
  final name = row['accountTypeName']?.toString();
  if (name != null && name.isNotEmpty && !_looksLikeEnum(name)) return name;
  switch (row['accountType']?.toString()) {
    case 'AGENT_MEMBER':
      return '会员';
    case 'AGENT':
      final level = row['agentLevel'];
      if (level is num && level > 0) return '${level.toInt()}级代理';
      return '代理';
    case 'AGENT_DELEGATE':
      return '协管';
    default:
      return row['accountType']?.toString() ?? '—';
  }
}

bool _looksLikeEnum(String s) => s.contains('_') && s == s.toUpperCase();

String agentBalanceLabel(dynamic balance) {
  if (balance == null) return '0';
  if (balance is num) {
    if (balance == balance.roundToDouble()) return '${balance.toInt()}';
    return balance.toStringAsFixed(2);
  }
  return balance.toString();
}

/// 代理侧栏 — 竞品「代理菜单栏.png」
class AgentDrawer extends ConsumerWidget {
  const AgentDrawer({super.key, required this.roomId, required this.currentRoute});

  final String roomId;
  final String currentRoute;

  static const _items = [
    ('个人信息', 'info'),
    ('收付统计', 'payment'),
    ('账户管理', 'accounts'),
    ('报表查询', 'reports'),
    ('额度变动', 'quota'),
    ('密码修改', 'password'),
  ];

  String _pathFor(String key) => switch (key) {
        'info' => RoutePaths.agentPersonalInfo(roomId),
        'payment' => RoutePaths.agentPayment(roomId),
        'accounts' => RoutePaths.agentAccounts(roomId),
        'reports' => RoutePaths.agentReports(roomId),
        'quota' => RoutePaths.agentQuota(roomId),
        'password' => RoutePaths.agentPassword(roomId),
        _ => RoutePaths.agentPersonalInfo(roomId),
      };

  bool _active(String key) {
    if (key == 'info') {
      return currentRoute.contains('/info') || currentRoute.endsWith('/agent/$roomId');
    }
    return currentRoute.contains('/$key');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authSessionProvider.select((s) => s.user));
    final username = user?.username ?? '--';

    return Drawer(
      width: 0.42.sw,
      backgroundColor: const Color(0xFF7A9CD5),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 28.h),
            Center(
              child: Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Icon(Icons.people_outline, color: Colors.white, size: 24.sp),
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              '($username)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.sp, color: Colors.white),
            ),
            SizedBox(height: 32.h),
            for (final item in _items)
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  context.go(_pathFor(item.$2));
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 20.w),
                  child: Text(
                    item.$1,
                    style: TextStyle(
                      fontSize: 15.sp,
                      color: _active(item.$2) ? const Color(0xFFE8D44A) : Colors.white,
                      fontWeight: _active(item.$2) ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            const Spacer(),
            InkWell(
              onTap: () async {
                dismissAllShellCovers();
                await ref.read(authSessionProvider.notifier).logout();
                if (context.mounted) context.go(RoutePaths.login);
              },
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 20.w),
                child: Text('安全退出', style: TextStyle(fontSize: 15.sp, color: Colors.white)),
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'v${EnvConfig.appVersion}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.sp, color: Colors.white70),
            ),
            SizedBox(height: 20.h),
          ],
        ),
      ),
    );
  }
}

/// Agent top bar — hamburger / refresh / ID / balances from API
class AgentTopBar extends ConsumerWidget {
  const AgentTopBar({super.key, this.onRefresh});

  final VoidCallback? onRefresh;

  String _fmt(dynamic v) {
    if (v == null) return '--';
    if (v is num) {
      if (v == v.roundToDouble()) return '${v.toInt()}';
      return v.toStringAsFixed(2);
    }
    final s = '$v'.trim();
    return s.isEmpty ? '--' : s;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authSessionProvider.select((s) => s.user));
    final id = user?.id ?? '--';
    final headerAsync = ref.watch(agentHeaderProvider);
    final header = headerAsync.valueOrNull ?? {};
    final balance = _fmt(header['balance']);
    final sub = _fmt(header['subordinateBalance']);
    final headerDisplayId = header['displayId']?.toString().trim() ?? '';
    final shownId = headerDisplayId.isNotEmpty ? headerDisplayId : id;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      padding: EdgeInsets.fromLTRB(4.w, 6.h, 52.w, 8.h),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => IconButton(
              icon: Icon(Icons.menu, size: 22.sp, color: AppColors.textPrimary),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 22.sp, color: AppColors.navBlue),
            onPressed: () {
              ref.invalidate(agentHeaderProvider);
              ref.invalidate(agentGamesProvider);
              onRefresh?.call();
            },
          ),
          Expanded(
            child: Text(
              'ID: $shownId',
              style: TextStyle(fontSize: 14.sp, color: Colors.red, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(width: 12.w),
          if (headerAsync.isLoading)
            SizedBox(
              width: 16.w,
              height: 16.w,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _balanceLine('下级余额', sub),
                _balanceLine('余额', balance),
              ],
            ),
        ],
      ),
    );
  }

  static Widget _balanceLine(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 56.w,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12.sp, color: Colors.red, height: 1.25),
          ),
        ),
        Text(
          ': $value',
          style: TextStyle(fontSize: 12.sp, color: Colors.red, height: 1.25),
        ),
      ],
    );
  }
}

/// 代理页通用外框
class AgentPageFrame extends ConsumerWidget {
  const AgentPageFrame({
    super.key,
    required this.title,
    required this.child,
    this.onRefresh,
    this.titleOnBar = false,
  });

  final String title;
  final Widget child;
  final VoidCallback? onRefresh;

  /// 报表查询等：标题在浅灰条上
  final bool titleOnBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentTopBar(onRefresh: onRefresh),
          if (title.isNotEmpty)
            titleOnBar
                ? Container(
                    width: double.infinity,
                    color: const Color(0xFFF0F0F0),
                    padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 10.h),
                    child: Text(title, style: TextStyle(fontSize: 15.sp, color: AppColors.textSecondary)),
                  )
                : Padding(
                    padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 4.h),
                    child: Text(title, style: TextStyle(fontSize: 15.sp, color: AppColors.textSecondary)),
                  ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

enum AgentGameTabStyle { info, payment }

/// 游戏 Tab — 个人信息：青绿字+竖线；收付统计：绿字+下划线
class AgentGameTabs extends StatelessWidget {
  const AgentGameTabs({
    super.key,
    required this.games,
    required this.current,
    required this.onChanged,
    this.style = AgentGameTabStyle.info,
  });

  final List<String> games;
  final int current;
  final ValueChanged<int> onChanged;
  final AgentGameTabStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8.w),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFCCCCCC)),
        color: Colors.white,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < games.length; i++) ...[
              if (i > 0) Container(width: 1, height: 32.h, color: const Color(0xFFDDDDDD)),
              GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  decoration: style == AgentGameTabStyle.payment && current == i
                      ? const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFF4CAF50), width: 2)),
                        )
                      : null,
                  child: Text(
                    games[i],
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: current == i
                          ? (style == AgentGameTabStyle.payment
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFF5A9AA8))
                          : AppColors.textSecondary,
                      fontWeight: current == i ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 代理表格边框容器
class AgentBorderBox extends StatelessWidget {
  const AgentBorderBox({super.key, required this.child, this.padding, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? EdgeInsets.symmetric(horizontal: 8.w),
      padding: padding ?? EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFAAAAAA)),
        color: Colors.white,
      ),
      child: child,
    );
  }
}

/// 收付统计 — 带边框的数值格
class AgentStatCell extends StatelessWidget {
  const AgentStatCell({super.key, this.value = '0'});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
      height: 28.h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFCCCCCC)),
        color: Colors.white,
      ),
      child: Text(value, style: TextStyle(fontSize: 12.sp)),
    );
  }
}

/// 分页栏（可内嵌在边框容器内）
class AgentPaginationBar extends StatelessWidget {
  const AgentPaginationBar({
    super.key,
    required this.page,
    required this.totalPages,
    required this.total,
    required this.onPrev,
    required this.onNext,
    this.compact = false,
  });

  final int page;
  final int totalPages;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: compact ? EdgeInsets.only(top: 8.h) : EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 12.h),
      child: Row(
        children: [
          Text('页码 $page / $totalPages 共 $total 条', style: TextStyle(fontSize: 13.sp)),
          const Spacer(),
          _pageBtn('上一页', onPrev),
          SizedBox(width: 8.w),
          _pageBtn('下一页', onNext),
        ],
      ),
    );
  }

  Widget _pageBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: const Color(0xFF92C5F9),
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Text(label, style: TextStyle(fontSize: 13.sp, color: Colors.white)),
      ),
    );
  }
}

/// 青绿操作按钮
class AgentTealButton extends StatelessWidget {
  const AgentTealButton({super.key, required this.label, required this.onTap, this.outlined = false});

  final String label;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: outlined ? Colors.white : const Color(0xFF4E9BA3),
          border: Border.all(color: const Color(0xFF4E9BA3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            color: outlined ? const Color(0xFF666666) : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 报表快捷日期：选中蓝灰，未选中绿
class AgentReportQuickBtn extends StatelessWidget {
  const AgentReportQuickBtn({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF5D708C) : const Color(0xFF66A15B),
          borderRadius: BorderRadius.circular(2.r),
        ),
        child: Text(label, style: TextStyle(fontSize: 12.sp, color: Colors.white)),
      ),
    );
  }
}

/// 额度变动快捷日期
class AgentQuotaQuickBtn extends StatelessWidget {
  const AgentQuotaQuickBtn({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.blue = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool blue;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? (blue ? const Color(0xFF5B7B9D) : const Color(0xFF76AB5B))
        : (blue ? const Color(0xFF5B7B9D) : const Color(0xFF76AB5B));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2.r)),
        child: Text(label, style: TextStyle(fontSize: 12.sp, color: Colors.white)),
      ),
    );
  }
}

/// 游戏下拉 overlay
class AgentGamePickerOverlay extends StatelessWidget {
  const AgentGamePickerOverlay({
    super.key,
    required this.games,
    required this.selectedIndex,
    required this.onSelect,
    required this.onDismiss,
  });

  final List<String> games;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black26,
        alignment: Alignment.topCenter,
        padding: EdgeInsets.fromLTRB(24.w, 200.h, 24.w, 0),
        child: Material(
          elevation: 6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _item('全部游戏', 0),
              for (var i = 0; i < games.length; i++) _item(games[i], i + 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(String label, int index) {
    final active = selectedIndex == index;
    return InkWell(
      onTap: () => onSelect(index),
      child: Container(
        color: active ? const Color(0xFFE8EAF6) : Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: Text(label, style: TextStyle(fontSize: 14.sp)),
      ),
    );
  }
}

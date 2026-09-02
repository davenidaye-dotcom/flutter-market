import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/router/route_paths.dart';
import '../../features/auth/pages/captcha_page.dart';
import '../../features/auth/pages/login_page.dart';
import '../../features/auth/pages/register_page.dart';
import '../../features/auth/providers/auth_session_provider.dart';
import '../../features/home/pages/home_page.dart';
import '../../features/agent/pages/agent_account_manage_page.dart';
import '../../features/agent/pages/agent_change_password_page.dart';
import '../../features/agent/pages/agent_payment_stats_page.dart';
import '../../features/agent/pages/agent_personal_info_page.dart';
import '../../features/agent/pages/agent_quota_change_page.dart';
import '../../features/agent/pages/agent_report_query_page.dart';
import '../../features/agent/pages/agent_shell_page.dart';
import '../../features/host/pages/fly/fly_balance_page.dart';
import '../../features/host/pages/fly/fly_bind_page.dart';
import '../../features/host/pages/fly/fly_hub_page.dart';
import '../../features/host/pages/fly/fly_logs_page.dart';
import '../../features/host/pages/fly/fly_odds_page.dart';
import '../../features/host/pages/fly/fly_report_page.dart';
import '../../features/host/pages/host_audit_page.dart';
import '../../features/host/pages/host_manage_center_page.dart';
import '../../features/host/pages/host_room_manage_page.dart';
import '../../features/host/pages/host_service_page.dart';
import '../../features/host/pages/host_shell_page.dart';
import '../../features/host/pages/reports/rebate_report_page.dart';
import '../../features/host/pages/reports/room_report_page.dart';
import '../../features/host/pages/reports/score_flow_page.dart';
import '../../features/host/pages/room/host_advance_rebate_page.dart';
import '../../features/host/pages/room/host_agents_page.dart';
import '../../features/host/pages/room/host_announcements_page.dart';
import '../../features/host/pages/room/host_assistants_page.dart';
import '../../features/host/pages/room/host_atmosphere_page.dart';
import '../../features/host/pages/room/host_basic_settings_page.dart';
import '../../features/host/pages/room/host_batch_rebate_page.dart';
import '../../features/host/pages/room/host_default_rebate_page.dart';
import '../../features/host/pages/room/host_games_manage_page.dart';
import '../../features/host/pages/room/host_member_detail_page.dart';
import '../../features/host/pages/room/host_members_page.dart';
import '../../features/host/pages/room/host_odds_limits_page.dart';
import '../../features/host/pages/room/host_operation_logs_page.dart';
import '../../features/host/pages/room/host_room_settings_page.dart';
import '../../features/lottery/pages/chat_bet_page.dart';
import '../../features/lottery/pages/lottery_hall_page.dart';
import '../../features/lottery/pages/market_bet_page.dart';
import '../../features/profile/pages/change_password_page.dart';
import '../../features/profile/pages/personal_settings_page.dart';
import '../../features/profile/pages/profile_page.dart';
import '../../features/room/pages/customer_service_page.dart';
import '../../features/room/pages/room_intro_page.dart';
import '../../features/room/pages/room_shell_page.dart';
import '../../features/room/widgets/shell_branch_gate.dart';
import '../../features/wallet/pages/agent_info_page.dart';
import '../../features/wallet/pages/apply_records_page.dart';
import '../../features/wallet/pages/bet_records_page.dart';
import '../../features/wallet/pages/points_change_page.dart';
import '../../features/wallet/pages/wallet_page.dart';
import '../../features/wallet/pages/welfare_report_page.dart';

/// 根导航 Key：聊天/盘口等全屏页盖在 Shell 之上，Shell（含彩种列表）不销毁
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<AuthSession>(authSessionProvider, (prev, next) {
    // 仅登录态/角色变化时刷新路由，避免无关 session 更新导致 Shell 重建丢保活
    if (prev?.isLoggedIn != next.isLoggedIn || prev?.role != next.role) {
      refresh.value++;
    }
  });
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: RoutePaths.login,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(authSessionProvider);
      final loc = state.matchedLocation;
      final roomId = session.user?.roomId ?? '1001';

      if (session.isHostSide) {
        if (loc == RoutePaths.home) return RoutePaths.hostLottery(roomId);
        // 仅拦截玩家彩种大厅入口；聊天/报表等 /room 子页放行（房主只读进房）
        if (loc == RoutePaths.roomLottery(roomId)) return RoutePaths.hostLottery(roomId);
        if (loc.startsWith('/agent/')) return RoutePaths.hostLottery(roomId);
      }
      if (session.isAgentSide) {
        if (loc == RoutePaths.home) return RoutePaths.agentPersonalInfo(roomId);
        if (loc.startsWith('/host/') || loc.startsWith('/room/')) {
          return RoutePaths.agentPersonalInfo(roomId);
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: RoutePaths.login, builder: (_, _) => const LoginPage()),
      GoRoute(path: RoutePaths.register, builder: (_, _) => const RegisterPage()),
      GoRoute(path: RoutePaths.captcha, builder: (_, _) => const CaptchaPage()),
      GoRoute(path: RoutePaths.home, builder: (_, _) => const HomePage()),
      GoRoute(path: RoutePaths.personalSettings, builder: (_, _) => const PersonalSettingsPage()),
      GoRoute(path: RoutePaths.changePassword, builder: (_, _) => const ChangePasswordPage()),

      // StatefulShellBranch 默认路由不能带 path 参数，故把 :roomId 放在父级。
      // 注意：聊天/记录等全屏页必须挂在「同级顶层」，不能和 Shell 同挂在 /room/:roomId 下，
      // 否则匹配切到 chat 时 Shell 整棵被卸掉，返回就会闪。
      GoRoute(
        path: '/room/:roomId',
        redirect: (context, state) {
          final id = state.pathParameters['roomId']!;
          if (state.uri.path == '/room/$id') {
            return RoutePaths.roomLottery(id);
          }
          return null;
        },
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) {
              final roomId = state.pathParameters['roomId'] ?? '';
              return RoomShellPage(roomId: roomId, navigationShell: navigationShell);
            },
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'lottery',
                    builder: (_, state) => LotteryHallPage(roomId: state.pathParameters['roomId']!),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'service',
                    builder: (_, state) => ShellBranchGate(
                      branchIndex: 1,
                      child: CustomerServicePage(roomId: state.pathParameters['roomId']!),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'wallet',
                    builder: (_, state) => ShellBranchGate(
                      branchIndex: 2,
                      child: WalletPage(roomId: state.pathParameters['roomId']!),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'intro',
                    builder: (_, state) => ShellBranchGate(
                      branchIndex: 3,
                      child: RoomIntroPage(roomId: state.pathParameters['roomId']),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'profile',
                    builder: (_, state) => ShellBranchGate(
                      branchIndex: 4,
                      child: ProfilePage(roomId: state.pathParameters['roomId']),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // 全屏：push 到根 Navigator，底下 Shell（彩种列表）保持挂载
      GoRoute(
        path: '/room/:roomId/chat/:gameId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => ChatBetPage(
          roomId: state.pathParameters['roomId']!,
          gameId: state.pathParameters['gameId']!,
        ),
        routes: [
          GoRoute(
            path: 'market',
            builder: (_, state) => MarketBetPage(
              roomId: state.pathParameters['roomId']!,
              gameId: state.pathParameters['gameId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/room/:roomId/records/apply',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const ApplyRecordsPage(),
      ),
      GoRoute(
        path: '/room/:roomId/records/welfare',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const WelfareReportPage(),
      ),
      GoRoute(
        path: '/room/:roomId/records/bet',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const BetRecordsPage(),
      ),
      GoRoute(
        path: '/room/:roomId/records/points',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const PointsChangePage(),
      ),
      GoRoute(
        path: '/room/:roomId/records/agent',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const AgentInfoPage(),
      ),

      // —— 房主端壳（二级页同样挂顶层，避免卸掉 Shell） ——
      GoRoute(
        path: '/host/:roomId',
        redirect: (context, state) {
          final id = state.pathParameters['roomId']!;
          if (state.uri.path == '/host/$id') {
            return RoutePaths.hostLottery(id);
          }
          return null;
        },
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) {
              final roomId = state.pathParameters['roomId'] ?? '';
              return HostShellPage(roomId: roomId, navigationShell: navigationShell);
            },
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'lottery',
                    builder: (_, state) => LotteryHallPage(roomId: state.pathParameters['roomId']!),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'service',
                    builder: (_, state) => ShellBranchGate(
                      branchIndex: 1,
                      child: HostServicePage(roomId: state.pathParameters['roomId']!),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'manage',
                    builder: (_, state) => ShellBranchGate(
                      branchIndex: 2,
                      child: HostRoomManagePage(roomId: state.pathParameters['roomId']!),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'center',
                    builder: (_, state) => ShellBranchGate(
                      branchIndex: 3,
                      child: HostManageCenterPage(roomId: state.pathParameters['roomId']!),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'audit',
                    builder: (_, state) => ShellBranchGate(
                      branchIndex: 4,
                      child: HostAuditPage(roomId: state.pathParameters['roomId']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      GoRoute(
        path: '/host/:roomId/basic-settings',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => HostBasicSettingsPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/members',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => HostMembersPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/members/:memberId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => HostMemberDetailPage(
          roomId: state.pathParameters['roomId']!,
          memberId: state.pathParameters['memberId']!,
        ),
      ),
      GoRoute(
        path: '/host/:roomId/agents',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => HostAgentsPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/odds-limits',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => HostOddsLimitsPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/default-rebate',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => HostDefaultRebatePage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/batch-rebate',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => HostBatchRebatePage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/games',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => HostGamesManagePage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/announcements',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => HostAnnouncementsPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/atmosphere',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => HostAtmospherePage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/assistants',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => HostAssistantsPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/op-logs',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => HostOperationLogsPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/room-settings',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => HostRoomSettingsPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/advance-rebate',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => HostAdvanceRebatePage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/fly',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => FlyHubPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/fly/bind',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => FlyBindPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/fly/odds',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => FlyOddsPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/fly/report',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => FlyReportPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/fly/balance',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => FlyBalancePage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/fly/logs',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => FlyLogsPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/reports/room',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => RoomReportPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/reports/score',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => ScoreFlowPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/host/:roomId/reports/rebate',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => RebateReportPage(roomId: state.pathParameters['roomId']!),
      ),

      // —— 代理端壳 ——
      GoRoute(
        path: '/agent/:roomId',
        redirect: (context, state) {
          final id = state.pathParameters['roomId']!;
          if (state.uri.path == '/agent/$id') {
            return RoutePaths.agentPersonalInfo(id);
          }
          return null;
        },
        routes: [
          ShellRoute(
            builder: (context, state, child) {
              final roomId = state.pathParameters['roomId'] ?? '';
              return AgentShellPage(roomId: roomId, child: child);
            },
            routes: [
              GoRoute(
                path: 'info',
                builder: (_, state) => AgentPersonalInfoPage(roomId: state.pathParameters['roomId']!),
              ),
              GoRoute(
                path: 'payment',
                builder: (_, state) => AgentPaymentStatsPage(roomId: state.pathParameters['roomId']!),
              ),
              GoRoute(
                path: 'accounts',
                builder: (_, state) => AgentAccountManagePage(roomId: state.pathParameters['roomId']!),
              ),
              GoRoute(
                path: 'reports',
                builder: (_, state) => AgentReportQueryPage(roomId: state.pathParameters['roomId']!),
              ),
              GoRoute(
                path: 'quota',
                builder: (_, state) => AgentQuotaChangePage(roomId: state.pathParameters['roomId']!),
              ),
              GoRoute(
                path: 'password',
                builder: (_, state) => AgentChangePasswordPage(roomId: state.pathParameters['roomId']!),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../config/router/route_paths.dart';
import '../../../config/theme/app_colors.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../../auth/providers/auth_session_provider.dart';
import '../providers/lottery_live_provider.dart';
import '../widgets/announcement_marquee.dart';
import '../widgets/live_period_widgets.dart';
import 'chat_bet_page.dart';

/// 彩种列表 — Shell IndexedStack 保活 + 房间实时态共享
class LotteryHallPage extends ConsumerStatefulWidget {
  const LotteryHallPage({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<LotteryHallPage> createState() => _LotteryHallPageState();
}

class _LotteryHallPageState extends ConsumerState<LotteryHallPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// 关闭下注页不销毁，再进同彩种秒开。最多保活 2 个彩种，防内存涨。
  static const _maxKeptChats = 2;
  final Map<String, OverlayEntry> _chatOverlays = {};
  final List<String> _chatLru = [];
  String? _activeChatGameId;

  bool get _chatVisible => _activeChatGameId != null;

  void _hideChat() {
    if (_activeChatGameId == null) return;
    final id = _activeChatGameId!;
    _activeChatGameId = null;
    _chatOverlays[id]?.markNeedsBuild();
    ref
        .read(roomLotteryLiveProvider(widget.roomId).notifier)
        .resumeFromInteraction();
    if (mounted) setState(() {});
  }

  void _touchChatLru(String gameId) {
    _chatLru.remove(gameId);
    _chatLru.add(gameId);
  }

  void _evictChatLru() {
    while (_chatLru.length > _maxKeptChats) {
      final victim = _chatLru.first;
      if (victim == _activeChatGameId) {
        _chatLru.removeAt(0);
        _chatLru.add(victim);
        if (_chatLru.length <= _maxKeptChats) break;
        continue;
      }
      _chatLru.removeAt(0);
      _chatOverlays.remove(victim)?.remove();
    }
  }

  void _openChat(String gameId) {
    final prev = _activeChatGameId;
    if (prev != null && prev != gameId) {
      _chatOverlays[prev]?.markNeedsBuild();
    }

    ref.read(roomLotteryLiveProvider(widget.roomId).notifier).pauseForInteraction();
    _activeChatGameId = gameId;
    _touchChatLru(gameId);

    final existing = _chatOverlays[gameId];
    if (existing != null) {
      existing.markNeedsBuild();
      if (mounted) setState(() {});
      return;
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) {
        final visible = _activeChatGameId == gameId;
        return Offstage(
          offstage: !visible,
          child: TickerMode(
            enabled: visible,
            child: IgnorePointer(
              ignoring: !visible,
              child: Material(
                type: visible ? MaterialType.canvas : MaterialType.transparency,
                color: visible ? const Color(0xFFF5F5F5) : Colors.transparent,
                child: AppToastScope(
                  child: HeroControllerScope.none(
                    child: Navigator(
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (_) => ChatBetPage(
                          key: ValueKey('chat-$gameId'),
                          roomId: widget.roomId,
                          gameId: gameId,
                          onClose: _hideChat,
                          onSwitchGame: _openChat,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    _chatOverlays[gameId] = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _evictChatLru();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final e in _chatOverlays.values) {
      e.remove();
    }
    _chatOverlays.clear();
    _chatLru.clear();
    _activeChatGameId = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isHost = ref.watch(authSessionProvider.select((s) => s.isHostSide));
    final liveProvider = roomLotteryLiveProvider(widget.roomId);
    final ready = ref.watch(liveProvider.select((s) => s.ready));
    final loadError = ref.watch(liveProvider.select((s) => s.loadError));
    final announcement = ref.watch(liveProvider.select((s) => s.announcement));
    final gameIdsKey = ref.watch(
      liveProvider.select(
        (s) => s.games.map((g) => g.id).where((id) => id.isNotEmpty).join('|'),
      ),
    );
    final gameIds = gameIdsKey.isEmpty
        ? const <String>[]
        : gameIdsKey.split('|');

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8ECAFE), AppColors.bgGradientEnd],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: const Alignment(0, 0.15),
                  child: Text(
                    'LOTTERY',
                    style: TextStyle(
                      fontSize: 64.sp,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.12),
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                _HallHeader(
                  onBack: isHost
                      ? () async {
                          dismissAllShellCovers();
                          ref.invalidate(roomLotteryLiveProvider(widget.roomId));
                          await ref.read(authSessionProvider.notifier).logout();
                          if (context.mounted) context.go(RoutePaths.login);
                        }
                      : () {
                          dismissAllShellCovers();
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(RoutePaths.home);
                          }
                        },
                ),
                AnnouncementMarquee(
                  text: announcement,
                ),
                Expanded(
                  child: !ready
                      ? const Center(child: CircularProgressIndicator())
                      : loadError != null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    loadError,
                                    style: TextStyle(fontSize: 14.sp, color: Colors.white),
                                  ),
                                  SizedBox(height: 12.h),
                                  FilledButton(
                                    onPressed: () => ref
                                        .read(roomLotteryLiveProvider(widget.roomId).notifier)
                                        .retryLoad(),
                                    child: const Text('重试'),
                                  ),
                                ],
                              ),
                            )
                          : gameIds.isEmpty
                              ? Center(
                                  child: Text(
                                    '暂无彩种',
                                    style: TextStyle(fontSize: 14.sp, color: Colors.white),
                                  ),
                                )
                              : ListView.separated(
                          key: PageStorageKey<String>('lottery-hall-${widget.roomId}'),
                          padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 12.h),
                          itemCount: gameIds.length,
                          separatorBuilder: (_, _) => SizedBox(height: 10.h),
                          itemBuilder: (_, i) => _GameCard(
                            roomId: widget.roomId,
                            gameId: gameIds[i],
                            countdownActive: !_chatVisible,
                            onTap: () => _openChat(gameIds[i]),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HallHeader extends StatelessWidget {
  const _HallHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios, size: 18.sp, color: Colors.white),
            onPressed: onBack,
          ),
          const Expanded(child: Center(child: AppLogoHeader())),
          Text('已连接', style: TextStyle(fontSize: 12.sp, color: Colors.white)),
          SizedBox(width: 12.w),
        ],
      ),
    );
  }
}

class _GameCard extends ConsumerWidget {
  const _GameCard({
    required this.roomId,
    required this.gameId,
    required this.onTap,
    this.countdownActive = true,
  });

  final String roomId;
  final String gameId;
  final VoidCallback onTap;
  final bool countdownActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(
      roomLotteryLiveProvider(roomId).select((s) {
        final g = s.gameById(gameId);
        if (g == null) return null;
        return (
          g.name,
          g.currentIssue,
          g.previousIssue?.trim() ?? '',
        );
      }),
    );
    if (game == null) return const SizedBox.shrink();

    final (name, currentIssue, prevIssue) = game;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF002D62),
                    ),
                  ),
                ),
                Text(
                  currentIssue.isEmpty
                      ? (prevIssue.isNotEmpty ? '第$prevIssue期' : '等待开奖数据')
                      : '第$currentIssue期',
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Row(
              children: [
                LiveLatestDrawIssueText(
                  roomId: roomId,
                  gameId: gameId,
                  style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
                ),
                const Spacer(),
                LiveHallGameCountdown(
                  roomId: roomId,
                  gameId: gameId,
                  tickEnabled: countdownActive,
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Align(
              alignment: Alignment.centerLeft,
              child: LiveLatestDrawBalls(roomId: roomId, gameId: gameId),
            ),
          ],
        ),
      ),
    );
  }
}

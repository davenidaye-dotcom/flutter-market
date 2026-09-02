import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../lottery/providers/lottery_live_provider.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/gradient_background.dart';
import '../../../shared/widgets/page_app_bar.dart';
import 'room_shell_page.dart';

/// Room intro — GET /member/rooms/intro
class RoomIntroPage extends ConsumerStatefulWidget {
  const RoomIntroPage({super.key, this.roomId});

  final String? roomId;

  @override
  ConsumerState<RoomIntroPage> createState() => _RoomIntroPageState();
}

class _RoomIntroPageState extends ConsumerState<RoomIntroPage> {
  int _selectedGame = 0;
  bool _loading = true;
  List<Map<String, dynamic>> _games = [];
  String _rulesText = '';

  static const _bodyColor = Color(0xFF666666);
  static const _titleColor = Color(0xFF333333);

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load({String? gameType}) async {
    setState(() => _loading = true);
    try {
      final roomId = widget.roomId ?? '';
      List<Map<String, dynamic>> games = [];
      if (roomId.isNotEmpty) {
        final live = ref.read(roomLotteryLiveProvider(roomId).notifier);
        await live.ensureLoaded();
        games = ref.read(roomLotteryLiveProvider(roomId)).games
            .map(
              (g) => <String, dynamic>{
                'gameType': g.id,
                'gameName': g.name,
                'type': g.id,
                'typeName': g.name,
              },
            )
            .toList(growable: false);
      }

      final effectiveType = gameType ??
          (games.isNotEmpty
              ? (games[_selectedGame.clamp(0, games.length - 1)]['gameType']
                      ?.toString() ??
                  games.first['gameType']?.toString())
              : null);

      if (effectiveType == null || effectiveType.isEmpty) {
        if (!mounted) return;
        setState(() {
          _games = games;
          _rulesText = '暂无游戏';
          _loading = false;
        });
        return;
      }

      final data = await ref.read(memberRepositoryProvider).getRoomIntro(
            gameType: effectiveType,
          );
      if (!mounted) return;
      final rules = (data['content'] ??
              data['contentHtml'] ??
              data['rules'] ??
              data['ruleText'] ??
              data['intro'] ??
              '')
          .toString();
      var idx = _selectedGame;
      final current = data['gameType']?.toString() ?? effectiveType;
      if (games.isNotEmpty) {
        final found = games.indexWhere(
          (g) => (g['gameType'] ?? g['type'])?.toString() == current,
        );
        if (found >= 0) idx = found;
      }
      setState(() {
        _games = games;
        _rulesText = rules.isEmpty ? '暂无规则说明' : rules;
        _selectedGame = idx.clamp(0, games.isEmpty ? 0 : games.length - 1);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  String? get _currentType {
    if (_games.isEmpty) return null;
    final g = _games[_selectedGame.clamp(0, _games.length - 1)];
    return (g['gameType'] ?? g['type'])?.toString();
  }

  @override
  Widget build(BuildContext context) {
    final roomId = widget.roomId ?? '';
    return AppPageScaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageAppBar(
                title: '房间介绍',
                onBack: () {
                  if (roomId.isNotEmpty) {
                    goRoomLottery(context, roomId);
                  } else {
                    appSafePop(context);
                  }
                },
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_games.isNotEmpty) _buildGameSelector(),
                      if (_games.isNotEmpty) SizedBox(height: 12.h),
                      _buildRulesCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameSelector() {
    final current = _currentType;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: current,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textHint),
          style: TextStyle(fontSize: 15.sp, color: _titleColor, fontWeight: FontWeight.w600),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          items: _games.map((g) {
            final type = (g['gameType'] ?? g['type'])?.toString() ?? '';
            final name = (g['gameName'] ?? g['typeName'] ?? type).toString();
            return DropdownMenuItem<String>(
              value: type,
              child: Text(name, style: TextStyle(fontSize: 14.sp, color: _titleColor)),
            );
          }).toList(),
          onChanged: _loading
              ? null
              : (type) async {
                  if (type == null) return;
                  final idx = _games.indexWhere(
                    (g) => (g['gameType'] ?? g['type'])?.toString() == type,
                  );
                  setState(() {
                    if (idx >= 0) _selectedGame = idx;
                  });
                  await _load(gameType: type);
                },
        ),
      ),
    );
  }

  Widget _buildRulesCard() {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: 200.h),
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 20.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4.w,
                height: 16.h,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                '玩法规则',
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.bold,
                  color: _titleColor,
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          Divider(height: 1, color: Colors.grey.shade200),
          SizedBox(height: 14.h),
          if (_loading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 48.h),
              child: const Center(child: CircularProgressIndicator()),
            )
          else
            Text(
              _rulesText,
              style: TextStyle(
                fontSize: 14.sp,
                color: _bodyColor,
                height: 1.65,
              ),
            ),
        ],
      ),
    );
  }
}

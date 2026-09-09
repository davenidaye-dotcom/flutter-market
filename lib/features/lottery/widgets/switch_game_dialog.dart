import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/models/lottery_game_model.dart';
import '../../../shared/widgets/emulator_safe_dialog.dart';

/// 切换彩种弹窗 — 对应原型「切换项目详情」
///
/// 必须等退场动画跑完再返回：聊天页在 Overlay+Offstage 里，若弹窗未卸完就切彩种，
/// 旧页 TickerMode 关掉会导致弹窗消失「卡一下」。
Future<LotteryGameModel?> showSwitchGameDialog({
  required BuildContext context,
  required List<LotteryGameModel> games,
  required String currentGameId,
}) async {
  await dismissSoftKeyboard();
  if (!context.mounted) return null;

  final navigator = Navigator.of(context, rootNavigator: false);
  final route = DialogRoute<LotteryGameModel>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => SwitchGameDialog(
      games: games,
      currentGameId: currentGameId,
    ),
  );

  final result = await navigator.push<LotteryGameModel>(route);
  await route.completed;
  if (context.mounted) {
    await dismissSoftKeyboard();
  }
  return result;
}

class SwitchGameDialog extends StatelessWidget {
  const SwitchGameDialog({
    super.key,
    required this.games,
    required this.currentGameId,
  });

  final List<LotteryGameModel> games;
  final String currentGameId;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.6;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 36.w),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        padding: EdgeInsets.fromLTRB(14.w, 16.h, 14.w, 16.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14.r),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: games.length,
          separatorBuilder: (_, _) => SizedBox(height: 10.h),
          itemBuilder: (context, i) => _GameItem(
            game: games[i],
            selected: games[i].id == currentGameId,
            onTap: () => Navigator.of(context).pop(games[i]),
          ),
        ),
      ),
    );
  }
}

class _GameItem extends StatelessWidget {
  const _GameItem({
    required this.game,
    required this.selected,
    required this.onTap,
  });

  final LotteryGameModel game;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFEAF4FF) : Colors.white,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10.r),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(
              color: selected ? const Color(0xFFB7D9F8) : const Color(0xFFE5E5E5),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(
                  Icons.sports_esports_outlined,
                  color: AppColors.textSecondary,
                  size: 22.sp,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.name,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      selected ? '当前游戏' : '点击切换',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: selected ? AppColors.navBlue : AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Container(
                  width: 22.w,
                  height: 22.w,
                  decoration: const BoxDecoration(
                    color: AppColors.navBlue,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check, color: Colors.white, size: 14.sp),
                )
              else
                Icon(Icons.chevron_right, color: AppColors.textHint, size: 22.sp),
            ],
          ),
        ),
      ),
    );
  }
}

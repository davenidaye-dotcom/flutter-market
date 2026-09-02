import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../shared/widgets/lottery_ball.dart';

/// 快捷下注面板 — 对应原型快捷/两面/1-10名/冠亚和
class QuickBetPanel extends StatefulWidget {
  const QuickBetPanel({super.key, required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  State<QuickBetPanel> createState() => _QuickBetPanelState();
}

class _QuickBetPanelState extends State<QuickBetPanel> {
  int _tabIndex = 0;
  static const _tabs = ['快捷', '两面', '1-10名', '冠亚和'];
  static const _ranks = ['冠军', '亚军', '三名', '四名', '五名', '六名', '七名', '八名', '九名', '十名'];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280.h,
      color: AppColors.sidebarInactive,
      child: Row(
        children: [
          _Sidebar(tabs: _tabs, current: _tabIndex, onTap: (i) => setState(() => _tabIndex = i)),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return switch (_tabIndex) {
      0 => _QuickGrid(ranks: _ranks, onSelect: widget.onSelect),
      1 => _TwoSidesGrid(onSelect: widget.onSelect),
      2 => _NumberGrid(onSelect: widget.onSelect),
      _ => _SumGrid(onSelect: widget.onSelect),
    };
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.tabs, required this.current, required this.onTap});

  final List<String> tabs;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72.w,
      child: Column(
        children: List.generate(tabs.length, (i) {
          final active = i == current;
          return GestureDetector(
            onTap: () => onTap(i),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 14.h),
              color: active ? AppColors.sidebarActive : AppColors.sidebarInactive,
              alignment: Alignment.center,
              child: Text(
                tabs[i],
                style: TextStyle(
                  fontSize: 13.sp,
                  color: active ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.ranks, required this.onSelect});

  final List<String> ranks;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.all(8.w),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 6.h,
        crossAxisSpacing: 6.w,
        childAspectRatio: 2.5,
      ),
      itemCount: ranks.length,
      itemBuilder: (_, i) => _selectBtn(ranks[i], () => onSelect('${ranks[i]}/大/100')),
    );
  }

  Widget _selectBtn(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: Text(text, style: TextStyle(fontSize: 13.sp)),
      ),
    );
  }
}

class _TwoSidesGrid extends StatelessWidget {
  const _TwoSidesGrid({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    const items = ['大', '小', '单', '双', '龙', '虎'];
    return GridView.builder(
      padding: EdgeInsets.all(8.w),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 6.h, crossAxisSpacing: 6.w),
      itemCount: items.length,
      itemBuilder: (_, i) => GestureDetector(
        onTap: () => onSelect('冠军/${items[i]}/100'),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6.r)),
          child: Text(items[i], style: TextStyle(fontSize: 14.sp)),
        ),
      ),
    );
  }
}

class _NumberGrid extends StatelessWidget {
  const _NumberGrid({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.all(8.w),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 6.h, crossAxisSpacing: 6.w),
      itemCount: 10,
      itemBuilder: (_, i) {
        final n = i + 1;
        return GestureDetector(
          onTap: () => onSelect('冠军/$n/100'),
          child: Container(
            padding: EdgeInsets.all(6.w),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6.r)),
            child: Row(
              children: [
                LotteryBall(number: n, size: 24.w),
                SizedBox(width: 8.w),
                Text('9.995', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SumGrid extends StatelessWidget {
  const _SumGrid({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    const items = ['大', '小', '单', '双'];
    return GridView.builder(
      padding: EdgeInsets.all(8.w),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 6.h, crossAxisSpacing: 6.w),
      itemCount: items.length,
      itemBuilder: (_, i) => GestureDetector(
        onTap: () => onSelect('冠亚和/${items[i]}/100'),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6.r)),
          child: Text('冠亚和 ${items[i]}', style: TextStyle(fontSize: 13.sp)),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 输入框右侧宫格弹出的功能菜单（可左右翻页）
class BetActionMenuPanel extends StatefulWidget {
  const BetActionMenuPanel({super.key, this.onItemTap});

  final ValueChanged<String>? onItemTap;

  /// 与网格布局一致，供聊天页预留列表底部空白
  static double panelHeight(BuildContext context) {
    final iconSize = 52.w;
    final itemExtent = iconSize + 6.h + 18.h;
    final rowGap = 10.h;
    final gridHeight = itemExtent * 2 + rowGap;
    return 10.h + gridHeight + 10.h + 10.h + 7.w;
  }

  @override
  State<BetActionMenuPanel> createState() => _BetActionMenuPanelState();
}

class _BetActionMenuPanelState extends State<BetActionMenuPanel> {
  final _pageCtrl = PageController();
  final _pageNotifier = ValueNotifier(0);

  /// 第 1 页：上分 / 下分 / 申请记录 / 竞猜报表 / 福利报表 / 自助回水
  /// 第 2 页：积分账变
  static const _pages = [
    [
      _MenuItem('上分', Icons.keyboard_arrow_up_rounded),
      _MenuItem('下分', Icons.keyboard_arrow_down_rounded),
      _MenuItem('申请记录', Icons.confirmation_number_outlined),
      _MenuItem('竞猜报表', Icons.show_chart),
      _MenuItem('福利报表', Icons.card_giftcard_outlined),
      _MenuItem('自助回水', Icons.desktop_windows_outlined),
    ],
    [
      _MenuItem('积分账变', Icons.swap_horiz_rounded),
    ],
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    _pageNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = 52.w;
    final itemExtent = iconSize + 6.h + 18.h; // 图标 + 间距 + 文字
    final rowGap = 10.h;
    final gridHeight = itemExtent * 2 + rowGap;

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 10.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            SizedBox(
              height: gridHeight,
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _pages.length,
                onPageChanged: (i) => _pageNotifier.value = i,
                itemBuilder: (_, page) {
                  final pageItems = _pages[page];
                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: pageItems.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: rowGap,
                      crossAxisSpacing: 12.w,
                      mainAxisExtent: itemExtent,
                    ),
                    itemBuilder: (_, i) {
                      final item = pageItems[i];
                      return GestureDetector(
                        onTap: () => widget.onItemTap?.call(item.label),
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: iconSize,
                              height: iconSize,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F4FF),
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: Icon(
                                item.icon,
                                color: const Color(0xFF5BA8E8),
                                size: 28.sp,
                              ),
                            ),
                            SizedBox(height: 6.h),
                            Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.sp,
                                height: 1.1,
                                color: const Color(0xFF333333),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            SizedBox(height: 10.h),
            ValueListenableBuilder<int>(
              valueListenable: _pageNotifier,
              builder: (_, page, __) {
                return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++) ...[
                  if (i > 0) SizedBox(width: 8.w),
                  Container(
                    width: 7.w,
                    height: 7.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: page == i ? const Color(0xFF999999) : const Color(0xFFDDDDDD),
                    ),
                  ),
                ],
              ],
            );
              },
            ),
          ],
        ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

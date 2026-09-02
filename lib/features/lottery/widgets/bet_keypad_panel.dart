import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';

/// 自定义下注键盘 — 固定行高，按键防抖，减轻模拟器连点卡顿
class BetKeypadPanel extends StatefulWidget {
  const BetKeypadPanel({
    super.key,
    required this.onInsert,
    required this.onBackspace,
    required this.onClearAll,
    required this.onAction,
    this.enabled = true,
  });

  final ValueChanged<String> onInsert;
  final VoidCallback onBackspace;
  final VoidCallback onClearAll;
  final ValueChanged<String> onAction;
  final bool enabled;

  static const _grid = [
    ['大', '1', '2', '3', '⌫'],
    ['小', '4', '5', '6', '龙'],
    ['单', '7', '8', '9', '虎'],
    ['双', '空格', '0', '/', '冠亚和'],
  ];

  static const double actionRowHeight = 44;
  static const double keyRowHeight = 46;

  static double get panelHeight => actionRowHeight + keyRowHeight * 4 + 1;

  @override
  State<BetKeypadPanel> createState() => _BetKeypadPanelState();
}

class _BetKeypadPanelState extends State<BetKeypadPanel> {
  DateTime? _lastKeyAt;

  bool _acceptTap() {
    if (!widget.enabled) return false;
    final now = DateTime.now();
    final last = _lastKeyAt;
    if (last != null && now.difference(last).inMilliseconds < 60) {
      return false;
    }
    _lastKeyAt = now;
    return true;
  }

  void _onKey(String key) {
    if (!_acceptTap()) return;
    if (key == '⌫') {
      widget.onBackspace();
      return;
    }
    if (key == '空格') {
      widget.onInsert(' ');
      return;
    }
    widget.onInsert(key);
  }

  void _onAction(String action) {
    if (!_acceptTap()) return;
    widget.onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ColoredBox(
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: BetKeypadPanel.actionRowHeight,
              child: _ActionRow(onAction: _onAction, enabled: widget.enabled),
            ),
            const Divider(height: 1, thickness: 0.5, color: AppColors.divider),
            for (final row in BetKeypadPanel._grid)
              SizedBox(
                height: BetKeypadPanel.keyRowHeight,
                child: Row(
                  children: [
                    for (final key in row)
                      Expanded(
                        child: _KeyCell(
                          label: key,
                          enabled: widget.enabled,
                          onTap: () => _onKey(key),
                          onLongPress: key == '⌫' ? widget.onClearAll : null,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.onAction, required this.enabled});

  final ValueChanged<String> onAction;
  final bool enabled;
  static const _actions = ['上分', '取消', '梭哈', '重复', '下分'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _actions.length; i++) ...[
          if (i > 0) Container(width: 0.5, height: 16, color: AppColors.divider),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? () => onAction(_actions[i]) : null,
              child: Center(
                child: Text(
                  _actions[i],
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: enabled ? const Color(0xFF666666) : AppColors.textHint,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _KeyCell extends StatelessWidget {
  const _KeyCell({
    required this.label,
    required this.onTap,
    required this.enabled,
    this.onLongPress,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  Color? get _bg {
    return switch (label) {
      '龙' => const Color(0xFFE53935),
      '虎' => const Color(0xFF1E88E5),
      '冠亚和' => const Color(0xFF43A047),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final bg = _bg;
    final isColorKey = bg != null;
    final textColor = enabled ? const Color(0xFF666666) : AppColors.textHint;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      child: Center(
        child: isColorKey
            ? Opacity(
                opacity: enabled ? 1 : 0.45,
                child: Container(
                  width: double.infinity,
                  height: 38,
                  margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: label.length > 2 ? 13.sp : 17.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            : label == '⌫'
                ? Icon(Icons.backspace_outlined, size: 22.sp, color: textColor)
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: label == '空格' ? 15.sp : 20.sp,
                      color: textColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
      ),
    );
  }
}

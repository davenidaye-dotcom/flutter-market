import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';

/// 自定义下注键盘 — 固定行高，按键防抖，按下蓝色反馈
class BetKeypadPanel extends StatefulWidget {
  const BetKeypadPanel({
    super.key,
    required this.onInsert,
    required this.onBackspace,
    required this.onClearAll,
    required this.onAction,
    this.enabled = true,
    this.disabledActions = const {},
    this.currentText = '',
  });

  final ValueChanged<String> onInsert;
  final VoidCallback onBackspace;
  final VoidCallback onClearAll;
  final ValueChanged<String> onAction;
  final bool enabled;
  /// 试玩号禁用：上分 / 下分
  final Set<String> disabledActions;
  /// 当前输入，用于玩法键互斥与禁连点
  final String currentText;

  /// 大/小/单/双/龙/虎/冠亚和 整框互斥（只能出现其中一个）
  static const playMutexTokens = [
    '冠亚和', // 先匹配长词
    '大',
    '小',
    '单',
    '双',
    '龙',
    '虎',
  ];

  /// 大/小/单/双/龙/虎/冠亚和、/ 禁止连续插入
  static const noRepeatTokens = {
    '大',
    '小',
    '单',
    '双',
    '龙',
    '虎',
    '冠亚和',
    '/',
  };

  static const _grid = [
    ['大', '1', '2', '3', '⌫'],
    ['小', '4', '5', '6', '龙'],
    ['单', '7', '8', '9', '虎'],
    ['双', '/', '0', '/', '冠亚和'],
  ];

  static const double actionRowHeight = 44;
  static const double keyRowHeight = 46;

  static double get panelHeight => actionRowHeight + keyRowHeight * 4 + 1;

  /// 输入中已出现的玩法词；无则 null
  static String? activePlayToken(String text) {
    for (final t in playMutexTokens) {
      if (text.contains(t)) return t;
    }
    return null;
  }

  /// 再插入 [token] 是否被玩法互斥挡住
  static bool isPlayMutexBlocked(String current, String token) {
    if (!playMutexTokens.contains(token)) return false;
    final active = activePlayToken(current);
    return active != null && active != token;
  }

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
    if (BetKeypadPanel.isPlayMutexBlocked(widget.currentText, key)) {
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
    final activePlay = BetKeypadPanel.activePlayToken(widget.currentText);
    return RepaintBoundary(
      child: ColoredBox(
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: BetKeypadPanel.actionRowHeight,
              child: _ActionRow(
                onAction: _onAction,
                enabled: widget.enabled,
                disabledActions: widget.disabledActions,
              ),
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
                          enabled: widget.enabled &&
                              !_isPlayKeyDisabled(key, activePlay),
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

  bool _isPlayKeyDisabled(String key, String? activePlay) {
    if (activePlay == null) return false;
    if (!BetKeypadPanel.playMutexTokens.contains(key)) return false;
    return key != activePlay;
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.onAction,
    required this.enabled,
    this.disabledActions = const {},
  });

  final ValueChanged<String> onAction;
  final bool enabled;
  final Set<String> disabledActions;
  static const _actions = ['上分', '取消', '梭哈', '重复', '下分'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _actions.length; i++) ...[
          if (i > 0) Container(width: 0.5, height: 16, color: AppColors.divider),
          Expanded(
            child: Builder(
              builder: (_) {
                final action = _actions[i];
                final actionEnabled =
                    enabled && !disabledActions.contains(action);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: actionEnabled ? () => onAction(action) : null,
                  child: Center(
                    child: Text(
                      action,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: actionEnabled
                            ? const Color(0xFF666666)
                            : AppColors.textHint,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _KeyCell extends StatefulWidget {
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

  @override
  State<_KeyCell> createState() => _KeyCellState();
}

class _KeyCellState extends State<_KeyCell> {
  bool _pressed = false;

  Color? get _fixedBg {
    return switch (widget.label) {
      '龙' => const Color(0xFFE53935),
      '虎' => const Color(0xFF1E88E5),
      '冠亚和' => const Color(0xFF43A047),
      _ => null,
    };
  }

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final fixedBg = _fixedBg;
    final isColorKey = fixedBg != null;
    final pressBlue = _pressed && widget.enabled && !isColorKey;
    final textColor = !widget.enabled
        ? AppColors.textHint
        : pressBlue
            ? Colors.white
            : const Color(0xFF666666);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
      onPointerUp: widget.enabled ? (_) => _setPressed(false) : null,
      onPointerCancel: widget.enabled ? (_) => _setPressed(false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        child: Center(
          child: isColorKey
              ? Opacity(
                  opacity: widget.enabled ? (_pressed ? 0.78 : 1) : 0.45,
                  child: Container(
                    width: double.infinity,
                    height: 38,
                    margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: fixedBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: widget.label.length > 2 ? 13.sp : 17.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              : Container(
                  width: double.infinity,
                  height: 38,
                  margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: pressBlue ? AppColors.navBlue : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: widget.label == '⌫'
                      ? Icon(
                          Icons.backspace_outlined,
                          size: 22.sp,
                          color: pressBlue ? Colors.white : textColor,
                        )
                      : Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 20.sp,
                            color: textColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
        ),
      ),
    );
  }
}

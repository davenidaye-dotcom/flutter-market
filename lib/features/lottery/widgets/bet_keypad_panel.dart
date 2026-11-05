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
    this.walletEnabled = true,
    this.disabledActions = const {},
    this.currentText = '',
    this.canada = false,
  });

  final ValueChanged<String> onInsert;
  final VoidCallback onBackspace;
  final VoidCallback onClearAll;
  final ValueChanged<String> onAction;
  final bool enabled;
  /// 封盘时投注键置灰，上分 / 下分仍可点。
  final bool walletEnabled;
  /// 试玩号禁用：上分 / 下分
  final Set<String> disabledActions;
  /// 当前输入，用于玩法键互斥与禁连点
  final String currentText;
  /// 加拿大 PC28 专用键盘。赛车彩种保持 false。
  final bool canada;

  /// 大/小/单/双/龙/虎/冠亚和 整框互斥（只能出现其中一个）。
  /// 冠亚和的选项段里，大小单双可以混选、也可以连点。
  static const playMutexTokens = [
    '冠亚和', // 先匹配长词
    '大',
    '小',
    '单',
    '双',
    '龙',
    '虎',
  ];

  static const gyhSides = {'大', '小', '单', '双'};

  /// 正在写冠亚和选项：`冠亚和`、`冠亚和/`、`冠亚和/大大小`。金额斜杠之后不再算。
  static bool inGyhSideField(String text) {
    return RegExp(r'(?:^|\s)冠亚和(/[大小单双]*)?$').hasMatch(text);
  }

  /// 大/小/单/双/龙/虎/冠亚和、/ 禁止连续插入。冠亚和选项段里的大小单双除外。
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

  static double heightFor({bool canada = false}) =>
      actionRowHeight + keyRowHeight * (canada ? 4 : 4) + 1;

  static const pc28Grid = [
    ['大', '1', '2', '3', '⌫'],
    ['小', '4', '5', '6', '红波'],
    ['单', '7', '8', '9', '蓝波'],
    ['双', '/', '0', '/', '绿波'],
  ];

  /// 长词在前，避免「大」吃掉「大单」。
  static const pc28Mutex = [
    '大单',
    '大双',
    '小单',
    '小双',
    '极大',
    '极小',
    '红波',
    '蓝波',
    '绿波',
    '豹子',
    '大',
    '小',
    '单',
    '双',
    '龙',
    '虎',
    '和',
  ];

  static String? activePc28Token(String text) {
    for (final t in pc28Mutex) {
      if (text.contains(t)) return t;
    }
    return null;
  }

  static bool isPc28MutexBlocked(String current, String token) {
    if (!pc28Mutex.contains(token)) return false;
    final active = activePc28Token(current);
    return active != null && active != token;
  }

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
    if (gyhSides.contains(token) && inGyhSideField(current)) return false;
    final active = activePlayToken(current);
    return active != null && active != token;
  }

  @override
  State<BetKeypadPanel> createState() => _BetKeypadPanelState();
}

class _BetKeypadPanelState extends State<BetKeypadPanel> {
  DateTime? _lastKeyAt;

  bool _acceptTap({bool ignoreEnabled = false}) {
    if (!ignoreEnabled && !widget.enabled) return false;
    final now = DateTime.now();
    final last = _lastKeyAt;
    if (last != null && now.difference(last).inMilliseconds < 60) {
      return false;
    }
    _lastKeyAt = now;
    return true;
  }

  bool _isWalletAction(String action) => action == '上分' || action == '下分';

  void _onKey(String key) {
    if (!_acceptTap()) return;
    if (key == '⌫') {
      widget.onBackspace();
      return;
    }
    if (widget.canada) {
      if (BetKeypadPanel.isPc28MutexBlocked(widget.currentText, key)) {
        return;
      }
      widget.onInsert(key);
      return;
    }
    if (BetKeypadPanel.isPlayMutexBlocked(widget.currentText, key)) {
      return;
    }
    widget.onInsert(key);
  }

  void _onAction(String action) {
    if (_isWalletAction(action)) {
      if (!widget.walletEnabled || widget.disabledActions.contains(action)) {
        return;
      }
      if (!_acceptTap(ignoreEnabled: true)) return;
    } else if (!_acceptTap()) {
      return;
    }
    widget.onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final activePlay = widget.canada
        ? BetKeypadPanel.activePc28Token(widget.currentText)
        : BetKeypadPanel.activePlayToken(widget.currentText);
    final grid = widget.canada ? BetKeypadPanel.pc28Grid : BetKeypadPanel._grid;
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
                walletEnabled: widget.walletEnabled,
                disabledActions: widget.disabledActions,
              ),
            ),
            const Divider(height: 1, thickness: 0.5, color: AppColors.divider),
            for (final row in grid)
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
    if (widget.canada) {
      if (activePlay == null) return false;
      if (!BetKeypadPanel.pc28Mutex.contains(key)) return false;
      return key != activePlay;
    }
    if (BetKeypadPanel.gyhSides.contains(key) &&
        BetKeypadPanel.inGyhSideField(widget.currentText)) {
      return false;
    }
    if (activePlay == null) return false;
    if (!BetKeypadPanel.playMutexTokens.contains(key)) return false;
    return key != activePlay;
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.onAction,
    required this.enabled,
    required this.walletEnabled,
    this.disabledActions = const {},
  });

  final ValueChanged<String> onAction;
  final bool enabled;
  final bool walletEnabled;
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
                final wallet = action == '上分' || action == '下分';
                // 封盘只锁投注。上分 / 下分跟钱包开关走，不跟 enabled。
                final actionEnabled = !disabledActions.contains(action) &&
                    (wallet ? walletEnabled : enabled);
                final color = !actionEnabled
                    ? AppColors.textHint
                    : (wallet && !enabled)
                        ? AppColors.textPrimary
                        : const Color(0xFF666666);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: actionEnabled ? () => onAction(action) : null,
                  child: Center(
                    child: Text(
                      action,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: wallet && actionEnabled && !enabled
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: color,
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
      '红波' => const Color(0xFFE53935),
      '蓝波' => const Color(0xFF1E88E5),
      '绿波' => const Color(0xFF43A047),
      '豹子' => const Color(0xFF6D4C41),
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

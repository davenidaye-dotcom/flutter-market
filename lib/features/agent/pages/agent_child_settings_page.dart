import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/agent_ui.dart';
import 'agent_account_child_page.dart';

/// 下级账号设置：昵称 / 状态 / 重置密码
class AgentChildSettingsPage extends ConsumerStatefulWidget {
  const AgentChildSettingsPage({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  ConsumerState<AgentChildSettingsPage> createState() => _AgentChildSettingsPageState();
}

class _AgentChildSettingsPageState extends ConsumerState<AgentChildSettingsPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _confirmCtrl;
  late String _status;
  bool _saving = false;

  static const _statusOptions = [
    ('NORMAL', '正常'),
    ('LOCKED', '锁定'),
    ('FROZEN', '冻结'),
    ('DISABLED', '禁用'),
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: '${widget.row['displayName'] ?? ''}');
    _passCtrl = TextEditingController();
    _confirmCtrl = TextEditingController();
    final raw = '${widget.row['status'] ?? 'NORMAL'}'.toUpperCase();
    _status = _statusOptions.any((e) => e.$1 == raw) ? raw : 'NORMAL';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = agentRowAccountId(widget.row);
    if (id == null) {
      AppToast.error('账号无效');
      return;
    }
    final pwd = _passCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    if (pwd.isNotEmpty || confirm.isNotEmpty) {
      if (pwd.length < 6) {
        AppToast.error('密码至少 6 位');
        return;
      }
      if (pwd != confirm) {
        AppToast.error('两次密码不一致');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await ref.read(agentRepositoryProvider).updateChildAccount(
            accountId: id,
            displayName: _nameCtrl.text.trim(),
            status: _status,
            password: pwd.isEmpty ? null : pwd,
            confirmPassword: pwd.isEmpty ? null : confirm,
          );
      if (!mounted) return;
      AppToast.success('已保存');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = agentRowName(widget.row);
    final username = '${widget.row['username'] ?? ''}';
    return AgentPageFrame(
      title: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentBackTitle(title: '编辑 · $name'),
          Expanded(
            child: ListView(
        padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 24.h),
        children: [
          AgentSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                SizedBox(height: 4.h),
                Text(
                  '$username · ${agentAccountTypeLabel(widget.row)}',
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          AgentSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('昵称', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                SizedBox(height: 6.h),
                _nicknameField(),
                SizedBox(height: 14.h),
                Text('状态', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                SizedBox(height: 6.h),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    for (final opt in _statusOptions)
                      ChoiceChip(
                        label: Text(opt.$2),
                        selected: _status == opt.$1,
                        onSelected: (_) => setState(() => _status = opt.$1),
                      ),
                  ],
                ),
                SizedBox(height: 14.h),
                Text('重置密码（留空不改）', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                SizedBox(height: 6.h),
                _passwordField(_passCtrl),
                SizedBox(height: 8.h),
                _passwordField(_confirmCtrl, hint: '确认密码'),
                SizedBox(height: 16.h),
                AgentTealButton(
                  label: _saving ? '保存中…' : '保存',
                  onTap: () {
                    if (!_saving) _save();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
          ),
        ],
      ),
    );
  }

  /// 昵称：系统键盘 + 联想，支持中文输入（不走 EmulatorSafe 默认关联想）。
  Widget _nicknameField() {
    return Container(
      height: 40.h,
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        color: AgentChrome.fieldBg,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AgentChrome.cardBorder),
      ),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: _nameCtrl,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.next,
        enableSuggestions: true,
        autocorrect: true,
        style: TextStyle(fontSize: 14.sp, color: AgentChrome.ink),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: '可输入中文',
          hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _passwordField(TextEditingController ctrl, {String? hint}) {
    return Container(
      height: 40.h,
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        color: AgentChrome.fieldBg,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AgentChrome.cardBorder),
      ),
      alignment: Alignment.centerLeft,
      child: EmulatorSafeTextField(
        controller: ctrl,
        obscureText: true,
        style: TextStyle(fontSize: 14.sp, color: AgentChrome.ink),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

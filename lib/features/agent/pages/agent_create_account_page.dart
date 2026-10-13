import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../data/repositories/providers.dart';
import '../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../shared/widgets/page_app_bar.dart';
import '../widgets/agent_ui.dart';

/// 新增账户 — 整页表单（方案 A：Chip 选类型，无确认密码）
class AgentCreateAccountPage extends ConsumerStatefulWidget {
  const AgentCreateAccountPage({
    super.key,
    required this.roomId,
    this.parentAgentId,
  });

  final String roomId;
  final int? parentAgentId;

  @override
  ConsumerState<AgentCreateAccountPage> createState() =>
      _AgentCreateAccountPageState();
}

class _AgentCreateAccountPageState extends ConsumerState<AgentCreateAccountPage> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _type = 'AGENT_MEMBER';
  bool _loading = false;

  static const _types = <String, String>{
    'AGENT_MEMBER': '会员',
    'AGENT': '代理',
    'AGENT_DELEGATE': '子账号',
  };

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;
    final displayName = _nameCtrl.text.trim();
    if (username.isEmpty || password.isEmpty) {
      AppToast.error('请填写用户名和密码');
      return;
    }
    if (password.length < 6 || password.length > 64) {
      AppToast.info('密码需为6-64位');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(agentRepositoryProvider).createAccount(
            username: username,
            password: password,
            confirmPassword: password,
            type: _type,
            displayName: displayName.isEmpty ? null : displayName,
            parentAgentId: widget.parentAgentId,
          );
      if (!mounted) return;
      AppToast.success('创建成功');
      Navigator.of(context).pop(true);
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AgentPageFrame(
      title: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AgentBackTitle(title: '新增账户'),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(0, 4.h, 0, 24.h),
              child: Column(
                children: [
                  AgentSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _field('用户名', '请输入用户名', _userCtrl),
                        SizedBox(height: 10.h),
                        _field('密码', '请输入密码', _passCtrl, obscure: true),
                        SizedBox(height: 10.h),
                        _field(
                          '显示名称',
                          '可选，默认同用户名',
                          _nameCtrl,
                          enableSuggestions: true,
                        ),
                        SizedBox(height: 14.h),
                        Text(
                          '账户类型',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: [
                            for (final e in _types.entries)
                              _TypeChip(
                                label: e.value,
                                selected: _type == e.key,
                                onTap: () => setState(() => _type = e.key),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    child: GestureDetector(
                      onTap: _loading ? null : _submit,
                      child: Container(
                        width: double.infinity,
                        height: 44.h,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AgentChrome.accent,
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: _loading
                            ? SizedBox(
                                width: 22.w,
                                height: 22.w,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                '创建',
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    String hint,
    TextEditingController ctrl, {
    bool obscure = false,
    bool enableSuggestions = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: AgentChrome.fieldBg,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AgentChrome.cardBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72.w,
            child: Text(
              label,
              style: TextStyle(fontSize: 14.sp, color: AgentChrome.ink),
            ),
          ),
          Expanded(
            child: EmulatorSafeTextField(
              controller: ctrl,
              obscureText: obscure,
              enableSuggestions: enableSuggestions,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: selected ? AgentChrome.accent : AgentChrome.fieldBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AgentChrome.accent : AgentChrome.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

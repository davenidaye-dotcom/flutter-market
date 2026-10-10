import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../widgets/agent_ui.dart';
import 'agent_child_credit_page.dart';
import 'agent_child_odds_page.dart';
import 'agent_child_share_page.dart';

int? agentRowAccountId(Map<String, dynamic> row) {
  final v = row['accountId'];
  if (v is int) return v;
  return int.tryParse('$v');
}

String agentRowType(Map<String, dynamic> row) => '${row['accountType'] ?? ''}'.toUpperCase();

bool agentRowIsAgent(Map<String, dynamic> row) => agentRowType(row) == 'AGENT';

bool agentRowIsMember(Map<String, dynamic> row) => agentRowType(row).contains('MEMBER');

bool agentRowIsDelegate(Map<String, dynamic> row) => agentRowType(row) == 'AGENT_DELEGATE';

String agentRowName(Map<String, dynamic> row) =>
    '${row['displayName'] ?? row['username'] ?? row['accountId'] ?? ''}';

/// 赔率页信息卡：【几级代理】username (昵称)
String agentOddsSubjectTitle(Map<String, dynamic> row) {
  final type = agentAccountTypeLabel(row);
  final user = '${row['username'] ?? ''}'.trim();
  final nick = '${row['displayName'] ?? ''}'.trim();
  final showNick = nick.isNotEmpty && nick != user;
  final core = user.isEmpty
      ? (nick.isEmpty ? agentRowName(row) : nick)
      : (showNick ? '$user ($nick)' : user);
  return '【$type】$core';
}

/// 下级详情：占成 / 赔率与限额 / 额度
class AgentAccountChildPage extends StatelessWidget {
  const AgentAccountChildPage({
    super.key,
    required this.row,
  });

  final Map<String, dynamic> row;

  Future<void> _open(BuildContext context, Widget page) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => page),
    );
    if (changed == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = agentRowAccountId(row);
    final name = agentRowName(row);
    final typeLabel = agentAccountTypeLabel(row);
    final status = agentAccountStatusLabel(row['status']?.toString());
    final username = '${row['username'] ?? ''}';
    final showShare = !agentRowIsDelegate(row);
    final showOdds = !agentRowIsDelegate(row);
    final titleType = agentRowIsMember(row)
        ? '代理会员'
        : agentRowIsDelegate(row)
            ? '子账号'
            : typeLabel;

    return AgentPageFrame(
      title: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentBackTitle(title: '$titleType · $name'),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(bottom: 16.h),
              children: [
                AgentSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '$username · $typeLabel · $status',
                        style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                      ),
                      SizedBox(height: 12.h),
                      Row(
                        children: [
                          Text('可用额度', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                          const Spacer(),
                          Text(
                            agentBalanceLabel(row['balance'] ?? row['available']),
                            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: AgentChrome.ink),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10.h),
                AgentSurface(
                  padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
                  child: Column(
                    children: [
                      if (showShare)
                        _nav(
                          context,
                          label: '占成',
                          hint: '占成 / 上限',
                          onTap: id == null
                              ? null
                              : () => _open(
                                    context,
                                    AgentChildSharePage(accountId: id, title: name),
                                  ),
                        ),
                      if (showOdds)
                        _nav(
                          context,
                          label: '赔率与限额',
                          hint: '对齐赔率设置',
                          onTap: id == null
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AgentChildOddsPage(
                                        accountId: id,
                                        title: agentOddsSubjectTitle(row),
                                      ),
                                    ),
                                  ),
                        ),
                      _nav(
                        context,
                        label: '额度',
                        hint: '上分 / 下分',
                        last: true,
                        onTap: id == null
                            ? null
                            : () => _open(
                                  context,
                                  AgentChildCreditPage(
                                    accountId: id,
                                    title: name,
                                    available: row['balance'] ?? row['available'],
                                  ),
                                ),
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

  Widget _nav(
    BuildContext context, {
    required String label,
    required String hint,
    required VoidCallback? onTap,
    bool last = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: AgentChrome.cardBorder)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AgentChrome.ink)),
                  SizedBox(height: 2.h),
                  Text(hint, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20.sp, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

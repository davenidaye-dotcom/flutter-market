import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../../wallet/widgets/compact_draw_snapshot_row.dart';
import '../../../wallet/widgets/date_range_filter.dart';
import '../../../wallet/utils/draw_snapshot_utils.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// 玩家信息报表深链。路径不变，只加 accountId。每页 20 条，不扫全房。
class HostMemberReportPage extends ConsumerStatefulWidget {
  const HostMemberReportPage({
    super.key,
    required this.roomId,
    required this.accountId,
    required this.kind,
  });

  final String roomId;
  final String accountId;
  /// credits | updown | bets | welfare | redpacks
  final String kind;

  @override
  ConsumerState<HostMemberReportPage> createState() => _HostMemberReportPageState();
}

class _HostMemberReportPageState extends ConsumerState<HostMemberReportPage>
    with DateRangePageMixin {
  List<Map<String, dynamic>> _rows = [];
  String _summary = '';
  bool _loading = false;

  String get _title => switch (widget.kind) {
        'updown' => '上下分记录',
        'bets' => '竞猜记录',
        'welfare' => '福利报表',
        'redpacks' => '红包报表',
        _ => '积分账变',
      };

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void onQuery() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(ownerRepositoryProvider);
      final start = DateRangeFilter.format(this.start);
      final end = DateRangeFilter.format(this.end);
      final id = widget.accountId;
      late final Map<String, dynamic> data;
      switch (widget.kind) {
        case 'updown':
          data = await repo.getCreditRecords(
            startDate: start,
            endDate: end,
            accountId: id,
            direction: 'ALL',
          );
        case 'bets':
          data = await repo.getManageBets(
            startDate: start,
            endDate: end,
            accountId: id,
          );
        case 'welfare':
          data = await repo.getWelfare(
            type: 'SUMMARY',
            startDate: start,
            endDate: end,
            accountId: id,
          );
        case 'redpacks':
          data = await repo.listRedpacks(accountId: id);
        default:
          data = await repo.getCreditRecords(
            startDate: start,
            endDate: end,
            accountId: id,
          );
      }
      if (!mounted) return;
      final rows = widget.kind == 'welfare'
          ? hostRowsOf({'rows': data['detail']})
          : hostRowsOf(data);
      final summary = data['summary'];
      setState(() {
        _rows = rows;
        _summary = summary is Map ? _summaryText(Map<String, dynamic>.from(summary)) : '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  String _summaryText(Map<String, dynamic> s) {
    if (s.isEmpty) return '';
    const order = [
      'totalUp',
      'totalDown',
      'totalBet',
      'totalTurnover',
      'totalBonus',
      'totalWinLoss',
      'totalRebate',
      'totalOrders',
      'totalBalance',
    ];
    final parts = <String>[];
    final used = <String>{};
    for (final key in order) {
      if (s[key] == null) continue;
      used.add(key);
      parts.add('${ledgerChangeLabel(key)} ${hostNumStr(s[key], fraction: 2)}');
    }
    for (final e in s.entries) {
      if (used.contains(e.key) || e.key == 'rows') continue;
      parts.add('${ledgerChangeLabel(e.key)} ${hostNumStr(e.value, fraction: 2)}');
    }
    return parts.join('  ');
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: _title,
      body: Column(
        children: [
          SizedBox(height: 8.h),
          if (widget.kind != 'redpacks')
            DateRangeFilter(
              quickIndex: quickIndex,
              start: start,
              end: end,
              quickItems: quickItems,
              onQuickTap: onQuickTap,
              onPickStart: () => pickDate(isStart: true),
              onPickEnd: () => pickDate(isStart: false),
              onQuery: onQuery,
            ),
          if (_summary.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
              child: Text(
                _summary,
                style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
              ),
            ),
          SizedBox(height: 12.h),
          Expanded(
            child: _loading
                ? const AppPageLoading()
                : _rows.isEmpty
                    ? Center(
                        child: Text(
                          '暂无数据',
                          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => SizedBox(height: 10.h),
                        itemBuilder: (_, i) => _RecordCard(row: _rows[i]),
                      ),
          ),
        ],
      ),
    );
  }
}

class _Tone {
  const _Tone(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.row});

  final Map<String, dynamic> row;

  String _text(String key) {
    final v = row[key];
    if (v == null) return '';
    final s = '$v'.trim();
    return s == 'null' ? '' : s;
  }

  String _first(List<String> keys) {
    for (final key in keys) {
      final s = _text(key);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String get _typeLabel {
    final change = _text('changeType');
    if (change.isNotEmpty) return ledgerChangeLabel(change);
    if (_text('orderId').isNotEmpty) return betStatusLabel(_text('status'));
    final type = _text('type');
    if (type.isEmpty) return '记录';
    return switch (type.toUpperCase()) {
      'LUCKY' => '拼手气红包',
      'SCHEDULED' => '定时红包',
      _ => ledgerChangeLabel(type),
    };
  }

  _Tone get _tone {
    final key = _first(['changeType', 'type', 'status']).toUpperCase();
    return switch (key) {
      'BET' || 'DOWN' || 'OWNER_CREDIT_DOWN' || 'LOSE' =>
        const _Tone(Color(0xFFFFF3E0), Color(0xFFEF6C00)),
      'WIN' || 'UP' || 'OWNER_CREDIT_UP' || 'REBATE' || 'COMMISSION' =>
        const _Tone(Color(0xFFE8F5E9), Color(0xFF2E7D32)),
      'REDPACK' || 'LUCKY' || 'SCHEDULED' =>
        const _Tone(Color(0xFFFCE4EC), Color(0xFFC2185B)),
      'BET_CANCEL' || 'CANCEL' || 'VOID' || 'CANCELLED' =>
        const _Tone(Color(0xFFF5F5F5), Color(0xFF757575)),
      _ => const _Tone(Color(0xFFE3F2FD), Color(0xFF1565C0)),
    };
  }

  String get _who {
    final nick = _text('nickname');
    if (nick.isNotEmpty) return nick;
    final user = _text('username');
    if (user.isNotEmpty) return user;
    final id = _text('accountId');
    return id.isEmpty ? '未知成员' : id;
  }

  String get _accountLine {
    final user = _text('username');
    final id = _text('accountId');
    final parts = <String>[];
    if (user.isNotEmpty && user != _who) parts.add('账号 $user');
    if (id.isNotEmpty) parts.add('ID $id');
    return parts.join(' · ');
  }

  dynamic get _headlineAmount {
    if (_text('changeType').isNotEmpty || _text('claimId').isNotEmpty) {
      return row['amount'];
    }
    return row['winLoss'] ?? row['amount'] ?? row['totalAmount'];
  }

  String _fmtTime(String raw) {
    if (raw.isEmpty) return '';
    var s = raw.replaceFirst('T', ' ');
    final dot = s.indexOf('.');
    if (dot > 0) s = s.substring(0, dot);
    return s;
  }

  List<(String, String)> get _fields {
    final out = <(String, String)>[];
    void add(String label, String value) {
      if (value.isEmpty) return;
      out.add((label, value));
    }

    final balance = _text('balanceAfter');
    if (balance.isNotEmpty) add('变动后', hostNumStr(row['balanceAfter'], fraction: 2));
    final issue = _text('issueNo');
    if (issue.isNotEmpty) add('期号', issue);
    add('彩种', _text('gameType'));
    if (_text('changeType').isEmpty && row['totalAmount'] != null) {
      add('下注', hostNumStr(row['totalAmount'], fraction: 2));
    }
    if (_text('changeType').isEmpty && row['winAmount'] != null) {
      add('派彩', hostNumStr(row['winAmount'], fraction: 2));
    }
    final orderId = _first(['orderId', 'refId', 'redpackId', 'claimId']);
    if (orderId.isNotEmpty) add(_text('redpackId').isNotEmpty ? '红包' : '单号', orderId);
    final items = row['items'];
    if (items is List && items.isNotEmpty) {
      final names = items
          .whereType<Map>()
          .map((e) => '${e['playName'] ?? e['playCode'] ?? ''}'.trim())
          .where((s) => s.isNotEmpty)
          .take(3)
          .join('、');
      add('玩法', names);
    }
    if (_text('changeType').isNotEmpty && _text('status').isNotEmpty) {
      add('状态', betStatusLabel(_text('status')));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final signed = HostSignedPnl.of(_headlineAmount);
    final ranks = parseDrawRanks(pickDrawRanks(row));
    final remark = _text('remark');
    final time = _fmtTime(_first(['createdAt', 'settledAt', 'claimedAt']));
    final fields = _fields;

    return HostWhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: _tone.bg,
                  borderRadius: BorderRadius.circular(6.r),
                ),
                child: Text(
                  _typeLabel,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: _tone.fg,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  _who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                signed.text,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: signed.color,
                ),
              ),
            ],
          ),
          if (_accountLine.isNotEmpty) ...[
            SizedBox(height: 4.h),
            Text(
              _accountLine,
              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
            ),
          ],
          if (ranks.isNotEmpty) ...[
            SizedBox(height: 8.h),
            CompactDrawSnapshotRow(
              ranks: ranks,
              sumGy: pickSumGy(row),
              ballSize: 16.w,
            ),
          ],
          if (fields.isNotEmpty) ...[
            SizedBox(height: 10.h),
            Wrap(
              spacing: 12.w,
              runSpacing: 6.h,
              children: [
                for (final f in fields)
                  SizedBox(
                    width: 148.w,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${f.$1} ',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          TextSpan(
                            text: f.$2,
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF222222),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (remark.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              '备注 $remark',
              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
            ),
          ],
          if (time.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                time,
                style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

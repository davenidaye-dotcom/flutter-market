import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../config/theme/app_colors.dart';
import '../../../shared/format/display_number.dart';
import 'compact_draw_snapshot_row.dart';

class _Tone {
  const _Tone(this.bg, this.fg);
  final Color bg;
  final Color fg;
}

_Tone _toneFor(String? key) {
  final k = (key ?? '').toUpperCase();
  return switch (k) {
    'BET' ||
    'DOWN' ||
    'OWNER_CREDIT_DOWN' ||
    'LOSE' ||
    'REJECTED' =>
      const _Tone(Color(0xFFFFF3E0), Color(0xFFEF6C00)),
    'WIN' ||
    'UP' ||
    'OWNER_CREDIT_UP' ||
    'REBATE' ||
    'COMMISSION' ||
    'AGENT_REBATE' ||
    'APPROVED' =>
      const _Tone(Color(0xFFE8F5E9), Color(0xFF2E7D32)),
    'REDPACK' || 'LUCKY' || 'SCHEDULED' || 'ENTER' =>
      const _Tone(Color(0xFFFCE4EC), Color(0xFFC2185B)),
    'BET_CANCEL' ||
    'CANCEL' ||
    'VOID' ||
    'CANCELLED' ||
    'PENDING' =>
      const _Tone(Color(0xFFF5F5F5), Color(0xFF757575)),
    _ => const _Tone(Color(0xFFE3F2FD), Color(0xFF1565C0)),
  };
}

/// 会员侧账变/申请/福利明细卡片（对齐房主报表 `_RecordCard` 风格）。
class MemberLedgerCard extends StatelessWidget {
  const MemberLedgerCard({
    super.key,
    required this.typeLabel,
    required this.amount,
    this.title,
    this.subtitle,
    this.fields = const [],
    this.remark,
    this.time,
    this.toneKey,
    this.ranks = const [],
    this.sumGy,
    this.onShareToCs,
  });

  final String typeLabel;
  final dynamic amount;
  final String? title;
  final String? subtitle;
  final List<(String, String)> fields;
  final String? remark;
  final String? time;
  /// changeType / status / applyType 等，用于角标配色
  final String? toneKey;
  final List<int> ranks;
  final int? sumGy;
  final VoidCallback? onShareToCs;

  static const _green = Color(0xFF2E9E5B);
  static const _red = Color(0xFFE53935);

  (String, Color) get _signedAmount {
    final n = amount is num
        ? (amount as num).toDouble()
        : double.tryParse('$amount'.replaceAll(',', '')) ?? 0;
    final shown = displayNumber(amount);
    if (n > 0) {
      final t = shown.startsWith('+') ? shown : '+$shown';
      return (t, _green);
    }
    if (n < 0) return (shown, _red);
    return (shown, const Color(0xFF222222));
  }

  String _fmtTime(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    var s = raw.replaceFirst('T', ' ');
    final dot = s.indexOf('.');
    if (dot > 0) s = s.substring(0, dot);
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final tone = _toneFor(toneKey);
    final signed = _signedAmount;
    final head = (title != null && title!.trim().isNotEmpty)
        ? title!.trim()
        : typeLabel;
    final sub = subtitle?.trim() ?? '';
    final note = remark?.trim() ?? '';
    final when = _fmtTime(time);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: tone.bg,
                  borderRadius: BorderRadius.circular(6.r),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: tone.fg,
                  ),
                ),
              ),
              if (title != null && title!.trim().isNotEmpty) ...[
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    head,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              SizedBox(width: 8.w),
              Text(
                signed.$1,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: signed.$2,
                ),
              ),
            ],
          ),
          if (sub.isNotEmpty) ...[
            SizedBox(height: 4.h),
            Text(
              sub,
              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
            ),
          ],
          if (ranks.isNotEmpty) ...[
            SizedBox(height: 8.h),
            CompactDrawSnapshotRow(
              ranks: ranks,
              sumGy: sumGy,
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
          if (note.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              '备注 $note',
              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
            ),
          ],
          if (when.isNotEmpty || onShareToCs != null) ...[
            SizedBox(height: 8.h),
            Row(
              children: [
                if (onShareToCs != null)
                  TextButton(
                    onPressed: onShareToCs,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8.w),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '发给客服',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.navBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const Spacer(),
                if (when.isNotEmpty)
                  Text(
                    when,
                    style:
                        TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

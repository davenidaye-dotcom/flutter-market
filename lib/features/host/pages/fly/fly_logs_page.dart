import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// Feipan op logs — GET /owner/feipan/op-logs
/// 字段同房间操作日志：createdAt / operatorName / operatorId / content
class FlyLogsPage extends ConsumerStatefulWidget {
  const FlyLogsPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<FlyLogsPage> createState() => _FlyLogsPageState();
}

class _FlyLogsPageState extends ConsumerState<FlyLogsPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getFeipanOpLogs();
      if (!mounted) return;
      setState(() {
        _rows = hostRowsOf(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '飞盘日志',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? Center(child: Text('暂无数据', style: TextStyle(color: AppColors.textHint)))
              : ListView.separated(
                  padding: EdgeInsets.all(16.w),
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) => SizedBox(height: 8.h),
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    final content = '${r['content'] ?? ''}';
                    final op = '${r['operatorName'] ?? ''}';
                    final at = '${r['createdAt'] ?? ''}';
                    return HostWhiteCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            content.isEmpty ? '—' : content,
                            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            [
                              if (op.isNotEmpty) op,
                              if (at.isNotEmpty) at,
                            ].join(' · '),
                            style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

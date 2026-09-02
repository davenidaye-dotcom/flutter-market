import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// Feipan op logs
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
      title: '\u98de\u76d8\u65e5\u5fd7',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? Center(child: Text('\u6682\u65e0\u6570\u636e', style: TextStyle(color: AppColors.textHint)))
              : ListView.separated(
                  padding: EdgeInsets.all(16.w),
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) => SizedBox(height: 8.h),
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    return HostWhiteCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${r['summary'] ?? r['content'] ?? r['action'] ?? ''}',
                            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${r['createdAt'] ?? r['time'] ?? ''}',
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

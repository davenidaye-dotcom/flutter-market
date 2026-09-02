import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';

/// Room agents from owner API
class HostAgentsPage extends ConsumerStatefulWidget {
  const HostAgentsPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostAgentsPage> createState() => _HostAgentsPageState();
}

class _HostAgentsPageState extends ConsumerState<HostAgentsPage> {
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
      final list = await ref.read(ownerRepositoryProvider).getAgents();
      if (!mounted) return;
      setState(() {
        _rows = list;
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
      title: '\u623f\u95f4\u4ee3\u7406\u7ba1\u7406',
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
            child: HostWhiteCard(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              child: Row(
                children: [
                  Expanded(flex: 3, child: _headerCell('\u4ee3\u7406\u6210\u5458')),
                  Expanded(child: _headerCell('\u4e0b\u7ea7\u4eba\u6570')),
                  Expanded(child: _headerCell('\u4e0b\u7ea7\u6d41\u6c34')),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? Center(
                        child: Text(
                          '\u6682\u65e0\u4ee3\u7406',
                          style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => SizedBox(height: 8.h),
                        itemBuilder: (_, i) {
                          final m = _rows[i];
                          final nick =
                              (m['nickname'] ?? m['displayName'] ?? m['username'] ?? '').toString();
                          final user = (m['username'] ?? '').toString();
                          final id = (m['accountId'] ?? m['id'] ?? '').toString();
                          final subCount = m['subordinateCount'] ?? m['memberCount'] ?? 0;
                          final turnover = m['subordinateTurnover'] ?? m['turnover'] ?? 0;
                          return HostWhiteCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(nick, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
                                          SizedBox(height: 2.h),
                                          Text(
                                            '$user \u00b7 ID $id',
                                            style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Text('$subCount', style: TextStyle(fontSize: 14.sp)),
                                    ),
                                    Expanded(
                                      child: Text(
                                        hostNumStr(turnover),
                                        style: TextStyle(fontSize: 14.sp),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String label) {
    return Text(
      label,
      style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
    );
  }
}

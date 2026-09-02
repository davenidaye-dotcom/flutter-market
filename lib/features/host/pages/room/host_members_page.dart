import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../data/host_mock.dart';
import '../../widgets/host_ui.dart';
import 'host_member_detail_page.dart';

/// Room members
class HostMembersPage extends ConsumerStatefulWidget {
  const HostMembersPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostMembersPage> createState() => _HostMembersPageState();
}

class _HostMembersPageState extends ConsumerState<HostMembersPage> {
  int _filter = 0;
  final _search = TextEditingController();
  List<HostMember> _all = [];
  bool _loading = true;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getMembers(
            keyword: _search.text.trim(),
            pageSize: 100,
          );
      final rows = hostRowsOf(data);
      final list = rows.map(hostMemberFromMap).toList();
      if (!mounted) return;
      setState(() {
        _all = list;
        _stats = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  List<HostMember> get _list {
    return _all.where((m) {
      final byFilter = switch (_filter) {
        0 => m.online || true, // show all when online filter if API omits presence
        1 => m.isMood,
        2 => m.disabled,
        3 => false,
        4 => false,
        5 => false,
        6 => m.isAgent,
        _ => true,
      };
      if (_filter == 0) {
        // Prefer online; if none marked online, show all
        final anyOnline = _all.any((x) => x.online);
        if (anyOnline && !m.online) return false;
      } else if (!byFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  List<(String, int)> get _catCounts {
    final online = _all.where((m) => m.online).length;
    final mood = _all.where((m) => m.isMood).length;
    final disabled = _all.where((m) => m.disabled).length;
    final agents = _all.where((m) => m.isAgent).length;
    final showOnline = online == 0 ? _all.length : online;
    return [
      ('\u5728\u7ebf\u73a9\u5bb6', showOnline),
      ('\u673a\u5668\u4eba', mood),
      ('\u7981\u7528', disabled),
      ('\u4ee3\u6ce8', 0),
      ('\u7279\u6b8a\u8fd4\u70b9', 0),
      ('\u5b50\u8d26\u6237', 0),
      ('\u4ee3\u7406\u5217\u8868', agents),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final cats = _catCounts;
    return HostSubPageScaffold(
      title: '\u623f\u95f4\u6210\u5458',
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 8.h),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40.h,
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8.r)),
                    alignment: Alignment.center,
                    child: EmulatorSafeTextField(
                      controller: _search,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: '\u8bf7\u8f93\u5165\u73a9\u5bb6\u7528\u6237\u540d\u6216ID',
                        hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                GestureDetector(
                  onTap: _load,
                  child: Container(
                    height: 40.h,
                    padding: EdgeInsets.symmetric(horizontal: 18.w),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF6BB6F0), AppColors.navBlue]),
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: Text('\u67e5\u8be2', style: TextStyle(fontSize: 14.sp, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Row(
              children: [
                for (var i = 0; i < cats.length; i++) ...[
                  if (i > 0) SizedBox(width: 8.w),
                  GestureDetector(
                    onTap: () => setState(() => _filter = i),
                    child: Column(
                      children: [
                        Container(
                          width: 40.w,
                          height: 28.h,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _filter == i ? AppColors.navBlue : const Color(0xFFD6EBFA),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          child: Text(
                            '${cats[i].$2}',
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: _filter == i ? Colors.white : AppColors.navBlue,
                            ),
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(cats[i].$1, style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 10.h),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12.r)),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : list.isEmpty
                        ? Center(
                            child: Text(
                              '\u6682\u65e0\u6570\u636e',
                              style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.all(12.w),
                            itemCount: list.length,
                            separatorBuilder: (_, _) => SizedBox(height: 8.h),
                            itemBuilder: (_, i) {
                              final m = list[i];
                              return InkWell(
                                onTap: () => pushHostPage(
                                  context,
                                  HostMemberDetailPage(roomId: widget.roomId, memberId: m.id),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18.r,
                                      backgroundColor: const Color(0xFFBDE0FE),
                                      child: Text(m.nickname.isNotEmpty ? m.nickname.characters.first : '?'),
                                    ),
                                    SizedBox(width: 10.w),
                                    Expanded(child: Text('${m.nickname} (${m.username})')),
                                    Text('${m.points}'),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
            child: Row(
              children: [
                _foot('\u7528\u6237\u4f59\u989d', hostNumStr(_stats['totalBalance'] ?? _stats['balance'])),
                _foot('\u4eca\u65e5\u6d41\u6c34', hostNumStr(_stats['turnover'] ?? _stats['todayTurnover'])),
                _foot('\u4eca\u65e5\u76c8\u4e8f', hostNumStr(_stats['profitLoss'] ?? _stats['todayProfitLoss'])),
                _foot('\u4eca\u65e5\u56de\u6c34', hostNumStr(_stats['rebate'] ?? _stats['todayRebate'])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _foot(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
          SizedBox(height: 4.h),
          Text(value, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

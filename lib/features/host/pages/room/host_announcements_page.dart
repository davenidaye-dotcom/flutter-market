import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../data/repositories/providers.dart';
import '../../../../shared/widgets/emulator_safe_text_field.dart';
import '../../../../shared/widgets/page_app_bar.dart';
import '../../widgets/host_ui.dart';

/// Room announcement GET/PUT
class HostAnnouncementsPage extends ConsumerStatefulWidget {
  const HostAnnouncementsPage({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HostAnnouncementsPage> createState() =>
      _HostAnnouncementsPageState();
}

class _HostAnnouncementsPageState extends ConsumerState<HostAnnouncementsPage> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(ownerRepositoryProvider).getAnnouncement();
      if (!mounted) return;
      _ctrl.text = (data['content'] ?? data['announcement'] ?? '').toString();
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(e.toString());
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(ownerRepositoryProvider)
          .updateAnnouncement(_ctrl.text.trim());
      AppToast.success('\u4fdd\u5b58\u6210\u529f');
    } catch (e) {
      AppToast.error(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HostSubPageScaffold(
      title: '\u516c\u544a\u7ba1\u7406',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              children: [
                HostWhiteCard(
                  child: EmulatorSafeTextField(
                    controller: _ctrl,
                    maxLines: 8,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '\u8bf7\u8f93\u5165\u623f\u95f4\u516c\u544a',
                      hintStyle: TextStyle(
                        fontSize: 14.sp,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(
                    height: 44.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.navBlue,
                      borderRadius: BorderRadius.circular(22.r),
                    ),
                    child: Text(
                      _saving ? '...' : '\u4fdd\u5b58',
                      style: TextStyle(fontSize: 16.sp, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

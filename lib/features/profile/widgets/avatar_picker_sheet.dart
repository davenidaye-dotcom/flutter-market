import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../config/theme/app_colors.dart';
import '../../../shared/avatars/avatar_catalog.dart';

/// 底部弹层：四列网格选择本地预设头像，返回编码 avNN。
Future<String?> showAvatarPickerSheet(
  BuildContext context, {
  String? currentCode,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
    ),
    builder: (ctx) => _AvatarPickerBody(currentCode: currentCode),
  );
}

class _AvatarPickerBody extends StatelessWidget {
  const _AvatarPickerBody({this.currentCode});

  final String? currentCode;

  @override
  Widget build(BuildContext context) {
    final selected = AvatarCatalog.normalizeCode(currentCode);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      child: SizedBox(
        height: 0.62.sh,
        child: Column(
          children: [
            SizedBox(
              height: 48.h,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        '取消',
                        style: TextStyle(fontSize: 15.sp, color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                  Text(
                    '请选择头像',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 12.h + bottom),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10.w,
                  crossAxisSpacing: 10.w,
                ),
                itemCount: AvatarCatalog.count,
                itemBuilder: (context, i) {
                  final code = AvatarCatalog.codeAt(i);
                  final asset = AvatarCatalog.assetOf(code)!;
                  final isSel = code == selected;
                  return GestureDetector(
                    onTap: () => Navigator.of(context).pop(code),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(
                          color: isSel ? AppColors.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6.r),
                        child: Image.asset(asset, fit: BoxFit.cover),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

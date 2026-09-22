import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';
import '../avatars/avatar_catalog.dart';

/// 按头像编码显示本地预设图；兼容历史 http URL；否则占位人像。
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.codeOrUrl,
    this.radius,
    this.backgroundColor,
  });

  final String? codeOrUrl;
  final double? radius;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? 18.r;
    final bg = backgroundColor ?? const Color(0xFFBDBDBD);
    final asset = AvatarCatalog.assetOf(codeOrUrl);
    if (asset != null) {
      return CircleAvatar(
        radius: r,
        backgroundColor: bg,
        backgroundImage: AssetImage(asset),
      );
    }
    final url = (codeOrUrl ?? '').trim();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return CircleAvatar(
        radius: r,
        backgroundColor: bg,
        backgroundImage: NetworkImage(url),
        onBackgroundImageError: (_, _) {},
        child: Icon(Icons.person, color: Colors.white, size: r),
      );
    }
    return CircleAvatar(
      radius: r,
      backgroundColor: bg == const Color(0xFFBDBDBD) ? AppColors.primaryLight : bg,
      child: Icon(Icons.person, color: Colors.white, size: r),
    );
  }
}

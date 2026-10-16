import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/theme/app_colors.dart';
import '../avatars/avatar_catalog.dart';

/// 按头像编码显示本地预设图；其它一律占位人像，不再从网络取图。
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
    // 历史上的 http(s) 头像地址不再加载：它走系统证书和系统网络栈，会在抓包里留下连接。
    return CircleAvatar(
      radius: r,
      backgroundColor: bg == const Color(0xFFBDBDBD) ? AppColors.primaryLight : bg,
      child: Icon(Icons.person, color: Colors.white, size: r),
    );
  }
}

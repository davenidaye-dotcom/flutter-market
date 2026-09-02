import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'config/env/env_config.dart';
import 'config/router/app_router.dart';
import 'config/theme/app_theme.dart';

class LetouApp extends ConsumerStatefulWidget {
  const LetouApp({super.key});

  @override
  ConsumerState<LetouApp> createState() => _LetouAppState();
}

class _LetouAppState extends ConsumerState<LetouApp> {
  static bool _screenUtilReady = false;

  @override
  void initState() {
    super.initState();
    // 首帧后撤 splash，不依赖 LoginPage 是否挂载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_screenUtilReady) {
      ScreenUtil.init(
        context,
        designSize: const Size(375, 812),
        minTextAdapt: true,
      );
      _screenUtilReady = true;
    }

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: EnvConfig.environment.appName,
      debugShowCheckedModeBanner: EnvConfig.isDebug,
      theme: AppTheme.light,
      routerConfig: router,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: EasyLoading.init(),
    );
  }
}

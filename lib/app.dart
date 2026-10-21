import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'core/audio/bgm_prompt.dart';
import 'config/env/env_config.dart';
import 'config/router/app_router.dart';
import 'config/router/route_paths.dart';
import 'config/theme/app_theme.dart';
import 'core/network/session_kick.dart';
import 'core/network/session_store.dart';
import 'core/network/session_watch.dart';
import 'features/auth/providers/auth_session_provider.dart';
import 'features/host/widgets/host_apply_notice_dialog.dart';
import 'features/profile/app_release.dart';
import 'features/profile/update_progress_host.dart';
import 'shared/widgets/page_app_bar.dart';

class LetouApp extends ConsumerStatefulWidget {
  const LetouApp({super.key});

  @override
  ConsumerState<LetouApp> createState() => _LetouAppState();
}

class _LetouAppState extends ConsumerState<LetouApp> {
  final SessionWatch _sessionWatch = SessionWatch();

  @override
  void initState() {
    super.initState();
    // 首帧后撤 splash，不依赖 LoginPage 是否挂载
    unawaited(BgmPrompt.setEnabled(false));
    SessionKick.handler = () {
      final message = SessionKick.takePendingMessage();
      dismissAllShellCovers();
      unawaited(SessionStore.instance.clear());
      ref.read(authSessionProvider.notifier).dropLocal();
      ref.read(routerProvider).go(RoutePaths.login);
      if (message.contains('维护')) {
        AppToast.info('系统维护中');
      } else if (message.contains('其他地方')) {
        AppToast.info(message);
      }
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = ref.read(authSessionProvider);
      _sessionWatch.sync(loggedIn: session.isLoggedIn, host: session.isHostSide);
      FlutterNativeSplash.remove();
      unawaited(_promptUpdate());
    });
  }

  Future<void> _promptUpdate() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await AppRelease.promptOnColdStart(ctx);
        return;
      }
    }
  }

  @override
  void dispose() {
    _sessionWatch.stop();
    if (SessionKick.handler != null) {
      SessionKick.handler = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authSessionProvider, (prev, next) {
      _sessionWatch.sync(loggedIn: next.isLoggedIn, host: next.isHostSide);
    });
    final router = ref.watch(routerProvider);
    // 必须用 ScreenUtilInit：在 MaterialApp 内拿真实 MediaQuery。
    // 旧写法在 MaterialApp 外 init 一次，真机长屏会缩放错，登录卡片挤在顶部。
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      ensureScreenSize: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: EnvConfig.environment.appName,
          debugShowCheckedModeBanner: false,
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
          // 系统「字体大小」不再放大界面。当前设计字号即上限。
          // 包在 EasyLoading 外，页面、弹窗、Toast 共用这一份 MediaQuery。
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.noScaling,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  EasyLoading.init()(context, child),
                  const HostApplyNoticeHost(),
                  const UpdateProgressHost(),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

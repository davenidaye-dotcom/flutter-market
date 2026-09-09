import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/bootstrap/remote_endpoint_bootstrap.dart';
import 'core/network/session_store.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  EasyLoading.instance.toastPosition = EasyLoadingToastPosition.center;

  // 会话 + OSS/CDN 线路引导（失败自动降级缓存/内置，不阻塞过久）
  await SessionStore.instance.load();
  await RemoteEndpointBootstrap.instance.ensureReady();

  runApp(const ProviderScope(child: LetouApp()));
}

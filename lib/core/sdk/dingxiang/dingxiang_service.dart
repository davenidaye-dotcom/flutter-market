import 'package:flutter/material.dart';

/// 顶象 SDK 验证结果
class DingxiangVerifyResult {
  const DingxiangVerifyResult({
    required this.success,
    this.token,
    this.message,
  });

  final bool success;
  final String? token;
  final String? message;
}

/// 顶象 SDK 服务抽象 — 后期替换为真实 SDK 实现
///
/// 当前阶段：登录流程不调用本服务（已在 LoginPage / main 注释）。
abstract class DingxiangService {
  Future<void> init();

  /// 展示滑块拼图验证
  Future<DingxiangVerifyResult> showCaptcha(BuildContext context);

  /// 销毁资源
  void dispose();
}

/// 占位实现 — 顶象关闭期间不会被调用
class DingxiangPlaceholderService implements DingxiangService {
  DingxiangVerifyResult _lastResult =
      const DingxiangVerifyResult(success: false);

  DingxiangVerifyResult get lastResult => _lastResult;

  @override
  Future<void> init() async {
    // TODO: 接入顶象 SDK init(appId)
    // await DingxiangSdk.init(EnvConfig.dingxiangAppId);
  }

  @override
  Future<DingxiangVerifyResult> showCaptcha(BuildContext context) async {
    // TODO: 展示顶象滑块 / WebView
    // return await DingxiangSdk.verify(context);
    return _lastResult;
  }

  void setVerifyResult(DingxiangVerifyResult result) {
    _lastResult = result;
  }

  @override
  void dispose() {}
}

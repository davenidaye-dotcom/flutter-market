# 本机启动（Mac）

工程目录：

```bash
cd /Users/joe/project/stockhome/flutter-market/flutter-market
```

每次新开终端先把 Flutter 加进 PATH。这台机器的 Flutter 在 `/tmp/flutter-sdk`（3.47.5），不在系统 PATH 里。`/tmp` 重启后可能被清掉，命令找不到 `flutter` 时先确认这个目录还在。

```bash
export PATH="/tmp/flutter-sdk/bin:$PATH"
```

默认环境是 `dev`。不写 `--dart-define` 也是 dev。接口默认连 `http://207.148.105.182/api/v1`，WebSocket 是 `ws://207.148.105.182/ws/v1`。

跑起来之后终端不要关：`r` 热重载，`R` 热重启，`q` 退出。

## 改完代码之后

调试会话还在时，不用重新打包。Dart 界面和逻辑改动，在这个终端按 `r`。改了状态初始化、`main`，或热重载没生效，按 `R`。

终端已经关掉、或手机上的 App 不在了，再执行下面同一条 `flutter run`。这是增量编译后装回手机，不是打正式包。

改了 `android/`、`ios/`、`pubspec.yaml` 里的插件，热重载不够，按 `R` 或重新 `flutter run`。

## iPhone 模拟器

Xcode 27.0 已装在 `/Applications/Xcode.app`，开发者目录已指向它。模拟器关机时，`flutter devices` 里看不到 iPhone，只会看到 macOS 和 Chrome。先开机再跑。

iOS 只有 `Runner` 这一个 scheme，不要加 `--flavor`。

```bash
export PATH="/tmp/flutter-sdk/bin:$PATH"
cd /Users/joe/project/stockhome/flutter-market/flutter-market
xcrun simctl boot "iPhone 18 Pro"
open -a Simulator
flutter run -d "iPhone 18 Pro" --dart-define=APP_ENV=dev
```

已经开机时，`simctl boot` 会报错，忽略即可，直接 `flutter run`。这台工程的 iOS 插件走 Swift Package，不需要 CocoaPods。

## 安卓真机

Android Studio 在「应用程序」里（2026.1）。SDK 在：

```text
/Users/joe/Library/Android/sdk
```

Flutter 已配置使用这个目录（`flutter config --android-sdk`）。第一次打开 Android Studio 如果要选 SDK 位置，填上面这个路径。`adb` 在该目录的 `platform-tools` 里。

手机上：连续点「版本号」7 次打开开发者选项，打开「USB 调试」，数据线连上后在手机上点允许。

安卓必须带 `--flavor dev`（另外还有 `staging`、`pro`）。新开的终端里 `flutter` 会报 `command not found`，先执行第一行 `export`。

打包并安装到当前这台手机（`23116PN5BC`，id `47199271`）。换手机时先看 `flutter devices`，再把 `-d` 后面的 id 换成新的。

```bash
export PATH="/tmp/flutter-sdk/bin:$PATH"
cd /Users/joe/project/stockhome/flutter-market/flutter-market
flutter devices
flutter run --flavor dev -d 47199271 --dart-define=APP_ENV=dev
```

第一次会停在 `Running Gradle task 'assembleDevDebug'`，经常要几分钟到十几分钟，终端不要关，也不要按 `Ctrl+C`。手机保持解锁，弹出安装确认时点允许。装完后 App 会自己打开。

Android Studio 首次启动若弹出 `Unable to access Android SDK add-on list`：Clash Verge 开着系统代理时，选手动 HTTP 代理，主机 `127.0.0.1`，端口 `7897`，不要勾登录认证。SDK 已经在上面的目录里时，直接 Cancel 也可以，不影响这条 `flutter run`。

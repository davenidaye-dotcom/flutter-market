# iOS Ad Hoc 打包并装到真机

工程目录：

```bash
cd /Users/joe/project/stockhome/flutter-market/flutter-market
```

每次新开终端先把 Flutter 加进 PATH。Flutter 3.47.5 装在 `/Users/joe/flutter`。

```bash
export PATH="/Users/joe/flutter/bin:$PATH"
```

iOS 没有安卓那种 `dev` / `staging` / `pro` flavor，不要加 `--flavor`。生产环境用 `--dart-define=APP_ENV=pro`。包名是 `com.letou.letouApp`，显示名是「瑞丰」。

打出来的是 `.ipa`，不是 apk。这个包只能装到已经在开发者账号里登记过 UDID 的 iPhone 上。模拟器不算登记设备。

## 1. 开发者账号只加在 Xcode 里

不要在「系统设置 → Apple ID」里登录这个开发者账号，否则会换掉这台 Mac 现在的 iCloud。

1. 打开 Xcode → Settings → Apple Accounts。
2. 点 **+**，登录开发者 Apple ID。这次用的是 `linhthtai86@icloud.com`（Nguyen Thi Tai Linh）。双重认证在自己的设备上完成，不要把密码或收码链接发给别人。
3. 登录成功后，Teams 里会出现 **Nguyen Thi Tai Linh**，角色是 **Admin**。右边单独的 **Sign In...** 是用来再添加别的账号的，不用点。

Team ID：`7S7P9BQWY8`。

## 2. 给工程选上这个团队

1. 用 Xcode 打开 `ios/Runner.xcworkspace`。
2. 左侧最上面蓝色的 **Runner** 图标点一下，不要点下面的黄色文件夹。
3. 中间 **TARGETS** 里点 **Runner**。
4. 顶部切到 **Signing & Capabilities**。
5. 勾上 **Automatically manage signing**。
6. **Team** 选 **Nguyen Thi Tai Linh**。Bundle Identifier 保持 `com.letou.letouApp`。
7. 按 `Cmd+S` 保存。

常见状态：

- **Updating provisioning...**：等它消失。
- **The request timed out**：访问苹果超时。Clash 开着系统代理再点 **Try Again**；还超时就把系统代理关掉再试。
- **Revoke certificate**（私钥不在这台电脑的钥匙串里）：点 **Revoke Certificate**。旧证书会作废，Xcode 在这台 Mac 上重新生成。钥匙串问密码时，填这台 Mac 的开机登录密码，不是 Apple ID 密码，然后点 **始终允许**。
- **Your team has no devices**：这个团队还没有登记过任何一台真机。先做下一节，再回来点 **Try Again**。

签名成功时，证书一行是 `Apple Development: Nguyen Thi Tai Linh`，没有黄字。

## 3. 登记 iPhone 的 UDID

没有数据线也能登记。iPhone 的「设置」里看不到 UDID，让对方用手机浏览器打开一个显示 UDID 的网页，按提示安装描述文件，页面上会给出那串字符。

1. 用同一个开发者账号打开 [Devices](https://developer.apple.com/account/resources/devices/list)。
2. 右上角点 **+**。
3. Platform 选 **iOS, tvOS, watchOS**。
4. Device Name 填一个认得出来的名字。Device ID 粘贴 UDID，不要有空格。
5. **Continue**，再 **Register**。

要装这个包的每台 iPhone 都要加一次。后来又加了新的 UDID，必须重新导出 ipa，旧包不会自动带上新设备。

登记完成后，回到 Xcode 的 **Signing & Capabilities**，点 **Try Again**，直到黄字消失。

## 4. 打归档

```bash
export PATH="/Users/joe/flutter/bin:$PATH"
cd /Users/joe/project/stockhome/flutter-market/flutter-market
flutter build ipa --dart-define=APP_ENV=pro --release --export-method ad-hoc
```

第一次会下载 iOS 真机引擎，大约 93MB。速度停在 `0.0MB/s` 时，开着 Clash 停掉重跑：

```bash
export https_proxy=http://127.0.0.1:7897
export http_proxy=http://127.0.0.1:7897
flutter build ipa --dart-define=APP_ENV=pro --release --export-method ad-hoc
```

引擎下完后才会编译。编译成功的标志是：

```text
✓ Built build/ios/archive/Runner.xcarchive
```

命令行导出 ipa 这一步可能会失败，报：

```text
No signing certificate "iOS Distribution" found
No profiles for 'com.letou.letouApp' were found
```

这是因为本机当时只有 Development 证书，Ad Hoc 还要 Distribution 证书。归档已经打好了，不用重新编译，用下一节在 Xcode 里导出。

## 5. 在 Xcode 里导出 ipa

```bash
open /Users/joe/project/stockhome/flutter-market/flutter-market/build/ios/archive/Runner.xcarchive
```

没有弹出窗口时，Xcode 菜单 **Window → Organizer**。

1. 左边 **Archives**，选中这次的 **Runner**。
2. 点右边 **Distribute App**。
3. 选 **Custom**，再选 **Ad Hoc**。有的页面直接叫 **Release Testing**，选那个即可。
4. **App Thinning** 选 **None**，不要选某一款机型。点 **Next**。
5. 选 **Automatically manage signing**，Team 选 **Nguyen Thi Tai Linh**。
6. 提示创建 **Apple Distribution** 证书时点同意。又要吊销旧证书时，同样点 **Revoke Certificate**。钥匙串密码仍是这台 Mac 的开机密码，点 **始终允许**。
7. 摘要页应看到：
   - Team：Nguyen Thi Tai Linh
   - Certificate：Cloud Managed Apple Distribution
   - Profile：iOS Team Ad Hoc Provisioning Profile: com.letou.letouApp
8. 点 **Export**。文件名可以保持默认。这次保存在桌面：

```text
/Users/joe/Desktop/Runner 2026-10-18 14-54-20/letou_app.ipa
```

文件夹里其余的 `DistributionSummary.plist`、`ExportOptions.plist`、`Packaging.log` 不用发给别人。只发 `letou_app.ipa`。

## 6. 用数据线装到手机

线必须能传数据，不必是原装线。只能装到已经登记过 UDID 的那台手机。这次装上的是 **iPhone 12 Pro Max**（系统里的名字是 `iPhone`，iOS 26.6）。

1. 插上手机，解锁，点「信任这台电脑」。
2. Xcode 里按 **Shift+Command+2** 打开设备窗口。左边选这台真机，不要选 **iPhone 18 Pro Simulator**。
3. 如果写着 **Enable Developer Mode**：在手机上打开 **设置 → 隐私与安全性 → 开发者模式**，按提示重启，重启后再点「打开」。
4. 底部 **Preparing for development...** 消失之前不要拔线。手机保持解锁。
5. 这个窗口只负责看画面，把 ipa 拖进去没有反应。不要点 **View Screen**。在终端安装：

```bash
xcrun devicectl device install app --device "iPhone" \
  "/Users/joe/Desktop/Runner 2026-10-18 14-54-20/letou_app.ipa"
```

手机在系统里的名字不是 `iPhone` 时，把 `--device` 后面换成设备窗口里显示的名字。

成功时输出里有 `App installed` 和 `bundleID: com.letou.letouApp`。

点开 App 如果立刻退出：手机 **设置 → 通用 → VPN 与设备管理**，点这个开发者证书，再点信任。

## 7. 没有数据线时

不能靠无线把一台从没配对过的 iPhone 配上这台 Mac。Xcode 的无线连接要求以前用数据线配对过。

没有线、也不想登记 UDID 时，走 TestFlight，不走这份 Ad Hoc 包。

已经有 UDID、也已经导出 ipa 时，可以把 `letou_app.ipa` 上传到分发网页，用那台登记过的 iPhone 的 Safari 打开链接安装。不要用微信内置浏览器打开。装完后同样要在 **VPN 与设备管理** 里信任证书。

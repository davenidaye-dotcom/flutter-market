# 乐投 Flutter App

基于 `D:\老铁` 原型图 1:1 还原的用户端应用，当前为 **UI 阶段**（Mock 数据，预留 API 入口）。

## 技术栈

| 组件 | 用途 |
|------|------|
| flutter_riverpod | 状态管理，避免深层 setState |
| go_router | 声明式路由 |
| dio | HTTP 客户端（API 预留） |
| flutter_screenutil | 屏幕适配 |
| pin_code_fields | 房间号 6 位输入 |
| cached_network_image | 图片缓存 |
| flutter_easyloading | 全局 Loading |
| easy_refresh | 列表下拉刷新 |

## 项目结构

```
lib/
├── config/          # 环境、主题、路由
├── core/            # 网络、顶象 SDK 占位
├── data/            # Model、Repository、API 入口
├── features/        # 按功能模块划分页面
│   ├── auth/        # 登录、注册、滑块验证
│   ├── home/        # 进房首页
│   ├── lottery/     # 彩种大厅、聊天下注
│   ├── wallet/      # 钱包/积分中心
│   ├── profile/     # 个人设置
│   └── room/        # 房间 Shell、房间介绍
└── shared/widgets/  # 可复用 UI 组件
```

## 页面清单

- 登录 / 注册 / 顶象滑块验证（占位）
- 进房首页（房间号 + 历史房间）
- 彩种大厅（公告跑马灯 + 彩种卡片）
- 聊天下注页（期号倒计时、聊天、快捷面板）
- 钱包中心（积分概览 + 功能入口）
- 房间介绍 / 个人中心 / 个人设置 / 修改密码

## 多环境

通过 `--dart-define=APP_ENV=dev|test|pro` + Android Flavor 切换：

```bash
# 开发调试
flutter run --flavor dev --dart-define=APP_ENV=dev

# 测试包（APP_ENV=test，Android Flavor 名为 staging）
flutter build apk --flavor staging --dart-define=APP_ENV=test --release

# 生产包
flutter build apk --flavor pro --dart-define=APP_ENV=pro --release

# 或使用脚本（自动映射 test -> staging）
scripts\build.bat test apk
scripts\build.bat pro apk
```

| 环境 | APP_ENV | Android Flavor | API 地址 | 应用名 |
|------|---------|----------------|----------|--------|
| 开发 | dev | dev | https://dev-api.letou.com | 乐投Dev |
| 测试 | test | staging | https://test-api.letou.com | 乐投Test |
| 生产 | pro | pro | https://api.letou.com | 乐投 |

## 顶象 SDK

`lib/core/sdk/dingxiang/` 已预留接口：

- `DingxiangService` — 抽象层
- `DingxiangPlaceholderService` — 当前占位（CaptchaPage 本地滑块）
- 后期替换为真实 SDK 实现，UI 层无需改动

## API 对接

Repository 层已分离 Mock 与 API：

- `AuthRepository` / `RoomRepository` / `LotteryRepository` / `WalletRepository`
- 对应 `*Api` 类定义了真实接口路径，联调时切换 Repository 实现即可

## 原型参考

设计稿位于 `design_refs/`（从 `D:\老铁` 复制），`index.json` 为文件索引。

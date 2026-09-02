# FlyRoom App 接口 / WebSocket 全量对接与联调报告（详情版）

> 生成时间：`2026-08-24T03:43:09.132674`  
> HTTP Base：`http://207.148.105.182/api/v1`  
> WS Base：`ws://207.148.105.182/ws/v1`  
> 测试账号：player=`player01` / agent=`abcd658` / owner=`owner01` / roomCode=`679010`  
> 探测命令：`dart run scripts/api_e2e_flow.dart`（含真实写操作） → `scripts/_api_audit/last_probe.json`  
> 模式：`READONLY_AUDIT`  
> 原始文档：`scripts/_api_audit/member.md` / `agent.md` / `owner.md`

## 0. 结论摘要

| 指标 | 数量 | 说明 |
|---|---:|---|
| 条目总计 | 55 | 含文档接口、WS、文档缺口、跳过的写操作 |
| 探测成功 OK | 13 | 业务 code=200 或 WS 已连通 |
| 探测失败 FAIL | 42 | HTTP 通但业务码非 200（多为服务端 500） |
| 探测异常 ERROR | 0 | 超时/网络异常（本次主要为 WS） |
| 跳过 SKIP / N/A | 0 | 写操作未实打、Agent 无 WS |
| 文档/产品缺失 | null | 前端有入口，文档无独立接口 |
| 客户端已接线 YES | null | Repository / Provider / 页面已调用 |
| 客户端未接线 NO | null | 仍 Mock / Toast「待对接」 |
| 客户端部分 PARTIAL | null | 有降级 Mock 或复用其它接口 |

### 0.1 一句话判定

1. **已对接且服务端正常**：玩家登录、`GET /member/profile`、`PUT /member/profile/nickname`；代理登录及 PROFILE/STATS/accounts/reports；房主登录。
2. **已对接但服务端报错**：玩家进房链（verify/enter/history）及所有依赖房间上下文的接口；本次全部 `GET /owner/**`；`GET /agent/credits/changes`。
3. **WebSocket 异常**：`/ws/v1/member` 与 `/ws/v1/owner` 均 **8s 连接超时**（`:9080`）。
4. **文档缺失 / 未对接**：上下分申请、长龙、分享 App、房主客服会话列表、助手号/批量回水、玩家开奖历史 HTTP、大厅公告列表、顶象验证码。
5. **路径是否对**：文档内 HTTP 绝大多数已在 Repository 按正确 path 接线；当前 FAIL 主因是服务端 500，不是客户端拼错 URL。

### 0.2 关键阻塞（服务端）

| 优先级 | 问题 | 影响 |
|---:|---|---|
| P0 | `POST /member/rooms/enter` 及 verify/history 返回 500 | 玩家无法进房，房间内全部业务链崩溃 |
| P0 | 全部 `GET /owner/**` 返回 500 | 房主端页面无法拉到真实数据 |
| P0 | WS `:9080` 连不上 | 期态/开奖/聊天推送全无 |
| P1 | `GET /agent/credits/changes` 500 | 代理额度变更页报错 |

## 1. 探测成功（接口对且服务端正常）

| 角色 | 方法 | 路径/能力 | 客户端 | 探测 | bizCode | 说明 |
|---|---|---|---|---|---:|---|
| player | POST | `/auth/member/login` | 已对接 | ✅ 正常 | 200 | 操作成功 |
| player | POST | `/member/rooms/enter` | 已对接 | ✅ 正常 | 200 | 操作成功 |
| player | GET | `/member/profile` | 已对接 | ✅ 正常 | 200 | 操作成功 |
| player | GET | `/member/rooms/verify?roomCode=679010` | 已对接 | ✅ 正常 | 200 | 操作成功 |
| player | GET | `/member/rooms/history?limit=20` | 已对接 | ✅ 正常 | 200 | 操作成功 |
| player | WS | `/ws/v1/member` | 已对接 | ✅ 正常 | - | connected; topics=room:900010001:game:JS_SC; received=9; sample={"event":"CONNECTED","data":{"userId":900001005}} |
| agent | POST | `/auth/portal/login` | 已对接 | ✅ 正常 | 200 | 操作成功 |
| agent | GET | `/agent/lottery/info?scene=PROFILE` | 已对接 | ✅ 正常 | 200 | 操作成功 |
| agent | GET | `/agent/lottery/info?scene=STATS` | 已对接 | ✅ 正常 | 200 | 操作成功 |
| agent | GET | `/agent/accounts?pageNum=1&pageSize=20` | 已对接 | ✅ 正常 | 200 | 操作成功 |
| agent | GET | `/agent/reports?startDate=2026-08-11&endDate=2026-08-23` | 已对接 | ✅ 正常 | 200 | 操作成功 |
| owner | POST | `/auth/portal/login` | 已对接 | ✅ 正常 | 200 | 操作成功 |
| owner | WS | `/ws/v1/owner` | 已对接 | ✅ 正常 | - | connected; topics=room:900010001:game:JS_SC,room:900010001:sys; received=10; sample={"event":"CONNECTED","data":{"userId":900001010}} |

## 2. 探测失败 FAIL（已对接，服务端业务报错）

| 角色 | 方法 | 路径/能力 | 客户端 | 探测 | bizCode | 说明 |
|---|---|---|---|---|---:|---|
| player | GET | `/member/rooms/games` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| player | GET | `/member/rooms/messages?gameType=JS_SC&limit=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| player | GET | `/member/wallet` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| player | GET | `/member/wallet/adjustments?pageNum=1&pageSize=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| player | GET | `/member/bets?pageNum=1&pageSize=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| player | GET | `/member/points/changes?pageNum=1&pageSize=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| player | GET | `/member/welfare?type=SUMMARY` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| player | GET | `/member/agent-info` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| player | GET | `/member/rooms/intro?gameType=JS_SC` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| player | GET | `/member/redpacks?status=ALL` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| player | GET | `/member/cs/messages?limit=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| agent | GET | `/agent/credits/changes?pageNum=1&pageSize=20&changeType=ALL` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/notices` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/games` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/games/JS_SC/history?date=2026-08-12` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/games/JS_SC/messages?limit=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/room` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/room/announcement` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/room/members?presence=ALL&pageNum=1&pageSize=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/room/agents?pageNum=1&pageSize=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/room/odds?gameType=JS_SC` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/room/rebate` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/room/op-logs?startDate=2026-08-11&endDate=2026-08-23` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/room/games/settings` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/manage/dashboard` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/manage/applications/up?status=PENDING&pageNum=1&pageSize=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/manage/applications/down?status=PENDING&pageNum=1&pageSize=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/manage/applications/enter?status=PENDING&pageNum=1&pageSize=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/manage/reports/bets?startDate=2026-08-01&endDate=2026-08-23&category=ALL` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/manage/welfare?type=SUMMARY&startDate=2026-08-01&endDate=2026-08-23` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/manage/credits/records?startDate=2026-08-01&endDate=2026-08-23&pageNum=1&pageSize=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/manage/bets?startDate=2026-08-01&endDate=2026-08-23&pageNum=1&pageSize=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/manage/redpacks?pageNum=1&pageSize=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/feipan/status` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/feipan/credit?gameType=JS_SC` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/feipan/reports?startDate=2026-08-01&endDate=2026-08-23&category=ALL` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/feipan/odds?gameType=JS_SC` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/feipan/points/changes?changeType=ALL&pageNum=1&pageSize=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/feipan/op-logs?startDate=2026-08-11&endDate=2026-08-23` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/cs/sessions?pageNum=1&pageSize=20` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/room/assistants` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |
| owner | GET | `/owner/room/rebate/batch-preview?presence=ALL` | 已对接 | ❌ 报错 | 500 | 发生未知异常，请联系管理员 |

## 3. 探测异常 ERROR（网络/超时）

| 角色 | 方法 | 路径/能力 | 客户端 | 探测 | bizCode | 说明 |
|---|---|---|---|---|---:|---|
| — | — | — | — | — | — | （无） |

## 4. 跳过（无数据可操作，非故意不请求）

| 角色 | 方法 | 路径/能力 | 客户端 | 探测 | bizCode | 说明 |
|---|---|---|---|---|---:|---|
| — | — | — | — | — | — | （无） |

## 5. 文档缺失 / 未对接 / 部分对接 / 桩

| 角色 | 方法 | 路径/能力 | 客户端 | 探测 | bizCode | 说明 |
|---|---|---|---|---|---:|---|
| — | — | — | — | — | — | （无） |

## 6. WebSocket 详情

| 角色 | 端点 | 客户端实现 | 文档 event | 本次探测 |
|---|---|---|---|---|
| player | `ws://{host}/ws/v1/member?token=` | `FlyroomWsClient(member)` + `roomLotteryLiveProvider`；SUBSCRIBE `room:{roomId}:game:{gameType}` | PERIOD_TICK / SEAL_WARN / SEALED / DRAW_RESULT / CHAT / REDPACK_NOTICE | **ERROR 超时 8s** |
| owner | `ws://{host}/ws/v1/owner?token=` | 同上 role=owner；文档还有 `room:{id}:sys` | 另含 APPLY_NOTICE | **ERROR 超时 8s** |
| agent | （无） | 未实现 | agent.md 无 WS 章节 | N/A |

**客户端已处理的入站 event**（`lottery_live_provider._onWsEvent`）：`PERIOD_TICK` / `SEAL_WARN` / `SEALED` / `DRAW_RESULT`。
**尚未完整消费**：`CHAT` / `REDPACK_NOTICE` / `APPLY_NOTICE`（通道已预留，UI 未全量绑定）。

### 6.1 WS 对照文档的客户端行为

| 项 | 文档 | App |
|---|---|---|
| 连接 URL | `/ws/v1/member` `/ws/v1/owner` | `EnvConfig.wsBaseUrl` + role path |
| SUBSCRIBE | `room:{roomId}:game:{gameType}` | 进厅后按游戏列表订阅 |
| owner sys topic | `room:{id}:sys` | **未订阅**（部分缺口） |
| PING | 有 | `FlyroomWsClient.ping()` 存在，未做定时心跳 |
| 重连 | 建议 | **未实现自动重连** |

## 7. 按角色：文档 ↔ 客户端 ↔ 探测

### 7.1 玩家 member

| 文档接口 | 客户端位置 | 对接 | 探测 |
|---|---|---|---|
| `POST /auth/member/login` | AuthRepository.login | 已对接 | ✅ 正常 操作成功 |
| `POST /auth/member/register` | AuthRepository.register | 已对接 | -  |
| `POST /auth/password/change` | AuthRepository.changePassword | 已对接 | -  |
| `POST /auth/logout` | AuthRepository.logout | 已对接 | -  |
| `GET /member/profile` | MemberRepository | 已对接 | ✅ 正常 操作成功 |
| `PUT /member/profile/nickname` | MemberRepository / 个人设置 | 已对接 | -  |
| `GET /member/rooms/verify` | RoomRepository.verifyRoom | 已对接 | ✅ 正常 操作成功 |
| `POST /member/rooms/enter` | RoomRepository.enterRoom / HomePage | 已对接 | ✅ 正常 操作成功 |
| `GET /member/rooms/history` | RoomRepository.getHistoryRooms | 已对接 | ✅ 正常 操作成功 |
| `GET /member/rooms/games` | LotteryRepository.getGames | 已对接 | ❌ 报错 发生未知异常，请联系管理员 |
| `GET /member/rooms/messages` | LotteryRepository.getChatMessages | 已对接 | ❌ 报错 发生未知异常，请联系管理员 |
| `WS /ws/v1/member` | FlyroomWsClient + RoomLotteryLive | 已对接 | ✅ 正常 connected; topics=room:900010001:game:JS_SC; received=9; sample={"event":"CONNECTED","data":{"userId":900001005}} |
| `GET /member/redpacks` | MemberRepository + chat FAB | 已对接 | ❌ 报错 发生未知异常，请联系管理员 |
| `POST /member/redpacks/{id}/claim` | MemberRepository.claimRedpack | 已对接 | -  |
| `GET /member/cs/messages` | customer_service_page | 已对接 | ❌ 报错 发生未知异常，请联系管理员 |
| `POST /member/cs/messages` | customer_service_page | 已对接 | -  |
| `GET /member/wallet` | WalletRepository + 钱包/直播顶栏 | 已对接 | ❌ 报错 发生未知异常，请联系管理员 |
| `GET /member/wallet/adjustments` | apply_records_page | 已对接 | ❌ 报错 发生未知异常，请联系管理员 |
| `GET /member/welfare` | welfare_report_page | 已对接 | ❌ 报错 发生未知异常，请联系管理员 |
| `GET /member/bets` | bet_records_page | 已对接 | ❌ 报错 发生未知异常，请联系管理员 |
| `POST /member/bets` | chat_bet / market_bet | 已对接 | -  |
| `GET /member/points/changes` | points_change_page | 已对接 | ❌ 报错 发生未知异常，请联系管理员 |
| `GET /member/agent-info` | agent_info_page | 已对接 | ❌ 报错 发生未知异常，请联系管理员 |
| `GET /member/rooms/intro` | room_intro_page | 已对接 | ❌ 报错 发生未知异常，请联系管理员 |

### 7.2 代理 agent

| 文档接口 | 客户端位置 | 对接 | 探测 |
|---|---|---|---|
| `POST /auth/portal/login` | AuthRepository.login(portal) | 已对接 | ✅ 正常 操作成功 |
| `GET /agent/lottery/info` | AgentRepository PROFILE/STATS + 顶栏 | 已对接 | ✅ 正常 操作成功 |
| `GET /agent/accounts` | agent_account_manage_page | 已对接 | ✅ 正常 操作成功 |
| `POST /agent/accounts` | agent_account_manage_page | 已对接 | -  |
| `GET /agent/reports` | agent_report_query_page | 已对接 | ✅ 正常 操作成功 |
| `GET /agent/credits/changes` | agent_quota_change_page | 已对接 | ❌ 报错 发生未知异常，请联系管理员 |
| `POST /auth/password/change` | agent_change_password_page | 已对接 | -  |
| `POST /auth/logout` | agent_ui logout | 已对接 | -  |

### 7.3 房主 owner

`OwnerRepository` 已覆盖文档中的 GET/PUT/POST；审核/管理中心/房间设置/赔率回水/报表/飞盘等页面已调用。

| 接口族 | 客户端 | 本次探测 |
|---|---|---|
| `POST /auth/portal/login` | 已对接 | ✅ 正常 |
| 全部探测到的 `GET /owner/**` | 已对接 | ❌ 全部 biz=500 |
| 各类 PUT/POST 变更 | 已对接 | ⏭ 审计跳过实打 |
| `WS /ws/v1/owner` | 已对接 | ⚠️ 连接超时 |

详细 GET 清单见第 2 节与第 9 节全表。

## 8. UI 仍 Mock / Toast「待对接」（产品/文档缺口）

| 位置 | 现象 | 文档是否有接口 | 建议 |
|---|---|---|---|
| `chat_bet_page` 上分/下分 | Toast 待对接 | 无 member 申请接口；仅有 owner applications 审核 | 补玩家申请 API |
| `chat_bet_page` 长龙 | `mockLongDragonRows` | 无 | 补长龙统计接口 |
| `chat_bet_page` 历史开奖（玩家） | 失败回退 `mockHistoryDraws` | member 无 history；owner 有 | 给 member 开 history |
| `room_repository.getAnnouncements` | 固定 `AnnouncementModel.mockList` | 无独立 member notices | 用房间公告/intro 或新增 list |
| `profile_page` 分享 App | Toast | 无 | 客户端分享 SDK，可不做后端 |
| `host_service_page` | `HostMock.csSessions` | owner 无 CS 列表 | 补 owner CS API |
| `host_assistants_page` / `host_batch_rebate_page` | 硬编码 UI | 无 | 补文档或下线入口 |
| `captcha_page` | `mock_dx_token` | 顶象为外部 SDK | 接真实验证码 |
| `agent_ui` 余额兜底 | API 失败时用 `AgentMock.balance` | 有 PROFILE | 后端稳定后可去掉兜底 |
| owner `room:{id}:sys` WS topic | 未 SUBSCRIBE | 文档有 | 房主连 WS 时补订 |

## 9. 全量明细表（本次 probe 原始结果）

| # | 角色 | 方法 | 路径 | 客户端 | 探测 | HTTP | biz | message |
|---:|---|---|---|---|---|---:|---:|---|
| 1 | player | POST | `/auth/member/login` | YES | OK | - | 200 | 操作成功 |
| 2 | player | POST | `/member/rooms/enter` | YES | OK | 200 | 200 | 操作成功 |
| 3 | player | GET | `/member/profile` | YES | OK | 200 | 200 | 操作成功 |
| 4 | player | GET | `/member/rooms/verify?roomCode=679010` | YES | OK | 200 | 200 | 操作成功 |
| 5 | player | GET | `/member/rooms/history?limit=20` | YES | OK | 200 | 200 | 操作成功 |
| 6 | player | GET | `/member/rooms/games` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 7 | player | GET | `/member/rooms/messages?gameType=JS_SC&limit=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 8 | player | GET | `/member/wallet` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 9 | player | GET | `/member/wallet/adjustments?pageNum=1&pageSize=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 10 | player | GET | `/member/bets?pageNum=1&pageSize=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 11 | player | GET | `/member/points/changes?pageNum=1&pageSize=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 12 | player | GET | `/member/welfare?type=SUMMARY` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 13 | player | GET | `/member/agent-info` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 14 | player | GET | `/member/rooms/intro?gameType=JS_SC` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 15 | player | GET | `/member/redpacks?status=ALL` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 16 | player | GET | `/member/cs/messages?limit=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 17 | player | WS | `/ws/v1/member` | YES | OK | - | - | connected; topics=room:900010001:game:JS_SC; received=9; sample={"event":"CONNECTED","data":{"userId":900001005}} |
| 18 | agent | POST | `/auth/portal/login` | YES | OK | - | 200 | 操作成功 |
| 19 | agent | GET | `/agent/lottery/info?scene=PROFILE` | YES | OK | 200 | 200 | 操作成功 |
| 20 | agent | GET | `/agent/lottery/info?scene=STATS` | YES | OK | 200 | 200 | 操作成功 |
| 21 | agent | GET | `/agent/accounts?pageNum=1&pageSize=20` | YES | OK | 200 | 200 | 操作成功 |
| 22 | agent | GET | `/agent/reports?startDate=2026-08-11&endDate=2026-08-23` | YES | OK | 200 | 200 | 操作成功 |
| 23 | agent | GET | `/agent/credits/changes?pageNum=1&pageSize=20&changeType=ALL` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 24 | owner | POST | `/auth/portal/login` | YES | OK | - | 200 | 操作成功 |
| 25 | owner | GET | `/owner/notices` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 26 | owner | GET | `/owner/games` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 27 | owner | GET | `/owner/games/JS_SC/history?date=2026-08-12` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 28 | owner | GET | `/owner/games/JS_SC/messages?limit=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 29 | owner | GET | `/owner/room` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 30 | owner | GET | `/owner/room/announcement` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 31 | owner | GET | `/owner/room/members?presence=ALL&pageNum=1&pageSize=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 32 | owner | GET | `/owner/room/agents?pageNum=1&pageSize=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 33 | owner | GET | `/owner/room/odds?gameType=JS_SC` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 34 | owner | GET | `/owner/room/rebate` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 35 | owner | GET | `/owner/room/op-logs?startDate=2026-08-11&endDate=2026-08-23` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 36 | owner | GET | `/owner/room/games/settings` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 37 | owner | GET | `/owner/manage/dashboard` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 38 | owner | GET | `/owner/manage/applications/up?status=PENDING&pageNum=1&pageSize=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 39 | owner | GET | `/owner/manage/applications/down?status=PENDING&pageNum=1&pageSize=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 40 | owner | GET | `/owner/manage/applications/enter?status=PENDING&pageNum=1&pageSize=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 41 | owner | GET | `/owner/manage/reports/bets?startDate=2026-08-01&endDate=2026-08-23&category=ALL` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 42 | owner | GET | `/owner/manage/welfare?type=SUMMARY&startDate=2026-08-01&endDate=2026-08-23` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 43 | owner | GET | `/owner/manage/credits/records?startDate=2026-08-01&endDate=2026-08-23&pageNum=1&pageSize=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 44 | owner | GET | `/owner/manage/bets?startDate=2026-08-01&endDate=2026-08-23&pageNum=1&pageSize=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 45 | owner | GET | `/owner/manage/redpacks?pageNum=1&pageSize=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 46 | owner | GET | `/owner/feipan/status` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 47 | owner | GET | `/owner/feipan/credit?gameType=JS_SC` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 48 | owner | GET | `/owner/feipan/reports?startDate=2026-08-01&endDate=2026-08-23&category=ALL` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 49 | owner | GET | `/owner/feipan/odds?gameType=JS_SC` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 50 | owner | GET | `/owner/feipan/points/changes?changeType=ALL&pageNum=1&pageSize=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 51 | owner | GET | `/owner/feipan/op-logs?startDate=2026-08-11&endDate=2026-08-23` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 52 | owner | GET | `/owner/cs/sessions?pageNum=1&pageSize=20` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 53 | owner | GET | `/owner/room/assistants` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 54 | owner | GET | `/owner/room/rebate/batch-preview?presence=ALL` | YES | FAIL | 200 | 500 | 发生未知异常，请联系管理员 |
| 55 | owner | WS | `/ws/v1/owner` | YES | OK | - | - | connected; topics=room:900010001:game:JS_SC,room:900010001:sys; received=10; sample={"event":"CONNECTED","data":{"userId":900001010}} |

## 10. 分类统计（便于排期）

### A. 已对接 + 服务端正常（优先保持）

- `POST /auth/member/login`
- `POST /member/rooms/enter`
- `GET /member/profile`
- `GET /member/rooms/verify?roomCode=679010`
- `GET /member/rooms/history?limit=20`
- `WS /ws/v1/member`
- `POST /auth/portal/login`
- `GET /agent/lottery/info?scene=PROFILE`
- `GET /agent/lottery/info?scene=STATS`
- `GET /agent/accounts?pageNum=1&pageSize=20`
- `GET /agent/reports?startDate=2026-08-11&endDate=2026-08-23`
- `POST /auth/portal/login`
- `WS /ws/v1/owner`

### B. 已对接 + 服务端报错（需后端修）

- `GET /member/rooms/games` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /member/rooms/messages?gameType=JS_SC&limit=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /member/wallet` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /member/wallet/adjustments?pageNum=1&pageSize=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /member/bets?pageNum=1&pageSize=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /member/points/changes?pageNum=1&pageSize=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /member/welfare?type=SUMMARY` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /member/agent-info` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /member/rooms/intro?gameType=JS_SC` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /member/redpacks?status=ALL` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /member/cs/messages?limit=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /agent/credits/changes?pageNum=1&pageSize=20&changeType=ALL` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/notices` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/games` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/games/JS_SC/history?date=2026-08-12` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/games/JS_SC/messages?limit=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/room` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/room/announcement` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/room/members?presence=ALL&pageNum=1&pageSize=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/room/agents?pageNum=1&pageSize=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/room/odds?gameType=JS_SC` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/room/rebate` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/room/op-logs?startDate=2026-08-11&endDate=2026-08-23` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/room/games/settings` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/manage/dashboard` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/manage/applications/up?status=PENDING&pageNum=1&pageSize=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/manage/applications/down?status=PENDING&pageNum=1&pageSize=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/manage/applications/enter?status=PENDING&pageNum=1&pageSize=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/manage/reports/bets?startDate=2026-08-01&endDate=2026-08-23&category=ALL` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/manage/welfare?type=SUMMARY&startDate=2026-08-01&endDate=2026-08-23` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/manage/credits/records?startDate=2026-08-01&endDate=2026-08-23&pageNum=1&pageSize=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/manage/bets?startDate=2026-08-01&endDate=2026-08-23&pageNum=1&pageSize=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/manage/redpacks?pageNum=1&pageSize=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/feipan/status` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/feipan/credit?gameType=JS_SC` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/feipan/reports?startDate=2026-08-01&endDate=2026-08-23&category=ALL` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/feipan/odds?gameType=JS_SC` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/feipan/points/changes?changeType=ALL&pageNum=1&pageSize=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/feipan/op-logs?startDate=2026-08-11&endDate=2026-08-23` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/cs/sessions?pageNum=1&pageSize=20` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/room/assistants` → FAIL biz=500 发生未知异常，请联系管理员
- `GET /owner/room/rebate/batch-preview?presence=ALL` → FAIL biz=500 发生未知异常，请联系管理员

### C. 已对接 + 未实打写操作（需功能测试补验）


### D. 文档缺失 / 未对接（需产品补接口或下线入口）


## 11. 复现命令

```bash
dart run scripts/api_e2e_flow.dart
dart run scripts/gen_audit_md_zh.dart
```

原始 JSON：`scripts/_api_audit/last_probe.json`

---

*说明：`clientWired=YES` 表示 App 已按文档路径调用；`probe=FAIL/ERROR` 表示当前测试环境服务端未正确返回。修复进房 + `/owner/**` + WS:9080 后，用同一脚本可重新出报告。*

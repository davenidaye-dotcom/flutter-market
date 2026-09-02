# 房主接口文档

| 项目 | 内容 |
|---|---|
| 文档版本 | V1.1 |
| 日期 | 2026-08-24 |
| 设计方案 | `docs/执行方案/06_房主端接口设计方案.md` |
| Base URL | `http://207.148.105.182/api/v1`（联调） / `http://localhost:8080`（本机） |
| 鉴权模块 | `bm-account`（portal 登录 / 改密 / 退出） |
| 业务模块 | 拟建 `bm-owner`（+ 共用 lottery/WS） |
| 种子房主 | `owner01` / `Pass1234`（见 `03_member_seed_测试数据.sql`，房间 `679010`） |

---

# 0. 通用约定

## 0.1 鉴权

| 接口 | 是否鉴权 |
|---|---|
| 经营端登录 | **否** |
| **其余全部** | **是**（`loginChannel=OWNER_PORTAL`，`accountType=OWNER` 或 `OWNER_DELEGATE`） |

```http
clientid: flyroom
Authorization: Bearer {accessToken}
```

## 0.2 房间作用域

房主登录后自动绑定自己的 `roomId`（一房一主）；协管绑定 `delegation.room_id`。  
业务接口**无需**再传房间号（调试可用 Header `X-Room-Id`，须属于本人）。

## 0.3 强制改密

登录若 `forceChangePassword=true`，前端跳转改密页；建议仅允许改密与退出，其它 `/api/v1/owner/**` 返回 `MUST_CHANGE_PASSWORD`。

## 0.4 统一响应

```json
{ "code": 200, "msg": "操作成功", "data": {} }
```

## 0.5 curl 变量

```bash
BASE=http://localhost:8080
TOKEN=登录返回的accessToken
```

## 0.6 申请状态枚举

| status | 说明 |
|---|---|
| PENDING | 未审核 |
| APPROVED | 已通过 |
| REJECTED | 已拒绝 |

| applyType | 说明 |
|---|---|
| UP | 上分申请 |
| DOWN | 下分申请 |
| ENTER | 进房审核 |

## 0.7 红包类型

| type | 说明 |
|---|---|
| LUCKY | 拼手气 |
| SCHEDULED | 定时红包 |

## 0.8 飞盘未绑定

相关接口未绑定返回业务码 **`FEIPAN_NOT_BOUND`**，文案建议：`未绑定网盘账户`。

---

# 1. 登录 / 改密 / 退出

## 1.1 经营端登录（房主）

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/auth/portal/login` |
| 鉴权 | **否** |
| 说明 | 与代理共用入口；房主 `accountType=OWNER` |

### 请求 Body

| 字段 | 类型 | 必填 |
|---|---|---|
| username | string | 是 |
| password | string | 是 |
| deviceId | string | 否 |
| clientType | string | 否 |

### 响应 data（房主关注字段）

| 字段 | 类型 | 说明 |
|---|---|---|
| accountId | number | |
| accountType | string | `OWNER` / `OWNER_DELEGATE` |
| loginChannel | string | `OWNER_PORTAL` |
| accessToken | string | |
| forceChangePassword | boolean | **true 则前端进改密页** |
| profile.displayName | string | |
| room.roomId | number | 绑定房间 |
| room.roomCode | string | |
| room.roomName | string | |

```bash
curl -s -X POST "$BASE/api/v1/auth/portal/login" \
  -H "clientid: flyroom" -H "Content-Type: application/json" \
  -d '{"username":"owner01","password":"Pass1234","clientType":"APP"}'
```

## 1.2 修改密码

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/auth/password/change` |
| 鉴权 | **是** |
| 说明 | 首登强制改密用此接口；成功后 `forceChangePassword=false` |

### 请求 Body

| 字段 | 类型 | 必填 |
|---|---|---|
| oldPassword | string | 是 |
| newPassword | string | 是 |

```bash
curl -s -X POST "$BASE/api/v1/auth/password/change" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"oldPassword":"Pass1234","newPassword":"Pass5678"}'
```

## 1.3 退出

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/auth/logout` |
| 鉴权 | **是** |

```bash
curl -s -X POST "$BASE/api/v1/auth/logout" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

---

# 2. 公告栏目

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/owner/notices` |
| 鉴权 | **是** |

### 响应 data（数组元素）

| 字段 | 类型 | 说明 |
|---|---|---|
| noticeId | number | |
| scope | string | `SYSTEM` / `ROOM` |
| content | string | 滚动文案 |
| sort | number | |

```bash
curl -s "$BASE/api/v1/owner/notices" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

---

# 3. 房间游戏列表

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/owner/games` |
| 鉴权 | **是** |

### 响应 data（数组元素）

| 字段 | 类型 | 说明 |
|---|---|---|
| gameType | string | `JS_SC` 等 |
| gameName | string | 极速赛车 |
| enabled | boolean | |
| sort | number | |
| latestIssueNo | string | 当前/最新期号 |
| countdownSeconds | number | 倒计时 |
| statusText | string | 如开奖中 |
| lastIssueNo | string | 上期 |
| lastRanks | number[] | 上期 1~10 名次 |

```bash
curl -s "$BASE/api/v1/owner/games" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

---

# 4. 历史行情 + 消息历史 + WebSocket

## 4.1 开奖历史行情

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/owner/games/{gameType}/history` |
| 鉴权 | **是** |
| 存储 | Mongo `lottery_draw` |

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| date | string | 否 | `yyyy-MM-dd`，默认当天 |
| pageNum | number | 否 | |
| pageSize | number | 否 | |

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| total | number | |
| rows[].issueNo | string | 期号 |
| rows[].openTime | string | |
| rows[].ranks | number[] | 10 个名次 |
| rows[].sumText | string | 如冠亚和文案 |

```bash
curl -s "$BASE/api/v1/owner/games/JS_SC/history?date=2026-08-12" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 4.2 游戏内消息历史

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/owner/games/{gameType}/messages` |
| 鉴权 | **是** |

### Query

| 字段 | 类型 | 必填 |
|---|---|---|
| beforeId | string | 否 |
| limit | number | 否 |

### 响应元素

| 字段 | 类型 | 说明 |
|---|---|---|
| id | string | |
| msgType | string | `CHAT`/`SEAL_WARN`/`SEALED`/`DRAW_RESULT`/… |
| content | string | |
| senderName | string | 如管理员 |
| createdAt | string | |

```bash
curl -s "$BASE/api/v1/owner/games/JS_SC/messages?limit=50" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 4.3 WebSocket

| 项 | 内容 |
|---|---|
| 端点 | `ws://{host}/ws/v1/owner?token={accessToken}` |

### 订阅

```json
{"action":"SUBSCRIBE","topic":"room:900010001:game:JS_SC"}
{"action":"SUBSCRIBE","topic":"room:900010001:sys"}
```

### 推送 event（节选）

| event | 说明 |
|---|---|
| PERIOD_TICK | 倒计时 |
| SEAL_WARN / SEALED | 封盘 |
| DRAW_RESULT | 开奖 |
| CHAT | 管理员消息 |
| APPLY_NOTICE | 新上下分/进房申请 |
| REDPACK_NOTICE | 红包 |

```bash
# 浏览器可打开 $BASE/ws-test.html
# 或使用 websocat / wscat：
# websocat "ws://localhost:8080/ws/v1/owner?token=$TOKEN"
# 连接后发送：
# {"action":"SUBSCRIBE","topic":"room:900010001:game:JS_SC"}
```

---

# 5. 房间管理

## 5.1 房间概要

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/owner/room` |

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| roomId | number | |
| roomCode | string | |
| roomName | string | |
| status | string | |
| hasEnterPassword | boolean | 是否设置进房密码 |

```bash
curl -s "$BASE/api/v1/owner/room" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 5.2 修改房间名称

| 项 | 内容 |
|---|---|
| 方法路径 | `PUT /api/v1/owner/room/name` |

### 请求 Body

| 字段 | 类型 | 必填 |
|---|---|---|
| roomName | string | 是 |

```bash
curl -s -X PUT "$BASE/api/v1/owner/room/name" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"roomName":"天天娱乐"}'
```

## 5.3 房间公告回显

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/owner/room/announcement` |

### 响应 data

| 字段 | 类型 |
|---|---|
| content | string |

```bash
curl -s "$BASE/api/v1/owner/room/announcement" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 5.4 房间公告修改

| 项 | 内容 |
|---|---|
| 方法路径 | `PUT /api/v1/owner/room/announcement` |

### 请求 Body

| 字段 | 类型 | 必填 |
|---|---|---|
| content | string | 是 |

```bash
curl -s -X PUT "$BASE/api/v1/owner/room/announcement" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content":"欢迎来到天天娱乐"}'
```

## 5.5 进房密码（建议补充）

| 项 | 内容 |
|---|---|
| 方法路径 | `PUT /api/v1/owner/room/password` |
| 说明 | **房间进房密码**，非登录密码 |

### 请求 Body

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| enterPassword | string | 否 | 空则清除进房密码 |
| oldEnterPassword | string | 条件 | 已设置时校验 |

```bash
curl -s -X PUT "$BASE/api/v1/owner/room/password" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enterPassword":"123456","oldEnterPassword":""}'
```

## 5.6 房间成员统计

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/owner/room/members` |
| 说明 | 依赖会员进房/离房/下单打点 |

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| keyword | string | 否 | 账号/昵称 |
| presence | string | 否 | `IN`/`OUT`/`ALL` |
| status | string | 否 | 会员状态 |
| pageNum | number | 否 | |
| pageSize | number | 否 | |

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| summary.onlineCount | number | 在线人数 |
| summary.totalCount | number | 成员总数 |
| summary.totalBalance | number | 积分合计 |
| rows[].accountId | number | |
| rows[].username | string | |
| rows[].nickname | string | |
| rows[].presence | string | `IN`/`OUT` |
| rows[].online | boolean | |
| rows[].status | string | 账号状态 |
| rows[].balance | number | 积分 |
| rows[].rebateRatio | number | 返点 |
| rows[].turnover | number | 流水 |
| rows[].winLoss | number | 输赢 |
| rows[].lastEnterAt | string | |
| rows[].lastBetAt | string | |

```bash
curl -s "$BASE/api/v1/owner/room/members?presence=ALL&pageNum=1&pageSize=20" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 5.7 修改成员状态 / 返点（建议补充）

```http
PUT /api/v1/owner/room/members/{accountId}/status
Body: { "status": "NORMAL" | "FROZEN" | "BAN_ENTER" }

PUT /api/v1/owner/room/members/{accountId}/rebate
Body: { "rebateRatio": 0.5 }
```

```bash
curl -s -X PUT "$BASE/api/v1/owner/room/members/900001020/status" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status":"NORMAL"}'

curl -s -X PUT "$BASE/api/v1/owner/room/members/900001020/rebate" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"rebateRatio":0.5}'
```

## 5.8 代理列表

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/owner/room/agents` |

### Query

| 字段 | 类型 | 必填 |
|---|---|---|
| keyword | string | 否 |
| pageNum / pageSize | number | 否 |

### 响应 rows 元素（示例）

| 字段 | 类型 | 说明 |
|---|---|---|
| agentId | number | |
| username | string | |
| displayName | string | |
| level | number | |
| status | string | |
| subordinateCount | number | |

```bash
curl -s "$BASE/api/v1/owner/room/agents?pageNum=1&pageSize=20" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 5.9 赔率设置（房间管理）

### 查询

`GET /api/v1/owner/room/odds?gameType=JS_SC`

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| gameType | string | |
| gameName | string | |
| items[].playCode | string | |
| items[].playName | string | 玩法 |
| items[].odds | number | 赔率 |
| items[].periodLimit | number | 单期限额 |
| items[].minBet | number | 单注最低 |

```bash
curl -s "$BASE/api/v1/owner/room/odds?gameType=JS_SC" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

### 保存

`PUT /api/v1/owner/room/odds`

### 请求 Body

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| gameType | string | 是 | |
| uniformDelta | number | 否 | 统一加减，如 `0.1` / `-0.1` |
| items | array | 否 | 逐条覆盖；与 uniformDelta 可组合 |

```json
{
  "gameType": "JS_SC",
  "uniformDelta": 0.1,
  "items": [
    { "playCode": "TM", "odds": 9.995, "periodLimit": 50000, "minBet": 1 }
  ]
}
```

```bash
curl -s -X PUT "$BASE/api/v1/owner/room/odds" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"gameType":"JS_SC","uniformDelta":0.1,"items":[{"playCode":"TM","odds":9.995,"periodLimit":50000,"minBet":1}]}'
```

## 5.10 回水设置

### 查询

`GET /api/v1/owner/room/rebate`

```bash
curl -s "$BASE/api/v1/owner/room/rebate" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

### 保存

`PUT /api/v1/owner/room/rebate`

Body 字段按产品回水规则定稿（比例、门槛、结算方式等），P0 可用：

| 字段 | 类型 | 说明 |
|---|---|---|
| enabled | boolean | |
| ratio | number | 默认回水比例 |
| minTurnover | number | 门槛 |
| settleMode | string | 如 `DAILY` |

```bash
curl -s -X PUT "$BASE/api/v1/owner/room/rebate" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled":true,"ratio":0.5,"minTurnover":0,"settleMode":"DAILY"}'
```

## 5.11 提前返点

`POST /api/v1/owner/room/rebate/advance`

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| success | boolean | |
| settledAmount | number | 本次结算金额 |
| message | string | |

```bash
curl -s -X POST "$BASE/api/v1/owner/room/rebate/advance" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 5.12 操作日志（房间管理）

`GET /api/v1/owner/room/op-logs`

### Query

| 字段 | 类型 | 必填 |
|---|---|---|
| startDate | string | 否 |
| endDate | string | 否 |
| keyword | string | 否 |
| pageNum / pageSize | number | 否 |

### 响应 rows

| 字段 | 类型 | 说明 |
|---|---|---|
| createdAt | string | |
| operatorName | string | 操作人 |
| operatorId | string | 操作人 id |
| content | string | 如 `密码修改--id:…` |

```bash
curl -s "$BASE/api/v1/owner/room/op-logs?startDate=2026-08-11&endDate=2026-08-12" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 5.13 房间游戏开关（建议补充）

```http
GET /api/v1/owner/room/games/settings
PUT /api/v1/owner/room/games/settings
Body: { "items": [ { "gameType":"JS_SC", "enabled":true, "sort":1 } ] }
```

```bash
curl -s "$BASE/api/v1/owner/room/games/settings" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"

curl -s -X PUT "$BASE/api/v1/owner/room/games/settings" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"items":[{"gameType":"JS_SC","enabled":true,"sort":1}]}'
```

---

# 6. 管理中心

## 6.1 今日总览

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/owner/manage/dashboard` |

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| todayProfitLoss | number | 今日盈亏 |
| upAmount | number | 上分 |
| downAmount | number | 下分 |
| turnover | number | 流水 |
| balance | number | 余额 |
| flyOrderAmount | number | 飞单（占位） |
| flyOrderTurnover | number | 飞单流水（占位） |

```bash
curl -s "$BASE/api/v1/owner/manage/dashboard" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 6.2 上分申请记录

`GET /api/v1/owner/manage/applications/up`

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| day | string | 否 | `TODAY`/`YESTERDAY` 或用日期 |
| startDate / endDate | string | 否 | |
| status | string | 否 | `ALL`/`PENDING`/`APPROVED`/`REJECTED` |
| pageNum / pageSize | number | 否 | |

### 响应 rows（示例）

| 字段 | 类型 |
|---|---|
| applicationId | number |
| applicantName | string |
| applicantUsername | string |
| amount | number |
| status | string |
| createdAt | string |
| reviewedAt | string |

```bash
curl -s "$BASE/api/v1/owner/manage/applications/up?day=TODAY&status=ALL&pageNum=1&pageSize=20" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 6.3 下分申请记录

`GET /api/v1/owner/manage/applications/down`  

参数同 6.2。

```bash
curl -s "$BASE/api/v1/owner/manage/applications/down?day=TODAY&status=PENDING&pageNum=1&pageSize=20" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 6.4 进房审核记录

`GET /api/v1/owner/manage/applications/enter`  

参数同 6.2（无 amount 或 amount 恒为 null）。

```bash
curl -s "$BASE/api/v1/owner/manage/applications/enter?status=PENDING&pageNum=1&pageSize=20" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 6.5 通过 / 拒绝

### 通过

`POST /api/v1/owner/manage/applications/{applicationId}/approve`

### 请求 Body（可选）

| 字段 | 类型 | 必填 |
|---|---|---|
| remark | string | 否 |

### 拒绝

`POST /api/v1/owner/manage/applications/{applicationId}/reject`

| 字段 | 类型 | 必填 |
|---|---|---|
| remark | string | 否 |

```bash
curl -s -X POST "$BASE/api/v1/owner/manage/applications/1001/approve" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"remark":"ok"}'

curl -s -X POST "$BASE/api/v1/owner/manage/applications/1001/reject" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"remark":"资料不全"}'
```

## 6.6 竞猜报表

`GET /api/v1/owner/manage/reports/bets`

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| startDate / endDate | string | 是 | |
| category | string | 否 | `ALL` 或游戏类型 |

### 响应

| 字段 | 类型 | 说明 |
|---|---|---|
| summary.orderCount | number | 笔数 |
| summary.betAmount | number | 下注金额 |
| summary.winLoss | number | 输赢 |
| summary.rebate | number | 退水 |
| rows[].label | string | 级别/用户 |
| rows[].orderCount | number | |
| rows[].betAmount | number | |
| rows[].winLoss | number | |
| rows[].rebate | number | |

```bash
curl -s "$BASE/api/v1/owner/manage/reports/bets?startDate=2026-08-01&endDate=2026-08-12&category=ALL" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 6.7 福利报表

`GET /api/v1/owner/manage/welfare?type=SUMMARY&startDate=&endDate=`

### type

| type | 说明 |
|---|---|
| SUMMARY | 总计+各栏目 |
| COMMISSION | 佣金返点明细 |
| SPECIAL | 特殊返点 |
| INVITE | 邀请返点 |
| REDPACK | 红包 |
| AGENT_REBATE | 代理返佣 |
| RATIO | 返点比例 |

### SUMMARY 字段

同会员福利：total、commissionRebate、specialRebate、inviteRebate、redpack、agentRebate、rebateRatio、rollback、returned、notReturned。

```bash
curl -s "$BASE/api/v1/owner/manage/welfare?type=SUMMARY&startDate=2026-08-01&endDate=2026-08-12" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

### 提前返点

`POST /api/v1/owner/manage/welfare/advance`

```bash
curl -s -X POST "$BASE/api/v1/owner/manage/welfare/advance" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 6.8 上下分记录

`GET /api/v1/owner/manage/credits/records`

### Query

startDate、endDate、pageNum、pageSize

### 响应

| 字段 | 类型 | 说明 |
|---|---|---|
| summary.totalUp | number | 上分合计 |
| summary.totalDown | number | 下分合计 |
| rows[] | array | 明细（时间、类型、积分、对象账号等） |

```bash
curl -s "$BASE/api/v1/owner/manage/credits/records?startDate=2026-08-01&endDate=2026-08-12&pageNum=1&pageSize=20" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 6.9 竞猜记录

`GET /api/v1/owner/manage/bets`

### Query

startDate、endDate、pageNum、pageSize

### 响应

| 字段 | 类型 | 说明 |
|---|---|---|
| summary.totalOrders | number | 总注单 |
| summary.totalBetAmount | number | 总注额 |
| summary.totalRebate | number | 返点合计 |
| summary.totalBonus | number | 红利合计 |
| summary.gameResult | number | 游戏总结果 |
| summary.playerResult | number | 玩家总结果 |
| rows[] | array | 明细 |

```bash
curl -s "$BASE/api/v1/owner/manage/bets?startDate=2026-08-01&endDate=2026-08-12&pageNum=1&pageSize=20" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 6.10 发红包

### 提交（拼手气 / 定时统一入口）

`POST /api/v1/owner/manage/redpacks`

### 请求 Body

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| type | string | 是 | `LUCKY` / `SCHEDULED` |
| totalAmount | number | 是 | 总金额 |
| count | number | 是 | 红包个数 |
| minTurnover | number | 否 | 打码量 ≥ |
| sendAt | string | 定时必填 | 定时发送时间 |
| gameType | string | 否 | 关联游戏，默认房间级可见 |

```bash
curl -s -X POST "$BASE/api/v1/owner/manage/redpacks" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type":"LUCKY","totalAmount":100,"count":10,"minTurnover":0}'
```

### 已发红包列表

`GET /api/v1/owner/manage/redpacks?status=&pageNum=&pageSize=`

```bash
curl -s "$BASE/api/v1/owner/manage/redpacks?pageNum=1&pageSize=20" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

玩家侧通过已有 `GET /api/v1/member/redpacks` 可见并可领取。

---

# 7. 飞盘助手

## 7.1 绑定状态

`GET /api/v1/owner/feipan/status`

### 响应

| 字段 | 类型 | 说明 |
|---|---|---|
| bound | boolean | |
| username | string | 已绑定时脱敏用户名 |
| boundAt | string | |

```bash
curl -s "$BASE/api/v1/owner/feipan/status" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 7.2 绑定 App

`POST /api/v1/owner/feipan/bind`

### 请求 Body

| 字段 | 类型 | 必填 |
|---|---|---|
| username | string | 是 |
| password | string | 是 |

```bash
curl -s -X POST "$BASE/api/v1/owner/feipan/bind" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"app4330","password":"******"}'
```

## 7.3 解绑（建议补充）

`POST /api/v1/owner/feipan/unbind`

```bash
curl -s -X POST "$BASE/api/v1/owner/feipan/unbind" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 7.4 信用资料

`GET /api/v1/owner/feipan/credit?gameType=JS_SC`  

未绑定 → `FEIPAN_NOT_BOUND`。

### 响应（绑定时）

结构同赔率表：玩法 / 赔率 / 单期限额 / 单注最低。

```bash
curl -s "$BASE/api/v1/owner/feipan/credit?gameType=JS_SC" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 7.5 报表查询

`GET /api/v1/owner/feipan/reports?startDate=&endDate=&category=ALL`  

列：级别/用户、笔数、下注金额、输赢、退水。未绑定同上。

```bash
curl -s "$BASE/api/v1/owner/feipan/reports?startDate=2026-08-01&endDate=2026-08-12&category=ALL" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 7.6 赔率配置查询 / 设置

```http
GET /api/v1/owner/feipan/odds?gameType=JS_SC
PUT /api/v1/owner/feipan/odds
```

Body 同房间赔率（含 `uniformDelta`）。未绑定 → `FEIPAN_NOT_BOUND`（或允许本地配置、同步飞盘时再校验，**实现时二选一，默认：读写均需绑定**）。

```bash
curl -s "$BASE/api/v1/owner/feipan/odds?gameType=JS_SC" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"

curl -s -X PUT "$BASE/api/v1/owner/feipan/odds" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"gameType":"JS_SC","uniformDelta":0.1,"items":[{"playCode":"TM","odds":9.995,"periodLimit":50000,"minBet":1}]}'
```

## 7.7 积分账变

`GET /api/v1/owner/feipan/points/changes?changeType=ALL&pageNum=&pageSize=`  

顶栏筛选「全部」。未绑定 → `FEIPAN_NOT_BOUND`。

```bash
curl -s "$BASE/api/v1/owner/feipan/points/changes?changeType=ALL&pageNum=1&pageSize=20" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 7.8 操作日志（飞盘）

`GET /api/v1/owner/feipan/op-logs?startDate=&endDate=`  

未绑定 → `FEIPAN_NOT_BOUND`。  
字段同房间操作日志。

```bash
curl -s "$BASE/api/v1/owner/feipan/op-logs?startDate=2026-08-11&endDate=2026-08-12" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

---

# 8. 错误码（房主常用）

| 业务码 | 说明 |
|---|---|
| 401 | 未登录 |
| MUST_CHANGE_PASSWORD | 须先改密 |
| NOT_OWNER | 非房主/协管 |
| ROOM_NOT_BOUND | 账号未绑定房间 |
| FEIPAN_NOT_BOUND | 未绑定网盘账户 |
| APPLICATION_NOT_FOUND | 申请不存在 |
| APPLICATION_STATUS_INVALID | 非待审不可操作 |
| ODDS_INVALID | 赔率参数非法 |
| REDPACK_PARAM_INVALID | 红包参数非法 |

---

# 9. 联调顺序建议

```bash
BASE=http://localhost:8080

# 1) 登录拿 TOKEN（种子：owner01 / Pass1234）
TOKEN=$(curl -s -X POST "$BASE/api/v1/auth/portal/login" \
  -H "clientid: flyroom" -H "Content-Type: application/json" \
  -d '{"username":"owner01","password":"Pass1234","clientType":"APP"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['accessToken'])")

# 2) 若 forceChangePassword=true 先改密
# curl -s -X POST "$BASE/api/v1/auth/password/change" ...

# 3) notices → games → history/messages
# 4) room / 改名 / 公告 / members / odds / op-logs
# 5) manage/dashboard → 申请列表 → approve/reject
# 6) feipan/bind → credit / reports / odds
# 7) manage/redpacks 发送 → 会员端领取
```

---

# 10. 修订

| 版本 | 说明 |
|---|---|
| V1.0 | 房主端初版契约（对照管理中心/飞盘/发红包等截图） |
| V1.1 | 补齐各接口 curl 示例；联调脚本补 TOKEN 提取 |

---

# 15. 中台联动说明（V1.1）

- 开奖/WS/账本/下注见 `docs/执行方案/07_中台能力设计.md`
- 游戏列表期号倒计时来自采集缓存
- 申请通过（上/下分）会写积分账本
- 发红包后推送 `REDPACK_NOTICE`
- WS 测试：`http://localhost:8080/ws-test.html`

<!-- AUTO_PROBE_START -->

# 11. 远端联调探测（自动生成）

| 项目 | 内容 |
|---|---|
| 生成时间 | `2026-08-24T03:44:32.849519` |
| HTTP Base | `http://207.148.105.182/api/v1` |
| WS Base | `ws://207.148.105.182/ws/v1` |
| 测试账号 | `owner01` / `Pass1234` |
| roomId | `900010001` |
| 探测脚本 | `dart run scripts/api_readonly_audit.dart` |
| 统计 | OK=2 / FAIL=30 / ERROR=0 |

## 11.1 探测明细

| 方法 | 路径 | 探测 | biz | 说明 |
|---|---|---|---:|---|
| GET | `/owner/cs/sessions?pageNum=1&pageSize=20` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/feipan/credit?gameType=JS_SC` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/feipan/odds?gameType=JS_SC` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/feipan/op-logs?startDate=2026-08-11&endDate=2026-08-23` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/feipan/points/changes?changeType=ALL&pageNum=1&pageSize=20` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/feipan/reports?startDate=2026-08-01&endDate=2026-08-23&category=ALL` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/feipan/status` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/games` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/games/JS_SC/history?date=2026-08-12` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/games/JS_SC/messages?limit=20` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/manage/applications/down?status=PENDING&pageNum=1&pageSize=20` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/manage/applications/enter?status=PENDING&pageNum=1&pageSize=20` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/manage/applications/up?status=PENDING&pageNum=1&pageSize=20` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/manage/bets?startDate=2026-08-01&endDate=2026-08-23&pageNum=1&pageSize=20` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/manage/credits/records?startDate=2026-08-01&endDate=2026-08-23&pageNum=1&pageSize=20` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/manage/dashboard` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/manage/redpacks?pageNum=1&pageSize=20` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/manage/reports/bets?startDate=2026-08-01&endDate=2026-08-23&category=ALL` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/manage/welfare?type=SUMMARY&startDate=2026-08-01&endDate=2026-08-23` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/notices` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/room` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/room/agents?pageNum=1&pageSize=20` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/room/announcement` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/room/assistants` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/room/games/settings` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/room/members?presence=ALL&pageNum=1&pageSize=20` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/room/odds?gameType=JS_SC` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/room/op-logs?startDate=2026-08-11&endDate=2026-08-23` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/room/rebate` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| GET | `/owner/room/rebate/batch-preview?presence=ALL` | ❌ 500 | 500 | 发生未知异常，请联系管理员 |
| POST | `/auth/portal/login` | ✅ 正常 | 200 | 操作成功 |
| WS | `/ws/v1/owner` | ✅ 正常 | - | connected; topics=room:900010001:game:JS_SC,room:900010001:sys; received=10; sample={"event":"CONNECTED","data":{"userId":900001010}} |

## 11.2 结论

- **登录**：`POST /auth/portal/login` ✅ 正常（portal token）
- **WebSocket**：`/ws/v1/owner` ✅ 已连通（port 80，非 :9080）
- **业务 GET**：几乎全部 `/owner/**` ❌ biz=500，需后端修复房主域
- **新增接口**：`/owner/cs/sessions*`、`/owner/room/assistants*`、`/owner/room/rebate/batch*` 同样 500

<!-- AUTO_PROBE_END -->


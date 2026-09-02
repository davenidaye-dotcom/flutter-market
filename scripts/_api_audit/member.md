# 会员玩家接口文档

| 项目 | 内容 |
|---|---|
| 文档版本 | V1.0 |
| 日期 | 2026-08-12 |
| 设计方案 | `docs/执行方案/05_会员玩家端接口设计方案.md` |
| Base URL | `http://localhost:8080` |
| 鉴权模块 | `bm-account`（登录/注册/改密/退出） |
| 业务模块 | 拟建 `bm-member` + `bm-lottery`（采集/WS） |
| 种子玩家 | `player01` / `Pass1234`（见 `01_agent_seed_测试数据.sql`） |

---

# 0. 通用约定

## 0.1 鉴权

| 接口 | 是否鉴权 |
|---|---|
| 玩家登录、注册 | **否** |
| **其余全部** | **是**（`loginChannel=MEMBER`，`accountType=PLAYER`） |

```http
clientid: flyroom
Authorization: Bearer {accessToken}
```

未登录或 Token 无效 → `401`。

## 0.2 房间上下文（进房后业务必填）

登录后**必须先进入房间**，再查房间域数据（钱包、注单、红包、客服、介绍等）。

| 方式 | 说明 |
|---|---|
| 推荐 | `POST /rooms/enter` 成功后服务端 Redis 记录当前房间；业务接口自动带上 |
| 备选 | Header：`X-Room-Id: {roomId}`（须与进房校验一致） |

未进房调用房间域接口 → `ROOM_CONTEXT_REQUIRED`。

## 0.3 统一响应包

| 字段 | 类型 | 说明 |
|---|---|---|
| code | number | 200 成功 |
| msg | string | 提示 |
| data | object/array/null | 业务数据 |

## 0.4 curl 变量

```bash
BASE=http://localhost:8080
TOKEN=登录返回的accessToken
ROOM_ID=进房后返回的roomId
```

---

# 1. 登录 / 注册 / 改密 / 退出

## 1.1 玩家登录

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/auth/member/login` |
| 鉴权 | **否** |
| 说明 | 仅 `PLAYER` |

### 请求 Body

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| username | string | 是 | 登录名 |
| password | string | 是 | 密码 |
| deviceId | string | 否 | 设备 ID |
| clientType | string | 否 | `APP` / `WEB` |

### 响应 data（核心字段）

| 字段 | 类型 | 说明 |
|---|---|---|
| accountId | number | 账号 ID |
| accountType | string | `PLAYER` |
| loginChannel | string | `MEMBER` |
| accessToken | string | Token |
| expireIn | number | 过期秒数 |
| profile.displayName | string | 昵称 |
| profile.username | string | 登录名 |
| header.displayId | string | 展示 ID |
| header.balance | number | 大厅余额（未进房可为 0） |

### curl

```bash
curl -s -X POST "$BASE/api/v1/auth/member/login" \
  -H "clientid: flyroom" -H "Content-Type: application/json" \
  -d '{"username":"player01","password":"Pass1234","clientType":"APP"}'
```

## 1.2 玩家注册

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/auth/member/register` |
| 鉴权 | **否** |
| 说明 | 仅注册 PLAYER |

### 请求 Body

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| username | string | 是 | 登录名 |
| password | string | 是 | 密码 |
| nickname | string | 否 | 昵称 |
| inviteCode | string | 否 | 邀请码（若开启） |

## 1.3 修改密码

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/auth/password/change` |
| 鉴权 | **是** |

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

## 1.4 退出登录

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/auth/logout` |
| 鉴权 | **是** |

```bash
curl -s -X POST "$BASE/api/v1/auth/logout" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

---

# 2. 个人资料（改昵称）

## 2.1 查询个人资料

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/member/profile` |
| 鉴权 | **是** |
| 房间上下文 | **否** |

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| accountId | number | 账号 ID |
| username | string | 登录名，如 `abc658` |
| nickname | string | 昵称，如 `小白爱你` |
| displayId | string | 展示 ID |
| avatarUrl | string | 头像 URL |
| bgmEnabled | boolean | 背景音乐开关（可本地，服务端可选持久化） |

```bash
curl -s "$BASE/api/v1/member/profile" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 2.2 修改昵称

| 项 | 内容 |
|---|---|
| 方法路径 | `PUT /api/v1/member/profile/nickname` |
| 鉴权 | **是** |

### 请求 Body

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| nickname | string | 是 | 1~32 字符 |

```bash
curl -s -X PUT "$BASE/api/v1/member/profile/nickname" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"nickname":"小白爱你"}'
```

---

# 3. 房间：校验 / 进入 / 历史 / 游戏列表

> 进房历史写入 `bm_room_enter_history`；当前房间写入 Redis。

## 3.1 校验房间是否存在

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/member/rooms/verify` |
| 鉴权 | **是** |
| 房间上下文 | **否** |

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| roomCode | string | 是 | 6 位房间号 |

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| exists | boolean | 是否存在且可进 |
| roomId | number | 存在时返回 |
| roomCode | string | 房间号 |
| roomName | string | 房间名 |
| coverUrl | string | 封面 |
| status | string | `OPEN` / `DISABLED` / … |
| reason | string | 不可进时原因码 |

```bash
curl -s "$BASE/api/v1/member/rooms/verify?roomCode=679010" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 3.2 进入房间（写历史 + 绑定上下文）

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/member/rooms/enter` |
| 鉴权 | **是** |
| 说明 | 验房通过后调用；**存储用户进房操作** |

### 请求 Body

| 字段 | 类型 | 必填 |
|---|---|---|
| roomCode | string | 是 |

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| roomId | number | 房间 ID |
| roomCode | string | 房间号 |
| roomName | string | 房间名 |
| coverUrl | string | 封面 |
| enteredAt | string | 进入时间 |
| currentRoomBound | boolean | 是否已绑定当前房间 |

```bash
curl -s -X POST "$BASE/api/v1/member/rooms/enter" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"roomCode":"679010"}'
```

## 3.3 历史房间列表

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/member/rooms/history` |
| 鉴权 | **是** |
| 房间上下文 | **否** |

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| limit | number | 否 | 默认 20 |

### 响应 data（数组元素）

| 字段 | 类型 | 说明 |
|---|---|---|
| roomId | number | |
| roomCode | string | 如 `679010` |
| roomName | string | 如 `天天娱乐` |
| coverUrl | string | |
| lastEnteredAt | string | 最近进入时间 |

```bash
curl -s "$BASE/api/v1/member/rooms/history?limit=20" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 3.4 房主游戏列表

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/member/rooms/games` |
| 鉴权 | **是** |
| 房间上下文 | **是**（或传 roomId） |

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| roomId | number | 否 | 不传则用当前绑定房间 |

### 响应 data（数组元素）

| 字段 | 类型 | 说明 |
|---|---|---|
| gameType | string | 如 `JS_SC`（极速赛车）、`AZXY10` |
| gameName | string | 展示名 |
| enabled | boolean | 是否开通 |
| sort | number | 排序 |
| latestIssueNo | string | 最新期号（可缓存） |
| countdownSeconds | number | 倒计时秒（可来自采集缓存） |
| lastRanks | number[] | 上期名次 1~10 |

```bash
curl -s "$BASE/api/v1/member/rooms/games" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

---

# 4. 房间消息历史 + WebSocket

## 4.1 聊天 / 系统消息历史

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/member/rooms/messages` |
| 鉴权 | **是** |
| 房间上下文 | **是** |
| 存储 | Mongo `room_chat_message` |

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| gameType | string | 是 | 如 `JS_SC` |
| beforeId | string | 否 | 游标（上一页最后一条 id） |
| limit | number | 否 | 默认 50 |

### 响应 data（数组元素）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | string | Mongo id |
| msgType | string | `CHAT` / `SEAL_WARN` / `SEALED` / `DRAW_RESULT` / `SYS` |
| content | string | 文本或结构化 JSON 字符串 |
| senderName | string | 如 `管理员` |
| createdAt | string | 时间 |

```bash
curl -s "$BASE/api/v1/member/rooms/messages?gameType=JS_SC&limit=50" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 4.2 WebSocket

| 项 | 内容 |
|---|---|
| 端点 | `ws://{host}/ws/v1/member?token={accessToken}` |
| 鉴权 | Token |
| 说明 | 进房并 `SUBSCRIBE` 后接收期态/开奖/聊天 |

### 客户端 → 服务端

```json
{"action":"SUBSCRIBE","topic":"room:10001:game:JS_SC"}
{"action":"UNSUBSCRIBE","topic":"room:10001:game:JS_SC"}
{"action":"PING"}
```

### 服务端 → 客户端

| event | 说明 |
|---|---|
| PERIOD_TICK | 倒计时/期号刷新 |
| SEAL_WARN | 封盘前 N 秒提醒 |
| SEALED | 封盘线 |
| DRAW_RESULT | 开奖结果（含 ranks、冠亚和等） |
| CHAT | 管理员/系统聊天 |
| REDPACK_NOTICE | 红包通知 |

```json
{
  "topic": "room:10001:game:JS_SC",
  "event": "SEAL_WARN",
  "data": { "issueNo": "5490", "remainSeconds": 10, "text": "距离封盘时间还有10秒" }
}
```

### 订阅优化要点

- 粒度：`room:{roomId}:game:{gameType}`，避免整房广播浪费。
- 多实例：业务发布 → Redis Pub/Sub / MQ → 各 WS 节点本地扇出。
- 连接侧：订阅上限、心跳、鉴权房间一致性校验。

## 4.3 开奖数据采集（内部，非前端直调）

| 用途 | 第三方示例 |
|---|---|
| 最新 | `https://api.api68.com/pks/getLotteryPksInfo.do?lotCode=10037` |
| 历史 | `https://api.api68.com/pks/getPksHistoryList.do?lotCode=10037&date=yyyy-MM-dd` |

- Job 定时拉取 → 规范化 → Mongo `lottery_draw`（幂等）。
- `gameType` ↔ Provider/SPI + `lotCode` 可配置，支持多游戏多平台扩展。
- 写入后发布推送事件，由 WS 按订阅转发。

---

# 5. 红包

## 5.1 红包列表

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/member/redpacks` |
| 鉴权 | **是** |
| 房间上下文 | **是** |

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| status | string | 否 | `AVAILABLE` / `CLAIMED` / `ALL` |

### 响应 data（数组元素）

| 字段 | 类型 | 说明 |
|---|---|---|
| redpackId | number | |
| title | string | |
| remainCount | number | 剩余份数 |
| claimed | boolean | 当前用户是否已领 |
| status | string | `OPEN` / `EMPTY` / `EXPIRED` |
| createdAt | string | |

```bash
curl -s "$BASE/api/v1/member/redpacks?status=AVAILABLE" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 5.2 领取红包

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/member/redpacks/{redpackId}/claim` |
| 鉴权 | **是** |
| 房间上下文 | **是** |

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| success | boolean | |
| amount | number | 领取积分数 |
| message | string | 如「暂无可领取红包」 |

```bash
curl -s -X POST "$BASE/api/v1/member/redpacks/1001/claim" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

---

# 6. 客服

## 6.1 查询客服消息

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/member/cs/messages` |
| 鉴权 | **是** |
| 房间上下文 | **是**（会话归属当前房） |

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| beforeId | string | 否 | 游标 |
| limit | number | 否 | 默认 50 |

### 响应 data（数组元素）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | string | |
| direction | string | `IN` 会员发 / `OUT` 客服回 |
| content | string | |
| createdAt | string | |

```bash
curl -s "$BASE/api/v1/member/cs/messages?limit=50" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 6.2 提交客服消息

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/member/cs/messages` |
| 鉴权 | **是** |
| 房间上下文 | **是** |

### 请求 Body

| 字段 | 类型 | 必填 |
|---|---|---|
| content | string | 是 |

```bash
curl -s -X POST "$BASE/api/v1/member/cs/messages" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content":"你好，请问怎么上下分？"}'
```

---

# 7. 钱包中心

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/member/wallet` |
| 鉴权 | **是** |
| 房间上下文 | **是** |

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| totalAssets | number | 总资产（积分） |
| turnover | number | 流水 |
| rebate | number | 回水 |
| profitLoss | number | 盈亏 |

```bash
curl -s "$BASE/api/v1/member/wallet" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

---

# 8. 上下分记录

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/member/wallet/adjustments` |
| 鉴权 | **是** |
| 房间上下文 | **是** |
| 说明 | 后台人工上下分 |

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| startDate | string | 否 | `yyyy-MM-dd` |
| endDate | string | 否 | `yyyy-MM-dd` |
| pageNum | number | 否 | 默认 1 |
| pageSize | number | 否 | 默认 20 |

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| total | number | 总数 |
| rows[].type | string | 类型文案/码 |
| rows[].createTime | string | 时间 |
| rows[].points | number | 积分增减 |
| rows[].status | string | 状态 |

```bash
curl -s "$BASE/api/v1/member/wallet/adjustments?startDate=2026-08-11&endDate=2026-08-11" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

---

# 9. 福利报表（预留）

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/member/welfare` |
| 鉴权 | **是** |
| 房间上下文 | **是** |
| 说明 | 业务未落地，先占位；`type` 区分结构 |

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| type | string | 是 | 见下表 |
| startDate | string | 否 | |
| endDate | string | 否 | |

### type 枚举

| type | 说明 |
|---|---|
| SUMMARY | 总计 + 各项汇总（佣金/特殊/邀请/红包/代理返佣/返点比例 + 退水已退未退） |
| COMMISSION | 佣金返点 |
| SPECIAL | 特殊返点 |
| INVITE | 邀请返点 |
| REDPACK | 红包 |
| AGENT_REBATE | 代理返佣 |
| RATIO | 返点比例 |

### SUMMARY 响应 data 示例字段

| 字段 | 类型 |
|---|---|
| total | number |
| commissionRebate | number |
| specialRebate | number |
| inviteRebate | number |
| redpack | number |
| agentRebate | number |
| rebateRatio | number |
| rollback | number |
| returned | number |
| notReturned | number |

```bash
curl -s "$BASE/api/v1/member/welfare?type=SUMMARY&startDate=2026-08-11&endDate=2026-08-11" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

---

# 10. 竞猜记录

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/member/bets` |
| 鉴权 | **是** |
| 房间上下文 | **是** |

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| startDate | string | 否 | |
| endDate | string | 否 | |
| pageNum | number | 否 | |
| pageSize | number | 否 | |

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| summary.totalOrders | number | 总注单 |
| summary.totalBetAmount | number | 总注额 |
| summary.totalRebate | number | 返点合计 |
| summary.totalBonus | number | 红利合计 |
| summary.gameResult | number | 游戏总结果 |
| summary.playerResult | number | 玩家总结果 |
| total | number | 明细总数 |
| rows[] | array | 订单明细（期号/玩法/金额/结果等，表落地后定稿） |

```bash
curl -s "$BASE/api/v1/member/bets?startDate=2026-08-11&endDate=2026-08-11" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

---

# 11. 积分变更 / 代理信息 / 房间介绍

## 11.1 积分变更

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/member/points/changes` |
| 鉴权 | **是** |
| 房间上下文 | **是** |

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| issueNo | string | 否 | 期号 |
| pageNum | number | 否 | |
| pageSize | number | 否 | |

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| total | number | |
| pageNum | number | |
| pageSize | number | |
| rows[].issueNo | string | 期号 |
| rows[].changeType | string | 变更类型 |
| rows[].points | number | 变更积分 |
| rows[].balanceAfter | number | 变更后余额 |
| rows[].createTime | string | |

```bash
curl -s "$BASE/api/v1/member/points/changes?issueNo=&pageNum=1&pageSize=20" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 11.2 代理信息

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/member/agent-info` |
| 鉴权 | **是** |
| 房间上下文 | **是** |

### Query

| 字段 | 类型 | 必填 |
|---|---|---|
| startDate | string | 否 |
| endDate | string | 否 |

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| summary.subordinateTurnover | number | 旗下流水 |
| summary.totalCommission | number | 返佣总金额 |
| summary.paidCommission | number | 已返佣 |
| summary.unpaidCommission | number | 未返佣 |
| rows[].label | string | 代理报表行 |
| rows[].subordinateTurnover | number | |
| rows[].rebateRatio | number | 回水比例 |
| rows[].paidCommission | number | |
| rows[].unpaidCommission | number | |

```bash
curl -s "$BASE/api/v1/member/agent-info?startDate=2026-08-11&endDate=2026-08-11" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

## 11.3 房间介绍

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/member/rooms/intro` |
| 鉴权 | **是** |
| 房间上下文 | **是** |

### Query

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| gameType | string | 是 | 如 `JS_SC` |

### 响应 data

| 字段 | 类型 | 说明 |
|---|---|---|
| gameType | string | |
| gameName | string | 如 `极速赛车` |
| content | string | 规则正文（Markdown/纯文本） |
| contentHtml | string | 可选 HTML |

```bash
curl -s "$BASE/api/v1/member/rooms/intro?gameType=JS_SC" \
  -H "clientid: flyroom" -H "Authorization: Bearer $TOKEN"
```

---

# 12. 错误码（会员常用）

| code / 业务码 | 说明 |
|---|---|
| 401 | 未登录 / Token 无效 |
| ROOM_CONTEXT_REQUIRED | 未进入房间 |
| ROOM_NOT_FOUND | 房间不存在 |
| ROOM_DISABLED | 房间不可用 |
| NICKNAME_INVALID | 昵称不合法 |
| REDPACK_EMPTY | 暂无可领取红包 |
| REDPACK_ALREADY_CLAIMED | 已领取 |
| WELFARE_TYPE_INVALID | 福利 type 非法 |

---

# 13. 联调顺序建议

1. 登录 `player01` → 拿 Token  
2. `profile` / 改昵称  
3. `rooms/verify` → `rooms/enter` → `rooms/history` → `rooms/games`  
4. 再调钱包 / 注单 / 红包 / 客服 / 介绍等房间域接口  
5. WS：连接 → `SUBSCRIBE room:{id}:game:JS_SC` → 观察推送  

---

# 14. 修订

| 版本 | 说明 |
|---|---|
| V1.0 | 会员玩家端初版契约（对照大厅/房间/钱包等截图） |


---

# 15. 下注（中台 C）

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/member/bets` |
| 鉴权 | 是 |
| 房间上下文 | 是 |
| 设计 | `docs/执行方案/07_中台能力设计.md` |

### 请求 Body

```json
{
  "gameType": "JS_SC",
  "issueNo": "可选，默认当前期",
  "items": [
    { "playCode": "GYH_11", "amount": 10 },
    { "playCode": "TM-5", "amount": 10 },
    { "playCode": "LM-BIG", "amount": 10 }
  ]
}
```

### playCode 说明

见 `07_中台能力设计.md`（特码/两面/冠亚和截图项/名次/龙虎）。

### 响应

```json
{ "code": 200, "data": { "orderIds": [1,2] } }
```

### 常见错误

`SEALED` / `BALANCE_NOT_ENOUGH` / `ISSUE_MISMATCH` / `PLAY_INVALID`

---

# 16. WebSocket（中台 A）

- 测试页：`http://localhost:8080/ws-test.html`
- 端点：`ws://localhost:8080/ws/v1/flyroom?token={accessToken}`
- 订阅：`{"action":"SUBSCRIBE","topic":"room:{roomId}:game:JS_SC"}`

# 房主 App：房间成员 / 房间代理 — 缺失接口（后端补齐）

App 已按下列路径对接。现有接口不够的标 **缺**。

前缀：`/api/v1`，鉴权房主 token。

## 已有（App 在用）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/owner/room/members` | 成员列表。App 新增 query `memberType=ALL\|ONLINE\|ROBOT\|FAKE` |
| PUT | `/owner/room/members/{accountId}/status` | `NORMAL` / `FROZEN` / `BAN_ENTER` / `DISABLED` |
| PUT | `/owner/room/members/{accountId}/rebate` | body 字段 **`rebateRatio`**（旧客户端曾传 `rebate`） |
| GET | `/owner/room/agents` | 代理列表。App 传 `keyword` |

## 列表需要补的响应字段

`GET /owner/room/members` 的 `summary` 请增加：

| 字段 | 说明 |
|------|------|
| totalTurnover | 总流水 |
| totalWinLoss | 总输赢 |
| totalRebate | 彩票回水 |
| realPlayerPoints | 真实玩家总积分 |
| robotCount / fakeCount | 机器人、假人数量 |

`rows[]` 请增加：

| 字段 | 说明 |
|------|------|
| remark | 房间备注 |
| isAgent | 是否代理 |
| isRobot | 是否机器人 |
| isFake | 是否假人 |
| avatar | 头像 URL（可空） |
| commissionRatio | 代理返佣比例 |

`GET /owner/room/agents` 的 `rows[]` 请增加：`accountId`、`nickname`、`remark`、`subordinateCount`、`subordinateTurnover`、`status`。

## 缺失接口（App 已调用，后端需实现）

| 方法 | 路径 | Body | 页面 |
|------|------|------|------|
| GET | `/owner/room/members/{accountId}` | — | 玩家信息 |
| PUT | `/owner/room/members/{accountId}/remark` | `{ "remark": "" }` | 设置备注 |
| POST | `/owner/room/members/{accountId}/credits` | `{ "direction":"UP"\|"DOWN", "amount": 100 }` | 上分 / 下分 |
| POST | `/owner/room/members/{accountId}/agent` | `{ "commissionRatio": 1.5 }` | 设置代理（%） |
| DELETE | `/owner/room/members/{accountId}/agent` | — | 取消代理 |
| PUT | `/owner/room/members/{accountId}/fake` | `{ "fake": true }` | 标记假人 |
| DELETE | `/owner/room/members/{accountId}` | — | 删除玩家 |
| POST | `/owner/room/members/robots` | `{ "nickname":"", "count":1 }` | 新增机器人（字段可再定） |
| GET | `/owner/room/agents/{accountId}/downlines` | query `keyword` | 下线管理 |
| POST | `/owner/room/agents/{accountId}/downlines` | `{ "memberAccountId": 123 }` | 添加下线 |

封禁走已有 `PUT .../status`，`status=BAN_ENTER`。

## 同房他人下注（会员端，不是房主页）

盘口下注 App 已同时传 `items` + `command`。后端 `POST /member/bets` 在 **有 items 时也要广播 CHAT**（现在只在 command 非空且无 items 时广播的话，别人看不到盘口单）。

历史拉取：`GET /member/rooms/messages` 的 `CHAT` 需带 `senderName`、`content`（指令原文）、`issueNo`、`orderId`。

可选增强（竞品「机器人投注成功」卡，当前没有）：

| 方法/事件 | 说明 |
|-----------|------|
| WS `BET_RECEIPT` 或消息 `msgType=BET_RECEIPT` | `@昵称`、期号、总金额、玩法明细 |

没有这条之前，App 只展示指令气泡，不伪造确认卡。

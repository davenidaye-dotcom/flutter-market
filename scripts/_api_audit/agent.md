# 代理接口文档

| 项目 | 内容 |
|---|---|
| 文档版本 | V1.2 |
| 日期 | 2026-08-12 |
| 设计方案 | `docs/执行方案/04_代理端接口设计方案.md` |
| Base URL | `http://localhost:8080` |
| 测试库 | PostgreSQL `user_SQT7TZ` |
| 种子数据 | `script/sql/flyroom/pgsql/01_agent_seed_测试数据.sql`（密码均为 `Pass1234`） |

---

# 0. 通用约定

## 0.1 鉴权

| 接口 | 是否鉴权 |
|---|---|
| 登录、注册 | **否** |
| **其余全部** | **是** |

登录后请求必须带：

```http
clientid: flyroom
Authorization: Bearer {accessToken}
```

未登录或 Token 无效 → HTTP/业务 `401`。

## 0.2 统一响应包

| 字段 | 类型 | 说明 |
|---|---|---|
| code | number | 200 成功；401 未登录；其它业务失败 |
| msg | string | 提示文案 |
| data | object/array/null | 业务数据 |

```json
{ "code": 200, "msg": "操作成功", "data": {} }
```

## 0.3 变量说明（下文 curl）

```bash
BASE=http://localhost:8080
TOKEN=登录返回的accessToken
```

---

# 1. 登录 / 注册

## 1.1 房主登录（代理与房主共用）

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/auth/portal/login` |
| 鉴权 | **否** |
| 说明 | 代理、房主等同页；一个接口 |

### 请求 Header

| 名称 | 必填 | 说明 |
|---|---|---|
| clientid | 是 | 固定 `flyroom` |
| Content-Type | 是 | `application/json` |

### 请求 Body

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| username | string | 是 | 登录名 |
| password | string | 是 | 密码 |
| deviceId | string | 否 | 设备 ID |
| clientType | string | 否 | `APP` / `WEB` |

### 响应 data 字段

| 字段 | 类型 | 说明 |
|---|---|---|
| accountId | number | 账号 ID |
| accountType | string | 如 `AGENT` |
| loginChannel | string | 固定 `OWNER_PORTAL` |
| effectiveStatus | string | `NORMAL` 等 |
| sessionMode | string | `NORMAL` / `READ_ONLY` / `EXPERIENCE` |
| accessToken | string | 后续鉴权 Token |
| expireIn | number | 过期秒数 |
| clientId | string | `flyroom` |
| profile.agentLevel | number | 代理等级，非代理可为 null |
| profile.agentNodeId | number | 代理节点 ID |
| profile.principalAccountId | number | 主账号（协管时） |
| profile.delegated | boolean | 是否协管 |
| profile.displayName | string | 显示名 |
| header.displayId | string | 顶栏 ID |
| header.balance | number | 余额（暂无额度表时为 0） |
| header.subordinateBalance | number | 下级余额 |

### 响应示例

```json
{
  "code": 200,
  "msg": "操作成功",
  "data": {
    "accountId": 900001001,
    "accountType": "AGENT",
    "loginChannel": "OWNER_PORTAL",
    "effectiveStatus": "NORMAL",
    "sessionMode": "NORMAL",
    "accessToken": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9...",
    "expireIn": 86400,
    "clientId": "flyroom",
    "profile": {
      "agentLevel": 1,
      "agentNodeId": 900002001,
      "principalAccountId": 900001001,
      "delegated": false,
      "experience": false,
      "displayName": "一级代理658"
    },
    "header": {
      "displayId": "900001001",
      "balance": 0,
      "subordinateBalance": 0
    },
    "permissions": ["portal:agent"],
    "dataScopeHint": "AGENT_SUBTREE"
  }
}
```

### curl

```bash
curl -s -X POST "$BASE/api/v1/auth/portal/login" \
  -H "Content-Type: application/json" \
  -H "clientid: flyroom" \
  -d '{"username":"abcd658","password":"Pass1234","clientType":"APP"}'
```

---

## 1.2 玩家注册（仅玩家）

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/auth/member/register` |
| 鉴权 | **否** |
| 说明 | 只能注册 PLAYER |

### 请求 Body

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| username | string | 是 | 4–32，字母开头 |
| password | string | 是 | 6–64 |
| displayName | string | 否 | 昵称 |

### 响应 data 字段

与登录成功结构相同（当前实现会自动登录并返回 `accessToken`），`accountType` 固定为 `PLAYER`，`loginChannel` 为 `MEMBER`。

### 响应示例

```json
{
  "code": 200,
  "msg": "操作成功",
  "data": {
    "accountId": 190001234567890,
    "accountType": "PLAYER",
    "loginChannel": "MEMBER",
    "effectiveStatus": "NORMAL",
    "sessionMode": "NORMAL",
    "accessToken": "eyJ...",
    "expireIn": 86400,
    "clientId": "flyroom",
    "profile": {
      "delegated": false,
      "experience": false,
      "displayName": "player_new01",
      "principalAccountId": 190001234567890
    }
  }
}
```

### curl

```bash
curl -s -X POST "$BASE/api/v1/auth/member/register" \
  -H "Content-Type: application/json" \
  -H "clientid: flyroom" \
  -d '{"username":"player_new01","password":"Pass1234","displayName":"新玩家"}'
```

---

# 2. 个人信息 / 收付统计

一个接口；`scene` 区分模块，`type` 区分彩票产品。**需鉴权。**

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/agent/lottery/info` |
| 鉴权 | **是** |

### Query

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| scene | string | 是 | `PROFILE` 个人信息；`STATS` 收付统计 |
| type | string | 否 | 产品编码，默认第一个；如 `JS_SC` |

### 响应 data 公共字段

| 字段 | 类型 | 说明 |
|---|---|---|
| scene | string | 回显 |
| type | string | 当前产品编码 |
| typeName | string | 当前产品名 |
| games | array | Tab 列表 `{type,typeName}` |
| header | object | 顶栏 displayId/balance/subordinateBalance |

### scene=PROFILE 额外字段

| 字段 | 类型 | 说明 |
|---|---|---|
| items | array | 玩法行 |
| items[].playCode | string | 玩法编码 |
| items[].playName | string | 玩法名（特码/两面…） |
| items[].odds | number | 赔率 |
| items[].periodLimit | number | 单期限额 |
| items[].minBet | number | 单注最低 |

### scene=STATS 额外字段

| 字段 | 类型 | 说明 |
|---|---|---|
| issueNo | string | 期号 |
| status | string | `OPEN`/`CLOSED`/`SETTLED` |
| statusText | string | 如「封盘中」 |
| countdownSeconds | number | 倒计时秒 |
| columns | array | 冠军/亚军等列 |
| columns[].columnCode | string | |
| columns[].columnName | string | |
| columns[].cells | array | 格子 |
| columns[].cells[].playCode | string | |
| columns[].cells[].playName | string | 1–10/大/小… |
| columns[].cells[].shareAmount | number | 占成金额 |
| columns[].cells[].betAmount | number | 下注金额 |

### 响应示例（PROFILE）

```json
{
  "code": 200,
  "msg": "操作成功",
  "data": {
    "scene": "PROFILE",
    "type": "JS_SC",
    "typeName": "极速赛车",
    "games": [
      { "type": "JS_SC", "typeName": "极速赛车" },
      { "type": "AZXY10", "typeName": "澳洲幸运10" }
    ],
    "header": {
      "displayId": "900001001",
      "balance": 0,
      "subordinateBalance": 0
    },
    "items": [
      {
        "playCode": "TM",
        "playName": "特码",
        "odds": 9.995,
        "periodLimit": 50000,
        "minBet": 1
      },
      {
        "playCode": "LM",
        "playName": "两面",
        "odds": 1.998,
        "periodLimit": 50000,
        "minBet": 1
      }
    ]
  }
}
```

### 响应示例（STATS）

```json
{
  "code": 200,
  "msg": "操作成功",
  "data": {
    "scene": "STATS",
    "type": "JS_SC",
    "typeName": "极速赛车",
    "games": [{ "type": "JS_SC", "typeName": "极速赛车" }],
    "header": {
      "displayId": "900001001",
      "balance": 0,
      "subordinateBalance": 0
    },
    "issueNo": "5486",
    "status": "CLOSED",
    "statusText": "封盘中",
    "countdownSeconds": 1,
    "columns": [
      {
        "columnCode": "CHAMPION",
        "columnName": "冠军",
        "cells": [
          {
            "playCode": "N1",
            "playName": "1",
            "shareAmount": 0,
            "betAmount": 0
          }
        ]
      }
    ]
  }
}
```

### curl

```bash
# 个人信息
curl -s "$BASE/api/v1/agent/lottery/info?scene=PROFILE&type=JS_SC" \
  -H "clientid: flyroom" \
  -H "Authorization: Bearer $TOKEN"

# 收付统计
curl -s "$BASE/api/v1/agent/lottery/info?scene=STATS&type=JS_SC" \
  -H "clientid: flyroom" \
  -H "Authorization: Bearer $TOKEN"
```

---

# 3. 账户管理

## 3.1 查询

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/agent/accounts` |
| 鉴权 | **是** |

### Query

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| keyword | string | 否 | 用户名/昵称模糊 |
| pageNum | number | 否 | 默认 1 |
| pageSize | number | 否 | 默认 20 |

### 响应 data 字段

| 字段 | 类型 | 说明 |
|---|---|---|
| header | object | 顶栏 |
| total | number | 总条数 |
| pageNum | number | |
| pageSize | number | |
| rows | array | 列表 |
| rows[].accountId | number | |
| rows[].username | string | |
| rows[].displayName | string | |
| rows[].accountType | string | `AGENT`/`AGENT_MEMBER`… |
| rows[].accountTypeName | string | 中文名 |
| rows[].agentLevel | number/null | 会员为 null |
| rows[].status | string | |
| rows[].balance | number | 暂无额度表时 0 |
| rows[].createdAt | string | ISO 时间 |

### 响应示例

```json
{
  "code": 200,
  "msg": "操作成功",
  "data": {
    "header": {
      "displayId": "900001001",
      "balance": 0,
      "subordinateBalance": 0
    },
    "total": 2,
    "pageNum": 1,
    "pageSize": 20,
    "rows": [
      {
        "accountId": 900001002,
        "username": "agent_l2",
        "displayName": "二级代理",
        "accountType": "AGENT",
        "accountTypeName": "代理",
        "agentLevel": 2,
        "status": "NORMAL",
        "balance": 0,
        "createdAt": "2026-08-12T00:00:00Z"
      },
      {
        "accountId": 900001004,
        "username": "member001",
        "displayName": "会员001",
        "accountType": "AGENT_MEMBER",
        "accountTypeName": "会员",
        "agentLevel": null,
        "status": "NORMAL",
        "balance": 0,
        "createdAt": "2026-08-12T00:00:00Z"
      }
    ]
  }
}
```

### curl

```bash
curl -s "$BASE/api/v1/agent/accounts?pageNum=1&pageSize=20&keyword=" \
  -H "clientid: flyroom" \
  -H "Authorization: Bearer $TOKEN"
```

---

## 3.2 新增

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/agent/accounts` |
| 鉴权 | **是** |
| 限制 | 当前代理等级=5 且 `type=AGENT` → `AGENT_LEVEL_MAX` |

### 请求 Body

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| type | string | 是 | `AGENT` / `AGENT_MEMBER` / `AGENT_DELEGATE` |
| parentAgentId | number | 否 | 默认当前代理节点 |
| username | string | 是 | 登录名 |
| displayName | string | 否 | |
| password | string | 是 | |
| confirmPassword | string | 是 | 须与 password 一致 |

### 响应 data 字段

| 字段 | 类型 | 说明 |
|---|---|---|
| accountId | number | 新账号 ID |
| username | string | |
| accountType | string | |
| agentLevel | number/null | 新代理等级；会员 null |

### 响应示例（成功）

```json
{
  "code": 200,
  "msg": "操作成功",
  "data": {
    "accountId": 900001099,
    "username": "member_new",
    "accountType": "AGENT_MEMBER",
    "agentLevel": null
  }
}
```

### 响应示例（五级开代理失败）

```json
{
  "code": 500,
  "msg": "已是五级代理，不能再新增代理账户",
  "data": null
}
```

（实现可将稳定码放在异常 detailMessage：`AGENT_LEVEL_MAX`）

### curl

```bash
# 一级代理开会员
curl -s -X POST "$BASE/api/v1/agent/accounts" \
  -H "Content-Type: application/json" \
  -H "clientid: flyroom" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "type":"AGENT_MEMBER",
    "username":"member_new",
    "displayName":"新会员",
    "password":"Pass1234",
    "confirmPassword":"Pass1234"
  }'

# 五级账号测限制（先用 agent_l5 登录拿 TOKEN5）
curl -s -X POST "$BASE/api/v1/agent/accounts" \
  -H "Content-Type: application/json" \
  -H "clientid: flyroom" \
  -H "Authorization: Bearer $TOKEN5" \
  -d '{
    "type":"AGENT",
    "username":"agent_l6_should_fail",
    "password":"Pass1234",
    "confirmPassword":"Pass1234"
  }'
```

---

# 4. 报表查询

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/agent/reports` |
| 鉴权 | **是** |

### Query

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| startDate | string | 是 | `yyyy-MM-dd` |
| endDate | string | 是 | `yyyy-MM-dd` |
| type | string | 否 | 产品；空=全部 |
| pageNum | number | 否 | |
| pageSize | number | 否 | |

### 响应 data 字段

| 字段 | 类型 | 说明 |
|---|---|---|
| header | object | 顶栏 |
| summary.betAmount | number | 下注 |
| summary.validAmount | number | 有效 |
| summary.winLoss | number | 盈亏 |
| summary.rebate | number | 返水 |
| summary.shareAmount | number | 占成 |
| total | number | |
| pageNum | number | |
| pageSize | number | |
| rows | array | 明细（列后续扩展） |

### 响应示例

```json
{
  "code": 200,
  "msg": "操作成功",
  "data": {
    "header": {
      "displayId": "900001001",
      "balance": 0,
      "subordinateBalance": 0
    },
    "summary": {
      "betAmount": 0,
      "validAmount": 0,
      "winLoss": 0,
      "rebate": 0,
      "shareAmount": 0
    },
    "total": 0,
    "pageNum": 1,
    "pageSize": 20,
    "rows": []
  }
}
```

### curl

```bash
curl -s "$BASE/api/v1/agent/reports?startDate=2026-08-11&endDate=2026-08-11&type=" \
  -H "clientid: flyroom" \
  -H "Authorization: Bearer $TOKEN"
```

---

# 5. 额度变动

| 项 | 内容 |
|---|---|
| 方法路径 | `GET /api/v1/agent/credits/changes` |
| 鉴权 | **是** |

### Query

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| startDate | string | 是 | |
| endDate | string | 是 | |
| changeType | string | 否 | `ALL`/`TO_SUB_UP`/`TO_SUB_DOWN`/`FROM_PARENT_UP`/`FROM_PARENT_DOWN` |
| pageNum | number | 否 | |
| pageSize | number | 否 | |

### 响应 data 字段

| 字段 | 类型 | 说明 |
|---|---|---|
| header | object | 顶栏 |
| summary.creditToSubUp | number | 给下级上分 |
| summary.creditToSubDown | number | 给下级下分 |
| summary.creditFromParentUp | number | 上级上分 |
| summary.creditFromParentDown | number | 上级下分 |
| total | number | |
| pageNum | number | |
| pageSize | number | |
| rows | array | 流水 |
| rows[].changeId | number | |
| rows[].changeType | string | |
| rows[].changeTypeName | string | |
| rows[].amount | number | |
| rows[].counterpartyUsername | string | 对手账号 |
| rows[].remark | string | |
| rows[].createdAt | string | |

### 响应示例

```json
{
  "code": 200,
  "msg": "操作成功",
  "data": {
    "header": {
      "displayId": "900001001",
      "balance": 0,
      "subordinateBalance": 0
    },
    "summary": {
      "creditToSubUp": 0,
      "creditToSubDown": 0,
      "creditFromParentUp": 0,
      "creditFromParentDown": 0
    },
    "total": 0,
    "pageNum": 1,
    "pageSize": 20,
    "rows": []
  }
}
```

### curl

```bash
curl -s "$BASE/api/v1/agent/credits/changes?startDate=2026-08-11&endDate=2026-08-11&changeType=ALL" \
  -H "clientid: flyroom" \
  -H "Authorization: Bearer $TOKEN"
```

---

# 6. 密码修改

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/auth/password/change` |
| 鉴权 | **是** |
| 规则 | 先校验旧密码，再写入新密码；成功后建议 Token 失效 |

### 请求 Body

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| oldPassword | string | 是 | 旧密码 |
| newPassword | string | 是 | 新密码 |
| confirmPassword | string | 是 | 须等于 newPassword |

### 响应 data 字段

| 字段 | 类型 | 说明 |
|---|---|---|
| data | null | 成功无业务体 |

### 响应示例（成功）

```json
{
  "code": 200,
  "msg": "操作成功",
  "data": null
}
```

### 响应示例（旧密码错误）

```json
{
  "code": 500,
  "msg": "旧密码错误",
  "data": null
}
```

### curl

```bash
curl -s -X POST "$BASE/api/v1/auth/password/change" \
  -H "Content-Type: application/json" \
  -H "clientid: flyroom" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "oldPassword":"Pass1234",
    "newPassword":"Pass5678",
    "confirmPassword":"Pass5678"
  }'
```

---

# 7. 安全退出

| 项 | 内容 |
|---|---|
| 方法路径 | `POST /api/v1/auth/logout` |
| 鉴权 | **是** |

### 请求

无 Body（或空 JSON）。

### 响应 data 字段

| 字段 | 类型 | 说明 |
|---|---|---|
| data | null | |

### 响应示例

```json
{
  "code": 200,
  "msg": "退出成功",
  "data": null
}
```

### curl

```bash
curl -s -X POST "$BASE/api/v1/auth/logout" \
  -H "clientid: flyroom" \
  -H "Authorization: Bearer $TOKEN"
```

---

# 8. 联调顺序建议

```bash
# 1) 导入种子
# psql ... -f script/sql/flyroom/pgsql/01_agent_seed_测试数据.sql

# 2) 登录
TOKEN=$(curl -s -X POST "$BASE/api/v1/auth/portal/login" \
  -H "Content-Type: application/json" -H "clientid: flyroom" \
  -d '{"username":"abcd658","password":"Pass1234"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['accessToken'])")

# 3) 带 TOKEN 调账户列表 / 其它需鉴权接口
```

---

# 9. 修订记录

| 版本 | 说明 |
|---|---|
| V1.1 | 侧栏合并 |
| V1.2 | 全接口补响应字段、示例、curl；除登录注册外全鉴权 |

# 缺失接口对接与联调报告

> 规范来源：`D:\product\bet\FlyRoom缺失接口规范.md`  
> 探测时间：见 `last_missing_probe.json`  
> 命令：`dart run scripts/api_e2e_missing.dart --base=http://207.148.105.182/api/v1 --ws=ws://207.148.105.182:9080/ws/v1`

## 联调约定（已按此执行）

1. **会员房间域**：先 `POST /member/rooms/enter`（roomCode=`679010`）→ 获得 `roomId=900010001` → 再调房间内接口  
2. **路径前缀**：`$BASE/api/v1`  
3. **房主 Token**：`POST /auth/portal/login`（owner01）  
4. **WS**：`ws://{host}/ws/v1/member?token=` / `owner`；房主额外订阅 `room:{roomId}:sys`

## 客户端对接状态（21 个 HTTP）

| # | 接口 | Repository / 页面 | 客户端 |
|---:|---|---|---|
| 1 | POST `/member/wallet/applications` | `WalletRepository.submitApplication` / `chat_bet_page` 上分下分 | ✅ 已对接 |
| 2 | GET `/member/wallet/applications/pending` | `WalletRepository.getPendingApplication` | ✅ 已对接 |
| 3 | GET `/member/wallet/applications` | `WalletRepository.getApplications` / `apply_records_page` | ✅ 已对接 |
| 4 | POST `/member/wallet/applications/{id}/cancel` | `WalletRepository.cancelApplication` | ✅ 已对接 |
| 5 | POST `/member/rooms/enter-applications` | `MemberRepository.submitEnterApplication` | ✅ 已对接（Repository） |
| 6 | GET `/member/rooms/enter-applications/pending` | `MemberRepository.getPendingEnterApplication` | ✅ 已对接（Repository） |
| 7 | GET `/member/games/{gameType}/history` | `LotteryRepository.getDrawHistory` / 聊天历史 | ✅ 已对接 |
| 8 | GET `/member/games/{gameType}/trends/long-dragon` | `LotteryRepository.getLongDragon` / 聊天长龙 | ✅ 已对接 |
| 9 | GET `/member/notices` | `MemberRepository.getNotices` / `room_repository.getAnnouncements` | ✅ 已对接 |
| 10 | GET `/member/rooms/announcement` | `MemberRepository.getRoomAnnouncement` | ✅ 已对接 |
| 11 | GET `/owner/cs/sessions` | `OwnerRepository.getCsSessions` / `host_service_page` | ✅ 已对接 |
| 12 | GET `/owner/cs/sessions/{accountId}/messages` | `OwnerRepository.getCsMessages` | ✅ 已对接 |
| 13 | POST `/owner/cs/sessions/{accountId}/messages` | `OwnerRepository.sendCsReply` | ✅ 已对接 |
| 14 | GET `/owner/room/assistants` | `OwnerRepository.getAssistants` / `host_assistants_page` | ✅ 已对接 |
| 15 | POST `/owner/room/assistants` | `OwnerRepository.createAssistant` | ✅ 已对接 |
| 16 | PUT `/owner/room/assistants/{id}` | `OwnerRepository.updateAssistant` | ✅ 已对接 |
| 17 | DELETE `/owner/room/assistants/{id}` | `OwnerRepository.deleteAssistant` | ✅ 已对接 |
| 18 | GET `/owner/room/rebate/batch-preview` | `OwnerRepository.getRebateBatchPreview` / `host_batch_rebate_page` | ✅ 已对接 |
| 19 | POST `/owner/room/rebate/batch` | `OwnerRepository.batchSetRebate` | ✅ 已对接 |
| 20 | POST `/owner/room/rebate/batch-advance` | `OwnerRepository.batchAdvanceRebate` | ✅ 已对接 |
| — | WS `room:{id}:sys` | `lottery_live_provider` 房主订阅 | ✅ 已对接 |

## 远端联调结果（207.148.105.182）

| 结果 | 数量 |
|---|---:|
| OK | 4（登录 + 进房 + 房主登录 + 进房申请查询） |
| FAIL | 14（多为 biz=500） |
| ERROR | 2（WS 超时） |
| SKIP | 3（无 applicationId / 无协管 / 无成员） |

### 正常

- `POST /auth/member/login`
- `POST /member/rooms/enter` → **roomId=900010001**
- `POST /auth/portal/login`
- `GET /member/rooms/enter-applications/pending`（非审核房，业务正常）

### 业务可预期失败

- `POST /member/rooms/enter-applications` → **500 该房间无需进房申请**（679010 非 AUDIT 模式，路径正确）

### 服务端待实现/修复（biz=500 未知异常）

- 全部 `/member/wallet/applications*`
- `/member/games/JS_SC/history`
- `/member/games/JS_SC/trends/long-dragon`
- `/member/notices`、`/member/rooms/announcement`
- 全部 `/owner/cs/*`、`/owner/room/assistants*`、`/owner/room/rebate/batch*`
- `GET /owner/room`

### WebSocket

- `ws://207.148.105.182:9080/ws/v1/member|owner` → **10s 超时**（需后端开放 :9080 或改网关）

### 本地 localhost:8080

- 未启动服务，登录/进房失败；请在本机 betmarket 启动后执行：  
  `dart run scripts/api_e2e_missing.dart --base=http://127.0.0.1:8080/api/v1 --ws=ws://127.0.0.1:8080/ws/v1`

## 其它修复

- `AuthRepository.changePassword` 补 `confirmPassword`
- `ApiClient` 增加 `delete`（协管删除）

## 复现

```bash
dart run scripts/api_e2e_missing.dart --base=http://207.148.105.182/api/v1 --ws=ws://207.148.105.182:9080/ws/v1
```

原始 JSON：`scripts/_api_audit/last_missing_probe.json`

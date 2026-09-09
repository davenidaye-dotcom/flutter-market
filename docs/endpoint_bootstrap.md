# 线路引导 + 验签密钥：操作流程（含测试环境）

## 开关（后端开发）

`application.yml`：

```yaml
flyroom:
  api-sign:
    enabled: false   # 现在联调：关验签
    # enabled: true  # 要测验签 / 上线前打开，并配齐 secrets
    secrets:
      "1": "eT4uY8nBFr9kQx2m6cH1jR5!P7vL0sW#"
```

- `false`：不装验签过滤器，Postman/App 都能直接调  
- `true`：必须 secrets 非空，且与 Dart 生成的 `--sign-secret` 一致  

---

## 先对齐三件事

| 项 | 放哪 | 谁生成/谁配 |
|----|------|-------------|
| **业务 API/WS 地址** | OSS 加密文件里 | `dart run tool/gen_...` |
| **验签密钥 signSecret + signKid** | OSS 文件 **且** 后端 `application.yml` | **两边必须一模一样** |
| **配置根密钥 cfgKid** | App 打散碎片（解 OSS 用） | 发包时固定，极少换 |

> 是的：OSS 文件用 **Dart 命令生成**；其中的 `--sign-secret` 必须等于后端 yaml 里 `secrets."kid"`。

当前测试默认（kid=1）密钥与包内打散兜底一致：

`eT4uY8nBFr9kQx2m6cH1jR5!P7vL0sW#`

对应 yaml：

```yaml
flyroom:
  api-sign:
    enabled: true
    mode: APP
    secrets:
      "1": "eT4uY8nBFr9kQx2m6cH1jR5!P7vL0sW#"
```

---

## 标准流程（测试环境）

### 1. 生成加密文件

在 `plus-app/flutter-market`：

```bash
dart run tool/gen_endpoint_frcfg.dart \
  --env=dev \
  --api=http://207.148.105.182/api/v1 \
  --ws=ws://207.148.105.182/ws/v1 \
  --sign-kid=1 \
  --sign-secret='eT4uY8nBFr9kQx2m6cH1jR5!P7vL0sW#'
```

产出：

- `tool/out/endpoint.dev.frcfg` ← **上传 OSS**
- `assets/bootstrap/endpoint.frcfg` ← 包内兜底（无 OSS 时用）

`--env` 必须与 App 的 `APP_ENV` 一致（dev/test/pro）。

### 2. 配后端 yaml（密钥对齐）

`betmarket/ruoyi-admin/src/main/resources/application.yml`（或 test profile）：

```yaml
flyroom:
  api-sign:
    enabled: true
    mode: APP          # 测试可 APP；生产建议 ALL
    secrets:
      "1": "eT4uY8nBFr9kQx2m6cH1jR5!P7vL0sW#"   # = 上面 --sign-secret
```

重启后端。

### 3. 上传 OSS

把 `endpoint.dev.frcfg` 放到公有读路径，例如：

`https://你的bucket.oss-cn-xxx.aliyuncs.com/flyroom/dev/endpoint.frcfg`

并改 App 引导地址：`lib/core/bootstrap/bootstrap_seeds.dart`  
或测试时不改代码，用：

```bash
flutter run --flavor dev --dart-define=APP_ENV=dev \
  --dart-define=BOOTSTRAP_URL=https://你的bucket.../flyroom/dev/endpoint.frcfg
```

### 4. 跑 App 验证

1. 清 App 数据（或卸装重装），避免旧缓存  
2. 启动看日志：`[bootstrap] source=oss ... signKid=1`  
   - `source=asset/builtin` 说明没拉到 OSS（可用 BOOTSTRAP_URL 排查）  
3. 登录玩家 / 房主 / 代理，应成功  
4. 代理会员应提示账号密码错误  

若验签密钥和 yaml **不一致**：接口会 403，App 提示「请求失败，请稍后重试」（细节在服务端日志 `api-sign reject`）。

---

## 没有 OSS 时怎么测？

也可以：

1. 只跑 `dart run tool/gen_...`（会写入 `assets/bootstrap/endpoint.frcfg`）  
2. **不配 OSS**，启动走 `source=asset` 或失败后再 `builtin`  
3. yaml 的 `secrets."1"` 仍须与生成时的 `--sign-secret` 一致（默认即包内打散密钥）

本地临时指定文件（任意可公网 GET 的 URL，甚至你自己起的静态站）：

```bash
--dart-define=BOOTSTRAP_URL=http://127.0.0.1:8080/endpoint.dev.frcfg
```

---

## 轮换验签密钥（不用重打包）

1. yaml **先加**新 kid（旧的先留着）  
2. `dart run ... --sign-kid=2 --sign-secret='新密钥'` 生成并上传 OSS  
3. App 拉到新配置后自动用 kid=2  
4. 确认无问题后 yaml **删掉**旧 `"1"`

---

## 检查清单

- [ ] `--sign-secret` == `flyroom.api-sign.secrets."kid"`  
- [ ] `--env` == App `APP_ENV`  
- [ ] `--api` / `--ws` 是真实可访问地址  
- [ ] OSS 公有读（或 CDN）能直接浏览器下载到 `FRCFG2|...` 开头内容  
- [ ] 后端已重启；Redis 可用（nonce 防重放）  

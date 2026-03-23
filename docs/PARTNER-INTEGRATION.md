# Partner API 整合指南（內部）

> 本文件為**內部操作文件**，說明如何上線和管理 Partner。
> Partner 介接請參考 [PARTNER-QUICKSTART.md](./PARTNER-QUICKSTART.md)。

---

## 流程概覽

### Partner 上線流程

```
   API 提供方                                  Partner
       │                                          │
       ▼                                          │
  ┌──────────────────────────┐                   │
  │  ① 設定 Lua 權限配置      │                   │
  │    partners-loader.lua   │                   │
  └────────────┬─────────────┘                   │
               │                                 │
               ▼                                 │
  ┌──────────────────────────┐                   │
  │  ② 建立 Podman Secret     │                   │
  │    manage-partner-        │                   │
  │    secrets.sh create      │                   │
  └────────────┬─────────────┘                   │
               │                                 │
               │      安全傳遞 Secret             │
               └────────────────────────────────▶│
                                                 │
                                                 ▼
                                     ┌───────────────────────┐
                                     │  ③ 存入 Secret Manager │
                                     │     / 環境變數         │
                                     └───────────┬───────────┘
                                                 │
                                                 ▼
                                     ┌───────────────────────┐
                                     │  ④ 產生 JWT Token      │
                                     │    （Secret 簽署）     │
                                     └───────────┬───────────┘
                                                 │
               ◀──────── API 呼叫（Bearer JWT）───┘
```

### API 呼叫認證流程

```
              ┌────────────────────────────┐
              │        Partner 發送請求     │
              │   Authorization:            │
              │   Bearer <JWT_TOKEN>        │
              └──────────────┬─────────────┘
                             │
                             ▼
              ┌────────────────────────────┐
              │   SSL Proxy（OpenResty）    │
              │   ・JWT 簽章驗證（HS256）   │
              │   ・過期時間檢查            │
              │   ・Partner 存在確認        │
              └──────────────┬─────────────┘
                             │
             ┌───────────────┴───────────────┐
          失敗 ▼                           通過 ▼
  ┌─────────────────────┐     ┌─────────────────────────────┐
  │  401 Unauthorized   │     │  注入 X-Partner-ID header    │
  └─────────────────────┘     │  轉發請求到 Backend API      │
                              └──────────────┬──────────────┘
                                             │
                                             ▼
                              ┌─────────────────────────────┐
                              │       Backend API            │
                              │   Endpoint 權限檢查          │
                              │  （路徑 + HTTP 方法）        │
                              └──────────────┬──────────────┘
                                             │
                             ┌───────────────┴───────────────┐
                          無權限 ▼                         通過 ▼
                  ┌─────────────────────┐     ┌─────────────────────┐
                  │   403 Forbidden     │     │    回應業務資料      │
                  └─────────────────────┘     └─────────────────────┘
```

---

## 權限矩陣

> 以下為概念性摘要。實際權限設定採用 **Endpoint 層級模型**，詳見 [ENDPOINT-PERMISSIONS.md](./ENDPOINT-PERMISSIONS.md)。

| Partner | Orders API | Products API | Users API |
|---------|-----------|--------------|-----------|
| partner-company-a | read, write | read, write | read |
| partner-company-b | read | - | - |
| partner-company-c | - | read, write | - |

---

## 安全架構與責任分離

採用對稱式 JWT 認證（HS256）：**我們產生並保管 Secret**，**Partner 用 Secret 自行產生 Token**。

| 角色 | 職責 |
|------|------|
| API 提供方 | 產生強隨機 Secret、安全傳遞給 Partner、儲存 Secret 用於驗證 |
| Partner | 安全儲存 Secret、在自己系統中產生 Token、管理 Token 生命週期 |

**重要**：不要在 API 提供方的伺服器上幫 Partner 產生 Token，這違反責任分離原則。

| 環境 | Secret 管理 | Token 產生 |
|------|------------|-----------|
| 開發 | 固定測試 Secret（公開） | 可用 `generate-jwt.sh` 模擬 |
| 生產 | Podman Secrets（加密） | 只能由 Partner 自行產生 |

---

## 添加新 Partner

### 步驟 1：配置 Partner 權限

編輯 `configs/ssl-proxy/lua/partners-loader.lua`：

```lua
_M.partners = {
    -- 現有 Partners...

    ["partner-company-d"] = {
        secret = os.getenv("JWT_SECRET_PARTNER_D") or "dev-secret-partner-d-change-in-production-32chars",
        name = "Company D Technologies",
        permissions = {
            orders = {
                endpoints = {
                    { pattern = "/list", methods = {"GET"} },
                    { pattern = "/search", methods = {"GET"} },
                    { pattern = "^/%d+$", methods = {"GET"}, regex = true }
                }
            },
            products = {
                endpoints = {
                    { pattern = "/", methods = {"GET"} },
                    { pattern = "/create", methods = {"POST"} },
                    { pattern = "^/%d+$", methods = {"GET", "PUT", "PATCH"}, regex = true }
                }
            }
        }
    }
}
```

> 完整格式說明見 [ENDPOINT-PERMISSIONS.md](./ENDPOINT-PERMISSIONS.md)。

### 步驟 2：配置 Secret

**開發環境** — 編輯 `quadlet/ssl-proxy.container.d/environment.conf.example`：

```ini
[Container]
Environment=JWT_SECRET_PARTNER_D=dev-secret-partner-d-for-testing-32chars
```

**生產環境** — 編輯 `quadlet/ssl-proxy.container` 添加 Secret 聲明，再建立 Secret：

```ini
[Container]
Secret=jwt-secret-partner-d,type=env,target=JWT_SECRET_PARTNER_D
```

```bash
./scripts/manage-partner-secrets.sh create d
```

### 步驟 3：重新載入配置

```bash
# 複製 Lua 配置
cp configs/ssl-proxy/lua/partners-loader.lua /opt/app/configs/ssl-proxy/lua/

# 開發環境：複製 env 檔
cp quadlet/ssl-proxy.container.d/environment.conf.example \
   ~/.config/containers/systemd/ssl-proxy.container.d/environment.conf

# 生產環境：複製 container 定義
cp quadlet/ssl-proxy.container ~/.config/containers/systemd/

# 重啟服務
systemctl --user daemon-reload
systemctl --user restart ssl-proxy
```

### 步驟 4：提供資訊給 Partner

| 項目 | 說明 |
|------|------|
| Partner ID | 例如 `partner-company-d` |
| JWT Secret | `manage-partner-secrets.sh create` 建立時顯示（僅一次） |
| API Base URL | 例如 `https://api.example.com` |
| 可訪問的端點 | 依權限配置 |
| 介接文件 | [PARTNER-QUICKSTART.md](./PARTNER-QUICKSTART.md) |

**安全傳遞 Secret**：使用加密密碼管理工具（1Password、HashiCorp Vault）或加密 ZIP。不要用明文 Email / Slack。

---

## 變更 Partner 配置

### 修改權限

編輯 `configs/ssl-proxy/lua/partners-loader.lua`，格式見 [ENDPOINT-PERMISSIONS.md](./ENDPOINT-PERMISSIONS.md)。

### 停用 Partner

```lua
["partner-company-a"] = {
    secret = "disabled",
    permissions = {}
}
```

### 輪換 Secret

```bash
# 使用管理腳本輪換 Secret（推薦）
./scripts/manage-partner-secrets.sh rotate a
# 通知 Partner 使用新 Secret
```

---

## 相關文件

- [PARTNER-QUICKSTART.md](./PARTNER-QUICKSTART.md) — 給 Partner 的介接指南
- [ENDPOINT-PERMISSIONS.md](./ENDPOINT-PERMISSIONS.md) — Endpoint 層級權限設定
- [DEPLOYMENT.md](./DEPLOYMENT.md) — Partner Secrets 管理（create / list / rotate / delete）
- [DEBUG.md](./DEBUG.md) — Partner API 除錯與日誌查閱

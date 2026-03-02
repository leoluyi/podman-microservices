# Partner API 整合指南

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

## 概覽

### 權限矩陣

> **注意**：以下為概念性摘要，使用舊的 API 層級表示法。實際權限設定採用 **Endpoint 層級模型**，格式為 `endpoints = { { pattern, methods } }`。詳見 [ENDPOINT-PERMISSIONS.md](./ENDPOINT-PERMISSIONS.md)。

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

## API 提供方：Partner 設定

### 1. 添加新 Partner

#### 步驟 1：配置 Partner 資訊

編輯 `configs/ssl-proxy/lua/partners-loader.lua`：

```lua
_M.partners = {
    -- 現有 Partners...

    -- 新增 Partner（Endpoint 層級權限格式）
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

#### 步驟 2：配置 Secret（混合方案）

本專案支援兩種 Secret 管理方式：

**開發環境**：使用環境檔案（方便測試）

編輯 `quadlet/ssl-proxy.container.d/environment.conf.example`：

```ini
[Container]
Environment=JWT_SECRET_PARTNER_A=dev-secret-partner-a-for-testing-32chars
Environment=JWT_SECRET_PARTNER_B=dev-secret-partner-b-for-testing-32chars
Environment=JWT_SECRET_PARTNER_C=dev-secret-partner-c-for-testing-32chars
Environment=JWT_SECRET_PARTNER_D=dev-secret-partner-d-for-testing-32chars  # 新增
```

**生產環境**：使用 Podman Secrets（加密存儲）

1. 編輯 `quadlet/ssl-proxy.container` 添加 Secret 聲明：
```ini
[Container]
Secret=jwt-secret-partner-d,type=env,target=JWT_SECRET_PARTNER_D
Environment=JWT_SECRET_PARTNER_D=fallback-secret-32chars  # Fallback
```

2. 創建 Podman Secret：
```bash
./scripts/manage-partner-secrets.sh create d
```

#### 步驟 3：重新載入配置

**開發環境**：
```bash
# 複製配置到 systemd 目錄
cp configs/ssl-proxy/lua/partners-loader.lua /opt/app/configs/ssl-proxy/lua/
cp quadlet/ssl-proxy.container.d/environment.conf.example \
   ~/.config/containers/systemd/ssl-proxy.container.d/environment.conf

# 重啟服務
systemctl --user daemon-reload
systemctl --user restart ssl-proxy
```

**生產環境**：
```bash
# 複製配置
cp configs/ssl-proxy/lua/partners-loader.lua /opt/app/configs/ssl-proxy/lua/
cp quadlet/ssl-proxy.container ~/.config/containers/systemd/

# 創建 Secret（已在步驟 2 完成）
# 重啟服務
systemctl --user daemon-reload
systemctl --user restart ssl-proxy
```

### 2. 權限說明

實際實作採用 Endpoint 層級權限控制，配置格式與範例見 [ENDPOINT-PERMISSIONS.md](./ENDPOINT-PERMISSIONS.md)。

### 3. 管理 Partner Secrets

create / list / rotate / delete 的完整操作說明見 [DEPLOYMENT.md § Partner API 管理](./DEPLOYMENT.md)。

### 4. 提供資訊給 Partner

提供以下資訊給 Partner：

| 項目 | 說明 |
|------|------|
| Partner ID | 例如 `partner-company-a` |
| JWT Secret | 從 `manage-partner-secrets.sh create` 創建時取得（僅顯示一次） |
| API Base URL | 例如 `https://api.example.com` |
| 可訪問的 API 列表 | 依權限配置 |
| 整合工具 | `generate-jwt.sh`、Node.js/Python SDK（`examples/partner-clients/`） |

#### 如何取得 JWT Secret

**生產環境**：

運行創建命令時會顯示 Secret 值（僅此一次）：

```bash
./scripts/manage-partner-secrets.sh create a

# 輸出：
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Partner ID: partner-company-a
# JWT Secret: rJ9kL2mN4oP6qR8sT0uV1wX3yZ5aB7cD9eF1gH3iJ5kL7
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

如選擇保存到文件，會存放在：
```
/opt/app/configs/ssl-proxy/partner-secret-a-20260213.txt
```

⚠️ **安全提醒**：提供給 Partner 後請立即刪除此文件

**開發環境**：

使用固定測試 Secret（位於 `quadlet/ssl-proxy.container.d/environment.conf.example`）

#### 安全傳遞 Secret

使用加密密碼管理工具（1Password、LastPass、HashiCorp Vault）或加密 ZIP 傳遞。不要用明文 Email、Slack 或文件共享服務。

---

## Partner：API 整合

### 1. 整合流程

#### 步驟 1：安裝依賴

**Node.js:**
```bash
npm install jsonwebtoken axios
```

**Python:**
```bash
pip install pyjwt requests
```

#### 步驟 2：設定環境變數

```bash
# Partner 身份資訊（由 API 提供方提供）
export PARTNER_ID="partner-company-a"
export JWT_SECRET_PARTNER_A="your-secret-from-provider"
export API_BASE_URL="https://api.example.com"
```

#### 步驟 3：使用 SDK

參考 `examples/partner-clients/` 目錄中的範例：

- `nodejs-client.js` - Node.js SDK
- `python-client.py` - Python SDK
- `README.md` - 詳細使用說明

### 2. JWT Token 生成

⚠️ **重要**：Partner 必須在自己的系統中產生 JWT Token，不應該向 API 提供方索取 Token。

#### Token 結構

```json
{
  "sub": "partner-company-a",    // Partner ID（必要）
  "iss": "partner-api-system",    // 發行者（建議）
  "aud": "partner-api",           // 接收者（建議）
  "exp": 1735689600,              // 過期時間（必要）
  "iat": 1735603200               // 發行時間（必要）
}
```

#### 產生方式

Partner 在**自己的系統**中產生 Token，不應向 API 提供方索取。

##### Shell（generate-jwt.sh）

```bash
export JWT_SECRET_PARTNER_A="your-secret-from-provider"
TOKEN=$(./generate-jwt.sh partner-company-a)           # 永久有效
TOKEN=$(./generate-jwt.sh partner-company-a 2592000)   # 30 天有效期
curl -H "Authorization: Bearer $TOKEN" https://api.example.com/partner/api/order/
```

有效期：`0` 或不指定為永久（預設），否則單位為秒。

⚠️ 永久 Token 須妥善保管 Secret，洩漏時立即聯繫 API 提供方輪換。

##### Node.js

```javascript
const PartnerAPIClient = require('./partner-client');
const client = new PartnerAPIClient(
    process.env.PARTNER_ID, process.env.JWT_SECRET, 'https://api.example.com'
);
const orders = await client.getOrders();
```

手動產生：

```javascript
const jwt = require('jsonwebtoken');
const token = jwt.sign(
    { sub: 'partner-company-a', iss: 'partner-api-system', aud: 'partner-api',
      iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 3600 },
    process.env.JWT_SECRET,
    { algorithm: 'HS256' }
);
```

##### Python

```python
from partner_client import PartnerAPIClient
client = PartnerAPIClient(
    partner_id=os.getenv('PARTNER_ID'),
    jwt_secret=os.getenv('JWT_SECRET'),
    base_url='https://api.example.com'
)

# SDK 會自動產生和管理 Token
orders = client.get_orders()
```

**手動產生 Token**：

```python
import jwt
import time
import os

token = jwt.encode(
    {
        'sub': 'partner-company-a',
        'iss': 'partner-api-system',
        'aud': 'partner-api',
        'iat': int(time.time()),
        'exp': int(time.time()) + 3600  # 1 小時
    },
    os.getenv('JWT_SECRET'),
    algorithm='HS256'
)
```

##### 方式 4：使用其他語言

**適合場景**：
- Java / Go / C# / PHP 等應用程式
- 企業級系統整合

**參考實作**：

<details>
<summary>Java 範例</summary>

```java
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import java.util.Date;

String token = Jwts.builder()
    .setSubject("partner-company-a")
    .setIssuer("partner-api-system")
    .setAudience("partner-api")
    .setIssuedAt(new Date())
    .setExpiration(new Date(System.currentTimeMillis() + 3600000))
    .signWith(SignatureAlgorithm.HS256, jwtSecret)
    .compact();
```
</details>

<details>
<summary>Go 範例</summary>

```go
import (
    "time"
    "github.com/golang-jwt/jwt/v5"
)

token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
    "sub": "partner-company-a",
    "iss": "partner-api-system",
    "aud": "partner-api",
    "iat": time.Now().Unix(),
    "exp": time.Now().Add(time.Hour * 1).Unix(),
})

tokenString, _ := token.SignedString([]byte(jwtSecret))
```
</details>

<details>
<summary>C# 範例</summary>

```csharp
using System;
using System.IdentityModel.Tokens.Jwt;
using Microsoft.IdentityModel.Tokens;

var tokenHandler = new JwtSecurityTokenHandler();
var key = Encoding.ASCII.GetBytes(jwtSecret);
var tokenDescriptor = new SecurityTokenDescriptor
{
    Subject = new ClaimsIdentity(new[]
    {
        new Claim("sub", "partner-company-a"),
        new Claim("iss", "partner-api-system"),
        new Claim("aud", "partner-api")
    }),
    Expires = DateTime.UtcNow.AddHours(1),
    SigningCredentials = new SigningCredentials(
        new SymmetricSecurityKey(key),
        SecurityAlgorithms.HmacSha256Signature
    )
};
var token = tokenHandler.CreateToken(tokenDescriptor);
var tokenString = tokenHandler.WriteToken(token);
```
</details>

#### Token 最佳實踐

- 過期時間：1-24 小時（永久 Token 須妥善管理 Secret）
- 快取：到期前 1 分鐘重新生成
- Secret：用環境變數，不要硬編碼
- 日誌：不要記錄完整 Token

### 3. API 呼叫

```bash
curl -H "Authorization: Bearer ${TOKEN}" https://api.example.com/partner/api/order/
```

### 4. 錯誤處理

#### HTTP 狀態碼

| 狀態碼 | 說明 | 原因 | 解決方式 |
|--------|------|------|----------|
| 401 | Unauthorized | Token 無效或過期 | 檢查 JWT Secret，確認 Token 未過期 |
| 403 | Forbidden | 權限不足 | 確認您的 Partner 有訪問此 API 的權限 |
| 404 | Not Found | 端點不存在 | 檢查 API 路徑 |
| 429 | Too Many Requests | 超過速率限制 | 減少請求頻率 |
| 500 | Internal Server Error | 伺服器錯誤 | 聯繫 API 提供方 |

#### 錯誤回應格式

```json
{
    "error": "Forbidden",
    "message": "Insufficient permissions for this API"
}
```

#### 範例：錯誤處理

```javascript
try {
    const orders = await client.getOrders();
} catch (error) {
    if (error.response) {
        switch (error.response.status) {
            case 401:
                console.error('認證失敗：請檢查 JWT Secret');
                break;
            case 403:
                console.error('權限不足：您沒有訪問此 API 的權限');
                break;
            default:
                console.error('API 錯誤：', error.response.data);
        }
    }
}
```

---

## API 端點參考

### Orders API

**端點**: `/partner/api/order/`

**權限**: `orders`

**方法**:
- `GET /partner/api/order/` - 取得訂單列表（需要 `read`）
- `POST /partner/api/order/` - 創建訂單（需要 `write`）
- `PUT /partner/api/order/{id}` - 更新訂單（需要 `write`）
- `DELETE /partner/api/order/{id}` - 刪除訂單（需要 `delete`）

### Products API

**端點**: `/partner/api/product/`

**權限**: `products`

**方法**:
- `GET /partner/api/product/` - 取得產品列表（需要 `read`）
- `POST /partner/api/product/` - 創建產品（需要 `write`）
- `PUT /partner/api/product/{id}` - 更新產品（需要 `write`）
- `DELETE /partner/api/product/{id}` - 刪除產品（需要 `delete`）

### Users API

**端點**: `/partner/api/user/`

**權限**: `users`

**方法**:
- `GET /partner/api/user/` - 取得用戶資訊（需要 `read`）

---

## 最佳實踐

- Secret：用環境變數，不要硬編碼，每 90 天輪換
- Token 過期：1-24 小時，到期前 1 分鐘自動重新生成
- 日誌：記錄 `partner_id`、endpoint、status、duration_ms，不記錄完整 Token
- HTTPS：生產環境必須驗證 SSL 憑證
- 速率限制：實作指數退避重試，尊重 API 速率限制

---

## 測試

### 本地測試

#### 1. 產生測試 Token

```bash
./scripts/generate-jwt.sh partner-company-a
```

#### 2. 測試 API

```bash
TOKEN=$(./scripts/generate-jwt.sh partner-company-a 2>/dev/null)

# 測試 Orders API
curl -k -H "Authorization: Bearer $TOKEN" \
     https://localhost/partner/api/order/

# 測試 Products API
curl -k -H "Authorization: Bearer $TOKEN" \
     https://localhost/partner/api/product/
```

### 權限測試

測試不同 Partner 的權限差異：

```bash
# Partner A（有完整權限）
TOKEN_A=$(./scripts/generate-jwt.sh partner-company-a 2>/dev/null)
curl -k -H "Authorization: Bearer $TOKEN_A" https://localhost/partner/api/order/
# 預期：200 OK

# Partner B（只有 orders read）
TOKEN_B=$(./scripts/generate-jwt.sh partner-company-b 2>/dev/null)
curl -k -H "Authorization: Bearer $TOKEN_B" https://localhost/partner/api/order/
# 預期：200 OK

curl -k -H "Authorization: Bearer $TOKEN_B" https://localhost/partner/api/product/
# 預期：403 Forbidden
```

---

## 故障排除

### 常見問題

#### Q1: 401 Unauthorized - Invalid token

**原因**：
- JWT Secret 不正確
- Token 已過期
- Token 格式錯誤

**解決**：
```bash
# 檢查 Secret 是否正確
echo $JWT_SECRET_PARTNER_A

# 驗證 Token（使用 jwt.io）
# 複製 Token 到 https://jwt.io 檢查 payload

# 重新生成 Token
./scripts/generate-jwt.sh partner-company-a
```

#### Q2: 403 Forbidden - Insufficient permissions

**原因**：
- Partner 沒有訪問該 API 的權限
- 嘗試執行未授權的操作（如：只有 read 權限但執行 POST）

**解決**：
- 確認 Partner 的權限配置
- 聯繫 API 提供方申請所需權限

#### Q3: Unknown partner

**原因**：
- Partner ID 不存在於系統中
- Partner ID 拼寫錯誤

**解決**：
- 確認 Partner ID 正確
- 確認 Partner 已在系統中註冊

### Debug 模式

啟用 Debug 模式查看詳細資訊：

```bash
# 在 quadlet/ssl-proxy.container
Environment=DEBUG_PARTNERS=true

# 重啟服務
systemctl --user restart ssl-proxy

# 查看日誌
./scripts/logs.sh ssl-proxy
```

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
NEW_SECRET=$(openssl rand -base64 32)
# 更新 quadlet/ssl-proxy.container：
# Environment=JWT_SECRET_PARTNER_A=$NEW_SECRET
systemctl --user daemon-reload && systemctl --user restart ssl-proxy
# 通知 Partner 使用新 Secret
```

---

## 支援

### 文檔資源

- **API 範例**: `examples/partner-clients/README.md`
- **架構說明**: `docs/ARCHITECTURE.md`
- **部署指南**: `docs/DEPLOYMENT.md`


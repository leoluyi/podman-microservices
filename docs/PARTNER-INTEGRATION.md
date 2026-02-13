# Partner API 整合指南

本文檔說明如何為 Partner 設定 API 訪問權限，以及 Partner 如何整合 API。

[toc]

---

## 概覽

### Partner API 特性

- **獨立 JWT Secret**：每個 Partner 有專屬的 JWT Secret
- **細粒度權限**：可針對不同 API 設定 read/write/delete 權限
- **HTTP 方法映射**：自動根據 HTTP 方法判斷操作類型
- **安全隔離**：一個 Partner 的 Secret 洩露不影響其他 Partner

### 權限矩陣

| Partner | Orders API | Products API | Users API |
|---------|-----------|--------------|-----------|
| partner-company-a | read, write | read, write | read |
| partner-company-b | read | - | - |
| partner-company-c | - | read, write | - |

---

## 安全架構與責任分離

### JWT Token 安全模型

本系統採用**對稱式 JWT 認證**（HS256），基於以下安全原則：

#### 責任分離原則

```
┌─────────────────────────────────────────────────────────┐
│ 我們的系統（API 提供方）                                  │
├─────────────────────────────────────────────────────────┤
│ 職責：                                                   │
│ 1. ✅ 產生強隨機 JWT Secret                              │
│    ./scripts/manage-partner-secrets.sh create a         │
│                                                          │
│ 2. ✅ 安全地提供 Secret 給 Partner（僅一次）              │
│    - 透過加密郵件、安全檔案傳輸、密碼管理系統             │
│    - 提供整合工具（generate-jwt.sh、SDK、文檔）          │
│                                                          │
│ 3. ✅ 儲存 Secret 用於「驗證」Token                       │
│    - Podman Secrets（生產環境，加密儲存）                │
│    - Environment Files（開發環境，固定測試值）           │
│                                                          │
│ 4. ❌ 不產生 Partner 的 Token                            │
│    - 違反責任分離原則                                    │
│    - 使認證失去意義                                      │
│    - 無法追蹤責任歸屬                                    │
└─────────────────────────────────────────────────────────┘
                          ↓
              【安全地傳遞 Secret + 工具】
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Partner 的系統（API 使用方）                              │
├─────────────────────────────────────────────────────────┤
│ 職責：                                                   │
│ 1. ✅ 安全地儲存我們提供的 Secret                         │
│    - 環境變數、Secrets 管理系統                          │
│    - 不放在程式碼中、不提交到版本控制                     │
│                                                          │
│ 2. ✅ 在自己的系統中產生 JWT Token                        │
│    方式 A：使用我們提供的 generate-jwt.sh                │
│    方式 B：使用我們提供的 SDK（Node.js/Python）          │
│    方式 C：使用自己的 JWT 函式庫實作                      │
│                                                          │
│ 3. ✅ 使用自己產生的 Token 呼叫我們的 API                 │
│    Authorization: Bearer <partner_generated_token>      │
│                                                          │
│ 4. ✅ 對自己的 Token 安全負責                             │
│    - Token 生命週期管理                                  │
│    - Token 洩漏時的處理                                  │
└─────────────────────────────────────────────────────────┘
```

#### 為什麼這樣設計？

| 原則 | 說明 | 效益 |
|------|------|------|
| **身份認證意義** | Partner 產生的 Token 代表他們的身份 | 如果我們產生 Token，就失去「證明對方身份」的意義 |
| **責任歸屬清晰** | Token 由 Partner 控制 | 安全事件發生時，責任歸屬清楚 |
| **最小權限原則** | 我們的系統無法偽造 Partner 身份 | 降低內部人員濫用風險 |
| **安全邊界分明** | Secret 只用於驗證，不用於生成 | 降低 Secret 洩漏的影響範圍 |

#### 常見誤解澄清

❓ **「我們可以用 generate-jwt.sh 幫 Partner 產生 Token 嗎？」**

❌ **錯誤做法**：在我們的系統中執行
```bash
# 在 API 提供方的伺服器上（錯誤）
./scripts/generate-jwt.sh partner-company-a
# 然後把 Token 給 Partner... ← 違反安全原則
```

✅ **正確做法**：Partner 在他們的系統中執行
```bash
# 在 Partner 的伺服器上（正確）
./scripts/generate-jwt.sh partner-company-a
# Partner 自己產生、自己使用
```

#### 開發與生產環境的差異

| 環境 | Secret 管理 | Token 產生 |
|------|------------|-----------|
| **開發環境** | 固定測試 Secret（公開、不安全） | 我們可以用 generate-jwt.sh 測試（模擬 Partner） |
| **生產環境** | Podman Secrets（加密、隨機） | 只能由 Partner 產生（使用我們提供的工具） |

⚠️ **開發環境例外**：開發環境使用公開的測試 Secret，我們可以用 `generate-jwt.sh` 產生 Token 來測試系統，這是在**模擬 Partner 的行為**，不是實際的生產使用。

---

## API 提供方：Partner 設定

### 1. 添加新 Partner

#### 步驟 1：配置 Partner 資訊

編輯 `configs/ssl-proxy/lua/partners-loader.lua`：

```lua
_M.partners = {
    -- 現有 Partners...

    -- 新增 Partner
    ["partner-company-d"] = {
        secret = os.getenv("JWT_SECRET_PARTNER_D") or "dev-secret-partner-d-change-in-production-32chars",
        name = "Company D Technologies",
        permissions = {
            orders = { "read" },           -- 只能讀取訂單
            products = { "read", "write" }  -- 可讀寫產品
        }
    }
}
```

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

#### 權限類型

- **read**：允許 GET 請求
- **write**：允許 POST, PUT, PATCH 請求
- **delete**：允許 DELETE 請求

#### 配置範例

```lua
permissions = {
    orders = { "read", "write" },  -- GET, POST, PUT, PATCH
    products = { "read" },          -- 只有 GET
    users = { "read", "delete" }    -- GET 和 DELETE
}
```

#### HTTP 方法映射

系統自動根據 HTTP 方法判斷所需權限：

| HTTP 方法 | 需要權限 |
|-----------|----------|
| GET | read |
| POST | write |
| PUT | write |
| PATCH | write |
| DELETE | delete |

### 3. 管理 Partner Secrets

本專案使用**混合管理方案**：
- **開發環境**：固定測試 Secret（環境檔案）
- **生產環境**：Podman Secrets（加密存儲）

#### 生產環境：使用 Podman Secrets（推薦）

**創建新 Partner Secret**：

```bash
# 互動式創建（會自動產生隨機 Secret）
./scripts/manage-partner-secrets.sh create a

# 輸出範例：
# Partner ID: partner-company-a
# JWT Secret: rJ9kL2mN4oP6qR8sT0uV1wX3yZ5aB7cD9eF1gH3iJ5kL7
```

**查看現有 Secrets**：

```bash
# 列出所有 Partner Secrets
./scripts/manage-partner-secrets.sh list

# 查看特定 Secret 詳細資訊（不含實際值）
./scripts/manage-partner-secrets.sh show a
```

**輪換 Secret（安全更新）**：

```bash
# 停用舊 Token 並產生新 Secret
./scripts/manage-partner-secrets.sh rotate a

# ⚠️ 注意：會立即停用所有使用舊 Secret 的 Token
```

**刪除 Partner**：

```bash
# 刪除 Secret（Partner 將無法訪問）
./scripts/manage-partner-secrets.sh delete c
```

#### 開發環境：使用環境檔案

開發模式已預設固定測試 Secret（由 `setup.sh dev` 自動配置）：

```bash
# setup.sh dev 會自動部署
JWT_SECRET_PARTNER_A=dev-secret-partner-a-for-testing-only-32chars
JWT_SECRET_PARTNER_B=dev-secret-partner-b-for-testing-only-32chars
JWT_SECRET_PARTNER_C=dev-secret-partner-c-for-testing-only-32chars
```

**手動生成隨機 Secret**：

```bash
# 如需自訂，可手動生成
openssl rand -base64 32
```

### 4. 提供資訊給 Partner

Partner 需要以下資訊才能整合 API：

#### 必要資訊清單

- ✅ **Partner ID**：例如 `partner-company-a`
- ✅ **JWT Secret**：該 Partner 專屬的 Secret（從 `manage-partner-secrets.sh` 創建時取得）
- ✅ **API Base URL**：例如 `https://api.example.com`
- ✅ **可訪問的 API 列表**：根據權限配置
- ✅ **API 文檔**：端點說明和範例
- ✅ **整合工具**：提供以下任一或全部
  - `scripts/generate-jwt.sh` - Shell 腳本工具
  - `examples/partner-clients/nodejs-client.js` - Node.js SDK
  - `examples/partner-clients/python-client.py` - Python SDK
  - 整合文檔 - JWT 規範和其他語言實作參考

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

#### 範例：提供給 Partner 的資訊

```
Partner 整合資訊
================

基本資訊
--------
Partner ID: partner-company-a
JWT Secret: rJ9kL2mN4oP6qR8sT0uV1wX3yZ5aB7cD9eF1gH3iJ5kL7
API Base URL: https://api.example.com

⚠️ 請妥善保管 JWT Secret，不要分享或提交到版本控制

可訪問的 API
-----------
- Orders API: /partner/api/order/ (read, write)
- Products API: /partner/api/product/ (read, write)
- Users API: /partner/api/user/ (read)

整合工具
--------
我們提供以下工具協助您快速整合：

1. Shell 腳本（最簡單）
   檔案: scripts/generate-jwt.sh
   使用: ./generate-jwt.sh partner-company-a
   適合: 快速測試、Shell 腳本、CI/CD Pipeline

2. Node.js SDK
   檔案: examples/partner-clients/nodejs-client.js
   使用: const client = new PartnerAPIClient(...)
   適合: Node.js 應用程式

3. Python SDK
   檔案: examples/partner-clients/python-client.py
   使用: client = PartnerAPIClient(...)
   適合: Python 應用程式

4. 自行實作
   請參考整合文檔中的 JWT 規範
   適合: Java、Go、C#、PHP 等其他語言

重要提醒
--------
✅ 請在您的系統中產生 JWT Token（使用上述工具）
❌ 請勿向我們索取 Token（違反安全原則）

文檔與支援
---------
- 整合指南: https://github.com/your-org/repo/docs/PARTNER-INTEGRATION.md
- API 參考: https://api.example.com/docs
- 範例程式碼: https://github.com/your-org/repo/tree/main/examples/partner-clients

技術支援
--------
- Email: partner-support@example.com
- Slack: #partner-api-support
- 工作時間: 週一至週五 09:00-18:00 (GMT+8)
```

#### 安全傳遞 Secret

**不要使用的方式**：
- ❌ 明文 Email
- ❌ Slack 訊息
- ❌ 文件共享（Google Docs, Dropbox）

**推薦方式**：
- ✅ 加密的密碼管理工具（1Password, LastPass）
- ✅ 安全檔案傳輸（加密的 Zip + 電話告知密碼）
- ✅ 專用的 Secrets 管理系統（HashiCorp Vault）

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

#### 產生方式選擇

Partner 可以選擇以下任一方式在自己的系統中產生 Token：

##### 方式 1：使用 generate-jwt.sh 腳本（推薦 - 最簡單）

**適合場景**：
- 快速整合測試
- Shell 腳本環境
- CI/CD Pipeline
- Cron Job 定期任務

**使用方法**：

```bash
# 設定環境變數（使用 API 提供方給的 Secret）
export JWT_SECRET_PARTNER_A="your-secret-from-provider"

# 產生 Token
TOKEN=$(./generate-jwt.sh partner-company-a)

# 使用 Token 呼叫 API
curl -H "Authorization: Bearer $TOKEN" https://api.example.com/partner/api/order/
```

**腳本特性**：
- ✅ 自動產生符合規範的 JWT Token
- ✅ 包含完整的 Payload 欄位（sub, iss, aud, iat, exp）
- ✅ 預設有效期 24 小時
- ✅ 輸出詳細的 Debug 資訊（stderr）
- ✅ 只輸出 Token 到 stdout（方便腳本使用）

**範例：整合到 Cron Job**

```bash
#!/bin/bash
# 每天凌晨同步訂單資料

# 產生 Token
TOKEN=$(./generate-jwt.sh partner-company-a 2>/dev/null)

# 呼叫 API 取得訂單
curl -H "Authorization: Bearer $TOKEN" \
     https://api.example.com/partner/api/order/ \
     -o /tmp/orders.json

# 處理資料...
```

##### 方式 2：使用 Node.js SDK

**適合場景**：
- Node.js 應用程式
- 需要完整的 API 客戶端
- 自動 Token 管理

**使用方法**：

```javascript
// 使用我們提供的 SDK
const PartnerAPIClient = require('./partner-client');

const client = new PartnerAPIClient(
    process.env.PARTNER_ID,
    process.env.JWT_SECRET,
    'https://api.example.com'
);

// SDK 會自動產生和管理 Token
const orders = await client.getOrders();
```

**手動產生 Token**：

```javascript
const jwt = require('jsonwebtoken');

const token = jwt.sign(
    {
        sub: 'partner-company-a',
        iss: 'partner-api-system',
        aud: 'partner-api',
        iat: Math.floor(Date.now() / 1000),
        exp: Math.floor(Date.now() / 1000) + 3600  // 1 小時
    },
    process.env.JWT_SECRET,
    { algorithm: 'HS256' }
);
```

##### 方式 3：使用 Python SDK

**適合場景**：
- Python 應用程式
- 資料分析腳本
- 自動化任務

**使用方法**：

```python
# 使用我們提供的 SDK
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

#### Token 生成最佳實踐

| 實踐項目 | 建議 | 原因 |
|---------|------|------|
| **過期時間** | 1-24 小時 | 平衡安全性與便利性 |
| **Token 快取** | 快過期前 1 分鐘重新生成 | 避免 Token 過期導致 API 呼叫失敗 |
| **Secret 儲存** | 環境變數或 Secrets 管理系統 | 不要硬編碼在程式碼中 |
| **錯誤處理** | 401 錯誤時自動重新生成 Token | 提高系統健壯性 |
| **日誌記錄** | 不要記錄完整 Token | 防止 Token 洩漏 |

### 3. API 呼叫

#### 基本請求

```bash
# 使用 Token 呼叫 API
curl -X GET https://api.example.com/partner/api/order/ \
     -H "Authorization: Bearer ${TOKEN}" \
     -H "Content-Type: application/json"
```

#### 完整範例（Node.js）

```javascript
const axios = require('axios');

async function getOrders(token) {
    const response = await axios.get(
        'https://api.example.com/partner/api/order/',
        {
            headers: {
                'Authorization': `Bearer ${token}`
            }
        }
    );
    return response.data;
}
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

### Token 管理

#### Token 生命週期

```javascript
class TokenManager {
    constructor(partnerId, secret) {
        this.partnerId = partnerId;
        this.secret = secret;
        this.token = null;
        this.expiresAt = 0;
    }

    getToken() {
        // 如果 Token 快過期，重新生成
        if (!this.token || Date.now() / 1000 > this.expiresAt - 60) {
            this.refreshToken();
        }
        return this.token;
    }

    refreshToken() {
        const expiresIn = 3600; // 1 小時
        this.token = jwt.sign(
            {
                sub: this.partnerId,
                iat: Math.floor(Date.now() / 1000),
                exp: Math.floor(Date.now() / 1000) + expiresIn
            },
            this.secret,
            { algorithm: 'HS256' }
        );
        this.expiresAt = Math.floor(Date.now() / 1000) + expiresIn;
    }
}
```

### 安全建議

1. **保護 JWT Secret**
   - 使用環境變數，不要硬編碼
   - 不要提交到版本控制
   - 定期輪換（建議每 90 天）

2. **Token 過期時間**
   - 使用合理的過期時間（建議 1-24 小時）
   - 不要使用永久 Token

3. **HTTPS**
   - 生產環境必須使用 HTTPS
   - 驗證 SSL 憑證

4. **錯誤處理**
   - 不要在日誌中輸出完整 Token
   - 實現重試邏輯（指數退避）

5. **速率限制**
   - 實現本地速率限制
   - 尊重 API 的速率限制

### 監控與日誌

#### 建議記錄的資訊

```javascript
// 成功請求
logger.info('API Request', {
    partner_id: partnerId,
    endpoint: '/partner/api/order/',
    method: 'GET',
    status: 200,
    duration_ms: 123
});

// 失敗請求
logger.error('API Error', {
    partner_id: partnerId,
    endpoint: '/partner/api/order/',
    method: 'POST',
    status: 403,
    error: 'Forbidden',
    message: 'Insufficient permissions'
});
```

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

```lua
-- 修改 configs/ssl-proxy/lua/partners-loader.lua
["partner-company-a"] = {
    secret = os.getenv("JWT_SECRET_PARTNER_A"),
    name = "Company A Corp",
    permissions = {
        orders = { "read", "write" },
        products = { "read", "write", "delete" },  -- 新增 delete
        users = { "read" }
    }
}
```

### 停用 Partner

暫時停用 Partner（不刪除配置）：

```lua
["partner-company-a"] = {
    secret = "disabled",  -- 設為無效 Secret
    name = "Company A Corp (Disabled)",
    permissions = {}      -- 清空權限
}
```

### 輪換 Secret

```bash
# 1. 生成新 Secret
NEW_SECRET=$(openssl rand -base64 32)

# 2. 更新環境變數
# 編輯 quadlet/ssl-proxy.container
Environment=JWT_SECRET_PARTNER_A=$NEW_SECRET

# 3. 重啟服務
systemctl --user daemon-reload
systemctl --user restart ssl-proxy

# 4. 通知 Partner 使用新 Secret
```

---

## 支援

### 文檔資源

- **API 範例**: `examples/partner-clients/README.md`
- **架構說明**: `docs/ARCHITECTURE.md`
- **部署指南**: `docs/DEPLOYMENT.md`


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

Partner ID: partner-company-a
JWT Secret: rJ9kL2mN4oP6qR8sT0uV1wX3yZ5aB7cD9eF1gH3iJ5kL7
API Base URL: https://api.example.com

可訪問的 API：
- Orders API: /partner/api/order/ (read, write)
- Products API: /partner/api/product/ (read, write)
- Users API: /partner/api/user/ (read)

文檔：
- 整合指南: https://github.com/your-org/repo/tree/main/examples/partner-clients
- API 參考: https://api.example.com/docs

支援聯絡：
- Email: partner-support@example.com
- Slack: #partner-api-support
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

#### Token 結構

```json
{
  "sub": "partner-company-a",    // Partner ID（必要）
  "iss": "partner-api-system",    // 發行者（可選）
  "aud": "partner-api",           // 接收者（可選）
  "exp": 1735689600,              // 過期時間（必要）
  "iat": 1735603200               // 發行時間（必要）
}
```

#### Node.js 範例

```javascript
const jwt = require('jsonwebtoken');

const token = jwt.sign(
    {
        sub: 'partner-company-a',
        iat: Math.floor(Date.now() / 1000),
        exp: Math.floor(Date.now() / 1000) + 3600  // 1 小時
    },
    JWT_SECRET,
    { algorithm: 'HS256' }
);
```

#### Python 範例

```python
import jwt
import time

token = jwt.encode(
    {
        'sub': 'partner-company-a',
        'iat': int(time.time()),
        'exp': int(time.time()) + 3600  # 1 小時
    },
    JWT_SECRET,
    algorithm='HS256'
)
```

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


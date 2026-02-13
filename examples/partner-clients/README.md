# Partner API Client 範例

這些範例展示如何作為 Partner 客戶端使用不同的 JWT Secret 訪問 Partner API。

## 權限說明

每個 Partner 有不同的 API 訪問權限：

| Partner | Orders API | Products API | Users API |
|---------|-----------|--------------|-----------|
| partner-company-a | read, write | read, write | read |
| partner-company-b | read | - | - |
| partner-company-c | - | read, write | - |

## 配置

### 1. 從 API 提供方獲取

您需要從 API 提供方獲取以下資訊：

- **Partner ID**：例如 `partner-company-a`
- **JWT Secret**：用於簽發 JWT Token 的共享密鑰
- **API Base URL**：例如 `https://api.example.com`

### 2. 設定環境變數

```bash
# Partner 身份
export PARTNER_ID="partner-company-a"

# JWT Secret（由 API 提供方提供）
export JWT_SECRET_PARTNER_A="your-secret-from-provider"

# API 端點
export API_BASE_URL="https://api.example.com"
```

## Node.js 範例

### 安裝依賴

```bash
npm install jsonwebtoken axios
```

### 執行

```bash
node nodejs-client.js
```

### 整合到專案

```javascript
const PartnerAPIClient = require('./nodejs-client');

const client = new PartnerAPIClient(
    process.env.PARTNER_ID,
    process.env.JWT_SECRET_PARTNER_A,
    process.env.API_BASE_URL
);

// 取得訂單
const orders = await client.getOrders();

// 創建訂單
const newOrder = await client.createOrder({
    product_id: '123',
    quantity: 5
});
```

## Python 範例

### 安裝依賴

```bash
pip install pyjwt requests
```

### 執行

```bash
python python-client.py
```

### 整合到專案

```python
from python_client import PartnerAPIClient
import os

client = PartnerAPIClient(
    partner_id=os.getenv('PARTNER_ID'),
    jwt_secret=os.getenv('JWT_SECRET_PARTNER_A'),
    base_url=os.getenv('API_BASE_URL')
)

# 取得訂單
orders = client.get_orders()

# 創建訂單
new_order = client.create_order({
    'product_id': '123',
    'quantity': 5
})
```

## API 端點

### Orders API

- `GET /partner/api/order/` - 取得訂單列表（需要 `orders:read`）
- `POST /partner/api/order/` - 創建訂單（需要 `orders:write`）
- `PUT /partner/api/order/{id}` - 更新訂單（需要 `orders:write`）
- `DELETE /partner/api/order/{id}` - 刪除訂單（需要 `orders:delete`）

### Products API

- `GET /partner/api/product/` - 取得產品列表（需要 `products:read`）
- `POST /partner/api/product/` - 創建產品（需要 `products:write`）
- `PUT /partner/api/product/{id}` - 更新產品（需要 `products:write`）
- `DELETE /partner/api/product/{id}` - 刪除產品（需要 `products:delete`）

### Users API

- `GET /partner/api/user/` - 取得用戶資訊（需要 `users:read`）

## Token 產生邏輯

每個 Partner 使用相同的邏輯產生 JWT Token：

```javascript
// Node.js
const jwt = require('jsonwebtoken');

const token = jwt.sign(
    {
        sub: 'partner-company-a',      // Partner ID
        iat: Math.floor(Date.now() / 1000),
        exp: Math.floor(Date.now() / 1000) + 3600  // 1 小時後過期
    },
    JWT_SECRET,  // Partner 專屬的 Secret
    { algorithm: 'HS256' }
);
```

## 錯誤處理

### 401 Unauthorized

- **原因**：JWT Token 無效或過期
- **解決**：檢查 JWT Secret 是否正確，確認 Token 未過期

### 403 Forbidden

- **原因**：Partner 沒有訪問此 API 的權限
- **解決**：聯繫 API 提供方申請所需權限

### 其他錯誤

參考範例代碼中的錯誤處理邏輯。

## 安全建議

1. **保護 JWT Secret**
   - 不要將 Secret 硬編碼在代碼中
   - 使用環境變數或密鑰管理服務
   - 不要將 Secret 提交到版本控制

2. **Token 生命週期**
   - 使用合理的過期時間（建議 1-24 小時）
   - 實現 Token 自動刷新機制

3. **HTTPS**
   - 生產環境必須使用 HTTPS
   - 不要在開發環境關閉 SSL 驗證

4. **錯誤處理**
   - 不要在日誌中輸出完整的 JWT Token
   - 實現適當的重試邏輯

## 支援

如有問題，請聯繫 API 提供方。

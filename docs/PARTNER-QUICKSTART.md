# Partner API 介接指南

## 概述

你會從 API 提供方收到以下資訊：

| 項目 | 範例 |
|------|------|
| Partner ID | `partner-company-a` |
| JWT Secret | (安全傳遞的隨機字串) |
| API Base URL | `https://api.example.com` |
| 可用端點 | 依權限配置 |

認證方式：在 HTTP header 帶入 JWT Token（HS256 簽署）。

## JWT Token 格式

| Claim | 必要 | 說明 | 範例 |
|-------|------|------|------|
| `sub` | 必要 | Partner ID | `"partner-company-a"` |
| `iat` | 必要 | Token 簽發時間 (Unix timestamp) | `1735603200` |
| `exp` | 必要 | Token 過期時間 (Unix timestamp) | `1735689600` |
| `iss` | 建議 | 固定值 | `"partner-api-system"` |
| `aud` | 建議 | 固定值 | `"partner-api"` |

演算法：**HS256**（HMAC-SHA256）

## Token 產生範例

### Shell（無外部依賴）

```bash
#!/bin/bash
PARTNER_ID="partner-company-a"
SECRET="your-jwt-secret"
EXP_SECONDS=3600  # 1 小時

HEADER=$(echo -n '{"alg":"HS256","typ":"JWT"}' | openssl base64 -e | tr '+/' '-_' | tr -d '=\n')
NOW=$(date +%s)
PAYLOAD=$(echo -n "{\"sub\":\"${PARTNER_ID}\",\"iss\":\"partner-api-system\",\"aud\":\"partner-api\",\"iat\":${NOW},\"exp\":$((NOW + EXP_SECONDS))}" | openssl base64 -e | tr '+/' '-_' | tr -d '=\n')
SIGNATURE=$(echo -n "${HEADER}.${PAYLOAD}" | openssl dgst -sha256 -hmac "${SECRET}" -binary | openssl base64 -e | tr '+/' '-_' | tr -d '=\n')

TOKEN="${HEADER}.${PAYLOAD}.${SIGNATURE}"
echo "$TOKEN"
```

### Python

```python
import jwt, time, os

token = jwt.encode(
    {
        "sub": "partner-company-a",
        "iss": "partner-api-system",
        "aud": "partner-api",
        "iat": int(time.time()),
        "exp": int(time.time()) + 3600,
    },
    os.getenv("JWT_SECRET"),
    algorithm="HS256",
)
```

需要安裝：`pip install pyjwt`

### Node.js

```javascript
const jwt = require("jsonwebtoken");

const token = jwt.sign(
  {
    sub: "partner-company-a",
    iss: "partner-api-system",
    aud: "partner-api",
  },
  process.env.JWT_SECRET,
  { algorithm: "HS256", expiresIn: "1h" }
);
```

需要安裝：`npm install jsonwebtoken`

### Java

```java
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import java.util.Date;

String token = Jwts.builder()
    .setSubject("partner-company-a")
    .setIssuer("partner-api-system")
    .setAudience("partner-api")
    .setIssuedAt(new Date())
    .setExpiration(new Date(System.currentTimeMillis() + 3600_000))
    .signWith(SignatureAlgorithm.HS256, jwtSecret)
    .compact();
```

依賴：`io.jsonwebtoken:jjwt`

## API 呼叫範例

```bash
# GET — 查詢訂單列表
curl -H "Authorization: Bearer ${TOKEN}" \
     https://api.example.com/partner/api/order/orders

# POST — 建立訂單
curl -X POST \
     -H "Authorization: Bearer ${TOKEN}" \
     -H "Content-Type: application/json" \
     -d '{"customerName":"Test Corp","totalAmount":1500}' \
     https://api.example.com/partner/api/order/orders
```

API 路徑格式：`/partner/api/{service}/{endpoint}`

可用的 service：`order`、`product`、`user`（依你的權限而定）。

## 錯誤代碼

| HTTP 狀態碼 | 說明 | 處理方式 |
|------------|------|----------|
| 401 | Token 無效或過期 | 確認 JWT Secret 正確，重新產生 Token |
| 403 | 無此端點權限 | 確認你的 Partner 有此端點/方法的存取權限 |
| 404 | 端點不存在 | 檢查 API 路徑拼寫 |
| 429 | 請求頻率超過限制 | 降低頻率，使用指數退避重試 |
| 500 | 伺服器錯誤 | 聯繫 API 提供方 |

錯誤回應格式：

```json
{
    "error": "Forbidden",
    "message": "Insufficient permissions for this API"
}
```

## 注意事項

- **Token 有效期**：建議 1-24 小時，到期前自動重新產生
- **Secret 保管**：存放在環境變數或 Secret Manager，不要硬編碼
- **Secret 輪換**：聯繫 API 提供方，輪換後舊 Token 立即失效
- **日誌安全**：不要記錄完整的 JWT Token
- **SSL 驗證**：生產環境必須驗證 SSL 憑證（不要用 `-k` / `verify=False`）

## 完整文件

- [PARTNER-INTEGRATION.md](./PARTNER-INTEGRATION.md) — 完整架構與上線流程
- [ENDPOINT-PERMISSIONS.md](./ENDPOINT-PERMISSIONS.md) — 端點權限模型詳細說明

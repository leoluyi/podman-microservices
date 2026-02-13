# API Key 管理指南

## 概述

Public Nginx 使用 API Key 機制保護對外開放的 Backend APIs (api-order 和 api-product)。

## API Key 驗證機制

### 工作原理

```
1. 客戶端發送請求
   ↓
   GET /api/order/list
   Header: X-API-Key: dev-key-12345
   
2. Nginx 檢查 API Key
   ↓
   map $http_x_api_key $api_client_name {
       "dev-key-12345" → "development"
   }
   
3. 驗證結果
   ↓
   if ($api_client_name = "") {
       return 401 "Unauthorized"
   }
   
4. 代理到後端
   ↓
   proxy_pass http://api-order:8082/
```

### 配置文件位置

- **API Keys 定義**: `/opt/app/nginx-public/conf.d/api-keys.conf`
- **路由配置**: `/opt/app/nginx-public/conf.d/apis.conf`
- **主配置**: `/opt/app/nginx-public/nginx.conf`

## 管理 API Keys

### 查看現有 Keys

```bash
cat /opt/app/nginx-public/conf.d/api-keys.conf
```

預設包含：
```nginx
map $http_x_api_key $api_client_name {
    default "";
    
    # 開發環境
    "dev-key-12345678901234567890"   "development";
    "test-key-abcdefghijklmnopqrs"   "testing";
    
    # 生產環境（範例）
    # "PROD_KEY_REPLACE_ME_001"      "partner-company-a";
}
```

### 生成安全的 API Key

**方法一：使用 OpenSSL（推薦）**

```bash
# 生成 32 字元的 Base64 編碼字串
openssl rand -base64 32

# 輸出範例：
# kX9vF2mN8pQ1rS4tU5vW6xY7zA8bC9dE0fG1hH2iI3j=
```

**方法二：使用 /dev/urandom**

```bash
# 生成 48 字元的英數字字串
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 48 | head -n 1

# 輸出範例：
# Abc123XYZ789def456GHI012jkl345MNO678pqr901STU234
```

**方法三：線上工具**

- https://www.uuidgenerator.net/
- https://randomkeygen.com/

**建議長度：至少 32 字元**

### 新增 API Key

**步驟 1：編輯配置檔**

```bash
vim /opt/app/nginx-public/conf.d/api-keys.conf
```

**步驟 2：新增 Key**

```nginx
map $http_x_api_key $api_client_name {
    default "";
    
    "dev-key-12345678901234567890"          "development";
    "test-key-abcdefghijklmnopqrs"          "testing";
    
    # 新增合作夥伴 A 的 Key
    "kX9vF2mN8pQ1rS4tU5vW6xY7zA8bC9dE0f"   "partner-company-a";
    
    # 新增合作夥伴 B 的 Key
    "Abc123XYZ789def456GHI012jkl345MNO6"   "partner-company-b";
}
```

**步驟 3：驗證配置**

```bash
# 測試 Nginx 配置語法
podman exec public-nginx nginx -t
```

**步驟 4：重新載入**

```bash
# 重啟 Public Nginx
./scripts/restart-service.sh public-nginx

# 或使用 Nginx reload (零停機)
podman exec public-nginx nginx -s reload
```

**步驟 5：測試新 Key**

```bash
curl -i -H "X-API-Key: kX9vF2mN8pQ1rS4tU5vW6xY7zA8bC9dE0f" \
     http://localhost:8090/api/order/
```

### 移除 API Key

**步驟 1：編輯配置檔**

```bash
vim /opt/app/nginx-public/conf.d/api-keys.conf
```

**步驟 2：刪除或註解該行**

```nginx
map $http_x_api_key $api_client_name {
    default "";
    
    "dev-key-12345678901234567890"   "development";
    
    # 停用：已註解
    # "OLD_KEY_TO_REMOVE"             "old-client";
}
```

**步驟 3：重新載入 Nginx**

```bash
podman exec public-nginx nginx -s reload
```

**步驟 4：驗證 Key 已失效**

```bash
curl -i -H "X-API-Key: OLD_KEY_TO_REMOVE" \
     http://localhost:8090/api/order/
# 預期：401 Unauthorized
```

### 更新（輪換）API Key

**安全的輪換流程：**

```bash
# 1. 生成新 Key
NEW_KEY=$(openssl rand -base64 32)
echo "新 Key: $NEW_KEY"

# 2. 同時啟用新舊 Keys（過渡期）
vim /opt/app/nginx-public/conf.d/api-keys.conf
```

```nginx
map $http_x_api_key $api_client_name {
    "OLD_KEY_partner_a"   "partner-company-a";  # 舊 Key
    "NEW_KEY_partner_a"   "partner-company-a";  # 新 Key
}
```

```bash
# 3. 重新載入
podman exec public-nginx nginx -s reload

# 4. 通知客戶端更新為新 Key

# 5. 等待客戶端完全切換（例如 7 天）

# 6. 移除舊 Key
vim /opt/app/nginx-public/conf.d/api-keys.conf
# 刪除 OLD_KEY 那行

# 7. 再次重新載入
podman exec public-nginx nginx -s reload
```

## 進階配置

### 不同權限級別

**場景：部分 API 只給特定客戶**

**步驟 1：定義權限 Map**

```nginx
# /opt/app/nginx-public/conf.d/api-keys.conf

map $http_x_api_key $api_client_name {
    "readonly-key-12345"   "readonly-client";
    "fullaccess-key-678"   "admin-client";
}

map $api_client_name $api_permissions {
    default             "none";
    "readonly-client"   "read";
    "admin-client"      "all";
}
```

**步驟 2：在路由中使用**

```nginx
# /opt/app/nginx-public/conf.d/apis.conf

# 一般端點：所有客戶都可訪問
location /api/order/list {
    if ($api_client_name = "") {
        return 401;
    }
    proxy_pass http://api-order:8082/list;
}

# 管理端點：只有 admin 可訪問
location /api/order/admin/ {
    if ($api_permissions != "all") {
        return 403 '{"error":"Forbidden"}';
    }
    proxy_pass http://api-order:8082/admin/;
}
```

### IP 白名單

**場景：某些 Key 只能從特定 IP 使用**

```nginx
# /opt/app/nginx-public/conf.d/api-keys.conf

# 定義允許的 IP
geo $remote_addr $ip_allowed {
    default         0;
    127.0.0.1       1;  # localhost
    10.0.0.0/8      1;  # 內部網路
    203.0.113.100   1;  # 合作夥伴 A 的公網 IP
}

map $http_x_api_key $api_client_name {
    "partner-a-key"   "partner-a";
}
```

```nginx
# /opt/app/nginx-public/conf.d/apis.conf

location /api/order/ {
    # 檢查 API Key
    if ($api_client_name = "") {
        return 401;
    }
    
    # 檢查 IP（針對 partner-a）
    if ($api_client_name = "partner-a") {
        set $check "${ip_allowed}";
        if ($check = "0") {
            return 403 '{"error":"IP not allowed"}';
        }
    }
    
    proxy_pass http://api-order:8082/;
}
```

### Rate Limiting（速率限制）

**場景：限制每個客戶的請求頻率**

**步驟 1：在主配置定義 zone**

```nginx
# /opt/app/nginx-public/nginx.conf

http {
    # 根據客戶名稱限速
    limit_req_zone $api_client_name zone=api_limit:10m rate=100r/s;
    
    # 或根據 IP 限速
    # limit_req_zone $binary_remote_addr zone=ip_limit:10m rate=10r/s;
    
    include /etc/nginx/conf.d/*.conf;
}
```

**步驟 2：應用到路由**

```nginx
# /opt/app/nginx-public/conf.d/apis.conf

location /api/order/ {
    if ($api_client_name = "") {
        return 401;
    }
    
    # 應用速率限制
    # rate=100r/s, burst 允許突發 20 個請求
    limit_req zone=api_limit burst=20 nodelay;
    
    proxy_pass http://api-order:8082/;
}
```

**測試 Rate Limit：**

```bash
# 用 ab 測試
ab -n 200 -c 10 \
   -H "X-API-Key: dev-key-12345678901234567890" \
   http://localhost:8090/api/order/

# 超過限制的請求會收到 503
```

### 不同 API 使用不同 Keys

**場景：Order API 和 Product API 使用不同的 Keys**

```nginx
# /opt/app/nginx-public/conf.d/api-keys.conf

map $http_x_api_key $api_order_client {
    default "";
    "order-key-12345"   "order-client-a";
}

map $http_x_api_key $api_product_client {
    default "";
    "product-key-67890"   "product-client-b";
}
```

```nginx
# /opt/app/nginx-public/conf.d/apis.conf

location /api/order/ {
    if ($api_order_client = "") {
        return 401;
    }
    proxy_pass http://api-order:8082/;
}

location /api/product/ {
    if ($api_product_client = "") {
        return 401;
    }
    proxy_pass http://api-product:8083/;
}
```

## 安全最佳實踐

### 1. Key 強度

- ✅ 使用至少 32 字元
- ✅ 包含大小寫字母、數字
- ✅ 使用加密安全的隨機生成器
- ❌ 不要使用可預測的字串（如 "api-key-001"）
- ❌ 不要使用常見單詞或日期

### 2. Key 存儲

- ✅ 配置檔權限設為 600
  ```bash
  chmod 600 /opt/app/nginx-public/conf.d/api-keys.conf
  ```
- ✅ 不要提交到版本控制（Git）
  ```bash
  echo "configs/nginx-public/conf.d/api-keys.conf" >> .gitignore
  ```
- ✅ 使用環境變數或 Secrets 管理（進階）
- ❌ 不要記錄在日誌中
- ❌ 不要通過 URL 傳遞（用 Header）

### 3. Key 輪換

- ✅ 定期更換（建議每 3-6 個月）
- ✅ 洩漏時立即更換
- ✅ 使用過渡期策略（新舊並存）
- ✅ 記錄 Key 變更歷史

### 4. 監控與審計

**啟用詳細日誌：**

```nginx
# /opt/app/nginx-public/nginx.conf

log_format detailed '$remote_addr - $api_client_name [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_x_api_key"';  # 記錄 Key (小心日誌安全)

access_log /var/log/nginx/access.log detailed;
```

**分析日誌：**

```bash
# 查看使用最頻繁的客戶
cat /opt/app/nginx-public/logs/access.log \
  | awk '{print $3}' | sort | uniq -c | sort -rn

# 查看失敗的驗證
grep "401" /opt/app/nginx-public/logs/access.log

# 查看特定客戶的請求
grep "partner-company-a" /opt/app/nginx-public/logs/access.log
```

### 5. 其他安全措施

- ✅ 結合 HTTPS（防止 Key 被竊聽）
- ✅ 結合 IP 白名單（雙重驗證）
- ✅ 結合 Rate Limiting（防止濫用）
- ✅ 設定告警（異常流量、失敗次數過多）

## 測試 API Key

### 基本測試

```bash
# 正確的 Key
curl -i -H "X-API-Key: dev-key-12345678901234567890" \
     http://localhost:8090/api/order/

# 錯誤的 Key
curl -i -H "X-API-Key: wrong-key" \
     http://localhost:8090/api/order/

# 沒有 Key
curl -i http://localhost:8090/api/order/
```

### 自動化測試腳本

```bash
#!/bin/bash
# test-api-keys.sh

VALID_KEY="dev-key-12345678901234567890"
INVALID_KEY="wrong-key-99999"
API_URL="http://localhost:8090/api/order/"

echo "測試 API Key 驗證..."

# 測試 1：有效 Key
echo -n "測試有效 Key... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "X-API-Key: $VALID_KEY" $API_URL)
if [ "$HTTP_CODE" != "401" ]; then
    echo "✓ 通過 (HTTP $HTTP_CODE)"
else
    echo "✗ 失敗"
fi

# 測試 2：無效 Key
echo -n "測試無效 Key... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "X-API-Key: $INVALID_KEY" $API_URL)
if [ "$HTTP_CODE" == "401" ]; then
    echo "✓ 通過 (正確拒絕)"
else
    echo "✗ 失敗 (應該返回 401)"
fi

# 測試 3：沒有 Key
echo -n "測試無 Key... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $API_URL)
if [ "$HTTP_CODE" == "401" ]; then
    echo "✓ 通過 (正確拒絕)"
else
    echo "✗ 失敗 (應該返回 401)"
fi
```

## 常見問題

### Q: API Key 應該放在哪裡？

A: **推薦使用 HTTP Header `X-API-Key`**

✅ 好的方式：
```bash
curl -H "X-API-Key: your-key" https://api.example.com/data
```

❌ 不好的方式：
```bash
# URL 參數（會被記錄在日誌、瀏覽器歷史等）
curl https://api.example.com/data?api_key=your-key
```

### Q: 如何在應用程式中使用？

**JavaScript (Fetch API):**
```javascript
fetch('http://localhost:8090/api/order/list', {
  headers: {
    'X-API-Key': 'dev-key-12345678901234567890'
  }
})
```

**Python (requests):**
```python
import requests

headers = {'X-API-Key': 'dev-key-12345678901234567890'}
response = requests.get('http://localhost:8090/api/order/list', 
                       headers=headers)
```

**Java:**
```java
HttpClient client = HttpClient.newHttpClient();
HttpRequest request = HttpRequest.newBuilder()
    .uri(URI.create("http://localhost:8090/api/order/list"))
    .header("X-API-Key", "dev-key-12345678901234567890")
    .build();
```

### Q: 如何管理多個環境的 Keys？

A: 使用環境變數或配置檔分離：

```bash
# 開發環境
export API_KEY="dev-key-12345"

# 測試環境
export API_KEY="test-key-67890"

# 生產環境
export API_KEY="prod-key-xxxxx"
```

### Q: API Key 被洩漏了怎麼辦？

A: **立即行動計畫：**

1. 立刻停用洩漏的 Key
2. 生成新 Key
3. 通知客戶端更新
4. 調查洩漏原因
5. 檢查是否有異常使用
6. 加強安全措施

```bash
# 快速停用
vim /opt/app/nginx-public/conf.d/api-keys.conf
# 刪除或註解洩漏的 Key

podman exec public-nginx nginx -s reload
```

## 遷移到更安全的方案

如果需要更高級的認證：

1. **OAuth 2.0**: 適合第三方應用
2. **JWT (JSON Web Token)**: 適合微服務間認證
3. **mTLS**: 雙向 TLS 認證

這些需要較大的架構調整，API Key 已足夠應付大部分場景。

## 總結

API Key 管理的核心原則：

1. **生成**：使用強隨機字串
2. **存儲**：安全保管，不提交版本控制
3. **使用**：通過 HTTP Header 傳遞
4. **輪換**：定期更新
5. **監控**：記錄使用情況，設定告警
6. **洩漏處理**：有應急計畫

需要更多安全建議？參考：
- OWASP API Security Top 10
- RFC 6750 (OAuth 2.0 Bearer Token)

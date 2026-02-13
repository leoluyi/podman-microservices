# Endpoint 層級權限控制指南

本文檔說明如何配置和使用 **Endpoint 層級的精細權限控制**。

## 概覽

權限控制已從 **API 層級**（orders, products, users）升級到 **Endpoint 層級**，支援：

- ✅ **完全匹配**：精確控制特定路徑（如 `/list`, `/create`）
- ✅ **前綴匹配**：允許路徑下的所有子路徑（如 `/detail/*`）
- ✅ **正則匹配**：靈活匹配動態路徑（如 `/123`, `/456`）
- ✅ **HTTP 方法控制**：針對每個 endpoint 指定允許的方法（GET, POST, PUT, PATCH, DELETE）

## 權限結構

### 配置格式

在 `configs/ssl-proxy/lua/partners-loader.lua` 中：

```lua
_M.partners = {
    ["partner-company-a"] = {
        secret = os.getenv("JWT_SECRET_PARTNER_A"),
        name = "Company A Corp",
        permissions = {
            orders = {
                endpoints = {
                    { pattern = "/list", methods = {"GET"} },
                    { pattern = "/create", methods = {"POST"} },
                    { pattern = "/detail/", methods = {"GET"}, prefix = true },
                    { pattern = "^/%d+$", methods = {"GET", "PUT", "PATCH"}, regex = true }
                }
            }
        }
    }
}
```

### 匹配類型

#### 1. 完全匹配（預設）

```lua
{ pattern = "/list", methods = {"GET"} }
```

- ✅ 允許：`GET /partner/api/order/list`
- ❌ 拒絕：`GET /partner/api/order/list/abc`
- ❌ 拒絕：`POST /partner/api/order/list`

#### 2. 前綴匹配

```lua
{ pattern = "/detail/", methods = {"GET"}, prefix = true }
```

- ✅ 允許：`GET /partner/api/order/detail/`
- ✅ 允許：`GET /partner/api/order/detail/123`
- ✅ 允許：`GET /partner/api/order/detail/abc/xyz`
- ❌ 拒絕：`POST /partner/api/order/detail/123`（方法不允許）
- ❌ 拒絕：`GET /partner/api/order/detail`（沒有結尾斜線）

#### 3. 正則匹配

```lua
{ pattern = "^/%d+$", methods = {"GET", "PUT", "PATCH"}, regex = true }
```

- ✅ 允許：`GET /partner/api/order/123`
- ✅ 允許：`PUT /partner/api/order/456`
- ✅ 允許：`PATCH /partner/api/order/789`
- ❌ 拒絕：`DELETE /partner/api/order/123`（方法不允許）
- ❌ 拒絕：`GET /partner/api/order/abc`（路徑不匹配）

**常用正則模式**：

| 模式 | 說明 | 範例 |
|------|------|------|
| `^/%d+$` | 數字 ID | `/123`, `/456` |
| `^/%w+$` | 字母數字 | `/abc`, `/abc123` |
| `^/[a-f0-9-]+$` | UUID | `/550e8400-e29b-41d4-a716-446655440000` |
| `^/%d+/cancel$` | 數字 ID + 固定路徑 | `/123/cancel` |

## 實際範例

### 範例 1：完整權限 Partner（Company A）

```lua
["partner-company-a"] = {
    secret = os.getenv("JWT_SECRET_PARTNER_A"),
    name = "Company A Corp",
    permissions = {
        orders = {
            endpoints = {
                { pattern = "/", methods = {"GET"} },
                { pattern = "/list", methods = {"GET"} },
                { pattern = "/search", methods = {"GET", "POST"} },
                { pattern = "/create", methods = {"POST"} },
                { pattern = "/detail/", methods = {"GET"}, prefix = true },
                { pattern = "^/%d+$", methods = {"GET", "PUT", "PATCH"}, regex = true },
                { pattern = "^/%d+/cancel$", methods = {"POST"}, regex = true },
                { pattern = "^/%d+/items$", methods = {"GET"}, regex = true }
            }
        },
        products = {
            endpoints = {
                { pattern = "/", methods = {"GET"} },
                { pattern = "/search", methods = {"GET", "POST"} },
                { pattern = "^/%d+$", methods = {"GET", "PUT", "PATCH", "DELETE"}, regex = true }
            }
        },
        users = {
            endpoints = {
                { pattern = "/", methods = {"GET"} },
                { pattern = "^/%d+$", methods = {"GET"}, regex = true }
            }
        }
    }
}
```

**可訪問的 endpoints**：
- ✅ `GET /partner/api/order/list`
- ✅ `POST /partner/api/order/create`
- ✅ `GET /partner/api/order/123`
- ✅ `PUT /partner/api/order/456`
- ✅ `POST /partner/api/order/123/cancel`
- ❌ `DELETE /partner/api/order/123`（沒有 DELETE 權限）

### 範例 2：唯讀 Partner（Company B）

```lua
["partner-company-b"] = {
    secret = os.getenv("JWT_SECRET_PARTNER_B"),
    name = "Company B Ltd",
    permissions = {
        orders = {
            endpoints = {
                { pattern = "/", methods = {"GET"} },
                { pattern = "/list", methods = {"GET"} },
                { pattern = "/search", methods = {"GET"} },
                { pattern = "^/%d+$", methods = {"GET"}, regex = true }
                -- 注意：只有 GET 方法，完全唯讀
            }
        }
    }
}
```

**可訪問的 endpoints**：
- ✅ `GET /partner/api/order/list`
- ✅ `GET /partner/api/order/123`
- ❌ `POST /partner/api/order/create`（沒有此路徑）
- ❌ `PUT /partner/api/order/123`（方法不允許）
- ❌ `DELETE /partner/api/order/123`（方法不允許）

### 範例 3：受限 Partner（Company C）

```lua
["partner-company-c"] = {
    secret = os.getenv("JWT_SECRET_PARTNER_C"),
    name = "Company C Inc",
    permissions = {
        products = {
            endpoints = {
                { pattern = "/", methods = {"GET"} },
                { pattern = "/search", methods = {"GET", "POST"} },
                { pattern = "/create", methods = {"POST"} },
                { pattern = "/detail/", methods = {"GET"}, prefix = true },
                { pattern = "^/%d+$", methods = {"GET", "PUT", "PATCH"}, regex = true }
                -- 注意：沒有 DELETE 方法
            }
        }
    }
}
```

**可訪問的 endpoints**：
- ✅ `GET /partner/api/product/list`
- ✅ `POST /partner/api/product/create`
- ✅ `GET /partner/api/product/123`
- ✅ `PUT /partner/api/product/123`
- ❌ `DELETE /partner/api/product/123`（方法不允許）

## API 路徑映射

當 Partner 發送請求時，系統會自動提取路徑進行匹配：

| 完整 URL | API | 提取路徑 | HTTP 方法 | 說明 |
|---------|-----|---------|----------|------|
| `GET /partner/api/order/` | `orders` | `/` | `GET` | 根路徑 |
| `GET /partner/api/order/list` | `orders` | `/list` | `GET` | 列表 |
| `POST /partner/api/order/create` | `orders` | `/create` | `POST` | 建立 |
| `GET /partner/api/order/123` | `orders` | `/123` | `GET` | 查詢 |
| `PUT /partner/api/order/123` | `orders` | `/123` | `PUT` | 更新 |
| `DELETE /partner/api/order/123` | `orders` | `/123` | `DELETE` | 刪除 |
| `GET /partner/api/order/detail/abc` | `orders` | `/detail/abc` | `GET` | 詳情 |

查詢參數會被自動移除：
- `GET /partner/api/product/search?q=abc` → 路徑: `/search`, 方法: `GET`

## 配置步驟

### 1. 修改 partners-loader.lua

編輯 `configs/ssl-proxy/lua/partners-loader.lua`：

```lua
["partner-company-new"] = {
    secret = os.getenv("JWT_SECRET_PARTNER_NEW"),
    name = "New Partner Corp",
    permissions = {
        orders = {
            endpoints = {
                { pattern = "/list", methods = {"GET"} },
                { pattern = "/search", methods = {"GET"} },
                { pattern = "^/%d+$", methods = {"GET"}, regex = true }
            }
        }
    }
}
```

### 2. 配置 Secret

**開發環境**：

編輯 `quadlet/ssl-proxy.container.d/environment.conf.example`：

```ini
Environment=JWT_SECRET_PARTNER_NEW=dev-secret-partner-new-for-testing-32chars
```

**生產環境**：

```bash
./scripts/manage-partner-secrets.sh create new
```

### 3. 複製配置並重啟

```bash
# 複製配置
cp configs/ssl-proxy/lua/partners-loader.lua /opt/app/configs/ssl-proxy/lua/

# 開發環境
cp quadlet/ssl-proxy.container.d/environment.conf.example \
   ~/.config/containers/systemd/ssl-proxy.container.d/environment.conf

# 重啟服務
systemctl --user restart ssl-proxy
```

## 測試

### 測試腳本

```bash
#!/bin/bash

PARTNER_ID="partner-company-a"
TOKEN=$(./scripts/generate-jwt.sh $PARTNER_ID 2>/dev/null)

# 測試允許的 endpoint
echo "Testing allowed endpoints..."

# GET 請求
curl -k -H "Authorization: Bearer $TOKEN" \
     https://localhost/partner/api/order/list
# 預期：200 OK

# POST 請求
curl -k -X POST -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"item":"test"}' \
     https://localhost/partner/api/order/create
# 預期：200 OK

# PUT 請求
curl -k -X PUT -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"status":"updated"}' \
     https://localhost/partner/api/order/123
# 預期：200 OK

# 測試被拒絕的 endpoint
echo "Testing forbidden endpoints..."

# 方法不允許
curl -k -X DELETE -H "Authorization: Bearer $TOKEN" \
     https://localhost/partner/api/order/123
# 預期：403 Forbidden (Partner A 的 orders 沒有 DELETE)

# 路徑不匹配
curl -k -H "Authorization: Bearer $TOKEN" \
     https://localhost/partner/api/order/unknown
# 預期：403 Forbidden

# Partner B 測試（唯讀）
PARTNER_B_TOKEN=$(./scripts/generate-jwt.sh partner-company-b 2>/dev/null)

# 允許 GET
curl -k -H "Authorization: Bearer $PARTNER_B_TOKEN" \
     https://localhost/partner/api/order/list
# 預期：200 OK

# 拒絕 POST
curl -k -X POST -H "Authorization: Bearer $PARTNER_B_TOKEN" \
     https://localhost/partner/api/order/create
# 預期：403 Forbidden (Partner B 沒有此路徑)

# 拒絕 PUT
curl -k -X PUT -H "Authorization: Bearer $PARTNER_B_TOKEN" \
     https://localhost/partner/api/order/123
# 預期：403 Forbidden (Partner B 只允許 GET)
```

### 查看日誌

```bash
# 查看 SSL Proxy 日誌
./scripts/logs.sh ssl-proxy

# 查看 Partner 訪問日誌
podman exec ssl-proxy tail -f /var/log/nginx/partner-access.log

# 查看權限檢查日誌
podman exec ssl-proxy tail -f /var/log/nginx/error.log | grep "Permission"
```

## 權限設計建議

### 1. 最小權限原則

只授予 Partner 實際需要的權限：

```lua
-- ❌ 不好：授予過多權限
endpoints = {
    { pattern = "/", methods = {"GET", "POST", "PUT", "DELETE"}, prefix = true }
}

-- ✅ 好：精確控制
endpoints = {
    { pattern = "/list", methods = {"GET"} },
    { pattern = "/create", methods = {"POST"} },
    { pattern = "^/%d+$", methods = {"GET", "PUT"}, regex = true }
}
```

### 2. RESTful API 設計

遵循 RESTful 原則，讓路徑和方法語意清晰：

```lua
endpoints = {
    -- 集合操作
    { pattern = "/", methods = {"GET"} },              -- 列表
    { pattern = "/", methods = {"POST"} },             -- 建立（也可用 /create）

    -- 單一資源操作
    { pattern = "^/%d+$", methods = {"GET"}, regex = true },     -- 查詢
    { pattern = "^/%d+$", methods = {"PUT"}, regex = true },     -- 完整更新
    { pattern = "^/%d+$", methods = {"PATCH"}, regex = true },   -- 部分更新
    { pattern = "^/%d+$", methods = {"DELETE"}, regex = true },  -- 刪除

    -- 子資源操作
    { pattern = "^/%d+/items$", methods = {"GET"}, regex = true }
}
```

### 3. 分組相關操作

```lua
-- 唯讀 Partner
endpoints = {
    { pattern = "/", methods = {"GET"} },
    { pattern = "/list", methods = {"GET"} },
    { pattern = "/search", methods = {"GET"} },
    { pattern = "^/%d+$", methods = {"GET"}, regex = true }
}

-- 讀寫 Partner（不含刪除）
endpoints = {
    { pattern = "/", methods = {"GET", "POST"} },
    { pattern = "/create", methods = {"POST"} },
    { pattern = "^/%d+$", methods = {"GET", "PUT", "PATCH"}, regex = true }
}

-- 完整權限 Partner
endpoints = {
    { pattern = "/", methods = {"GET", "POST"} },
    { pattern = "^/%d+$", methods = {"GET", "PUT", "PATCH", "DELETE"}, regex = true }
}
```

## 故障排除

### 問題 1：Permission denied

```
No matching endpoint rule: partner-company-a -> orders /unknown [GET]
```

**原因**：路徑不在允許列表中

**解決**：檢查 `partners-loader.lua` 的 endpoints 配置，添加所需路徑

### 問題 2：Method not allowed

```
Method not allowed: partner-company-b -> orders /create [POST]
```

**原因**：該 endpoint 不允許此 HTTP 方法

**解決**：
1. 如果 Partner 需要此方法，添加到 methods 陣列
2. 如果是故意限制（如唯讀），這是預期行為

### 問題 3：正則不匹配

```
No matching endpoint rule: partner-company-a -> orders /abc [GET]
```

**原因**：正則表達式 `^/%d+$` 只匹配數字

**解決**：
- 使用 `^/%w+$` 匹配字母數字
- 或新增完全匹配規則 `{ pattern = "/abc", methods = {"GET"} }`

### 問題 4：前綴匹配失效

```
No matching endpoint rule: partner-company-a -> orders /detail [GET]
```

**原因**：前綴匹配要求 pattern 以 `/` 結尾

**解決**：確保 pattern 是 `"/detail/"` 並設定 `prefix = true`

## 進階技巧

### 動態路徑參數

```lua
-- 訂單 + 子資源
{ pattern = "^/%d+/items$", methods = {"GET"}, regex = true }
-- 匹配：GET /123/items, GET /456/items

{ pattern = "^/%d+/items/%d+$", methods = {"GET", "PUT", "DELETE"}, regex = true }
-- 匹配：GET /123/items/1, PUT /123/items/2, DELETE /456/items/3

{ pattern = "^/%d+/status$", methods = {"GET", "PUT"}, regex = true }
-- 匹配：GET /123/status, PUT /456/status
```

### 複雜操作控制

```lua
-- 取消訂單（特殊操作）
{ pattern = "^/%d+/cancel$", methods = {"POST"}, regex = true }

-- 退款（需審核）
{ pattern = "^/%d+/refund$", methods = {"POST"}, regex = true }

-- 批次操作
{ pattern = "/batch/create", methods = {"POST"} }
{ pattern = "/batch/update", methods = {"POST"} }
```

### 版本控制

```lua
-- API v1
{ pattern = "/v1/list", methods = {"GET"} }
{ pattern = "^/v1/%d+$", methods = {"GET"}, regex = true }

-- API v2（更多方法）
{ pattern = "/v2/list", methods = {"GET"} }
{ pattern = "^/v2/%d+$", methods = {"GET", "PUT", "PATCH", "DELETE"}, regex = true }
```

## 權限控制層級對比

| 控制維度 | API 層級（舊） | Endpoint 層級（新） |
|---------|-------------|----------------|
| **控制單位** | API + 操作 | API + 路徑 + HTTP 方法 |
| **範例** | `orders` + `read` | `orders` + `/list` + `GET` |
| **路徑控制** | 無 | 完全/前綴/正則 |
| **方法控制** | 粗略（read/write/delete） | 精確（GET/POST/PUT/PATCH/DELETE） |
| **實作複雜度** | 簡單 | 中等 |
| **權限顆粒度** | 粗略 | 非常精細 |
| **適用場景** | 簡單 API | 生產環境精細權控 |

## 參考文檔

- [Partner 整合指南](./PARTNER-INTEGRATION.md) - Partner 端整合文檔
- [部署指南](./DEPLOYMENT.md) - 生產環境配置
- [OpenResty Lua 文檔](https://github.com/openresty/lua-nginx-module) - Lua API 參考

---

**最後更新：2026-02-13**

# Endpoint 層級權限控制指南

## 概覽

權限控制採用 **Endpoint 層級**，支援：

- **完全匹配**：精確控制特定路徑（如 `/list`, `/create`）
- **前綴匹配**：允許路徑下的所有子路徑（如 `/detail/*`）
- **正則匹配**：靈活匹配動態路徑（如 `/123`, `/456`）
- **HTTP 方法控制**：針對每個 endpoint 指定允許的方法

## 配置格式

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

## 匹配類型

### 1. 完全匹配（預設）

```lua
{ pattern = "/list", methods = {"GET"} }
```

- 允許：`GET /partner/api/order/list`
- 拒絕：`GET /partner/api/order/list/abc`（路徑不同）
- 拒絕：`POST /partner/api/order/list`（方法不允許）

### 2. 前綴匹配

```lua
{ pattern = "/detail/", methods = {"GET"}, prefix = true }
```

- 允許：`GET /partner/api/order/detail/123`
- 拒絕：`POST /partner/api/order/detail/123`（方法不允許）
- 拒絕：`GET /partner/api/order/detail`（沒有結尾斜線）

### 3. 正則匹配

```lua
{ pattern = "^/%d+$", methods = {"GET", "PUT", "PATCH"}, regex = true }
```

- 允許：`GET /partner/api/order/123`
- 拒絕：`DELETE /partner/api/order/123`（方法不允許）
- 拒絕：`GET /partner/api/order/abc`（路徑不匹配）

**常用正則模式**：

| 模式 | 說明 | 範例 |
|------|------|------|
| `^/%d+$` | 數字 ID | `/123`, `/456` |
| `^/%w+$` | 字母數字 | `/abc`, `/abc123` |
| `^/[a-f0-9-]+$` | UUID | `/550e8400-e29b-...` |
| `^/%d+/cancel$` | ID + 固定路徑 | `/123/cancel` |

## 完整範例

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

**常用權限模式摘要**：

| 類型 | 特點 | 範例 |
|------|------|------|
| 唯讀 | 只有 GET | `{ pattern = "/list", methods = {"GET"} }` |
| 讀寫 | GET + POST/PUT/PATCH | 上方 orders 範例 |
| 完整 | 含 DELETE | 上方 products 範例 |

## API 路徑映射

Partner 請求 URL 會自動提取路徑進行匹配：

| 完整 URL | API | 提取路徑 | HTTP 方法 |
|---------|-----|---------|----------|
| `GET /partner/api/order/` | `orders` | `/` | `GET` |
| `GET /partner/api/order/list` | `orders` | `/list` | `GET` |
| `POST /partner/api/order/create` | `orders` | `/create` | `POST` |
| `GET /partner/api/order/123` | `orders` | `/123` | `GET` |
| `PUT /partner/api/order/123` | `orders` | `/123` | `PUT` |

查詢參數會被自動移除：`GET /partner/api/product/search?q=abc` -> 路徑: `/search`

## 配置步驟

### 1. 修改 partners-loader.lua

編輯 `configs/ssl-proxy/lua/partners-loader.lua`，新增 Partner 配置。

### 2. 配置 Secret

**開發環境** — 編輯 `quadlet/ssl-proxy.container.d/environment.conf.example`：

```ini
Environment=JWT_SECRET_PARTNER_NEW=dev-secret-partner-new-for-testing-32chars
```

**生產環境**：

```bash
./scripts/manage-partner-secrets.sh create new
```

### 3. 重啟服務

```bash
cp configs/ssl-proxy/lua/partners-loader.lua /opt/app/configs/ssl-proxy/lua/
systemctl --user daemon-reload
systemctl --user restart ssl-proxy
```

## 故障排除

### Permission denied

```
No matching endpoint rule: partner-company-a -> orders /unknown [GET]
```

路徑不在允許列表中。檢查 `partners-loader.lua` 的 endpoints 配置。

### Method not allowed

```
Method not allowed: partner-company-b -> orders /create [POST]
```

該 endpoint 不允許此 HTTP 方法。如需授權，添加到 methods 陣列。

### 正則不匹配

```
No matching endpoint rule: partner-company-a -> orders /abc [GET]
```

`^/%d+$` 只匹配數字。使用 `^/%w+$` 匹配字母數字，或新增完全匹配規則。

### 前綴匹配失效

```
No matching endpoint rule: partner-company-a -> orders /detail [GET]
```

前綴匹配要求 pattern 以 `/` 結尾：`"/detail/"` + `prefix = true`。

## 參考文件

- [PARTNER-INTEGRATION.md](./PARTNER-INTEGRATION.md) — Partner 上線與管理流程
- [DEPLOYMENT.md](./DEPLOYMENT.md) — 生產環境配置

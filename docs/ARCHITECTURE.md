# 架構設計文件

## 目錄

1. [架構概覽](#架構概覽)
2. [架構決策](#架構決策)
3. [端口規劃](#端口規劃)
4. [核心設計原則](#核心設計原則)
5. [Partner JWT 驗證](#partner-jwt-驗證)
6. [服務職責](#服務職責)
7. [網路隔離](#網路隔離)
8. [安全機制](#安全機制)
9. [擴展性](#擴展性)

---

## 架構概覽

### 架構圖

```
                        Internet
                           ↓
                    ┌──────────────┐
                    │   Firewall   │
                    │  (443, 80)   │
                    └──────┬───────┘
                           ↓
              ╔═══════════════════════════╗
              ║   SSL Termination Proxy   ║
              ║   (OpenResty/Nginx)       ║
              ║                           ║
              ║   - SSL 憑證終止          ║
              ║   - Partner JWT 驗證      ║  ← 簡化的 Lua 實作
              ║   - 路由分發              ║
              ╚═══════════╦═══════════════╝
                          ↓ (HTTP)
         ┌────────────────┼────────────────┐
         ↓                ↓                ↓
    ┌─────────┐     ┌─────────┐    ┌──────────────┐
    │Frontend │     │   BFF   │    │ Backend APIs │
    │(Nginx)  │     │ Gateway │    │  (Partner)   │
    │  :80    │     │  :8080  │    └──────────────┘
    └─────────┘     └────┬────┘
                         ↓
              ════════════════════════
              Internal Network (隔離)
              10.89.0.0/24
              ════════════════════════
                         ↓
         ┌───────────────┼───────────────┐
         ↓               ↓               ↓
    ┌─────────┐   ┌──────────┐   ┌───────────┐
    │API-User │   │API-Order │   │API-Product│
    │  :8080  │   │  :8080   │   │   :8080   │
    └─────────┘   └──────────┘   └───────────┘
```

### 核心特性

- ✅ **統一 SSL 終止**：憑證只需掛載一處
- ✅ **Partner JWT 驗證**：簡化的 OpenResty/Lua 實作
- ✅ **完全網路隔離**：Backend APIs 在 internal-net
- ✅ **內部 HTTP 通訊**：簡化配置，提升效能
- ✅ **混合 Debug 模式**：開發環境可開啟 localhost 訪問

---

## 架構決策

### 最終結論：簡化的 Partner JWT 驗證

經過審慎評估，我們採用以下架構：

#### 使用場景澄清

**Partner JWT 驗證場景：**
- Partner Client 使用 JWT Token 訪問 `/partner/api/`
- 固定的合作夥伴，穩定的驗證邏輯
- 不常變動，適合在 Nginx 層處理

**Web/App 場景：**
- BFF 已有既有的 Session 認證機制
- 不需要在 SSL Proxy 層額外驗證

#### 架構方案：簡化的 OpenResty + Lua

```
SSL Proxy (OpenResty)
├─ SSL 終止              ✅ 專注網路層
├─ 反向代理              ✅ 專注網路層
├─ Partner JWT 驗證      ✅ 簡化實作（30-40 行 Lua）
└─ 路由分發              ✅ 專注網路層

BFF (Node.js/Java)
├─ Session 認證          ✅ 既有機制
├─ Web/App API 處理      ✅ 應用層
└─ API 聚合              ✅ 應用層

Backend APIs
└─ 業務邏輯              ✅ 專注業務
```

#### 為什麼使用簡化的 OpenResty？

**適用理由：**

1. **固定的 Partner 認證場景**
   - Partner 數量有限且穩定
   - 驗證邏輯簡單（只檢查 JWT 簽章和過期）
   - 不需要複雜的權限管理

2. **簡化實作（30-40 行）**
   - 只做必要的驗證
   - 避免過度設計
   - 易於維護

3. **效能優先**
   - Nginx 層驗證（~0.5-1ms）
   - 避免額外的網路跳轉
   - Partner API 通常對延遲敏感

4. **職責分離**
   - Nginx：網路層 + 簡單 Partner 認證
   - BFF：應用層 + Web/App Session 認證
   - Backend：業務邏輯

#### 不過度設計的原則

**避免：**
- ❌ 50+ 行的複雜 Lua 邏輯
- ❌ 多層 Claims 檢查（iss, aud, roles）
- ❌ 複雜的錯誤處理
- ❌ 快取機制（過早優化）

**保持：**
- ✅ 簡單的 JWT 驗證（30-40 行）
- ✅ 清晰的錯誤日誌
- ✅ 必要的安全檢查

---

## 端口規劃

### 設計原則

1. **容器內部端口統一化** - 所有 Backend APIs 內部使用 8080
2. **主機端口分層編號** - 清晰識別服務類型
3. **生產完全隔離** - Backend APIs 不暴露到主機
4. **開發綁定 localhost** - Debug 端口只能本機訪問

### 端口配置表

#### 生產環境

| 服務 | 容器內部 | 主機端口 | 訪問方式 | 說明 |
|------|---------|---------|---------|------|
| **SSL Proxy** | 80, 443 | 80, 443 | 對外開放 | 統一 HTTPS 入口 |
| **Frontend** | 80 | - | 內部 | 透過 SSL Proxy 訪問 |
| **BFF** | 8080 | - | 內部 | 透過 SSL Proxy 訪問 |
| **API-User** | 8080 | - | 完全隔離 | internal-net only |
| **API-Order** | 8080 | - | 完全隔離 | internal-net only |
| **API-Product** | 8080 | - | 完全隔離 | internal-net only |

#### 開發環境（Debug 模式）

| 服務 | 主機端口 | 綁定 | 用途 |
|------|---------|------|------|
| SSL Proxy | 80, 443 | 所有介面 | 對外服務 |
| API-User | 8101 | 127.0.0.1 | localhost Debug |
| API-Order | 8102 | 127.0.0.1 | localhost Debug |
| API-Product | 8103 | 127.0.0.1 | localhost Debug |

**Debug 端口特性：**
- 只綁定 `127.0.0.1`，外部無法訪問
- 編號規則：81 + 服務編號（01, 02, 03）
- 生產環境自動禁用

### 端口分配邏輯

```
對外端口：
  443, 80   → SSL Proxy（統一入口）

內部端口（統一）：
  8080      → 所有 Backend APIs（容器內部）
  8080      → BFF（容器內部）
  80        → Frontend（容器內部）

Debug 端口（開發模式）：
  8101-8103 → Backend APIs（127.0.0.1 綁定）

預留擴展：
  8104-8199 → 未來 Backend APIs
  82xx      → 其他服務類型
  90xx      → 監控工具
```

### 端口映射格式

**格式：** `[主機IP:]主機端口:容器端口`

**範例：**

```ini
# 綁定所有網路介面（不安全，只用於對外服務）
PublishPort=443:443

# 只綁定 localhost（安全，用於 Debug）
PublishPort=127.0.0.1:8101:8080

# 不映射（完全隔離，生產環境）
# PublishPort=  （不設定此參數）
```

### 為什麼容器內部端口統一？

**問：** 為什麼所有 Backend APIs 都用 8080？

**答：** 容器是隔離的網路命名空間：

```
容器視角（各自獨立）：
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  API-User   │  │ API-Order   │  │ API-Product │
│  :8080      │  │  :8080      │  │  :8080      │
└─────────────┘  └─────────────┘  └─────────────┘
      ↓                 ↓                 ↓
  各自綁定         各自綁定          各自綁定
  0.0.0.0:8080    0.0.0.0:8080     0.0.0.0:8080
      ↓                 ↓                 ↓
  容器內網路空間是獨立的，不會衝突！
```

**優勢：**
- ✅ 簡化 Dockerfile（統一 EXPOSE 8080）
- ✅ 簡化健康檢查配置
- ✅ 開發環境切換容易
- ✅ 容器內沒有端口衝突

### 防火牆設定

```bash
# 生產環境：只開放 80 和 443
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --reload

# 驗證
sudo firewall-cmd --list-ports
```

**不需要開放的端口：**
- 8080（BFF，內部訪問）
- 81xx（Backend APIs，完全隔離）

### 擴展端口分配

新增第 4 個 Backend API 範例（api-payment）：

```ini
# quadlet/api-payment.container
PublishPort=${DEBUG_PORT_8104}

# api-payment.container.d/environment.conf（Dev only）
[Container]
Environment=DEBUG_PORT_8104=127.0.0.1:8104:8080
```

---

## 核心設計原則

### 1. 統一 SSL 終止

**設計理念：**
- 所有 HTTPS 流量統一在 SSL Proxy 終止
- 內部服務使用 HTTP 通訊（效能優化）
- 憑證只需掛載和管理一處

**優勢：**
- ✅ 憑證管理簡單（單一掛載點）
- ✅ 憑證更新只需重啟 SSL Proxy
- ✅ 內部 HTTP 通訊效能更好
- ✅ 減少憑證同步問題

### 2. Partner JWT 驗證（簡化實作）

**設計理念：**
- Partner Client 固定且穩定
- 驗證邏輯簡單（JWT 簽章 + 過期檢查）
- 在 Nginx 層處理（效能優先）

**實作原則：**
- ✅ 保持簡單（30-40 行 Lua）
- ✅ 只做必要驗證
- ✅ 清晰的錯誤日誌
- ✅ 複雜邏輯放 Backend

**驗證流程：**

```
1. Partner 發送請求
   GET /partner/api/order/
   Authorization: Bearer <JWT_TOKEN>

2. SSL Proxy 驗證 JWT
   - 檢查 Authorization Header
   - 提取 Bearer Token
   - 驗證簽章（HMAC-SHA256）
   - 檢查過期時間

3. 驗證通過
   - 提取 Partner ID (sub)
   - 注入 Header: X-Partner-ID
   - 轉發到 Backend

4. Backend 處理
   - 接收 X-Partner-ID
   - 檢查 Partner 權限（業務邏輯）
   - 返回資料
```

### 3. 完全網路隔離

**Internal Network 設計：**

```ini
[Network]
NetworkName=internal-net
Subnet=10.89.0.0/24
Internal=true  ← 關鍵設定
```

**`Internal=true` 的效果：**
- 創建完全隔離的虛擬網路
- 不連接到主機的網路介面
- 只有連接此網路的容器可互相通訊
- 主機和外部網路無法直接訪問

### 4. 混合 Debug 模式

**生產模式（預設）：**
```bash
./scripts/setup.sh prod
```
- Backend APIs 完全隔離
- 無法從主機直接訪問

**開發模式：**
```bash
./scripts/setup.sh dev
```
- 啟用 localhost Debug 端口
- 127.0.0.1:8101-8103
- 安全且便利

---

## Partner JWT 驗證

### 簡化版配置

#### Nginx 配置（OpenResty）

**nginx.conf（Lua 初始化）：**

```nginx
http {
    # Lua 配置
    lua_package_path "/usr/local/openresty/nginx/lua/?.lua;;";
    lua_shared_dict jwt_cache 10m;
    
    # 初始化 JWT
    init_by_lua_block {
        jwt = require "resty.jwt"
        jwt_secret = os.getenv("JWT_SECRET") or "default-secret"
        ngx.log(ngx.NOTICE, "Partner JWT initialized")
    }
    
    include /etc/nginx/conf.d/*.conf;
}
```

**routes.conf（Partner JWT 驗證）：**

```nginx
# Partner API - Order Service
location /partner/api/order/ {
    # 簡化的 JWT 驗證（30-40 行）
    access_by_lua_block {
        -- 1. 檢查 Authorization Header
        local auth_header = ngx.var.http_authorization
        if not auth_header then
            ngx.log(ngx.ERR, "Missing Authorization from ", ngx.var.remote_addr)
            ngx.status = 401
            ngx.say('{"error":"Missing Authorization header"}')
            return ngx.exit(401)
        end
        
        -- 2. 提取 Token
        local _, _, token = string.find(auth_header, "Bearer%s+(.+)")
        if not token then
            ngx.log(ngx.ERR, "Invalid format from ", ngx.var.remote_addr)
            ngx.status = 401
            ngx.say('{"error":"Invalid Authorization format"}')
            return ngx.exit(401)
        end
        
        -- 3. 驗證 JWT（只檢查簽章和過期）
        local jwt_obj = jwt:verify(jwt_secret, token)
        if not jwt_obj.verified then
            ngx.log(ngx.ERR, "JWT failed: ", jwt_obj.reason)
            ngx.status = 401
            ngx.say('{"error":"Invalid or expired token"}')
            return ngx.exit(401)
        end
        
        -- 4. 提取 Partner ID
        local partner_id = jwt_obj.payload.sub or "unknown"
        ngx.req.set_header("X-Partner-ID", partner_id)
        ngx.log(ngx.INFO, "Authenticated partner=", partner_id)
    }
    
    # 轉發到 Backend
    proxy_pass http://api-order/;
    proxy_set_header X-Partner-ID $http_x_partner_id;
}
```

### JWT Payload 規格

**必要欄位：**

```json
{
  "sub": "partner-company-a",    // Partner ID（必要）
  "exp": 1735689600              // 過期時間（必要）
}
```

**可選欄位：**

```json
{
  "iss": "your-auth-service",    // 發行者（建議）
  "iat": 1735603200              // 發行時間（建議）
}
```

### 產生 Partner JWT

```javascript
// Node.js
const jwt = require('jsonwebtoken');

const token = jwt.sign(
  {
    sub: 'partner-company-a',
    iss: 'your-auth-service',
    exp: Math.floor(Date.now() / 1000) + (60 * 60 * 24 * 365) // 1 年
  },
  JWT_SECRET,
  { algorithm: 'HS256' }
);
```

### 為什麼簡化實作？

#### Partner API 特性

- **固定合作夥伴** - 不需要複雜的角色管理
- **穩定邏輯** - 不常變動
- **簡單需求** - 只需要知道是哪個 Partner

#### 複雜邏輯應該在 Backend

Partner 特定的業務邏輯應該在 Backend API 處理：

```java
// Backend API-Order
@GetMapping("/")
public OrderResponse getOrders(
    @RequestHeader("X-Partner-ID") String partnerId) {
    
    // 在這裡檢查 Partner 權限
    if (!partnerService.hasAccess(partnerId, "orders")) {
        throw new ForbiddenException();
    }
    
    // 業務邏輯...
}
```

#### 維護優勢

- ✅ 程式碼簡潔（30-40 行）
- ✅ 邏輯清晰
- ✅ 容易 Debug
- ✅ 新人容易理解

### 何時需要更複雜的驗證？

只有在以下情況才需要更複雜的實作：

- Partner 數量大幅增加（>100）
- 需要複雜的權限管理
- JWT 邏輯需要頻繁變動

此時應考慮：
- 獨立的 Partner Gateway（Go/Java）
- 或遷移到 BFF 統一管理

---

## 服務職責

### SSL Termination Proxy (OpenResty)

**職責：**
- SSL/TLS 終止
- Partner JWT 驗證（簡化 Lua）
- 路由分發
- 安全 Headers 設定

**關鍵配置：**
- `nginx.conf` - 主配置 + Lua 初始化
- `conf.d/upstream.conf` - Backend 定義
- `conf.d/routes.conf` - 路由規則 + Partner JWT 驗證

### Frontend (Nginx)

**職責：**
- 提供靜態檔案
- SPA 路由支援
- 簡單的健康檢查

**特點：**
- 純 HTTP（透過 SSL Proxy 訪問）
- 不需要 SSL 憑證

### BFF Gateway

**職責：**
- Web/Mobile 應用的統一 API 入口
- Session 認證（既有機制）
- 聚合多個 Backend APIs
- 資料轉換和適配

**通訊模式：**
```
Web/Mobile → SSL Proxy (HTTPS) → BFF (HTTP) → Backend APIs (HTTP)
```

### Backend APIs

**職責：**
- 核心業務邏輯
- 資料庫訪問
- 內部服務通訊
- Partner 權限檢查（業務層面）

**隔離特性：**
- 連接到 internal-net
- 完全隔離（生產模式）
- 透過容器名稱互相訪問

---

## 網路隔離

### 網路拓撲

```
主機網路 (192.168.1.0/24)
    ↓
    ✗ (無法訪問)
    
Internal Network (10.89.0.0/24)
├─ api-user:     10.89.0.2
├─ api-order:    10.89.0.3
├─ api-product:  10.89.0.4
└─ bff:          10.89.0.5

容器 DNS:
├─ api-user     → 10.89.0.2
├─ api-order    → 10.89.0.3
└─ api-product  → 10.89.0.4
```

### 訪問矩陣

| 來源 | 目標 | 端口 | 是否允許 |
|------|------|------|---------|
| 外部 | SSL Proxy | 443/80 | ✅ 允許 |
| 外部 | Frontend | 80 | ❌ 拒絕 |
| 外部 | BFF | 8080 | ❌ 拒絕 |
| 外部 | Backend APIs | 8080 | ❌ 拒絕 |
| SSL Proxy | Frontend | 80 | ✅ 允許 |
| SSL Proxy | BFF | 8080 | ✅ 允許 |
| SSL Proxy | Backend APIs | 8080 | ✅ 允許（Partner）|
| BFF | Backend APIs | 8080 | ✅ 允許 |
| 主機（生產）| Backend APIs | - | ❌ 拒絕 |
| 主機（開發）| Backend APIs | 8101-8103 | ✅ 允許 |

---

## 安全機制

### 深度防禦

```
Layer 1: SSL/TLS 加密（傳輸層）
         ↓
Layer 2: Partner JWT 驗證（應用層，簡化）
         ↓
Layer 3: 網路隔離（網路層）
         ↓
Layer 4: 資源限制（容器層）
```

### 最小權限原則

- Backend APIs 無法直接對外
- 只暴露必要的端點
- 容器資源限制
- Rootless 容器（Podman）

### 審計追蹤

**日誌記錄：**
- SSL Proxy: Partner JWT 驗證日誌
- Backend: 業務操作 + Partner ID
- systemd journald: 容器生命週期

---

## 擴展性

### 水平擴展

**當前架構（單機）：**
```
SSL Proxy (1) → BFF (1) → Backend APIs (N)
```

**多節點擴展（未來）：**
```
Load Balancer
    ↓
SSL Proxy (M)
    ↓
BFF (N)
    ↓
Backend APIs (X)
```

### 新增服務

1. 建立 Dockerfile
2. 建立 Quadlet 配置
3. 更新 SSL Proxy 路由
4. 部署

---

## 效能優化

### Keepalive 連接

```nginx
upstream bff {
    server bff:8080;
    keepalive 32;  ← 保持 32 個連接
}

proxy_http_version 1.1;
proxy_set_header Connection "";
```

### Gzip 壓縮

```nginx
gzip on;
gzip_types text/plain application/json;
```

---

## 故障容錯

### 健康檢查

```ini
HealthCmd=curl -f http://localhost:8080/health || exit 1
HealthInterval=30s
HealthRetries=3
```

### 自動重啟

```ini
Restart=always
RestartSec=10
```

---

## 總結

此架構平衡了：
- **簡單性**：統一 SSL + 簡化 Partner JWT
- **安全性**：多層防禦 + 網路隔離
- **效能**：內部 HTTP + Keepalive
- **可維護性**：Quadlet + systemd + 簡化 Lua
- **擴展性**：容易新增服務

**適合場景：**
- RHEL 9 / Podman 環境
- 中小型微服務部署
- Partner API 固定且穩定
- Web/App 已有 Session 認證

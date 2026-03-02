# 架構設計文件

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
- ✅ **分層認證機制**：SSL Proxy 只驗證 Partner JWT，BFF 處理 Session
- ✅ **完全網路隔離**：Backend APIs 在 internal-net
- ✅ **內部 HTTP 通訊**：簡化配置，提升效能
- ✅ **混合 Debug 模式**：開發環境可開啟 localhost 訪問

---

## 架構決策

### 最終結論：簡化的 Partner JWT 驗證

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
├─ Partner JWT 驗證      ✅ 只驗證 /partner/api/*
└─ 路由分發              ✅ /api/* 直接轉發給 BFF

BFF (Node.js/Java)
├─ Session 認證          ✅ 處理 /api/* 認證
├─ Web/App API 處理      ✅ 應用層邏輯
└─ API 聚合              ✅ 聚合 Backend APIs

Backend APIs
└─ 業務邏輯              ✅ 專注業務
```

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

### 容器內部端口統一

每個容器有獨立的網路命名空間，多個容器各自綁定 `:8080` 不衝突。統一使用 8080 可簡化 Dockerfile、健康檢查和開發環境切換。

### 防火牆設定

生產環境只需開放 80 和 443。設定步驟見 [DEPLOYMENT.md § 防火牆設定](./DEPLOYMENT.md)。

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

所有 HTTPS 流量在 SSL Proxy 終止，內部服務使用 HTTP。憑證只需管理一處，更新只需重啟 SSL Proxy。

### 2. Partner JWT 驗證（簡化實作）

Partner 數量固定，驗證邏輯簡單（JWT 簽章 + 過期），在 Nginx 層處理。Lua 實作維持 30-40 行，複雜業務邏輯放 Backend。

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

## Endpoint 命名與路由設計

### URL Namespace

三個命名空間對應三類消費者，認證責任各自獨立：

```
/                          → Frontend SPA（無認證）
/api/{resource}            → Web/App via BFF（Session 認證，BFF 層）
/partner/api/{service}/    → Partner B2B（JWT 認證，SSL Proxy 層）
```

Partner API 以 service 再分層，每個 service 直連獨立 Backend：

| URL Prefix | Backend 服務 |
|-----------|-------------|
| `/partner/api/user/` | `api-user:8080` |
| `/partner/api/order/` | `api-order:8080` |
| `/partner/api/product/` | `api-product:8080` |

### 反向代理路由表（SSL Proxy 層）

| 請求路徑 | `proxy_pass` | 路徑重寫 | `access_by_lua_block` |
|---------|-------------|---------|----------------------|
| `/` | `frontend:80` | 無 | 無 |
| `/api/*` | `bff:8080/api/*` | 無 | 無 |
| `/partner/api/user/*` | `api-user:8080/` | 自動剝除前綴 | JWT + endpoint 權限 |
| `/partner/api/order/*` | `api-order:8080/` | 自動剝除前綴 | JWT + endpoint 權限 |
| `/partner/api/product/*` | `api-product:8080/` | 自動剝除前綴 | JWT + endpoint 權限 |

### Frontend 內部路由（frontend nginx 層）

`/` 路徑由 SSL Proxy 轉發至 `frontend:80` 後，frontend nginx 再做第二層路由：

| Location | 行為 |
|----------|------|
| `= /health` | 回傳 200，不寫 access log |
| `~* \.(js\|css\|png\|jpg\|…\|woff2)$` | 提供靜態檔，`Cache-Control: public, immutable`，`expires 1y` |
| `/`（fallback） | `try_files $uri $uri/ /index.html`，SPA 路由 fallback |

靜態資源快取設為 `immutable`，需搭配 build 工具的 content hash 檔名（如 `main.a1b2c3.js`），確保版本更新時 URL 變動、快取自動失效。

Document root：`/usr/share/nginx/html`。

**路徑剝除機制：** `proxy_pass http://api-order/;`（尾端 `/`）搭配 `location /partner/api/order/`，Nginx 自動移除 location 前綴。

```
外部請求：  GET /partner/api/order/list
Backend 收到：GET /list
```

### JWT 影響範圍

`access_by_lua_block` 只掛在 `/partner/api/*` 三個 location，其他路徑完全不受影響：

| 路徑 | SSL 終止 | 安全 Headers | JWT 驗證 |
|------|---------|-------------|---------|
| `/` | ✓ | ✓ | — |
| `/api/*` | ✓ | ✓ | — |
| `/partner/api/*` | ✓ | ✓ | ✓ |

`init_by_lua_block` 在 worker 啟動時預載 `resty.jwt`、`partners-loader` 模組，不介入非 partner 路徑的請求處理。

### Partner JWT 驗證流程

```
1. 解析 Authorization: Bearer <token>
2. jwt:load_jwt(token) → 提取 sub（partner_id），不驗證簽章
3. partners.get_secret(partner_id) → 查詢各 Partner 專屬 secret
4. jwt:verify(partner_secret, token) → 驗證簽章 + exp
5. has_endpoint_permission(partner_id, api, path, method)
   ├─ exact match：  path == "/list"
   ├─ prefix match： string.sub(path, 1, #pattern) == pattern
   └─ regex match：  ngx.re.match(path, "^/%d+$")
6. 通過 → 注入 X-Partner-ID、X-Partner-Name，轉發 Backend
7. 失敗 → 401 / 403 JSON，不轉發
```

各 Partner 使用獨立 secret（`JWT_SECRET_PARTNER_A/B/C`），單一 secret 洩漏不連帶影響其他 Partner。

### Partner Endpoint 權限矩陣

| Partner | orders | products | users |
|---------|--------|---------|-------|
| company-a | 讀寫（list / search / create / `{id}` / cancel / items） | 讀寫（含 DELETE） | 唯讀（list / `{id}`） |
| company-b | 唯讀（list / search / `{id}`） | — | — |
| company-c | — | 讀寫（無 DELETE） | — |

---

## 服務職責

### SSL Termination Proxy (OpenResty)

**職責：**
- SSL/TLS 終止
- Partner JWT 驗證（只針對 `/partner/api/*`）
- 路由分發（`/api/*` 直接轉發給 BFF）
- 安全 Headers 設定

**關鍵配置：**
- `nginx.conf` - 主配置 + Lua 初始化
- `conf.d/upstream.conf` - Backend 定義
- `conf.d/routes.conf` - 路由規則 + Partner JWT 驗證

### Frontend (Nginx)

純靜態檔案服務，HTTP only，不處理任何認證。SSL 終止由 SSL Proxy 負責。

**路由行為（`configs/frontend/nginx.conf`）：**

| Location | 行為 |
|----------|------|
| `= /health` | 回傳 200，不寫 access log |
| `/` | `try_files $uri $uri/ /index.html`（SPA fallback） |
| `~* \.(js\|css\|png\|…\|woff2)$` | `Cache-Control: public, immutable`，`expires 1y` |

**SPA fallback** 的作用：前端 router（React Router / Vue Router 等）的路徑（如 `/dashboard/123`）不對應實體檔案，Nginx 一律回傳 `index.html`，由前端 JS 接手路由。

**靜態資源快取策略：** `immutable` 表示瀏覽器在 1 年內不重新驗證。實務上需搭配 build 工具的 content hash 檔名（`main.abc123.js`），確保版本更新後 URL 不同，快取自動失效。

**Document root：** `/usr/share/nginx/html`（build 產物掛入此目錄）。

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



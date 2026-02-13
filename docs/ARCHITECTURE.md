# 架構詳解

## 整體架構

本專案採用前後端分離的微服務架構，使用 Podman + Quadlet 部署在 RHEL 9 系統上。

### 架構圖

```
┌─────────────────────────────────────────────────────┐
│  Server (RHEL 9)                                     │
│                                                     │
│  外部訪問層                                          │
│  ┌──────────────┐                                  │
│  │  Frontend /html .js css   │ :3000 → 外部用戶      │
│  │               │                                  │
│  └──────────────┘                                  │
│                                                    │
│  ┌──────────────┐                                  │
│  │     BFF      │ :8080 → Web/App 客戶端           │
│  │  Gateway     │ (聚合內部 APIs)                  │
│  └──────┬───────┘                                  │
│         │                                           │
│  ┌──────────────┐                                  │
│  │ Public Nginx │ :8090 → 外部合作夥伴             │
│  │ (API Key)    │ (只開放特定 APIs)                │
│  └──────┬───────┘                                  │
│         │                                           │
│  ═══════╪═══════════════════════════════════════   │
│   internal-net (完全隔離網路)                       │
│   10.89.0.0/24                                     │
│         │                                           │
│    ┌────┴────┬─────────┬──────────┐                │
│    │         │         │          │                │
│    ↓         ↓         ↓          ↓                │
│  ┌────────┐┌────────┐┌────────┐                   │
│  │API-User││API-Order│API-Prod│                   │
│  │  :8081 ││  :8082 ⭐│ :8083 ⭐│                   │
│  └────┬───┘└────┬───┘└────┬───┘                   │
│       │         │         │                        │
│       └─────────┴─────────┘                        │
│         API 間互相調用                              │
│         (透過容器名稱)                              │
│                                                     │
│  ⭐ = 透過 Public Nginx 對外                        │
│                                                     │
│         └─→ 外部 Database                          │
└─────────────────────────────────────────────────────┘
```

## 核心設計原則

### 1. 網路隔離

**Internal Network (internal-net)**
- 類型：Internal Network (`Internal=true`)
- 子網：10.89.0.0/24
- 特性：完全隔離，Host 無法直接訪問
- 用途：Backend APIs 之間的內部通訊

**隔離效果：**
```
✓ 允許：api-user → api-order (容器間通訊)
✓ 允許：BFF → api-user (Gateway 訪問)
✓ 允許：Public Nginx → api-order (Gateway 訪問)
✗ 禁止：Host → api-order (網路隔離)
✗ 禁止：外部 → api-order (沒有端口映射)
✗ 禁止：Frontend → api-user (不同網路)
```

### 2. 服務分層

#### Presentation 層
- **Frontend**: 純靜態資源，不連接內部網路
- 透過 BFF 與後端通訊

#### Gateway 層
- **BFF**: 連接 internal-net，聚合內部 APIs，給 Web/App 使用
- **Public Nginx**: 連接 internal-net，API Key 驗證，給外部合作夥伴使用

#### Business Logic 層
- **Backend APIs**: 
  - API-User (純內部)
  - API-Order (可對外，透過 Public Nginx)
  - API-Product (可對外，透過 Public Nginx)
- 所有 APIs 只連接 internal-net
- APIs 之間透過容器名稱互相調用

### 3. 混合 Debug 模式

**開發環境 (dev)**
```ini
# 環境變數設定
Environment=DEBUG_PORT_8082=127.0.0.1:8082:8082

# 效果
✓ Host 可訪問：curl http://localhost:8082/health
✓ 快速 Debug
✓ 本地測試
```

**生產環境 (prod)**
```ini
# 不設定 DEBUG_PORT 變數
# PublishPort=${DEBUG_PORT_8082} → 沒有端口映射

# 效果
✗ Host 無法訪問
✓ 完全隔離
✓ 只能透過 Gateway
```

## 服務依賴關係

### 啟動順序

```
1. internal-net.service          (網路)
   ↓
2. api-*.service                 (Backend APIs)
   ↓
3. public-nginx.service          (Public Gateway)
   bff.service                   (BFF Gateway)
   ↓
4. frontend.service              (Frontend)
```

### systemd 依賴配置

```ini
[Unit]
After=internal-net.service
Requires=internal-net.service  # 必須先有網路
Wants=api-user.service         # 希望有，但非必須
```

## 容器通訊機制

### DNS 解析

Podman 自動為 internal-net 提供 DNS 服務：

```bash
# 在 BFF 容器內
curl http://api-user:8081/api/users
      ↑
      容器名稱自動解析為內部 IP
```

### 服務發現

不需要額外的服務發現工具，直接使用容器名稱：

```javascript
// BFF 配置範例
const API_USER_URL = process.env.API_USER_URL || 'http://api-user:8081';
const API_ORDER_URL = process.env.API_ORDER_URL || 'http://api-order:8082';
```

## 安全機制

### 1. 網路層安全

- Internal Network 完全隔離
- 只有 Gateway 可訪問內部 APIs
- Frontend 與 Backend 網路隔離

### 2. API Key 驗證

**Public Nginx 實作：**

```nginx
# 1. 定義 API Keys
map $http_x_api_key $api_client_name {
    "dev-key-12345"    "development";
    "prod-key-67890"   "partner-a";
}

# 2. 驗證邏輯
location /api/order/ {
    if ($api_client_name = "") {
        return 401 "Unauthorized";
    }
    proxy_pass http://api-order:8082/;
}
```

**使用方式：**

```bash
curl -H "X-API-Key: dev-key-12345" \
     http://localhost:8090/api/order/list
```

### 3. 資源限制

每個容器都設定資源上限：

```ini
[Container]
Memory=512M        # 記憶體限制
MemorySwap=512M    # Swap 限制
CPUQuota=50%       # CPU 限制（50% = 0.5 核心）
```

## 擴展性設計

### 水平擴展

**方式一：手動複製容器**

```bash
# 複製 API-Order 配置
cp api-order.container api-order-2.container

# 修改
ContainerName=api-order-2
Environment=SERVICE_PORT=8084
PublishPort=${DEBUG_PORT_8084}

# 更新 BFF 或 Nginx 配置以負載均衡
```

**方式二：使用 Podman Kube**

未來可轉換為 Kubernetes YAML 並使用 `podman kube play`。

### 垂直擴展

調整資源限制：

```ini
[Container]
Memory=1G
CPUQuota=100%
```

## 監控與日誌

### 日誌位置

- **systemd Journal**: `journalctl --user -u <service>.service`
- **Public Nginx**: `/opt/app/nginx-public/logs/access.log`
- **容器內部**: `podman logs <container-name>`

### 健康檢查

每個容器都配置健康檢查：

```ini
[Container]
HealthCmd=curl -f http://localhost:8082/health || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
```

失敗時 systemd 自動重啟。

### 監控建議

1. **Prometheus + cAdvisor**: 容器指標
2. **Grafana**: 視覺化 Dashboard
3. **Loki**: 日誌聚合
4. **AlertManager**: 告警通知

## 常見問題

### Q: 為什麼不用 Kubernetes？

A: 對於 3-10 個微服務的中小規模部署，Podman + systemd 提供：
- 更簡單的配置
- 更低的資源消耗
- 原生 systemd 整合
- 適合單機或少量節點部署

### Q: 如何新增更多 Backend API？

A: 
1. 複製現有 API 容器配置
2. 修改容器名稱和端口
3. 更新 BFF/Public Nginx 配置
4. 重新載入 systemd

詳見 README 的「擴展指南」。

### Q: 如何實作 HTTPS？

A: 在 Public Nginx 或 BFF 前再加一層反向代理（如 Traefik, Caddy），或直接在 Public Nginx 配置 SSL 憑證。

### Q: 生產環境還需要什麼？

A: 
- CI/CD 流程
- 監控告警
- 備份策略
- 災難恢復計畫
- 日誌輪轉
- 安全審計

## 參考資料

- [Podman Documentation](https://docs.podman.io)
- [Quadlet Guide](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [Nginx Reverse Proxy](https://nginx.org/en/docs/http/ngx_http_proxy_module.html)
- [systemd Service Management](https://www.freedesktop.org/software/systemd/man/systemd.service.html)

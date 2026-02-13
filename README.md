# Podman 微服務架構範例

基於 Podman + Quadlet 的前後端分離微服務容器化部署方案。

## 架構概覽

```
┌─────────────────────────────────────────────────────┐
│  Server (RHEL 9)                                     │
│                                                     │
│  ┌──────────────┐                                  │
│  │  Frontend    │ :3000 → 外部                     │
│  │  (Nginx)     │                                  │
│  └──────────────┘                                  │
│                                                     │
│  ┌──────────────┐                                  │
│  │     BFF      │ :8080 → 外部 (Web/App)          │
│  │  Gateway     │                                  │
│  └──────┬───────┘                                  │
│         │                                           │
│  ┌──────────────┐                                  │
│  │ Public Nginx │ :8090 → 外部 (Partner API)      │
│  │ (API Key驗證) │                                  │
│  └──────┬───────┘                                  │
│         │                                           │
│  ═══════╪═══════════════════════════════════════   │
│   internal-net (隔離網路)                          │
│         │                                           │
│    ┌────┴────┬─────────┬──────────┐                │
│    │         │         │          │                │
│    ↓         ↓         ↓          ↓                │
│  ┌────┐  ┌────┐  ┌────┐                           │
│  │API1│  │API2│  │API3│                           │
│  │User│  │Order│ │Prod│                           │
│  │8081│  │8082│⭐│8083│⭐                          │
│  └────┘  └────┘  └────┘                           │
│   純內部  需對外  需對外                            │
│                                                     │
│  ⭐ = 透過 Public Nginx 對外 (需 API Key)          │
│  🔧 = Debug 模式下可從 localhost 訪問              │
└─────────────────────────────────────────────────────┘
```

## 核心特性

- ✅ **完全網路隔離**：Backend APIs 在 internal-net，預設外部無法訪問
- ✅ **API Key 權限控管**：Public Nginx 提供 API Key 驗證
- ✅ **獨立更新部署**：每個服務獨立容器，互不影響
- ✅ **systemd 依賴管理**：Quadlet 自動處理啟動順序
- ✅ **混合 Debug 模式**：開發環境可開啟 localhost 訪問
- ✅ **健康檢查與自動重啟**：服務異常自動恢復

## 快速開始

### 前置需求

- RHEL 9 / Rocky Linux 9 / AlmaLinux 9
- Podman 4.4+
- systemd 250+
- rootless 模式執行

### 安裝步驟

#### 1. 下載專案

```bash
# 下載並解壓縮
tar -xzf podman-microservices.tar.gz
cd podman-microservices
```

#### 2. 選擇環境模式

**開發/測試環境（推薦）：**
```bash
./scripts/setup.sh dev
```

**生產環境：**
```bash
./scripts/setup.sh prod
```

差異說明：
- **dev 模式**：Backend APIs 綁定到 `127.0.0.1:808x`，方便 debug
- **prod 模式**：Backend APIs 完全隔離，只能透過 Gateway 訪問

#### 3. 配置服務

編輯配置檔：
```bash
# 修改 API 鏡像位置
vim configs/images.env

# 修改 Public Nginx API Keys
vim configs/nginx-public/conf.d/api-keys.conf

# 修改資料庫連線（如需要）
vim quadlet/*.container
```

#### 4. 啟動服務

```bash
# 啟動所有服務
./scripts/start-all.sh

# 檢查狀態
./scripts/status.sh
```

#### 5. 驗證部署

```bash
# 執行整合測試
./scripts/test-connectivity.sh
```

## 目錄結構

```
podman-microservices/
├── README.md                          # 本文件
├── quadlet/                           # Quadlet 配置檔（systemd）
│   ├── internal-net.network           # 內部隔離網路
│   ├── api-user.container             # User API (純內部)
│   ├── api-order.container            # Order API (可對外)
│   ├── api-product.container          # Product API (可對外)
│   ├── public-nginx.container         # Public Nginx (API Key 驗證)
│   ├── bff.container                  # BFF Gateway
│   ├── frontend.container             # Frontend
│   └── *.container.d/                 # 環境變數覆蓋目錄
│       └── environment.conf           # Debug 模式配置
├── configs/                           # 應用程式配置
│   ├── images.env                     # 鏡像定義
│   ├── nginx-public/                  # Public Nginx 配置
│   │   ├── nginx.conf                 # 主配置
│   │   └── conf.d/
│   │       ├── api-keys.conf          # API Key 定義
│   │       └── apis.conf              # API 路由配置
│   ├── bff/                           # BFF 配置（範例）
│   └── frontend/                      # Frontend 配置（範例）
├── scripts/                           # 管理腳本
│   ├── setup.sh                       # 初始化部署
│   ├── start-all.sh                   # 啟動所有服務
│   ├── stop-all.sh                    # 停止所有服務
│   ├── restart-service.sh             # 重啟單一服務
│   ├── status.sh                      # 查看服務狀態
│   ├── logs.sh                        # 查看日誌
│   ├── test-connectivity.sh           # 連通性測試
│   └── cleanup.sh                     # 清理環境
└── docs/                              # 文件
    ├── ARCHITECTURE.md                # 架構詳解
    ├── DEPLOYMENT.md                  # 部署指南
    ├── DEBUG.md                       # Debug 指南
    └── API-KEY-MANAGEMENT.md          # API Key 管理

```

## 常用操作

### 服務管理

```bash
# 查看所有服務狀態
systemctl --user status 'api-*' bff public-nginx frontend

# 重啟單一服務
./scripts/restart-service.sh api-order

# 查看即時日誌
./scripts/logs.sh api-order

# 查看所有 API 日誌
journalctl --user -u 'api-*' -f
```

### Debug 操作

**開發模式（已開啟 Debug）：**
```bash
# 直接測試 API
curl http://localhost:8081/health  # API-User
curl http://localhost:8082/health  # API-Order
curl http://localhost:8083/health  # API-Product

# 測試 BFF
curl http://localhost:8080/api/users

# 測試 Public Nginx (需 API Key)
curl -H "X-API-Key: dev-key-12345" http://localhost:8090/api/order/list
```

**生產模式（完全隔離）：**
```bash
# 透過 Gateway 測試
curl http://localhost:8080/api/users

# 或進入容器內部
podman exec -it api-order curl http://localhost:8082/health
```

### 更新服務

```bash
# 1. 拉取新鏡像
podman pull your-registry/api-order:v2

# 2. 更新配置檔中的鏡像標籤
vim configs/images.env

# 3. 重啟服務
./scripts/restart-service.sh api-order

# 4. 驗證
curl http://localhost:8082/health
```

### 切換環境模式

```bash
# 從 prod 切換到 dev
./scripts/setup.sh dev
./scripts/restart-all.sh

# 從 dev 切換到 prod
./scripts/setup.sh prod
./scripts/restart-all.sh
```

## 網路隔離驗證

### 測試完全隔離（生產模式）

```bash
# 應該失敗（無法從 host 訪問）
curl http://localhost:8082/health
# 預期：Connection refused

# 應該成功（透過 BFF）
curl http://localhost:8080/api/orders

# 應該成功（透過 Public Nginx + API Key）
curl -H "X-API-Key: prod-key-67890" http://localhost:8090/api/order/list
```

### 測試 Debug 模式（開發環境）

```bash
# 應該成功（localhost 訪問）
curl http://localhost:8082/health
# 預期：{"status":"healthy"}
```

## API Key 管理

### 新增 API Key

編輯 `configs/nginx-public/conf.d/api-keys.conf`：

```nginx
map $http_x_api_key $api_client_name {
    "dev-key-12345"    "development";
    "prod-key-67890"   "partner-a";
    "new-key-abcde"    "partner-b";  # 新增
}
```

重新載入 Nginx：
```bash
./scripts/restart-service.sh public-nginx
```

詳細說明請參考：`docs/API-KEY-MANAGEMENT.md`

## 效能調優

### 資源限制調整

編輯 `quadlet/*.container`：

```ini
[Container]
# 調整記憶體限制
Memory=1G

# 調整 CPU 限制
CPUQuota=100%
```

### 健康檢查調整

```ini
[Container]
# 調整檢查間隔
HealthInterval=60s
HealthTimeout=15s
HealthRetries=5
```

## 故障排除

### 服務無法啟動

```bash
# 檢查服務狀態
systemctl --user status api-order

# 查看詳細日誌
journalctl --user -u api-order.service -n 100

# 檢查容器是否存在
podman ps -a | grep api-order

# 檢查鏡像是否存在
podman images | grep api-order
```

### 網路連通問題

```bash
# 檢查網路是否存在
podman network ls | grep internal-net

# 檢查網路詳情
podman network inspect internal-net

# 測試容器間連通性
podman exec -it bff curl http://api-order:8082/health
```

### 依賴啟動問題

```bash
# 手動啟動網路
systemctl --user start internal-net.service

# 按順序啟動服務
systemctl --user start api-user.service
systemctl --user start api-order.service
systemctl --user start api-product.service
systemctl --user start public-nginx.service
systemctl --user start bff.service
systemctl --user start frontend.service
```

完整 Debug 指南：`docs/DEBUG.md`

## 安全建議

### 生產環境檢查清單

- [ ] 切換到 `prod` 模式（完全隔離）
- [ ] 更換預設 API Keys
- [ ] 啟用 HTTPS (需額外配置反向代理)
- [ ] 設定 firewall 規則
- [ ] 配置日誌輪轉
- [ ] 設定監控告警
- [ ] 定期更新鏡像

### API Key 安全

- 使用強隨機字串（至少 32 字元）
- 定期輪換 Keys
- 不同環境使用不同 Keys
- 不要提交 Keys 到版本控制

## 監控與日誌

### 日誌位置

- **Systemd Journal**：`journalctl --user -u <service>`
- **Public Nginx 日誌**：`/opt/app/nginx-public/logs/`
- **容器內部日誌**：`podman logs <container-name>`

### 推薦監控工具

- **Prometheus + Grafana**：容器指標監控
- **Loki**：日誌聚合
- **cAdvisor**：容器效能監控

## 備份與恢復

### 備份配置

```bash
# 備份 Quadlet 配置
tar -czf quadlet-backup-$(date +%Y%m%d).tar.gz \
  /etc/containers/systemd/

# 備份應用配置
tar -czf configs-backup-$(date +%Y%m%d).tar.gz \
  /opt/app/
```

### 恢復配置

```bash
# 停止所有服務
./scripts/stop-all.sh

# 恢復配置
tar -xzf quadlet-backup-20260116.tar.gz -C /

# 重新載入
systemctl --user daemon-reload

# 啟動服務
./scripts/start-all.sh
```

## 擴展指南

### 新增 Backend API

1. 複製現有 API 配置：
```bash
cp quadlet/api-user.container quadlet/api-newservice.container
```

2. 修改配置：
```ini
ContainerName=api-newservice
Environment=SERVICE_PORT=8084
PublishPort=127.0.0.1:8084:8084  # Debug 模式
```

3. 更新 BFF 配置以包含新服務

4. 啟動新服務：
```bash
systemctl --user daemon-reload
systemctl --user start api-newservice.service
```

### 新增需對外的 API

額外需要修改 `configs/nginx-public/conf.d/apis.conf`：

```nginx
location /api/newservice/ {
    if ($api_client_name = "") {
        return 401 "Unauthorized";
    }
    proxy_pass http://api-newservice:8084/;
}
```

## 版本資訊

- **Podman**: 4.4+
- **RHEL**: 9.0+
- **Systemd**: 250+

## 授權

MIT License

## 支援

如有問題，請查閱：
- `docs/` 目錄下的詳細文件
- Podman 官方文件：https://docs.podman.io
- Quadlet 文件：https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html

## 貢獻

歡迎提交 Issue 和 Pull Request！

---

**最後更新：2026-01-16**

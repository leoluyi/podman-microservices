# 部署指南

## 部署前準備

### 系統需求

- **作業系統**: RHEL 9 / Rocky Linux 9 / AlmaLinux 9
- **Podman**: 4.4 或更高版本
- **systemd**: 250 或更高版本
- **CPU**: 建議 2 核心以上
- **記憶體**: 建議 4GB 以上
- **磁碟**: 建議 20GB 以上可用空間

### 檢查系統

```bash
# 檢查作業系統版本
cat /etc/redhat-release

# 檢查 Podman 版本
podman --version

# 檢查 systemd 版本
systemctl --version

# 檢查可用記憶體
free -h

# 檢查磁碟空間
df -h
```

### 安裝 Podman（如未安裝）

```bash
# RHEL 9 / Rocky Linux 9
sudo dnf install -y podman

# 啟用 Podman socket (可選)
systemctl --user enable --now podman.socket
```

### 配置 rootless Podman

```bash
# 檢查 subuid/subgid 配置
grep $USER /etc/subuid
grep $USER /etc/subgid

# 如果沒有，需要配置（需要 root）
# sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER

# 啟用 lingering (開機自動啟動 user services)
loginctl enable-linger $USER
```

## 快速部署

### 1. 下載專案

```bash
# 從 Git (如果有)
git clone https://github.com/your-org/podman-microservices.git
cd podman-microservices

# 或從壓縮檔
tar -xzf podman-microservices.tar.gz
cd podman-microservices
```

### 2. 準備容器鏡像

**方式一：從 Registry 拉取（推薦）**

```bash
# 編輯鏡像配置
vim configs/images.env

# 拉取鏡像
podman pull docker.io/your-registry/api-user:latest
podman pull docker.io/your-registry/api-order:latest
podman pull docker.io/your-registry/api-product:latest
podman pull docker.io/your-registry/bff:latest
podman pull docker.io/your-registry/frontend:latest

# 驗證鏡像
podman images
```

**方式二：載入本地鏡像**

```bash
# 如果有 .tar 檔案
podman load -i api-user.tar
podman load -i api-order.tar
podman load -i api-product.tar
podman load -i bff.tar
podman load -i frontend.tar
```

**方式三：本地建置（開發環境）**

```bash
# 範例：建置 API 鏡像
cd /path/to/api-user-source
podman build -t localhost/api-user:latest .
```

### 3. 配置環境

**編輯 Quadlet 配置檔：**

```bash
# 更新鏡像位置
vim quadlet/api-user.container
# 修改 Image= 那一行

vim quadlet/api-order.container
vim quadlet/api-product.container
vim quadlet/bff.container
vim quadlet/frontend.container
```

**配置資料庫連線：**

```bash
# 編輯每個 API 的環境變數
vim quadlet/api-user.container

# 修改這些行：
# Environment=DB_HOST=your-db-host.example.com
# Environment=DB_PORT=5432
# Environment=DB_NAME=userdb
```

**配置 API Keys：**

```bash
# 生成新的 API Keys
openssl rand -base64 32  # 執行多次生成不同 Keys

# 編輯 API Keys 配置
vim configs/nginx-public/conf.d/api-keys.conf

# 替換預設的 dev-key 和 test-key
```

### 4. 選擇部署模式

**開發/測試環境（推薦開始）：**

```bash
./scripts/setup.sh dev
```

**生產環境：**

```bash
./scripts/setup.sh prod
```

### 5. 啟動服務

```bash
./scripts/start-all.sh
```

### 6. 驗證部署

```bash
# 檢查服務狀態
./scripts/status.sh

# 執行連通性測試
./scripts/test-connectivity.sh

# 查看日誌
./scripts/logs.sh api-order
```

### 7. 測試訪問

```bash
# Frontend
curl http://localhost:3000

# BFF
curl http://localhost:8080/health

# Public Nginx
curl http://localhost:8090/health

# Public API (需 API Key)
curl -H "X-API-Key: your-api-key" \
     http://localhost:8090/api/order/
```

## 詳細配置

### 資料庫連線

每個 Backend API 都需要配置資料庫連線：

```ini
# quadlet/api-user.container
[Container]
Environment=DB_HOST=postgresql.example.com
Environment=DB_PORT=5432
Environment=DB_NAME=userdb
Environment=DB_USER=apiuser

# 密碼建議使用 Podman secrets (進階)
# Secret=db_password,type=env,target=DB_PASSWORD
```

**測試資料庫連線：**

```bash
# 從容器內測試
podman exec api-user curl -v telnet://postgresql.example.com:5432

# 或使用 psql
podman exec api-user psql -h postgresql.example.com -U apiuser -d userdb -c "SELECT 1"
```

### Volume 掛載

如果需要持久化資料或配置：

```ini
# quadlet/api-user.container
[Container]
# 配置檔（唯讀）
Volume=/opt/app/api-user/config:/app/config:ro

# 日誌目錄（可寫）
Volume=/opt/app/api-user/logs:/app/logs:rw

# 資料目錄（可寫）
Volume=/opt/app/api-user/data:/app/data:rw
```

**創建目錄：**

```bash
sudo mkdir -p /opt/app/api-user/{config,logs,data}
sudo chown -R $USER:$USER /opt/app/api-user
```

### 環境變數管理

**方式一：直接在 .container 檔案中**

```ini
[Container]
Environment=SERVICE_NAME=api-user
Environment=LOG_LEVEL=info
```

**方式二：使用 .env 檔案**

```ini
[Container]
EnvironmentFile=/opt/app/api-user/config/.env
```

```bash
# /opt/app/api-user/config/.env
SERVICE_NAME=api-user
LOG_LEVEL=info
DB_HOST=postgresql.example.com
```

### Secrets 管理（進階）

```bash
# 創建 secret
echo "my-db-password" | podman secret create db_password -

# 在容器中使用
[Container]
Secret=db_password,type=env,target=DB_PASSWORD
```

## 生產環境配置

### 1. 切換到生產模式

```bash
./scripts/setup.sh prod
```

### 2. 更新 API Keys

```bash
# 生成生產用的 Keys
for i in {1..3}; do
    openssl rand -base64 32
done

# 更新配置
vim /opt/app/nginx-public/conf.d/api-keys.conf
```

### 3. 調整資源限制

根據實際負載調整：

```ini
# quadlet/api-order.container
[Container]
Memory=1G          # 增加記憶體
CPUQuota=100%      # 增加 CPU
```

### 4. 配置日誌輪轉

```ini
[Container]
LogDriver=journald
LogOpt=max-size=50m
LogOpt=max-file=5
```

或使用系統的 logrotate：

```bash
sudo vim /etc/logrotate.d/nginx-public
```

```
/opt/app/nginx-public/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 your-user your-group
    sharedscripts
    postrotate
        podman exec public-nginx nginx -s reopen
    endscript
}
```

### 5. 設定開機自動啟動

```bash
# 已經在 Quadlet 配置中設定
# [Install]
# WantedBy=default.target

# 確認 lingering 已啟用
loginctl show-user $USER | grep Linger
# Linger=yes
```

### 6. 配置防火牆

```bash
# 如果使用 firewalld
sudo firewall-cmd --permanent --add-port=3000/tcp  # Frontend
sudo firewall-cmd --permanent --add-port=8080/tcp  # BFF
sudo firewall-cmd --permanent --add-port=8090/tcp  # Public Nginx
sudo firewall-cmd --reload

# 或使用 iptables
sudo iptables -A INPUT -p tcp --dport 3000 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8090 -j ACCEPT
```

### 7. 監控設定

**Prometheus + cAdvisor（可選）：**

```bash
# 啟動 cAdvisor
podman run -d \
  --name=cadvisor \
  --publish=8888:8080 \
  --volume=/:/rootfs:ro \
  --volume=/var/run:/var/run:ro \
  --volume=/sys:/sys:ro \
  --volume=/var/lib/containers/storage:/var/lib/containers/storage:ro \
  gcr.io/cadvisor/cadvisor:latest
```

## 更新與維護

### 更新單一服務

```bash
# 1. 拉取新鏡像
podman pull docker.io/your-registry/api-order:v2.0.0

# 2. 更新配置
vim quadlet/api-order.container
# 修改 Image= 到新版本

# 3. 重新載入並重啟
systemctl --user daemon-reload
./scripts/restart-service.sh api-order

# 4. 驗證
curl http://localhost:8082/health
./scripts/logs.sh api-order
```

### 零停機更新策略

**方式一：使用多實例（需要額外配置）**

1. 啟動新版本容器
2. 更新 BFF/Nginx 配置指向新容器
3. 測試新版本
4. 停止舊版本容器

**方式二：使用外部負載均衡器**

1. 將服務從負載均衡器移除
2. 更新服務
3. 測試服務
4. 加回負載均衡器

### 備份

```bash
# 備份 Quadlet 配置
tar -czf quadlet-backup-$(date +%Y%m%d).tar.gz \
  ~/.config/containers/systemd/

# 備份應用配置
tar -czf app-config-backup-$(date +%Y%m%d).tar.gz \
  /opt/app/

# 備份容器數據（如有）
tar -czf app-data-backup-$(date +%Y%m%d).tar.gz \
  /opt/app/*/data/
```

### 恢復

```bash
# 停止服務
./scripts/stop-all.sh

# 恢復配置
tar -xzf quadlet-backup-20260116.tar.gz -C ~/
tar -xzf app-config-backup-20260116.tar.gz -C /

# 重新載入
systemctl --user daemon-reload

# 啟動服務
./scripts/start-all.sh
```

## 故障排除

### 服務無法啟動

```bash
# 檢查 systemd 狀態
systemctl --user status api-order.service

# 查看詳細日誌
journalctl --user -u api-order.service -n 100 --no-pager

# 檢查鏡像
podman images | grep api-order

# 檢查網路
podman network ls
podman network inspect internal-net
```

### 網路連通問題

```bash
# 測試容器間連通
podman exec bff ping api-order
podman exec bff curl http://api-order:8082/health

# 檢查 DNS
podman exec bff nslookup api-order

# 檢查防火牆
sudo firewall-cmd --list-all
```

### 效能問題

```bash
# 查看資源使用
podman stats

# 檢查容器日誌是否有錯誤
./scripts/logs.sh api-order | grep -i error

# 檢查系統資源
top
free -h
df -h
```

## 進階主題

### 多節點部署

雖然本架構設計為單機部署，但可以擴展到多節點：

1. 使用外部負載均衡器（如 HAProxy, Nginx）
2. 使用共享存儲（如 NFS, GlusterFS）
3. 使用外部服務發現（如 Consul, etcd）

### Kubernetes 遷移

Quadlet 配置可以轉換為 Kubernetes YAML：

```bash
# 使用 Podman Kube
podman generate kube api-order > api-order-k8s.yaml

# 在 K8s 中部署
kubectl apply -f api-order-k8s.yaml
```

### CI/CD 整合

**GitLab CI 範例：**

```yaml
# .gitlab-ci.yml
deploy:
  stage: deploy
  script:
    - ssh user@server "cd /app && git pull"
    - ssh user@server "cd /app && ./scripts/setup.sh prod"
    - ssh user@server "cd /app && ./scripts/restart-service.sh api-order"
  only:
    - main
```

## 檢查清單

部署前檢查：

- [ ] Podman 版本 >= 4.4
- [ ] 已啟用 lingering
- [ ] 容器鏡像已準備
- [ ] 資料庫連線已配置
- [ ] API Keys 已更新
- [ ] 防火牆規則已設定
- [ ] 備份策略已規劃

部署後驗證：

- [ ] 所有服務狀態正常
- [ ] 連通性測試通過
- [ ] API Key 驗證正常
- [ ] 網路隔離生效
- [ ] 日誌正常記錄
- [ ] 監控已設定

## 獲取幫助

- 查看文件：`docs/` 目錄
- 執行測試：`./scripts/test-connectivity.sh`
- 查看日誌：`./scripts/logs.sh <service-name>`
- 檢查狀態：`./scripts/status.sh`

## 總結

遵循本指南，你應該能夠：

1. ✅ 在 RHEL 9 上成功部署微服務架構
2. ✅ 配置開發和生產環境
3. ✅ 管理服務生命週期
4. ✅ 處理常見故障
5. ✅ 進行維護和更新

需要更多協助？查閱其他文件：
- `ARCHITECTURE.md` - 架構詳解
- `DEBUG.md` - Debug 指南
- `API-KEY-MANAGEMENT.md` - API Key 管理

# Debug 指南

## Debug 模式切換

### 開發模式（推薦用於開發/測試）

```bash
# 啟用 Debug 模式
./scripts/setup.sh dev

# 重啟服務
./scripts/stop-all.sh
./scripts/start-all.sh
```

**效果：**
- Backend APIs 綁定到 `127.0.0.1:808x`
- 可直接從 Host 訪問：`curl http://localhost:8082/health`
- 方便快速測試和 debug

### 生產模式（完全隔離）

```bash
# 切換到生產模式
./scripts/setup.sh prod

# 重啟服務
./scripts/stop-all.sh
./scripts/start-all.sh
```

**效果：**
- Backend APIs 完全隔離
- 只能透過 Gateway 訪問
- 符合生產環境安全要求

## 常見 Debug 場景

### 1. 檢查服務是否正常運行

```bash
# 查看所有服務狀態
./scripts/status.sh

# 查看特定服務
systemctl --user status api-order.service

# 查看容器狀態
podman ps -a
```

**預期輸出：**
```
CONTAINER ID  IMAGE                     STATUS         PORTS
abc123        nginx:alpine              Up 5 minutes   0.0.0.0:8082->8082/tcp
```

### 2. 查看服務日誌

```bash
# 查看即時日誌
./scripts/logs.sh api-order

# 查看最近 100 行
./scripts/logs.sh api-order 100

# 查看所有 API 服務日誌
./scripts/logs.sh all
```

**常見日誌位置：**
- systemd Journal: `journalctl --user -u api-order.service`
- Nginx 日誌: `/opt/app/nginx-public/logs/access.log`
- 容器日誌: `podman logs api-order`

### 3. 測試 API 連通性

#### 開發模式（Debug 端口已開啟）

```bash
# 直接測試 Backend API
curl http://localhost:8081/health    # API-User
curl http://localhost:8082/health    # API-Order
curl http://localhost:8083/health    # API-Product

# 測試 Gateway
curl http://localhost:8080/api/users # BFF
curl http://localhost:8090/health    # Public Nginx
```

#### 生產模式（完全隔離）

```bash
# 透過 Gateway 測試
curl http://localhost:8080/api/users

# 或進入容器內部測試
podman exec -it bff curl http://api-order:8082/health
```

### 4. 測試網路隔離

```bash
# 執行整合測試
./scripts/test-connectivity.sh
```

這個腳本會測試：
- ✓ 對外服務是否可訪問
- ✓ Debug 模式端口狀態
- ✓ API Key 驗證是否正常
- ✓ 容器間連通性
- ✓ 網路隔離是否生效

### 5. 測試 API Key 驗證

```bash
# 沒有 API Key（應該 401）
curl -i http://localhost:8090/api/order/

# 錯誤的 API Key（應該 401）
curl -i -H "X-API-Key: wrong-key" http://localhost:8090/api/order/

# 正確的 API Key（應該通過）
curl -i -H "X-API-Key: dev-key-12345678901234567890" \
     http://localhost:8090/api/order/
```

## 深入 Debug 技巧

### 進入容器內部

```bash
# 進入 BFF 容器
podman exec -it bff sh

# 在容器內測試其他服務
curl http://api-user:8081/health
curl http://api-order:8082/health
ping api-user
```

### 檢查網路配置

```bash
# 查看網路列表
podman network ls

# 檢查 internal-net 詳情
podman network inspect internal-net

# 查看容器網路連接
podman inspect api-order | grep -A 10 "Networks"
```

**預期輸出（internal-net）：**
```json
{
  "Name": "internal-net",
  "Driver": "bridge",
  "Internal": true,   # 關鍵：必須是 true
  "Subnets": [
    {
      "Subnet": "10.89.0.0/24",
      "Gateway": "10.89.0.1"
    }
  ]
}
```

### 檢查容器詳細資訊

```bash
# 完整配置
podman inspect api-order

# 只看環境變數
podman inspect api-order --format '{{.Config.Env}}'

# 只看端口映射
podman inspect api-order --format '{{.NetworkSettings.Ports}}'

# 只看健康檢查狀態
podman inspect api-order --format '{{.State.Health.Status}}'
```

### 測試 DNS 解析

```bash
# 從 BFF 容器測試
podman exec bff nslookup api-order
podman exec bff nslookup api-user

# 或使用 ping
podman exec bff ping -c 3 api-order
```

### 查看資源使用

```bash
# 所有容器的資源使用
podman stats

# 特定容器
podman stats api-order

# 一次性查看（不持續更新）
podman stats --no-stream
```

## 常見問題排查

### 問題 1：服務無法啟動

**症狀：**
```bash
systemctl --user status api-order
# 顯示：failed (Result: exit-code)
```

**排查步驟：**

```bash
# 1. 查看詳細錯誤
journalctl --user -u api-order.service -n 50

# 2. 檢查鏡像是否存在
podman images | grep api-order

# 3. 嘗試手動啟動容器
podman run --rm -it --network internal-net \
  -e SERVICE_PORT=8082 \
  nginx:alpine sh

# 4. 檢查端口是否被佔用（Dev 模式）
ss -tuln | grep 8082
```

**可能原因：**
- 鏡像不存在或拉取失敗
- 端口已被佔用（Dev 模式）
- 環境變數配置錯誤
- 網路未創建

### 問題 2：容器間無法通訊

**症狀：**
```bash
podman exec bff curl http://api-order:8082
# curl: (6) Could not resolve host: api-order
```

**排查步驟：**

```bash
# 1. 檢查容器是否在同一網路
podman inspect bff | grep -A 5 "Networks"
podman inspect api-order | grep -A 5 "Networks"

# 2. 檢查 DNS 是否工作
podman exec bff nslookup api-order

# 3. 檢查網路配置
podman network inspect internal-net | grep Internal
# 應該是："Internal": true

# 4. 手動測試網路連通性
podman exec bff ping 10.89.0.2  # 替換為 api-order 的實際 IP
```

**可能原因：**
- 容器未連接到 internal-net
- 網路配置錯誤
- DNS 服務異常
- 防火牆規則問題

### 問題 3：API Key 驗證失敗

**症狀：**
```bash
curl -H "X-API-Key: dev-key-12345678901234567890" \
     http://localhost:8090/api/order/
# 返回：401 Unauthorized
```

**排查步驟：**

```bash
# 1. 檢查 Nginx 配置是否正確載入
podman exec public-nginx nginx -t

# 2. 查看 Nginx 日誌
tail -f /opt/app/nginx-public/logs/access.log

# 3. 檢查 API Key 配置
cat /opt/app/nginx-public/conf.d/api-keys.conf | grep dev-key

# 4. 測試 Nginx map 功能
podman exec public-nginx cat /etc/nginx/conf.d/api-keys.conf
```

**可能原因：**
- API Key 配置檔格式錯誤
- Nginx 未正確重載配置
- Header 名稱大小寫問題
- 配置檔路徑錯誤

### 問題 4：Debug 端口無法訪問

**症狀（Dev 模式）：**
```bash
curl http://localhost:8082/health
# curl: (7) Failed to connect to localhost port 8082: Connection refused
```

**排查步驟：**

```bash
# 1. 檢查環境變數配置是否存在
ls -la ~/.config/containers/systemd/api-order.container.d/

# 2. 檢查配置內容
cat ~/.config/containers/systemd/api-order.container.d/environment.conf

# 3. 檢查端口映射
podman port api-order

# 4. 檢查 systemd 是否已重載
systemctl --user daemon-reload
systemctl --user restart api-order

# 5. 確認端口綁定
ss -tuln | grep 8082
```

**可能原因：**
- 忘記執行 `setup.sh dev`
- systemd 未重載配置
- 端口被其他程序佔用
- 防火牆阻擋

### 問題 5：健康檢查失敗

**症狀：**
```bash
podman inspect api-order --format '{{.State.Health.Status}}'
# unhealthy
```

**排查步驟：**

```bash
# 1. 查看健康檢查日誌
podman inspect api-order --format '{{json .State.Health}}' | jq

# 2. 手動執行健康檢查命令
podman exec api-order curl -f http://localhost:8082/health

# 3. 檢查應用是否正常啟動
podman logs api-order | tail -20

# 4. 檢查端口是否監聽
podman exec api-order netstat -tuln | grep 8082
```

**可能原因：**
- 應用啟動失敗
- 健康檢查端點不存在
- 端口配置錯誤
- 啟動時間過長（調整 HealthStartPeriod）

## Debug 工具推薦

### 容器內必備工具

如果你的應用鏡像過於精簡，可以安裝這些工具：

```dockerfile
# 在 Dockerfile 中加入
RUN apk add --no-cache curl netcat-openbsd bind-tools
```

或臨時安裝：
```bash
podman exec -it --user root api-order apk add curl
```

### 本機工具

```bash
# 安裝有用的 debug 工具
sudo dnf install -y bind-utils net-tools tcpdump

# 抓包分析（需要 root）
sudo tcpdump -i any port 8082 -w /tmp/api-order.pcap
```

## 效能 Debug

### 查看響應時間

```bash
# 測試 API 響應時間
curl -w "\nTime: %{time_total}s\n" http://localhost:8082/health

# 或使用 ab (Apache Bench)
ab -n 100 -c 10 http://localhost:8082/health
```

### 查看資源瓶頸

```bash
# 持續監控資源
podman stats

# 查看記憶體詳情
podman inspect api-order --format '{{.HostConfig.Memory}}'

# 查看 CPU 限制
podman inspect api-order --format '{{.HostConfig.CpuQuota}}'
```

## 生產環境 Debug

在生產環境（完全隔離模式）下：

### 透過 Gateway Debug

```bash
# 透過 BFF 訪問內部 API
curl http://localhost:8080/api/internal-status

# 在 BFF 中加入 proxy headers 來 debug
# X-Debug-Backend-Time, X-Backend-Server 等
```

### 使用日誌分析

```bash
# 集中查看所有服務日誌
journalctl --user -u 'api-*' --since "10 minutes ago" \
  | grep ERROR

# JSON 格式日誌分析
tail -f /opt/app/nginx-public/logs/access.log \
  | jq '.status, .request_time'
```

### 臨時啟用 Debug

如果緊急需要：

```bash
# 1. 快速切換到 dev 模式
./scripts/setup.sh dev

# 2. 只重啟需要 debug 的服務
./scripts/restart-service.sh api-order

# 3. Debug 完成後切回 prod
./scripts/setup.sh prod
./scripts/restart-service.sh api-order
```

## 預防性措施

### 1. 健康檢查調優

根據應用啟動時間調整：

```ini
[Container]
HealthStartPeriod=60s  # 給應用足夠啟動時間
HealthInterval=30s     # 定期檢查
HealthRetries=3        # 失敗次數
```

### 2. 日誌輪轉

防止日誌佔滿磁碟：

```ini
[Container]
LogOpt=max-size=50m
LogOpt=max-file=5
```

### 3. 資源預留

確保容器有足夠資源：

```ini
[Container]
Memory=512M
MemoryReservation=256M  # 軟限制
```

## 進階：遠端 Debug

### SSH Tunnel

在遠端 Server 上：

```bash
# 轉發端口到本機
ssh -L 8082:localhost:8082 user@remote-server

# 本機訪問
curl http://localhost:8082/health
```

### Podman Remote

```bash
# 配置遠端連接
export CONTAINER_HOST=ssh://user@remote-server

# 像本地一樣操作
podman ps
podman logs api-order
```

## 總結

Debug 的黃金法則：

1. **從日誌開始**：99% 的問題日誌裡都有線索
2. **分層排查**：網路 → 容器 → 應用
3. **善用工具**：不要盲目猜測
4. **記錄步驟**：方便下次遇到同樣問題

需要更多幫助？查看：
- `./scripts/test-connectivity.sh` - 自動化測試
- `/opt/app/nginx-public/logs/` - Nginx 日誌
- `journalctl --user -u <service>` - systemd 日誌

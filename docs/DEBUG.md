# Debug 指南

## 常見問題

### 1. 服務無法啟動

**檢查步驟：**

```bash
# 查看服務狀態
systemctl --user status <service-name>

# 查看詳細日誌
journalctl --user -u <service-name> -n 100

# 檢查容器
podman ps -a
```

**常見原因：**
- 鏡像不存在
- 端口衝突
- 權限問題

### 2. JWT 驗證失敗

**檢查 JWT Secret 是否一致：**

```bash
# SSL Proxy 中的 Secret
podman inspect ssl-proxy | grep JWT_SECRET

# 產生 Token 時使用的 Secret
echo $JWT_SECRET
```

### 3. Backend API 無法訪問

**生產模式：**
- 預期行為，應透過 SSL Proxy 訪問

**開發模式：**
```bash
curl http://localhost:8101/health
```

### 4. SSL 憑證錯誤

**重新產生憑證：**
```bash
./scripts/generate-certs.sh
./scripts/restart-service.sh ssl-proxy
```

## Debug 工具

### 檢查網路

```bash
# 查看網路
podman network ls
podman network inspect internal-net

# 測試容器間通訊
podman exec bff curl http://api-user:8080/health
```

### 查看容器日誌

```bash
podman logs ssl-proxy
podman logs -f bff
```

### 進入容器

```bash
podman exec -it api-user /bin/sh
```

## 效能調優

### 資源限制

編輯 Quadlet 配置：

```ini
Memory=1G
CPUQuota=100%
```

### 日誌輪轉

```bash
# 配置 journald
sudo vi /etc/systemd/journald.conf
```

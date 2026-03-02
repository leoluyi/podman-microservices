# Debug 指南

## 日誌查閱

### 1. 容器日誌（所有服務）

所有服務的 stdout/stderr 都經由 journald 收集。

```bash
# 查看最新 100 筆，持續追蹤
journalctl --user -u ssl-proxy -n 100 -f

# 使用 wrapper script（預設 50 行，自動帶 -f）
./scripts/logs.sh ssl-proxy
./scripts/logs.sh bff 200
```

可用服務名稱：`ssl-proxy`、`frontend`、`bff`、`api-user`、`api-order`、`api-product`

### 2. SSL Proxy Nginx 日誌

Nginx 日誌透過 volume mount 直接寫入 host 檔案系統（`/opt/app/logs/ssl-proxy/`），容器重啟後仍保留。

```bash
# 主要存取日誌（所有請求）
tail -f /opt/app/logs/ssl-proxy/access.log

# Partner API 稽核日誌（含 JWT user ID）
tail -f /opt/app/logs/ssl-proxy/partner-access.log
grep "partner-company-a" /opt/app/logs/ssl-proxy/partner-access.log

# Nginx 錯誤日誌
tail -f /opt/app/logs/ssl-proxy/error.log
```

**partner-access.log 欄位格式：**

```
$remote_addr - $jwt_user_id [$time_local] "$request_method $uri" $status $body_bytes_sent client_type=$jwt_client_type request_time=$request_time
```

範例：
```
192.168.1.10 - partner-company-a [01/Mar/2026:12:00:00 +0800] "GET /partner/api/user/profile" 200 512 client_type=partner request_time=0.042
```

> 注意：`$uri` 不含查詢字串，避免敏感參數被記錄。

### 3. Frontend Nginx 日誌

Frontend 容器內部的 Nginx 日誌（`/var/log/nginx/`）沒有 volume mount，為 ephemeral storage，容器重啟後消失。

```bash
# 僅在容器存活時可讀取
podman exec frontend cat /var/log/nginx/access.log
podman exec frontend tail -f /var/log/nginx/error.log
```

---

## 常見問題

### 1. 服務無法啟動

```bash
# 查看服務狀態
systemctl --user status <service-name>

# 查看詳細日誌
journalctl --user -u <service-name> -n 100

# 確認容器是否存在
podman ps -a
```

常見原因：鏡像不存在、端口衝突、volume 路徑不存在、權限問題。

### 2. JWT 驗證失敗

```bash
# 確認 ssl-proxy 容器的 JWT Secret 設定
podman inspect ssl-proxy | grep -i jwt_secret

# 確認產生 Token 時使用的 Secret
echo $JWT_SECRET_PARTNER_A
```

確認 Token payload 中的 `sub`（partner ID）與 `configs/ssl-proxy/lua/partners.json` 一致。

### 3. Partner API 返回 403

403 通常是 JWT 驗證通過但 endpoint 權限不足。排查步驟：

```bash
# 查看 partner-access.log 確認請求是否到達 ssl-proxy
tail -20 /opt/app/logs/ssl-proxy/partner-access.log

# 查看 error.log 確認 Lua 層的拒絕原因
tail -50 /opt/app/logs/ssl-proxy/error.log | grep -i "partner\|permission\|403"
```

確認 `configs/ssl-proxy/lua/partners.json` 中，該 partner 的 `allowed_endpoints` 包含被請求的路徑。

### 4. Backend API 無法訪問

**生產模式：** 預期行為，Backend API 不對外暴露，應透過 SSL Proxy 訪問。

**開發模式：**
```bash
curl http://localhost:8101/health
```

### 5. SSL 憑證錯誤

```bash
./scripts/generate-certs.sh
./scripts/restart-service.sh ssl-proxy
```

---

## Debug 工具

### 檢查容器與網路

```bash
# 查看所有容器狀態
podman ps -a

# 查看網路
podman network ls
podman network inspect internal-net

# 測試容器間通訊
podman exec bff curl http://api-user:8080/health
```

### 進入容器

```bash
podman exec -it api-user /bin/sh
```

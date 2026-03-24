# Debug 指南

## 日誌查閱

### 1. 容器日誌（所有服務）

所有服務的 stdout/stderr 都經由 journald 收集。多副本服務使用 `@` 格式的 systemd unit。

```bash
# 查看特定副本日誌
journalctl --user -u api-user@1 -n 100 -f

# 查看同一服務所有副本
journalctl --user -u "api-user@*" -n 100 -f

# 使用 wrapper script
./scripts/logs.sh api-user         # 所有副本
./scripts/logs.sh api-user 1       # 指定副本
./scripts/logs.sh api-user 1 200   # 指定副本，最近 200 行
./scripts/logs.sh ssl-proxy        # singleton 服務
```

可用服務：`ssl-proxy`、`frontend`、`bff`、`api-user`、`api-order`、`api-product`

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
# 指定副本查看（僅在容器存活時可讀取）
podman exec frontend-1 cat /var/log/nginx/access.log
podman exec frontend-2 tail -f /var/log/nginx/error.log
```

---

## 常見問題

### 1. 服務無法啟動

```bash
# 查看服務狀態（多副本使用 @N 格式）
systemctl --user status api-user@1

# 查看詳細日誌
journalctl --user -u api-user@1 -n 100

# 確認容器是否存在
podman ps -a --filter "label=service=api-user"
```

常見原因：鏡像不存在、端口衝突、volume 路徑不存在、權限問題。

### 2. JWT 驗證失敗

```bash
# 確認 ssl-proxy 容器的 JWT Secret 設定
podman inspect ssl-proxy | grep -i jwt_secret

# 確認產生 Token 時使用的 Secret
echo $JWT_SECRET_PARTNER_A
```

確認 Token payload 中的 `sub`（partner ID）與 `configs/shared/ssl-proxy/lua/partners.json` 一致。

### 3. Partner API 返回 403

403 通常是 JWT 驗證通過但 endpoint 權限不足。排查步驟：

```bash
# 查看 partner-access.log 確認請求是否到達 ssl-proxy
tail -20 /opt/app/logs/ssl-proxy/partner-access.log

# 查看 error.log 確認 Lua 層的拒絕原因
tail -50 /opt/app/logs/ssl-proxy/error.log | grep -i "partner\|permission\|403"
```

確認 `configs/shared/ssl-proxy/lua/partners.json` 中，該 partner 的 `allowed_endpoints` 包含被請求的路徑。

### 4. Backend API 無法訪問

**生產模式：** 預期行為，Backend API 不對外暴露，應透過 SSL Proxy 訪問。

**開發模式：** 多副本模式下不映射 debug port，改用 `podman exec` 進入容器：

```bash
podman exec -it api-user-1 curl http://localhost:8080/health
```

### 5. SSL 憑證錯誤

```bash
./scripts/generate-certs.sh
./scripts/restart-service.sh ssl-proxy
```

### 6. 某個副本異常但其他正常

```bash
# 查看特定副本狀態
systemctl --user status api-user@2

# 查看該副本日誌
./scripts/logs.sh api-user 2

# 只重啟有問題的副本（不影響其他副本）
./scripts/restart-service.sh api-user 2
```

### 7. 負載均衡未生效

確認 `upstream.conf` 中的 server 名稱與實際容器名稱一致：

```bash
# 檢查容器名稱
podman ps --filter "label=service=api-user" --format '{{.Names}}'
# 預期輸出：api-user-1, api-user-2

# 確認 upstream.conf
cat configs/shared/ssl-proxy/conf.d/upstream.conf | grep "api-user"
# 預期：server api-user-1:8080 ...
#       server api-user-2:8080 ...

# 重新載入 ssl-proxy 配置（不需重啟容器）
podman exec ssl-proxy nginx -s reload
```

---

## Debug 工具

### 檢查容器與網路

```bash
# 查看所有容器狀態（含副本）
podman ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 查看網路
podman network ls
podman network inspect internal-net

# 測試容器間通訊（指定副本）
podman exec bff-1 curl http://api-user-1:8080/health

# 透過 DNS 別名測試（round-robin）
podman exec bff-1 curl http://api-user:8080/health
```

### 進入容器

```bash
# 指定副本
podman exec -it api-user-1 /bin/sh

# 查看特定服務的所有副本
podman ps --filter "label=service=api-user"
```

### 檢查副本配置

```bash
# 查看目前的副本設定
cat configs/shared/ha.conf

# 查看服務狀態摘要
./scripts/status.sh
```

### Cockpit Web 監控

Cockpit 提供視覺化的容器管理介面，可作為命令列 Debug 工具的補充：

- **容器狀態**：`https://<hostname>:9090` → 以 `appuser` 登入 → Podman 面板
- **即時日誌**：在 Cockpit Podman 面板中點選容器即可查看即時日誌串流
- **資源監控**：CPU、記憶體使用量圖表，快速定位資源瓶頸
- **微服務總覽**：自訂「微服務監控」插件提供所有服務與副本的聚合健康狀態

Cockpit 安裝與設定詳見 [COCKPIT-MONITORING.md](./COCKPIT-MONITORING.md)。

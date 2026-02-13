# 部署指南

## 系統需求

- RHEL 9 / Rocky Linux 9 / AlmaLinux 9
- Podman 4.4+
- systemd 250+
- 磁碟空間: 5GB+
- 記憶體: 4GB+

## 快速部署

### 1. 解壓專案

```bash
tar -xzf podman-microservices.tar.gz
cd podman-microservices
```

### 2. 建置容器鏡像

```bash
# 建置所有服務
for service in api-user api-order api-product bff frontend; do
    cd dockerfiles/$service
    podman build -t localhost/$service:latest .
    cd ../..
done
```

### 3. 初始化環境（開發模式）

```bash
./scripts/setup.sh dev
```

### 4. 啟動服務

```bash
./scripts/start-all.sh
```

### 5. 驗證部署

```bash
./scripts/test-connectivity.sh
```

## 生產環境部署

### 1. 切換到生產模式

```bash
./scripts/setup.sh prod
```

### 2. 更換 JWT Secret

編輯 `quadlet/ssl-proxy.container`:

```ini
Environment=JWT_SECRET=<使用 openssl rand -base64 32 產生>
```

### 3. 使用正式 SSL 憑證（可選）

```bash
# 替換自簽憑證
cp your-cert.crt /opt/app/certs/server.crt
cp your-key.key /opt/app/certs/server.key
chmod 644 /opt/app/certs/server.crt
chmod 600 /opt/app/certs/server.key
```

### 5. 防火牆設定

```bash
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --reload
```

### 6. 啟用開機自啟動

```bash
systemctl --user enable ssl-proxy frontend bff
systemctl --user enable api-user api-order api-product
```

## 故障排除

詳見 `DEBUG.md`

## 更新與維護

### 更新服務

```bash
# 重新建置鏡像
cd dockerfiles/api-user
podman build -t localhost/api-user:latest .

# 重啟服務
./scripts/restart-service.sh api-user
```

### 查看日誌

```bash
./scripts/logs.sh ssl-proxy
```

### 備份

```bash
# 備份配置
tar -czf backup-$(date +%Y%m%d).tar.gz \
    quadlet/ configs/ /opt/app/certs/
```

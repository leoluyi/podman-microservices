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

### 2. 配置 Partner Secrets

#### 自動配置（推薦）

運行 `setup.sh prod` 時會自動生成 Partner Secrets：

```bash
./scripts/setup.sh prod
```

生成的 Secrets 會保存到：
- `/opt/app/configs/ssl-proxy/partner-secrets.txt`

#### 手動更換 Secrets

編輯 `quadlet/ssl-proxy.container`，更換預設的開發 Secrets：

```bash
# 為每個 Partner 生成強隨機 Secret
SECRET_A=$(openssl rand -base64 32)
SECRET_B=$(openssl rand -base64 32)
SECRET_C=$(openssl rand -base64 32)

# 更新 Quadlet 配置
Environment=JWT_SECRET_PARTNER_A=$SECRET_A
Environment=JWT_SECRET_PARTNER_B=$SECRET_B
Environment=JWT_SECRET_PARTNER_C=$SECRET_C
```

#### 提供 Secrets 給 Partner

將對應的 Secret 安全地傳遞給 Partner：

| Partner ID | Secret 變數 | 可訪問的 API |
|-----------|-------------|-------------|
| partner-company-a | JWT_SECRET_PARTNER_A | orders, products, users |
| partner-company-b | JWT_SECRET_PARTNER_B | orders (read-only) |
| partner-company-c | JWT_SECRET_PARTNER_C | products |

**安全傳遞方式**：
- ✅ 加密的密碼管理工具（1Password, LastPass）
- ✅ 安全檔案傳輸（加密 ZIP + 電話告知密碼）
- ❌ 不要使用明文 Email 或 Slack

**詳細 Partner 整合指南**：請參考 [`PARTNER-INTEGRATION.md`](./PARTNER-INTEGRATION.md)

### 3. 使用正式 SSL 憑證（可選）

```bash
# 替換自簽憑證
cp your-cert.crt /opt/app/certs/server.crt
cp your-key.key /opt/app/certs/server.key
chmod 644 /opt/app/certs/server.crt
chmod 600 /opt/app/certs/server.key
```

### 4. 防火牆設定

```bash
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --reload
```

### 5. 啟用開機自啟動

```bash
systemctl --user enable ssl-proxy frontend bff
systemctl --user enable api-user api-order api-product
```

## Partner API 管理

本專案採用**混合 Secret 管理方案**：
- **開發環境**：使用環境檔案（`.container.d/environment.conf`）方便測試
- **生產環境**：使用 Podman Secrets 加密存儲

### Partner Secrets 管理（生產環境）

#### 創建 Partner Secret

```bash
# 互動式創建（會產生隨機 Secret 並顯示給你）
./scripts/manage-partner-secrets.sh create a

# 批量創建所有 Partners
for partner in a b c; do
    ./scripts/manage-partner-secrets.sh create $partner
done
```

#### 查看現有 Secrets

```bash
# 列出所有 Partner Secrets 及其狀態
./scripts/manage-partner-secrets.sh list

# 查看特定 Secret 的詳細資訊（不含實際值）
./scripts/manage-partner-secrets.sh show a
```

#### 輪換 Secret（安全更新）

```bash
# 輪換 Partner A 的 Secret
# 注意：會停用舊 Token，需通知 Partner 更新
./scripts/manage-partner-secrets.sh rotate a
```

#### 刪除 Partner

```bash
# 刪除 Partner Secret（該 Partner 將無法訪問 API）
./scripts/manage-partner-secrets.sh delete c
```

### 測試 Partner API

**開發環境**：
```bash
# setup.sh dev 會自動配置固定測試 Secrets
# 直接產生 Token 即可測試
TOKEN=$(./scripts/generate-jwt.sh partner-company-a)

curl -k -H "Authorization: Bearer $TOKEN" \
     https://localhost/partner/api/order/
```

**生產環境**：
```bash
# 需先創建 Podman Secret
./scripts/manage-partner-secrets.sh create a

# 使用創建時顯示的 Secret 產生 Token
# （或從安全存儲的文件中讀取）
```

### 驗證權限配置

```bash
# 運行完整的 Partner 權限測試
./scripts/test-connectivity.sh

# 測試會驗證：
# - Partner A: 可訪問 orders, products, users
# - Partner B: 只能訪問 orders (read-only)
# - Partner C: 只能訪問 products
```

### 新增 Partner

**開發環境**：

1. 編輯 `quadlet/ssl-proxy.container.d/environment.conf.example`
2. 添加新 Partner 的環境變數：
   ```ini
   Environment=JWT_SECRET_PARTNER_D=dev-secret-partner-d-for-testing-32chars
   ```
3. 編輯 `configs/ssl-proxy/lua/partners-loader.lua` 添加權限配置
4. 複製到 systemd 目錄並重啟：
   ```bash
   cp quadlet/ssl-proxy.container.d/environment.conf.example \
      ~/.config/containers/systemd/ssl-proxy.container.d/environment.conf
   systemctl --user restart ssl-proxy
   ```

**生產環境**：

1. 編輯 `configs/ssl-proxy/lua/partners-loader.lua` 添加權限配置
2. 更新 `quadlet/ssl-proxy.container` 添加 Secret 聲明：
   ```ini
   Secret=jwt-secret-partner-d,type=env,target=JWT_SECRET_PARTNER_D
   Environment=JWT_SECRET_PARTNER_D=fallback-secret-32chars
   ```
3. 創建 Podman Secret：
   ```bash
   ./scripts/manage-partner-secrets.sh create d
   ```
4. 重新部署：
   ```bash
   cp quadlet/ssl-proxy.container ~/.config/containers/systemd/
   systemctl --user daemon-reload
   systemctl --user restart ssl-proxy
   ```

**完整說明**：參考 [`PARTNER-INTEGRATION.md`](./PARTNER-INTEGRATION.md) 的「API 提供方：Partner 設定」章節

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

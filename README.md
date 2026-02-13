# Podman 微服務架構範例（方案 A：統一 SSL Termination）

基於 Podman + Quadlet 的前後端分離微服務容器化部署方案，採用統一 SSL 終止點架構。

## 架構概覽

```
                    ┌─────────────────────────────┐
外部 HTTPS :443 →  │  SSL Termination Proxy      │
                    │  (OpenResty)                │
                    │  - 統一 SSL 終止             │
                    │  - 統一 JWT/API Key 驗證    │
                    │  - 路由分發                 │
                    └──────────┬──────────────────┘
                               │ (內部 HTTP)
                ┌──────────────┼──────────────┐
                ↓              ↓              ↓
          Frontend         BFF            (直接訪問)
          HTTP :80      HTTP :8080       Backend APIs
                              ↓
                    ═════════════════════
                    internal-net (HTTP)
                    ═════════════════════
                              ↓
                ┌─────────────┼─────────────┐
                ↓             ↓             ↓
            API-User      API-Order    API-Product
            :8080         :8080        :8080
```

## 核心特性

- ✅ **統一 SSL 終止**：憑證只需掛載一處
- ✅ **統一 Token 驗證**：JWT + API Key 集中驗證
- ✅ **完全網路隔離**：Backend APIs 在 internal-net
- ✅ **內部 HTTP 通訊**：簡化配置，提升效能
- ✅ **獨立更新部署**：每個服務獨立容器
- ✅ **systemd 依賴管理**：Quadlet 自動處理啟動順序
- ✅ **混合 Debug 模式**：開發環境可開啟 localhost 訪問

## 端口規劃

### 設計原則

1. **容器內部端口統一化** - 所有 Backend APIs 內部使用 8080
2. **主機端口分層編號** - 清晰識別服務類型
3. **生產完全隔離** - Backend APIs 不暴露到主機
4. **開發綁定 localhost** - Debug 端口只能本機訪問

### 生產環境

| 服務 | 容器內部 | 主機端口 | 說明 |
|------|---------|---------|------|
| **SSL Proxy** | 80, 443 | 80, 443 | 統一 HTTPS 入口 |
| Frontend | 80 | - (內部) | 透過 SSL Proxy |
| BFF | 8080 | - (內部) | 透過 SSL Proxy |
| API-User | 8080 | - | 完全隔離（internal-net）|
| API-Order | 8080 | - | 完全隔離（internal-net）|
| API-Product | 8080 | - | 完全隔離（internal-net）|

### 開發環境（Debug 模式）

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

**完整端口設計說明：** 詳見 `docs/PORT-PLANNING.md`

## 快速開始

### 1. 前置需求

- RHEL 9 / Rocky Linux 9 / AlmaLinux 9
- Podman 4.4+
- systemd 250+

### 2. 產生自簽憑證

```bash
./scripts/generate-certs.sh
```

### 3. 選擇環境模式

**開發環境（推薦開始）：**
```bash
./scripts/setup.sh dev
```

**生產環境：**
```bash
./scripts/setup.sh prod
```

### 4. 啟動服務

```bash
./scripts/start-all.sh
```

### 5. 驗證部署

```bash
# 檢查狀態
./scripts/status.sh

# 執行連通性測試
./scripts/test-connectivity.sh
```

### 6. 測試訪問

```bash
# 前端（不需驗證）
curl -k https://localhost/

# API（需要 JWT Token）
# 先產生測試 Token
TOKEN=$(./scripts/generate-jwt.sh test-user)

# 使用 Token 訪問
curl -k -H "Authorization: Bearer $TOKEN" \
     https://localhost/api/users

# Partner API（使用 API Key）
curl -k -H "X-API-Key: dev-key-12345678901234567890" \
     https://localhost/partner/api/order/
```

## 目錄結構

```
podman-microservices/
├── 📄 專案文件
│   ├── README.md                      # 快速開始指南（本文件）
│   ├── SUMMARY.md                     # 專案總結
│   ├── CHECKLIST.md                   # 檢查清單
│   └── FINAL-ASSESSMENT.md            # 架構評估總結
│
├── 📁 quadlet/                        # Systemd Quadlet 服務定義
│   ├── internal-net.network           # 內部隔離網路定義
│   ├── ssl-proxy.container            # SSL Termination Proxy
│   ├── frontend.container             # Frontend 服務
│   ├── bff.container                  # BFF Gateway 服務
│   ├── api-user.container             # User API
│   ├── api-order.container            # Order API
│   ├── api-product.container          # Product API
│   └── *.container.d/                 # Debug 環境變數（開發模式）
│
├── 📁 configs/                        # 配置檔
│   ├── images.env                     # 容器鏡像定義
│   ├── ssl-proxy/                     # SSL Proxy 配置
│   │   ├── nginx.conf                 # 主配置（OpenResty + Lua）
│   │   └── conf.d/
│   │       ├── upstream.conf          # Backend 服務定義
│   │       ├── routes.conf            # 路由 + Partner JWT 驗證
│   │       └── api-keys.conf          # API Key 映射
│   └── frontend/                      # Frontend 配置
│       └── nginx.conf                 # Frontend Nginx 配置
│
├── 📁 dockerfiles/                    # Dockerfile（SUSE BCI）
│   ├── api-user/Dockerfile            # User API (OpenJDK 17)
│   ├── api-order/Dockerfile           # Order API (OpenJDK 17)
│   ├── api-product/Dockerfile         # Product API (OpenJDK 17)
│   ├── bff/Dockerfile                 # BFF Gateway (Node.js 20)
│   └── frontend/Dockerfile            # Frontend (Nginx 1.21)
│
├── 📁 scripts/                        # 管理腳本
│   ├── setup.sh                       # 初始化部署（dev/prod）
│   ├── start-all.sh                   # 啟動所有服務
│   ├── stop-all.sh                    # 停止所有服務
│   ├── status.sh                      # 查看服務狀態
│   ├── restart-service.sh             # 重啟單一服務
│   ├── logs.sh                        # 查看服務日誌
│   ├── test-connectivity.sh           # 連通性測試
│   ├── generate-certs.sh              # 產生自簽 SSL 憑證
│   └── generate-jwt.sh                # 產生測試 JWT Token
│
└── 📁 docs/                           # 詳細文件
    ├── ARCHITECTURE.md                # 架構詳解（含端口規劃、Partner JWT）
    ├── DEPLOYMENT.md                  # 部署指南
    ├── DEBUG.md                       # 故障排除
    └── JWT-TOKEN-GUIDE.md             # JWT Token 使用指南
```

**檔案統計：**
- Markdown 文件：8 個
- Quadlet 配置：7 個服務 + 1 個網路
- Dockerfile：5 個（SUSE BCI）
- Shell 腳本：9 個
- Nginx 配置：5 個
│   ├── api-user.container             # User API
│   ├── api-order.container            # Order API
│   ├── api-product.container          # Product API
│   └── *.container.d/                 # Debug 環境變數
├── configs/                           # 配置檔
│   ├── images.env                     # 鏡像定義
│   ├── ssl-proxy/                     # SSL Proxy 配置
│   │   ├── nginx.conf
│   │   └── conf.d/
│   │       ├── upstream.conf
│   │       ├── routes.conf
│   │       └── api-keys.conf
│   ├── frontend/                      # Frontend 配置
│   │   └── nginx.conf
│   └── bff/                           # BFF 配置
├── dockerfiles/                       # Dockerfile（SUSE BCI）
│   ├── api-user/
│   ├── api-order/
│   ├── api-product/
│   ├── bff/
│   └── frontend/
├── scripts/                           # 管理腳本
│   ├── setup.sh                       # 初始化
│   ├── start-all.sh                   # 啟動所有服務
│   ├── stop-all.sh                    # 停止所有服務
│   ├── status.sh                      # 查看狀態
│   ├── logs.sh                        # 查看日誌
│   ├── test-connectivity.sh           # 連通性測試
│   ├── generate-certs.sh              # 產生自簽憑證
│   └── generate-jwt.sh                # 產生測試 JWT
├── docs/                              # 文件
│   ├── ARCHITECTURE.md                # 架構詳解
│   ├── DEPLOYMENT.md                  # 部署指南
│   ├── DEBUG.md                       # Debug 指南
│   └── JWT-TOKEN-GUIDE.md             # JWT Token 使用指南
└── examples/                          # 範例程式
    ├── api-service/                   # 範例 API 服務
    └── bff-service/                   # 範例 BFF 服務
```

## Token 驗證機制

本專案採用**雙軌驗證**機制，針對不同類型的客戶端使用不同的認證方式：

### 1. Web/Mobile App → Session 驗證（BFF 層）

**路徑：** `/api/*`

**流程：**
```
Client → SSL Proxy (不驗證) → BFF (Session 驗證) → Backend APIs
```

**說明：**
- SSL Proxy 只做路由轉發，不驗證
- BFF 使用既有的 Session 機制進行認證
- 適合複雜的用戶狀態管理

**範例：**
```bash
# 先登入取得 Session
curl -k -X POST https://localhost/api/login \
     -d '{"username":"user","password":"pass"}' \
     -c cookies.txt

# 使用 Session 訪問 API
curl -k https://localhost/api/orders -b cookies.txt
```

### 2. Partner API → JWT Token 驗證（SSL Proxy 層）

**路徑：** `/partner/api/*`

**流程：**
```
Partner → SSL Proxy (JWT 驗證) → Backend APIs（直接）
```

**說明：**
- SSL Proxy 使用 OpenResty + Lua 進行 JWT 驗證
- 適合固定合作夥伴的 B2B API
- 邏輯簡單、效能優先

**範例：**
```bash
# 產生 Partner JWT Token
TOKEN=$(./scripts/generate-jwt.sh partner-company-a)

# 使用 Token 訪問 Partner API
curl -k -H "Authorization: Bearer $TOKEN" \
     https://localhost/partner/api/order/
```

### 3. API Key（向下相容，可選）

**範例：**
```bash
curl -k -H "X-API-Key: dev-key-12345678901234567890" \
     https://localhost/partner/api/order/
```

**架構說明：** 詳見 `docs/ARCHITECTURE.md`  
**JWT 使用指南：** 詳見 `docs/JWT-TOKEN-GUIDE.md`

## 建置容器鏡像

專案包含使用 SUSE BCI 的 Dockerfile 範例：

```bash
# 建置 API 服務
cd dockerfiles/api-user
podman build -t localhost/api-user:latest .

# 建置所有服務
for service in api-user api-order api-product bff frontend; do
    cd dockerfiles/$service
    podman build -t localhost/$service:latest .
    cd ../..
done
```

## 常用操作

### 服務管理

```bash
# 查看所有服務狀態
./scripts/status.sh

# 重啟單一服務
./scripts/restart-service.sh api-order

# 查看日誌
./scripts/logs.sh ssl-proxy
```

### 更新憑證

```bash
# 重新產生憑證
./scripts/generate-certs.sh

# 重啟 SSL Proxy
./scripts/restart-service.sh ssl-proxy
```

### Debug 操作

**開發模式：**
```bash
# 直接測試 Backend API
curl http://localhost:8101/health  # API-User
curl http://localhost:8102/health  # API-Order
curl http://localhost:8103/health  # API-Product
```

**生產模式：**
```bash
# 透過 SSL Proxy
curl -k https://localhost/api/users

# 或進入容器
podman exec -it api-order curl http://localhost:8080/health
```

## 安全建議

### 生產環境檢查清單

- [ ] 切換到 `prod` 模式
- [ ] 更換預設 JWT Secret
- [ ] 更換預設 API Keys
- [ ] 使用正式 SSL 憑證（非自簽）
- [ ] 設定 firewall 規則
- [ ] 配置日誌輪轉
- [ ] 設定監控告警

### JWT Secret 設定

```bash
# 在 ssl-proxy.container 中設定
Environment=JWT_SECRET=your-super-secret-random-string-at-least-32-chars
```

## 網路隔離驗證

```bash
# 執行完整測試
./scripts/test-connectivity.sh
```

測試項目：
- ✅ SSL Proxy 可訪問
- ✅ JWT Token 驗證
- ✅ API Key 驗證
- ✅ Backend APIs 完全隔離（生產模式）
- ✅ 容器間通訊正常

## 故障排除

### 服務無法啟動

```bash
# 檢查服務狀態
systemctl --user status ssl-proxy

# 查看日誌
./scripts/logs.sh ssl-proxy

# 檢查鏡像
podman images | grep ssl-proxy
```

### JWT 驗證失敗

```bash
# 檢查 JWT Secret 是否一致
# 產生 Token 和驗證 Token 必須使用相同的 Secret

# 查看 SSL Proxy 環境變數
podman inspect ssl-proxy | grep JWT_SECRET
```

完整 Debug 指南：`docs/DEBUG.md`

## 擴展指南

### 新增 Backend API

1. 複製 Dockerfile：`dockerfiles/api-user` → `dockerfiles/api-newservice`
2. 複製 Quadlet 配置：`quadlet/api-user.container` → `quadlet/api-newservice.container`
3. 修改配置中的服務名稱和端口
4. 更新 BFF 配置以包含新服務
5. 啟動新服務

## 文件

- [架構詳解](docs/ARCHITECTURE.md) - 完整架構說明
- [端口規劃](docs/PORT-PLANNING.md) - 端口設計原則與完整配置
- [部署指南](docs/DEPLOYMENT.md) - 詳細部署步驟
- [Debug 指南](docs/DEBUG.md) - 故障排除
- [JWT Token 指南](docs/JWT-TOKEN-GUIDE.md) - JWT 使用說明

## 版本資訊

- **Podman**: 4.4+
- **RHEL**: 9.0+
- **systemd**: 250+
- **OpenResty**: 1.21+

## 授權

MIT License

---

**最後更新：2026-02-13**

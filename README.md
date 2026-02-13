# Podman 微服務架構範例

基於 Podman + Quadlet 的前後端分離微服務容器化部署方案，採用統一 SSL 終止點架構。

## 架構概覽

```
                    ┌─────────────────────────────┐
外部 HTTPS :443 →  │  SSL Termination Proxy      │
                    │  (OpenResty)                │
                    │  - 統一 SSL 終止             │
                    │  - 統一 JWT 驗證             │
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
- ✅ **分層認證機制**：BFF 處理 Session，SSL Proxy 驗證 Partner JWT
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

**完整端口設計說明：** 詳見 `docs/ARCHITECTURE.md` 的「端口規劃」章節

## 快速開始

### 0. 安裝依賴（RHEL 9 / Rocky Linux 9 / AlmaLinux 9）

在執行部署腳本前，需要安裝必要的系統套件：

```bash
# 更新系統
sudo dnf update -y

# 安裝 Podman 和容器相關工具
sudo dnf install -y podman podman-plugins

# 安裝腳本執行所需的工具
sudo dnf install -y \
    openssl \
    jq \
    curl \
    git \
    systemd

# 驗證安裝
podman --version    # 應該是 4.4+
systemctl --version # 應該是 250+
jq --version
openssl version
```

**各套件用途說明**：

| 套件 | 用途 | 使用的腳本 |
|------|------|-----------|
| **podman** | 容器運行時 | 所有服務部署 |
| **podman-plugins** | Podman 網路插件 | internal-net 網路設定 |
| **openssl** | SSL 憑證產生、JWT Secret 產生 | `generate-certs.sh`, `manage-partner-secrets.sh` |
| **jq** | JSON 處理工具 | `generate-jwt.sh` |
| **curl** | HTTP 請求工具 | `test-connectivity.sh` |
| **systemd** | 服務管理（通常已安裝） | Quadlet 服務管理 |

**可選套件**（開發除錯用）：

```bash
# 安裝額外的除錯工具（可選）
sudo dnf install -y \
    bind-utils \
    net-tools \
    tcpdump \
    strace
```

**啟用 Podman Socket（Quadlet 必需）**：

```bash
# 啟用 user-level Podman socket
systemctl --user enable --now podman.socket

# 確認 socket 狀態
systemctl --user status podman.socket

# 啟用開機自動啟動（讓使用者服務在登入前啟動）
sudo loginctl enable-linger $(whoami)
```

**檢查 SELinux 狀態（可選）**：

```bash
# 檢查 SELinux 模式
getenforce

# 如果在 Enforcing 模式下遇到權限問題，可以臨時設為 Permissive
# 警告：生產環境請正確配置 SELinux policy，不要禁用
sudo setenforce 0  # 臨時設為 Permissive

# 永久設定（修改配置後需重啟）
# sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
```

### 1. 前置需求

依賴套件已安裝（參考上述步驟 0），確認版本符合：

- ✅ RHEL 9 / Rocky Linux 9 / AlmaLinux 9
- ✅ Podman 4.4+
- ✅ systemd 250+
- ✅ openssl, jq, curl 已安裝

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

# Web/App API（由 BFF 處理 Session 認證）
# 先登入取得 Session
curl -k -X POST https://localhost/api/login \
     -d '{"username":"user","password":"pass"}' \
     -c cookies.txt

# 使用 Session 訪問 API
curl -k https://localhost/api/orders -b cookies.txt

# Partner API（SSL Proxy 驗證 JWT Token）
PARTNER_TOKEN=$(./scripts/generate-jwt.sh partner-company-a)
curl -k -H "Authorization: Bearer $PARTNER_TOKEN" \
     https://localhost/partner/api/order/
```

## 目錄結構

```
podman-microservices/
├── 📄 專案文件
│   └── README.md                      # 快速開始指南（本文件）
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
│   │       └── routes.conf            # 路由 + JWT 驗證（Web/App + Partner）
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
│   └── generate-jwt.sh                # 產生 JWT Token（Partner 可用）
│
├── 📁 examples/                       # 範例代碼
│   └── partner-clients/               # Partner API 客戶端範例
│       ├── README.md                  # Partner 整合說明（Shell/Node.js/Python）
│       ├── nodejs-client.js           # Node.js 客戶端範例
│       └── python-client.py           # Python 客戶端範例
│
└── 📁 docs/                           # 詳細文件
    ├── ARCHITECTURE.md                # 架構詳解（含端口規劃）
    ├── DEPLOYMENT.md                  # 部署指南
    ├── PARTNER-INTEGRATION.md         # Partner API 整合指南（含安全架構）
    ├── ENDPOINT-PERMISSIONS.md        # API 端點權限對照表
    ├── DEBUG.md                       # 故障排除
    └── podman_rootless_min_offline_repo_rhel97_v3.md  # 離線部署指南（Air-Gapped）
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

- **架構說明：** 詳見 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **Partner 整合指南：** 詳見 [docs/PARTNER-INTEGRATION.md](docs/PARTNER-INTEGRATION.md)

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
- [ ] 創建 Partner Podman Secrets（每個 Partner 獨立 Secret）
- [ ] 使用正式 SSL 憑證（非自簽）
- [ ] 設定 firewall 規則
- [ ] 配置日誌輪轉
- [ ] 設定監控告警

### Partner JWT Secrets 管理

**開發環境**：使用固定測試 Secret（由 `setup.sh dev` 自動配置）

**生產環境**：使用 Podman Secrets

```bash
# 創建 Partner Secrets（每個 Partner 獨立）
./scripts/manage-partner-secrets.sh create a
./scripts/manage-partner-secrets.sh create b
./scripts/manage-partner-secrets.sh create c

# 查看現有 Secrets
./scripts/manage-partner-secrets.sh list

# 輪換 Secret（安全更新）
./scripts/manage-partner-secrets.sh rotate a
```

**詳細說明**：參考 [`docs/PARTNER-INTEGRATION.md`](docs/PARTNER-INTEGRATION.md)

## 網路隔離驗證

```bash
# 執行完整測試
./scripts/test-connectivity.sh
```

測試項目：
- ✅ SSL Proxy 可訪問
- ✅ Web/App API 路由（BFF Session 認證）
- ✅ Partner JWT Token 驗證（SSL Proxy 層）
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
# 產生 Token 和驗證 Token 必須使用相同的 Partner Secret

# 開發環境：查看環境變數
podman inspect ssl-proxy | grep JWT_SECRET_PARTNER

# 生產環境：檢查 Podman Secrets
./scripts/manage-partner-secrets.sh list
./scripts/manage-partner-secrets.sh show a

# 重新產生測試 Token
TOKEN=$(./scripts/generate-jwt.sh partner-company-a)
echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null  # 解碼查看 payload
```

完整 Debug 指南：`docs/DEBUG.md`

## 擴展指南

### 新增 Backend API

1. 複製 Dockerfile：`dockerfiles/api-user` → `dockerfiles/api-newservice`
2. 複製 Quadlet 配置：`quadlet/api-user.container` → `quadlet/api-newservice.container`
3. 修改配置中的服務名稱和端口
4. 更新 BFF 配置以包含新服務
5. 啟動新服務

## 離線環境部署（Air-Gapped）

### 適用場景

適合**完全隔離、無網路連線**的生產環境（金融、政府、高安全性場域）。

### 快速摘要

**目標**：在 RHEL 9.7 Air-Gapped 環境部署 Rootless Podman

**策略**：最小 RPM 集合 + 本機 `file://` repo（不建整包 BaseOS/AppStream）

**核心套件**（共 60-120 個 RPM，含依賴）：

| 分類 | 關鍵套件 |
|------|---------|
| **核心** | `podman`, `podman-plugins` |
| **Rootless 必要** | `shadow-utils`, `slirp4netns`, `fuse-overlayfs` |
| **Runtime** | `crun`, `conmon`, `netavark`, `aardvark-dns` |
| **Firewall** | `iptables-nft`, `nftables`, `conntrack-tools` |
| **SELinux** | `container-selinux` |

### 部署流程

#### 階段 1：連網機（Rocky Linux 9.7）

```bash
# 1. 下載 RPM（含完整依賴樹）
mkdir -p /tmp/podman-offline-repo
sudo dnf download --resolve --alldeps --destdir /tmp/podman-offline-repo \
  podman podman-plugins shadow-utils slirp4netns fuse-overlayfs \
  containernetworking-plugins crun conmon netavark aardvark-dns \
  container-selinux iptables-nft iptables-libs nftables \
  libnftnl libnetfilter_conntrack conntrack-tools iproute procps-ng

# 2. 產生 Repo metadata
createrepo_c /tmp/podman-offline-repo

# 3. 打包
cd /tmp
tar czf podman-rootless-offline-repo-rocky97.tgz podman-offline-repo
sha256sum podman-rootless-offline-repo-rocky97.tgz > podman-rootless-offline-repo-rocky97.tgz.sha256
```

#### 階段 2：離線機（RHEL 9.7）

```bash
# 1. 驗證檔案完整性
sha256sum -c podman-rootless-offline-repo-rocky97.tgz.sha256

# 2. 解壓並掛載 Repo
sudo mkdir -p /opt/offline-repos
sudo tar xzf podman-rootless-offline-repo-rocky97.tgz -C /opt/offline-repos
sudo mv /opt/offline-repos/podman-offline-repo /opt/offline-repos/podman

# 3. 建立 Repo 設定
sudo tee /etc/yum.repos.d/podman-offline.repo > /dev/null <<'EOF'
[podman-offline]
name=Podman Rootless Offline Repo
baseurl=file:///opt/offline-repos/podman
enabled=1
gpgcheck=0
metadata_expire=never
EOF

# 4. 安裝
sudo dnf makecache --disablerepo="*" --enablerepo="podman-offline"
sudo dnf install -y --disablerepo="*" --enablerepo="podman-offline" \
  podman podman-plugins shadow-utils slirp4netns fuse-overlayfs \
  containernetworking-plugins crun conmon netavark aardvark-dns \
  container-selinux iptables-nft nftables iproute procps-ng
```

#### 階段 3：Rootless 系統設定

```bash
# 1. 啟用 User Namespace
sudo sysctl -w user.max_user_namespaces=15000
echo "user.max_user_namespaces=15000" | sudo tee /etc/sysctl.d/99-userns.conf

# 2. 建立使用者並設定 subuid/subgid
sudo useradd -m appuser
echo "appuser:100000:65536" | sudo tee -a /etc/subuid
echo "appuser:100000:65536" | sudo tee -a /etc/subgid

# 3. 啟用 Linger（容器登出後持續運行）
sudo loginctl enable-linger appuser

# 4. 驗證
su - appuser
podman info | grep -E 'rootless|networkBackend|graphDriverName'
# 預期: rootless=true, networkBackend=netavark, graphDriverName=overlay
```

### 關鍵設定檢查

| 項目 | 檢查指令 | 預期結果 |
|------|---------|---------|
| User Namespace | `sysctl user.max_user_namespaces` | ≥ 15000 |
| UID/GID Mapping | `which newuidmap newgidmap` | 兩個路徑都存在 |
| Storage Driver | `podman info --format '{{.Store.GraphDriverName}}'` | `overlay` |
| Network Backend | `podman network ls` | 至少有預設網路 |

### 常見問題快速排查

| 症狀 | 原因 | 解決方式 |
|------|------|---------|
| `cannot find newuidmap` | `shadow-utils` 缺失 | 補裝 RPM |
| `cannot setup slirp4netns` | `slirp4netns` 缺失 | 補裝 RPM |
| `graphDriverName: vfs` | `fuse-overlayfs` 缺失 | 補裝後 `podman system reset` |
| `iptables: command not found` | `iptables-nft` 缺失 | 補裝 RPM |
| 容器登出後消失 | 未啟用 linger | `loginctl enable-linger` |

### 映像管理（離線環境）

離線環境無法 `podman pull`，需透過以下流程：

```bash
# 連網機：匯出映像
podman pull docker.io/nginx:alpine
podman save -o nginx-alpine.tar docker.io/nginx:alpine
sha256sum nginx-alpine.tar > nginx-alpine.tar.sha256

# 傳輸後，離線機：匯入映像
sha256sum -c nginx-alpine.tar.sha256
podman load -i nginx-alpine.tar
```

### 完整文件

詳細操作手冊、troubleshooting、維運建議：
- 📖 [Rootless Podman 離線部署完整指南](docs/podman_rootless_min_offline_repo_rhel97_v3.md)

---

## 文件

- [架構詳解](docs/ARCHITECTURE.md) - 完整架構說明
- [部署指南](docs/DEPLOYMENT.md) - 詳細部署步驟
- [Partner 整合指南](docs/PARTNER-INTEGRATION.md) - Partner API 設定與整合
- [Rootless Podman 離線部署](docs/podman_rootless_min_offline_repo_rhel97_v3.md) - Air-Gapped 環境部署指南
- [Debug 指南](docs/DEBUG.md) - 故障排除

## 版本資訊

- **Podman**: 4.4+
- **RHEL**: 9.0+
- **systemd**: 250+
- **OpenResty**: 1.21+

## 授權

MIT License

---

**最後更新：2026-02-13**

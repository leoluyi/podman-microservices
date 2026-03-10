# Cockpit 監控管理指南

| 項目 | 內容 |
|------|------|
| 適用平台 | RHEL 9.7 / Rocky Linux 9.7 |
| Cockpit 版本 | 300+ |
| 整合方式 | cockpit-podman + 自訂插件 |
| 最後更新 | 2026-03 |

---

## 1. 概述

[Cockpit](https://cockpit-project.org/) 是 RHEL 內建的 Web 管理介面，搭配 `cockpit-podman` 插件可直接在瀏覽器管理 Podman 容器。本專案另提供自訂插件 `microservices-monitor`，提供微服務拓撲總覽與聚合健康狀態儀表板。

**存取方式**：`https://<hostname>:9090`

---

## 2. 離線安裝指南

> 本章遵循 [podman_rootless_min_offline_repo_rhel97_v3.md](./podman_rootless_min_offline_repo_rhel97_v3.md) 的流程格式。

### 2.1 套件清單

| 套件 | 用途 |
|------|------|
| `cockpit` | Cockpit 核心框架 |
| `cockpit-ws` | Web Server（提供 HTTPS 服務） |
| `cockpit-bridge` | 系統指令橋接 |
| `cockpit-system` | 系統管理面板（服務、日誌、儲存） |
| `cockpit-podman` | Podman 容器管理插件 |
| `cockpit-storaged` | 儲存管理插件（可選） |

### 2.2 連網機作業（Rocky Linux 9.7）

```bash
# 建立下載目錄
mkdir -p /tmp/cockpit-offline-repo
cd /tmp/cockpit-offline-repo

# 下載 RPM（含完整相依樹）
sudo dnf download --resolve --alldeps --destdir . \
  cockpit cockpit-ws cockpit-bridge \
  cockpit-system cockpit-podman cockpit-storaged

# 移除意外混入的 src.rpm
rm -f *.src.rpm 2>/dev/null || true

# 產生 Repo Metadata
createrepo_c /tmp/cockpit-offline-repo

# 打包與校驗碼
cd /tmp
tar czf cockpit-offline-repo-rocky97.tgz cockpit-offline-repo
sha256sum cockpit-offline-repo-rocky97.tgz > cockpit-offline-repo-rocky97.tgz.sha256
```

**檢查點**：`ls /tmp/cockpit-offline-repo/*.rpm | wc -l` 確認 RPM 數量。

### 2.3 離線機作業（RHEL 9.7）

```bash
# 驗證檔案完整性
cd /tmp
sha256sum -c cockpit-offline-repo-rocky97.tgz.sha256

# 解壓至指定目錄
sudo mkdir -p /opt/offline-repos
sudo tar xzf cockpit-offline-repo-rocky97.tgz -C /opt/offline-repos
sudo mv /opt/offline-repos/cockpit-offline-repo /opt/offline-repos/cockpit

# 建立 Repo 設定檔
sudo tee /etc/yum.repos.d/cockpit-offline.repo > /dev/null <<'EOF'
[cockpit-offline]
name=Cockpit Offline Repo (Rocky 9.7)
baseurl=file:///opt/offline-repos/cockpit
enabled=1
gpgcheck=0
repo_gpgcheck=0
metadata_expire=never
EOF

# 安裝
sudo dnf clean all
sudo dnf makecache --disablerepo="*" --enablerepo="cockpit-offline"
sudo dnf install -y --disablerepo="*" --enablerepo="cockpit-offline" \
  cockpit cockpit-ws cockpit-bridge \
  cockpit-system cockpit-podman cockpit-storaged
```

**檢查點**：`rpm -q cockpit cockpit-ws cockpit-podman` 應回傳版本號。

### 2.4 可選方案：合併至 Podman 離線 Repo

可在建立 Podman 離線 repo 時，將 Cockpit 套件一併打包：

```bash
# 在 §2.4 的 dnf download 指令中加入 Cockpit 套件
sudo dnf download --resolve --alldeps --destdir /tmp/podman-offline-repo \
  podman podman-plugins shadow-utils slirp4netns fuse-overlayfs \
  ... \
  cockpit cockpit-ws cockpit-bridge cockpit-system cockpit-podman cockpit-storaged
```

---

## 3. Cockpit 設定

### 3.1 啟用 Cockpit 服務

```bash
# 啟用 socket-activated 服務（按需啟動，節省資源）
sudo systemctl enable --now cockpit.socket

# 驗證
sudo systemctl status cockpit.socket
```

### 3.2 防火牆開放 Port 9090

```bash
sudo firewall-cmd --permanent --add-service=cockpit
sudo firewall-cmd --reload

# 驗證
sudo firewall-cmd --list-services | grep cockpit
```

### 3.3 安全設定 `/etc/cockpit/cockpit.conf`

```ini
[WebService]
# 閒置自動登出（秒），建議 15-30 分鐘
IdleTimeout=900

# 允許的來源網段（限制存取來源）
Origins = https://192.168.1.0/24 https://10.0.0.0/8

# 禁止未加密連線（強制 HTTPS）
AllowUnencrypted = false

# 限制同時連線數
MaxStartups = 10

[Session]
# 閒置逾時（分鐘）
IdleTimeout = 15
```

```bash
# 建立設定目錄（若不存在）
sudo mkdir -p /etc/cockpit

# 寫入設定檔
sudo vi /etc/cockpit/cockpit.conf

# 重啟生效
sudo systemctl restart cockpit.socket
```

### 3.4 Rootless Podman 整合

Cockpit 使用 Linux 帳號登入。以 `appuser` 登入時，Cockpit 透過該用戶的 Podman socket 操作容器，自動看到該用戶的 rootless 容器。

```bash
# 以 appuser 啟用 Podman socket（若尚未啟用）
su - appuser
systemctl --user enable --now podman.socket

# 驗證 socket 路徑
echo $XDG_RUNTIME_DIR/podman/podman.sock
ls -la $XDG_RUNTIME_DIR/podman/podman.sock
```

### 3.5 SELinux 注意事項

若 SELinux 為 Enforcing 模式，cockpit-ws 預設已有正確的 SELinux context。若遇到存取問題：

```bash
# 檢查 SELinux 相關拒絕
sudo ausearch -m avc -ts recent | grep cockpit

# 若需要額外的 SELinux policy
sudo setsebool -P cockpit_enable_cert_auth on
```

---

## 4. 權限控制機制

### 4.1 認證層（PAM）

Cockpit 使用 Linux PAM（Pluggable Authentication Modules）進行認證。支援多種認證來源：

| 認證方式 | 說明 |
|---------|------|
| **本機帳號** | `/etc/passwd` + `/etc/shadow`（預設） |
| **LDAP** | 透過 `sssd` 整合企業 LDAP/AD |
| **Kerberos/SSO** | 透過 `cockpit-ws` 的 GSSAPI 支援單一登入 |

PAM 設定檔位於 `/etc/pam.d/cockpit`，可依需求調整認證策略。

### 4.2 授權層（Linux 用戶權限）

登入後，Cockpit 以該 Linux 用戶身份執行操作。權限完全受限於該用戶在系統上的權限：

- `appuser` 登入後只能看到自己的 rootless 容器
- 無法操作其他用戶的容器或系統級資源（除非有提權機制）
- 檔案操作受限於該用戶的讀寫權限

### 4.3 提權機制（polkit）

需要 root 權限的操作（如管理 systemd 系統服務、修改系統設定），Cockpit UI 會提示輸入管理員密碼。可透過 polkit 規則精細控制允許或拒絕的操作。

**範例：限制 `podman-admins` 群組可執行的管理操作**

```javascript
// /etc/polkit-1/rules.d/50-cockpit-podman-admins.rules
polkit.addRule(function(action, subject) {
    // 允許 podman-admins 群組重啟服務，無需密碼
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        subject.isInGroup("podman-admins")) {
        return polkit.Result.YES;
    }

    // 拒絕非管理員群組的系統層級操作
    if (action.id.indexOf("org.freedesktop.systemd1") === 0 &&
        !subject.isInGroup("podman-admins") &&
        !subject.isInGroup("wheel")) {
        return polkit.Result.NO;
    }
});
```

```bash
# 建立管理群組
sudo groupadd podman-admins
sudo usermod -aG podman-admins appuser
```

### 4.4 網路存取控制

**cockpit.conf Origins 設定**

透過 `Origins` 限制允許存取的來源網段：

```ini
[WebService]
Origins = https://192.168.1.0/24 https://10.0.0.0/8
```

**防火牆層級限制**

使用 firewalld zone + source 限制特定 IP/網段才能連線 9090：

```bash
# 建立專用 zone
sudo firewall-cmd --permanent --new-zone=cockpit-access
sudo firewall-cmd --permanent --zone=cockpit-access --add-service=cockpit

# 僅允許管理網段
sudo firewall-cmd --permanent --zone=cockpit-access --add-source=192.168.1.0/24
sudo firewall-cmd --permanent --zone=cockpit-access --add-source=10.0.0.0/8

# 從預設 zone 移除 cockpit
sudo firewall-cmd --permanent --remove-service=cockpit
sudo firewall-cmd --reload
```

**強制 HTTPS**

```ini
[WebService]
AllowUnencrypted = false
```

**連線數限制**

```ini
[WebService]
MaxStartups = 10
```

### 4.5 Session 管理

```ini
[Session]
IdleTimeout = 15
```

閒置超過設定時間（分鐘）後自動登出。建議值：15-30 分鐘。

### 4.6 TLS 憑證

**預設行為**：Cockpit 自動產生自簽憑證。

**使用自訂憑證**：

```bash
# 憑證目錄
ls /etc/cockpit/ws-certs.d/

# 放置自訂憑證（PEM 格式，key + cert 合併）
sudo cp your-cert.pem /etc/cockpit/ws-certs.d/99-custom.cert
sudo chmod 640 /etc/cockpit/ws-certs.d/99-custom.cert
sudo chown root:cockpit-ws /etc/cockpit/ws-certs.d/99-custom.cert

# 重啟生效
sudo systemctl restart cockpit.socket
```

憑證檔案格式為 PEM，包含 private key 和 certificate chain，按數字排序取最大編號的檔案。

---

## 5. cockpit-podman 功能說明

### 5.1 內建功能

| 功能 | 說明 |
|------|------|
| 容器列表/狀態 | 列出所有容器，顯示 Running/Stopped/Exited 狀態 |
| 啟停操作 | Start / Stop / Restart / Delete 容器 |
| 即時日誌 | 即時串流容器 stdout/stderr |
| 資源監控 | CPU、記憶體使用量圖表 |
| 映像管理 | 列出/刪除 images，支援 Pull（連網環境） |
| Health Check 狀態 | 顯示容器健康檢查結果 |

### 5.2 限制

| 限制項目 | 說明 |
|---------|------|
| Quadlet 拓撲視圖 | 不支援，無法顯示 template unit 之間的關聯 |
| 聚合健康儀表板 | 不支援，無法一覽所有微服務的整體健康狀態 |
| 負載均衡狀態 | 不支援，無法顯示 upstream 連線分佈 |

這些限制由本專案的自訂插件 `microservices-monitor` 補充。

---

## 6. 自訂插件安裝

### 6.1 安裝路徑

自訂插件安裝至使用者目錄（rootless 模式）：

```
~/.local/share/cockpit/microservices-monitor/
├── manifest.json    # 插件 metadata
└── index.html       # 監控儀表板 UI
```

### 6.2 手動安裝

```bash
# 建立插件目錄
mkdir -p ~/.local/share/cockpit/microservices-monitor/

# 複製插件檔案
cp cockpit/microservices-monitor/manifest.json \
   ~/.local/share/cockpit/microservices-monitor/
cp cockpit/microservices-monitor/index.html \
   ~/.local/share/cockpit/microservices-monitor/
```

或使用 `setup.sh` 自動安裝（見 `scripts/setup.sh`）。

### 6.3 驗證安裝

1. 以 `appuser` 登入 Cockpit：`https://<hostname>:9090`
2. 左側選單應出現「微服務監控」項目
3. 點選後顯示服務拓撲與健康狀態儀表板

### 6.4 插件功能

| 功能 | 說明 |
|------|------|
| 服務拓撲概覽 | 顯示所有服務與副本的架構圖 |
| Health Check 儀表板 | 以顏色標示每個容器的健康狀態（綠/黃/紅） |
| 快捷操作 | 重啟服務、查看日誌 |
| 自動定期刷新 | 每 30 秒自動更新狀態（可關閉） |

---

## 7. 故障排除

### Cockpit 無法連線

```bash
# 檢查 socket 狀態
sudo systemctl status cockpit.socket

# 檢查防火牆
sudo firewall-cmd --list-services | grep cockpit

# 檢查 port 是否被占用
sudo ss -tlnp | grep 9090
```

### cockpit-podman 看不到容器

確認以正確的使用者身份（`appuser`）登入，且 Podman socket 已啟用：

```bash
su - appuser
systemctl --user status podman.socket
podman ps    # 確認命令列可看到容器
```

### 自訂插件未出現在選單

```bash
# 確認檔案存在且 manifest.json 格式正確
ls -la ~/.local/share/cockpit/microservices-monitor/
python3 -m json.tool ~/.local/share/cockpit/microservices-monitor/manifest.json

# 重新登入 Cockpit（清除瀏覽器快取）
```

---

## 8. 參考資料

- [Cockpit 官方文件](https://cockpit-project.org/guide/latest/)
- [cockpit-podman](https://github.com/cockpit-project/cockpit-podman)
- [Cockpit 插件開發指南](https://cockpit-project.org/guide/latest/development.html)
- [本專案架構文件](./ARCHITECTURE.md)
- [離線部署指南](./podman_rootless_min_offline_repo_rhel97_v3.md)

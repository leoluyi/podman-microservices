# Rootless Podman 最小離線 Repo 部署操作手冊

| 項目 | 內容 |
|------|------|
| 文件編號 | OPS-PODMAN-OFFLINE-001 |
| 版本 | 3.0 |
| 適用平台 | RHEL 9.7 (x86_64) — Air-Gapped |
| RPM 來源機 | Rocky Linux 9.7 (x86_64) — 可連網 |
| Podman 模式 | Rootless |
| 最後更新 | 2025-02 |

---

## 0. 設計原則

本手冊採「最小 RPM 集合 + 本機 `file://` repo」策略，理由如下：

1. **不建整包 AppStream / BaseOS** — 體積達 GB 等級，傳輸與稽核成本過高。
2. **不只抓 podman 本體** — Rootless 模式額外需要 user-space networking、overlay storage、UID mapping、firewall backend 等套件。
3. **dnf 可管理、repo 可維運** — 比一次性 `rpm -ivh *.rpm` 更可控、可重現。
4. **版本鎖定 Rocky 9.7 ↔ RHEL 9.7** — 確保 ABI 相容、避免相依版本錯配。

---

## 1. 最小必要套件清單

### 1.1 核心套件

| 套件 | 用途 |
|------|------|
| `podman` | 容器引擎本體 |
| `podman-plugins` | 額外 network / volume plugins |

### 1.2 Rootless 關鍵套件（缺一不可）

| 套件 | 用途 |
|------|------|
| `shadow-utils` | 提供 `newuidmap` / `newgidmap`（UID/GID mapping） |
| `slirp4netns` | User-space networking（Rootless 網路必備） |
| `fuse-overlayfs` | Rootless overlay storage driver |
| `containernetworking-plugins` | CNI plugins（向下相容） |

### 1.3 Runtime / Network（建議鎖定版本）

| 套件 | 用途 |
|------|------|
| `crun` | OCI runtime（Podman 預設） |
| `conmon` | Container monitor |
| `netavark` | 新一代 network backend |
| `aardvark-dns` | Container DNS resolver |

### 1.4 SELinux

| 套件 | 用途 |
|------|------|
| `container-selinux` | 容器相關 SELinux policy（RHEL 必要） |

### 1.5 Firewall / Network 底層（Netavark 隱性依賴）

| 套件 | 用途 |
|------|------|
| `iptables-nft` | Netavark 預設 firewall driver 所需（bridge 網路隔離規則、`--internal` 網路） |
| `iptables-libs` | `iptables-nft` 的 runtime library |
| `nftables` | RHEL 9 原生 firewall framework；未來 Netavark 預設 driver |
| `libnftnl` | nftables 的 Netlink library |
| `libnetfilter_conntrack` | 連線追蹤（NAT / port-forwarding） |
| `conntrack-tools` | 使用者空間的 conntrack 工具（netavark 操作 conntrack 表） |
| `iproute` | `ip` 指令（bridge / veth 管理；通常已裝但精簡環境可能缺） |
| `procps-ng` | `sysctl` 指令（namespace 設定必要） |

> **為什麼要補 firewall 套件？** Netavark 建立 bridge 網路（含 `--internal`）時，需呼叫 `iptables` 設定 FORWARD chain 的隔離規則。RHEL 9 標準安裝通常已含這些套件，但 air-gapped 精簡環境可能被移除，保守補齊可避免執行期 `iptables: command not found` 失敗。

---

## 2. 連網機作業 — 建立離線 Repo（Rocky Linux 9.7）

### 2.1 前置確認

```bash
# 確認 OS 版本
cat /etc/os-release | grep -E 'PRETTY_NAME|VERSION_ID'

# 確認架構
uname -m    # 預期輸出：x86_64
```

**檢查點**：VERSION_ID 須為 `9.7`，架構須為 `x86_64`。

### 2.2 啟用必要 Repo

```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --set-enabled crb || true

# 驗證
dnf repolist
```

**檢查點**：輸出應包含 `baseos`、`appstream`、`crb`。

### 2.3 安裝打包工具

```bash
sudo dnf -y install createrepo_c
```

### 2.4 下載 RPM（含完整相依樹）

```bash
mkdir -p /tmp/podman-offline-repo
cd /tmp/podman-offline-repo

# --resolve: 解析相依
# --alldeps: 下載所有相依（含已安裝者），確保離線機不缺套件
sudo dnf download --resolve --alldeps --destdir . \
  podman podman-plugins \
  shadow-utils \
  slirp4netns fuse-overlayfs \
  containernetworking-plugins \
  crun conmon netavark aardvark-dns \
  container-selinux \
  iptables-nft iptables-libs \
  nftables libnftnl \
  libnetfilter_conntrack conntrack-tools \
  iproute procps-ng

# 移除意外混入的 src.rpm
rm -f *.src.rpm 2>/dev/null || true
```

> ⚠️ **重要**：若不加 `--alldeps`，已安裝於 Rocky 的套件（如 `shadow-utils`、`glibc` 等基礎相依）不會被下載，導致離線機缺件。

**檢查點**：執行 `ls *.rpm | wc -l` 確認 RPM 數量（通常 60–120 個，視環境而異）。

### 2.5 產生 Repo Metadata

```bash
createrepo_c /tmp/podman-offline-repo
```

**檢查點**：目錄下應出現 `repodata/` 子目錄，內含 `repomd.xml`。

### 2.6 打包與產生校驗碼

```bash
cd /tmp
tar czf podman-rootless-offline-repo-rocky97.tgz podman-offline-repo

sha256sum podman-rootless-offline-repo-rocky97.tgz \
  > podman-rootless-offline-repo-rocky97.tgz.sha256

# 驗證
cat podman-rootless-offline-repo-rocky97.tgz.sha256
```

### 2.7 傳輸至離線環境

將以下兩個檔案透過核准的媒介（USB、安全檔案傳輸）搬至離線機：

- `podman-rootless-offline-repo-rocky97.tgz`
- `podman-rootless-offline-repo-rocky97.tgz.sha256`

---

## 3. 離線機作業 — 掛載 Repo 並安裝（RHEL 9.7）

### 3.1 前置確認

```bash
# 確認 OS 版本
cat /etc/os-release | grep -E 'PRETTY_NAME|VERSION_ID'

# 確認目標機架構
uname -m    # 須與連網機一致：x86_64

# 確認是否已有舊版 podman（避免衝突）
rpm -qa | grep -E 'podman|slirp4netns|fuse-overlayfs|netavark' || echo "未安裝，可繼續"
```

### 3.2 驗證檔案完整性

```bash
cd /tmp
sha256sum -c podman-rootless-offline-repo-rocky97.tgz.sha256
```

**檢查點**：輸出須為 `OK`。若為 `FAILED`，檔案已損壞，須重新傳輸。

### 3.3 解壓至指定目錄

```bash
sudo mkdir -p /opt/offline-repos
sudo tar xzf podman-rootless-offline-repo-rocky97.tgz -C /opt/offline-repos
sudo mv /opt/offline-repos/podman-offline-repo /opt/offline-repos/podman
```

**檢查點**：確認 metadata 存在。

```bash
ls /opt/offline-repos/podman/repodata/repomd.xml
```

### 3.4 建立 Repo 設定檔

```bash
sudo tee /etc/yum.repos.d/podman-offline.repo > /dev/null <<'EOF'
[podman-offline]
name=Podman Rootless Offline Repo (Rocky 9.7)
baseurl=file:///opt/offline-repos/podman
enabled=1
gpgcheck=0
repo_gpgcheck=0
metadata_expire=never
EOF
```

### 3.5 建立快取並安裝

```bash
sudo dnf clean all
sudo dnf makecache --disablerepo="*" --enablerepo="podman-offline"

# 明確列出所有套件，便於稽核追蹤
sudo dnf install -y --disablerepo="*" --enablerepo="podman-offline" \
  podman podman-plugins \
  shadow-utils \
  slirp4netns fuse-overlayfs \
  containernetworking-plugins \
  crun conmon netavark aardvark-dns \
  container-selinux \
  iptables-nft iptables-libs \
  nftables libnftnl \
  libnetfilter_conntrack conntrack-tools \
  iproute procps-ng
```

> **說明**：雖然相依會自動拉入，但明確列出所有套件可確保安裝意圖清晰，也方便稽核比對白名單。若離線機已有同版本套件，`dnf` 會自動跳過。

**檢查點**：

```bash
rpm -q podman slirp4netns fuse-overlayfs netavark aardvark-dns \
      crun conmon container-selinux iptables-nft nftables iproute
```

所有套件皆應回傳版本號，無 `not installed` 訊息。

---

## 4. Rootless 系統設定（必要）

> ⚠️ **以下設定若未完成，Rootless Podman 將無法正常運作。**

### 4.1 啟用 User Namespace

**檢查目前值**：

```bash
sysctl user.max_user_namespaces
```

**若值為 0 或小於 15000，須修正**：

```bash
# 立即生效
sudo sysctl -w user.max_user_namespaces=15000

# 持久化（重開機仍有效）
echo "user.max_user_namespaces=15000" | sudo tee /etc/sysctl.d/99-userns.conf
sudo sysctl --system
```

**檢查點**：再次執行 `sysctl user.max_user_namespaces`，值須 ≥ 15000。

### 4.2 確認 UID/GID Mapping 工具

```bash
which newuidmap newgidmap
```

**檢查點**：兩個指令皆應回傳路徑（通常 `/usr/bin/newuidmap`）。若找不到，代表 `shadow-utils` 安裝不完整。

確認 SUID bit 已設定：

```bash
ls -l $(which newuidmap) $(which newgidmap)
```

輸出應包含 `-rws` 權限。

### 4.3 建立 Rootless 使用者

```bash
# 若使用者已存在則跳過
id appuser 2>/dev/null || sudo useradd -m appuser
```

### 4.4 設定 subuid / subgid

**先檢查是否已有對應條目**：

```bash
grep "^appuser:" /etc/subuid /etc/subgid
```

**若無輸出，則新增**：

```bash
echo "appuser:100000:65536" | sudo tee -a /etc/subuid
echo "appuser:100000:65536" | sudo tee -a /etc/subgid
```

> ⚠️ 注意：若有多個 rootless 使用者，各自的 UID/GID range 不可重疊。例如第二位使用者應使用 `200000:65536`。

**檢查點**：

```bash
cat /etc/subuid
cat /etc/subgid
```

### 4.5 啟用 Linger（容器於登出後持續運行）

```bash
sudo loginctl enable-linger appuser

# 驗證
loginctl show-user appuser --property=Linger
```

**檢查點**：輸出應為 `Linger=yes`。

> **說明**：若不啟用 linger，使用者登出後其 rootless 容器與 `podman` 程序將被 systemd 終止。

---

## 5. 初始化與驗證

### 5.1 切換至 Rootless 使用者

```bash
su - appuser
```

### 5.2 Podman 基本資訊

```bash
podman --version
podman info --debug 2>/dev/null | grep -E 'rootless|networkBackend|graphDriverName'
```

**預期輸出**：

```
rootless: true
networkBackend: netavark
graphDriverName: overlay
```

> **注意**：若 `graphDriverName` 顯示 `vfs` 而非 `overlay`，代表 `fuse-overlayfs` 未正確安裝或 kernel 不支援。`vfs` 效能極差，不建議用於生產環境。

### 5.3 Network 驗證

```bash
podman network ls
```

**預期輸出**：至少有一個 `podman` 預設網路。

### 5.4 Storage 驗證

```bash
podman info --format '{{.Store.GraphDriverName}}'
# 預期：overlay

podman info --format '{{.Store.GraphRoot}}'
# 預期：/home/appuser/.local/share/containers/storage
```

### 5.5 Internal Network 驗證

```bash
# 建立 internal 網路
podman network create --internal --subnet 10.89.100.0/24 test-internal

# 檢查設定
podman network inspect test-internal | grep -E '"internal"|"dns_enabled"|"driver"'
```

**預期輸出**：

```
"driver": "bridge",
"internal": true,
"dns_enabled": true,
```

```bash
# 驗證完畢後移除測試網路
podman network rm test-internal
```

### 5.6 功能測試（選擇性，需有離線映像）

若有預先匯入的容器映像（如透過 `podman save` / `podman load`）：

```bash
# 載入映像
podman load -i /path/to/image.tar

# 執行測試
podman run --rm <image-name> echo "rootless podman works"
```

> **離線環境無法 `podman pull`**，須透過 `podman save` → 離線傳輸 → `podman load` 匯入映像。

---

## 6. 常見錯誤對照表

| # | 現象 | 可能原因 | 解法 |
|---|------|----------|------|
| 1 | `cannot find newuidmap` | `shadow-utils` 未安裝 | 補裝 `shadow-utils` RPM |
| 2 | `cannot setup slirp4netns` | `slirp4netns` 缺失 | 補裝 `slirp4netns` RPM |
| 3 | `permission denied` on overlay mount | `fuse-overlayfs` 未安裝 | 補裝 `fuse-overlayfs` RPM |
| 4 | SELinux denial (`avc: denied`) | `container-selinux` 缺失 | 補裝 `container-selinux` RPM |
| 5 | `user namespaces are not enabled` | `user.max_user_namespaces` 為 0 | 執行 §4.1 sysctl 設定 |
| 6 | `graphDriverName: vfs`（效能差） | `fuse-overlayfs` 未裝或 kernel 不支援 | 補裝後執行 `podman system reset` |
| 7 | 容器登出後消失 | 未啟用 linger | 執行 §4.5 `loginctl enable-linger` |
| 8 | `ERRO[0000] cannot find mappings for user` | `/etc/subuid` 或 `/etc/subgid` 未設定 | 執行 §4.4 新增對應條目 |
| 9 | `iptables: command not found` 或 network create 失敗 | `iptables-nft` 未安裝 | 補裝 `iptables-nft` RPM |
| 10 | `network create` 成功但容器間無法通訊 | `conntrack-tools` 或 `iproute` 缺失 | 補裝對應 RPM |

---

## 7. 回滾與移除程序

如需完整移除 Podman 及相關設定：

### 7.1 停止所有容器並清除資料

```bash
# 以 appuser 身分執行
su - appuser
podman stop --all
podman system prune --all --force
podman system reset --force
exit
```

### 7.2 移除套件

```bash
sudo dnf remove -y \
  podman podman-plugins \
  slirp4netns fuse-overlayfs \
  containernetworking-plugins \
  crun conmon netavark aardvark-dns \
  container-selinux
```

> **注意**：`shadow-utils`、`iptables-nft`、`nftables`、`iproute`、`procps-ng` 為系統基礎套件，**請勿移除**。

### 7.3 清除 Repo 與設定

```bash
sudo rm -f /etc/yum.repos.d/podman-offline.repo
sudo rm -rf /opt/offline-repos/podman
sudo rm -f /etc/sysctl.d/99-userns.conf
sudo sysctl --system
```

### 7.4 清除使用者資料（視需求）

```bash
sudo userdel -r appuser    # -r 會一併刪除 home 目錄
sudo sed -i '/^appuser:/d' /etc/subuid /etc/subgid
```

---

## 8. 維運建議

1. **更新策略**：每次更新一律建立新目錄、新 tarball，避免就地覆蓋造成半更新狀態。
2. **RPM 白名單**：維護固定的套件清單文件（如本手冊 §1），方便稽核與重建。
3. **版本對齊**：連網機與離線機的 OS minor version 須一致（同為 9.7），避免 ABI 不相容。
4. **映像管理**：離線環境的容器映像需透過 `podman save` / `podman load` 流程管理，建議建立專屬的映像傳輸 SOP。
5. **安全優勢**：Rootless Podman 無 root daemon、無 root socket，攻擊面小，適合金融及高合規場域。

---

*— End of Document —*

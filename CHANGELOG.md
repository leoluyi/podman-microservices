# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Cockpit 監控管理整合**
  - 新增 `docs/COCKPIT-MONITORING.md`：完整指南含離線安裝、安全設定（PAM/polkit/TLS）、權限控制、cockpit-podman 功能說明
  - 新增自訂 Cockpit 插件 `cockpit/microservices-monitor/`：微服務拓撲總覽、Health Check 聚合儀表板、日誌查看、服務重啟、自動定期刷新
  - `scripts/setup.sh` 新增步驟 11：自動安裝 Cockpit 插件至 `~/.local/share/cockpit/`
  - 各文件新增 Cockpit 相關交叉引用（README、ARCHITECTURE、DEPLOYMENT、DEBUG、離線部署指南）
  - 端口規劃表新增 9090 (Cockpit)

## [0.5.0] - 2026-03-10

### Changed

- 將 API 容器轉換為 template unit 命名（`api-user@.container`），支援多副本
- 多副本負載均衡：Template Unit + OpenResty `least_conn` upstream
- `configs/shared/ha.conf` 集中管理各服務副本數
- `scripts/scale-service.sh` 動態調整副本數
- `scripts/restart-service.sh` 支援 rolling restart（零中斷）
- `scripts/logs.sh` 支援多副本日誌查看

## [0.4.0] - 2026-03-03

### Added

- BFF 改用 Go reverse-proxy 服務取代 Node/Express stub
- 端對端測試腳本 `scripts/test-stack.sh`

### Changed

- SSL Proxy 外部化 partner 設定至 JSON，改用自訂 image build
- 標準化 OpenResty 與 partner Node client 的開發工具配置

## [0.3.0] - 2026-03-02

### Added

- Endpoint 命名空間文件（SSL Proxy 路由、JWT 影響範圍）
- Partner endpoint 權限矩陣與 `docs/ENDPOINT-PERMISSIONS.md`
- OpenResty upstream 使用與離線映像搬移文件

### Changed

- 移除已棄用的 API 層級權限檢查，統一由 SSL Proxy Lua 處理
- 精簡架構與 Partner 整合文件

## [0.2.0] - 2026-02-14

### Added

- Rootless Podman 離線部署指南 (`docs/podman_rootless_min_offline_repo_rhel97_v3.md`)
- RHEL 9 系統依賴安裝指南
- Partner JWT Secret 管理工具 (`scripts/manage-partner-secrets.sh`)
- JWT Token 預設過期時間改為永久，支援彈性配置
- 完整目錄結構與離線部署文件

### Fixed

- 修復 HIGH/MEDIUM 優先級 bug
- 修復指令注入、路徑穿越等安全漏洞

### Security

- 修復 critical 及 medium 安全問題

## [0.1.0] - 2026-02-13

### Added

- 初始架構：Podman + Quadlet 微服務容器化部署
- SSL Termination Proxy (OpenResty) 統一 HTTPS 入口
- 雙軌認證機制（BFF Session + Partner JWT）
- 完全網路隔離（internal-net）
- 混合 Debug 模式（dev/prod）
- Frontend、BFF、API-User、API-Order、API-Product 服務
- 管理腳本：setup、start-all、stop-all、status、generate-certs、generate-jwt
- 自簽 SSL 憑證產生
- Hybrid Secrets 管理（per-partner JWT）
- Endpoint 層級權限控制
- Partner API 客戶端範例（Node.js、Python）

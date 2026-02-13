#!/bin/bash
# ============================================================================
# Podman 微服務架構 - 初始化部署腳本
# ============================================================================

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 函數：印出資訊
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# 檢查參數
# ============================================================================
if [ $# -ne 1 ]; then
    error "用法: $0 {dev|prod}"
    echo ""
    echo "  dev  - 開發/測試環境（Backend APIs 綁定到 localhost，方便 debug）"
    echo "  prod - 生產環境（Backend APIs 完全隔離）"
    exit 1
fi

MODE=$1

if [[ "$MODE" != "dev" && "$MODE" != "prod" ]]; then
    error "無效的模式: $MODE"
    error "請使用 'dev' 或 'prod'"
    exit 1
fi

info "部署模式: $MODE"

# ============================================================================
# 檢查前置需求
# ============================================================================
info "檢查前置需求..."

# 檢查 Podman
if ! command -v podman &> /dev/null; then
    error "Podman 未安裝"
    exit 1
fi

PODMAN_VERSION=$(podman --version | awk '{print $3}')
info "Podman 版本: $PODMAN_VERSION"

# 檢查 systemd
if ! command -v systemctl &> /dev/null; then
    error "systemctl 未找到"
    exit 1
fi

success "前置檢查完成"

# ============================================================================
# 創建必要的目錄
# ============================================================================
info "創建目錄結構..."

sudo mkdir -p /opt/app/{nginx-public/{conf.d,logs},bff,frontend}
sudo chown -R $USER:$USER /opt/app

success "目錄創建完成"

# ============================================================================
# 部署 Quadlet 配置檔
# ============================================================================
info "部署 Quadlet 配置檔到 /etc/containers/systemd/..."

# 創建 user systemd 目錄
mkdir -p ~/.config/containers/systemd

# 複製所有 .network 和 .container 檔案
cp -v quadlet/*.network ~/.config/containers/systemd/ 2>/dev/null || true
cp -v quadlet/*.container ~/.config/containers/systemd/

success "Quadlet 配置檔部署完成"

# ============================================================================
# 設定環境模式（Dev or Prod）
# ============================================================================
info "配置環境模式: $MODE"

if [ "$MODE" == "dev" ]; then
    # 開發模式：啟用 Debug 端口
    info "啟用 Debug 模式（Backend APIs 綁定到 localhost）"
    
    for service in api-user api-order api-product; do
        mkdir -p ~/.config/containers/systemd/${service}.container.d
        cp quadlet/${service}.container.d/environment.conf.example \
           ~/.config/containers/systemd/${service}.container.d/environment.conf
        success "已啟用 ${service} Debug 端口"
    done
    
elif [ "$MODE" == "prod" ]; then
    # 生產模式：禁用 Debug 端口
    info "生產模式（Backend APIs 完全隔離）"
    
    for service in api-user api-order api-product; do
        if [ -d ~/.config/containers/systemd/${service}.container.d ]; then
            rm -rf ~/.config/containers/systemd/${service}.container.d
            success "已禁用 ${service} Debug 端口"
        fi
    done
fi

# ============================================================================
# 部署應用配置
# ============================================================================
info "部署應用配置..."

# 複製 Nginx 配置
cp -rv configs/nginx-public/* /opt/app/nginx-public/

success "應用配置部署完成"

# ============================================================================
# 重新載入 systemd
# ============================================================================
info "重新載入 systemd daemon..."
systemctl --user daemon-reload
success "systemd daemon 重新載入完成"

# ============================================================================
# 拉取鏡像（如果需要）
# ============================================================================
info "檢查容器鏡像..."
warning "請確保已將正確的鏡像推送到 Registry 或本地載入"
echo ""
echo "如需拉取鏡像，請執行："
echo "  podman pull docker.io/your-registry/api-user:latest"
echo "  podman pull docker.io/your-registry/api-order:latest"
echo "  podman pull docker.io/your-registry/api-product:latest"
echo ""

# ============================================================================
# 完成
# ============================================================================
echo ""
success "=========================================="
success "部署完成！"
success "=========================================="
echo ""
info "環境模式: $MODE"
echo ""

if [ "$MODE" == "dev" ]; then
    info "Debug 端口已開啟："
    echo "  - API-User:    http://localhost:8081"
    echo "  - API-Order:   http://localhost:8082"
    echo "  - API-Product: http://localhost:8083"
    echo ""
fi

info "對外服務端口："
echo "  - Frontend:      http://localhost:3000"
echo "  - BFF:           http://localhost:8080"
echo "  - Public Nginx:  http://localhost:8090"
echo ""

info "下一步："
echo "  1. 檢查鏡像：podman images"
echo "  2. 啟動服務：./scripts/start-all.sh"
echo "  3. 查看狀態：./scripts/status.sh"
echo "  4. 查看日誌：./scripts/logs.sh <service-name>"
echo ""

info "如需切換環境模式，請執行："
echo "  ./scripts/setup.sh {dev|prod}"
echo ""

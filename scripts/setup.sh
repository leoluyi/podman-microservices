#!/bin/bash
# ============================================================================
# 初始化部署腳本
# 用途：準備環境、配置 Debug 模式、部署 Quadlet 配置
# ============================================================================

set -e

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 輔助函數
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 檢查參數
if [ $# -eq 0 ]; then
    error "使用方式: $0 {dev|prod}"
    echo ""
    echo "  dev  - 開發模式（啟用 Debug 端口）"
    echo "  prod - 生產模式（完全網路隔離）"
    exit 1
fi

MODE=$1

if [[ "$MODE" != "dev" && "$MODE" != "prod" ]]; then
    error "無效的模式: $MODE"
    error "使用方式: $0 {dev|prod}"
    exit 1
fi

info "初始化部署環境（模式: $MODE）"

# ============================================================================
# 1. 檢查前置需求
# ============================================================================
info "檢查前置需求..."

# 檢查 Podman
if ! command -v podman &> /dev/null; then
    error "Podman 未安裝"
    exit 1
fi

# 檢查 systemd
if ! command -v systemctl &> /dev/null; then
    error "systemctl 未安裝"
    exit 1
fi

# 檢查 Podman 版本
PODMAN_VERSION=$(podman version --format "{{.Version}}")
info "Podman 版本: $PODMAN_VERSION"

# ============================================================================
# 2. 建立必要目錄
# ============================================================================
info "建立必要目錄..."

mkdir -p ~/.config/containers/systemd
mkdir -p /opt/app/{certs,logs/{ssl-proxy,frontend,bff}}
mkdir -p /opt/app/configs/{ssl-proxy/{conf.d,lua},frontend,bff}

success "目錄建立完成"

# ============================================================================
# 3. 檢查 SSL 憑證
# ============================================================================
info "檢查 SSL 憑證..."

if [ ! -f "/opt/app/certs/server.crt" ] || [ ! -f "/opt/app/certs/server.key" ]; then
    warning "SSL 憑證不存在"
    info "執行憑證產生腳本..."
    ./scripts/generate-certs.sh
else
    success "SSL 憑證已存在"
fi

# ============================================================================
# 4. 複製配置檔
# ============================================================================
info "複製配置檔..."

# SSL Proxy 配置
cp -r configs/ssl-proxy/* /opt/app/configs/ssl-proxy/

# Frontend 配置
cp configs/frontend/nginx.conf /opt/app/configs/frontend/

success "配置檔複製完成"

# ============================================================================
# 5. 部署 Quadlet 配置
# ============================================================================
info "部署 Quadlet 配置..."

# 複製所有 .container 和 .network 檔案
cp quadlet/*.{container,network} ~/.config/containers/systemd/ 2>/dev/null || true

success "Quadlet 配置已部署"

# ============================================================================
# 6. 配置 Debug 模式
# ============================================================================
info "配置 $MODE 模式..."

# API 服務列表
APIS=("api-user" "api-order" "api-product")

if [ "$MODE" == "dev" ]; then
    info "啟用 Debug 模式（localhost 端口映射）"
    
    for api in "${APIS[@]}"; do
        mkdir -p ~/.config/containers/systemd/${api}.container.d
        cp quadlet/${api}.container.d/environment.conf.example \
           ~/.config/containers/systemd/${api}.container.d/environment.conf
        success "  $api: Debug 端口已啟用"
    done
    
    success "開發模式配置完成"
    info "Backend APIs 可透過 localhost 訪問："
    info "  - API-User:    http://localhost:8101"
    info "  - API-Order:   http://localhost:8102"
    info "  - API-Product: http://localhost:8103"
    
else
    info "生產模式（完全網路隔離）"
    
    for api in "${APIS[@]}"; do
        rm -rf ~/.config/containers/systemd/${api}.container.d
        success "  $api: Debug 端口已禁用"
    done
    
    success "生產模式配置完成"
    info "Backend APIs 完全隔離，只能透過 SSL Proxy 訪問"
fi

# ============================================================================
# 7. 重新載入 systemd
# ============================================================================
info "重新載入 systemd daemon..."
systemctl --user daemon-reload

success "systemd daemon 已重新載入"

# ============================================================================
# 8. 檢查容器鏡像
# ============================================================================
info "檢查容器鏡像..."

IMAGES=("localhost/api-user:latest" "localhost/api-order:latest" "localhost/api-product:latest" "localhost/bff:latest")
MISSING_IMAGES=()

for img in "${IMAGES[@]}"; do
    if ! podman image exists "$img"; then
        warning "  鏡像不存在: $img"
        MISSING_IMAGES+=("$img")
    else
        success "  鏡像存在: $img"
    fi
done

if [ ${#MISSING_IMAGES[@]} -gt 0 ]; then
    warning "發現缺少的鏡像"
    info "請先建置鏡像："
    echo ""
    echo "  cd dockerfiles/api-user && podman build -t localhost/api-user:latest ."
    echo "  cd dockerfiles/api-order && podman build -t localhost/api-order:latest ."
    echo "  cd dockerfiles/api-product && podman build -t localhost/api-product:latest ."
    echo "  cd dockerfiles/bff && podman build -t localhost/bff:latest ."
    echo ""
    warning "或使用 Nginx 替代（用於快速測試）："
    info "  修改 quadlet/*.container 中的 Image 為 nginx:alpine"
fi

# ============================================================================
# 9. 顯示後續步驟
# ============================================================================
echo ""
success "============================================"
success "初始化完成！"
success "============================================"
echo ""
info "後續步驟："
echo ""
echo "  1. 啟動服務："
echo "     ./scripts/start-all.sh"
echo ""
echo "  2. 檢查狀態："
echo "     ./scripts/status.sh"
echo ""
echo "  3. 測試連通性："
echo "     ./scripts/test-connectivity.sh"
echo ""
if [ "$MODE" == "dev" ]; then
    echo "  4. Debug 端口測試："
    echo "     curl http://localhost:8101/health"
    echo "     curl http://localhost:8102/health"
    echo "     curl http://localhost:8103/health"
    echo ""
fi
echo "  5. HTTPS 訪問："
echo "     curl -k https://localhost/"
echo ""

exit 0

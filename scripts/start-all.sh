#!/bin/bash
# ============================================================================
# 啟動所有微服務
# ============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

info "啟動所有微服務..."
echo ""

# 服務啟動順序（依賴關係）
SERVICES=(
    "internal-net"
    "api-user"
    "api-order"
    "api-product"
    "public-nginx"
    "bff"
    "frontend"
)

for service in "${SERVICES[@]}"; do
    info "啟動 ${service}..."
    systemctl --user start ${service}.service
    success "${service} 已啟動"
done

echo ""
success "所有服務已啟動完成！"
echo ""
info "查看服務狀態："
echo "  ./scripts/status.sh"
echo ""
info "查看服務日誌："
echo "  ./scripts/logs.sh <service-name>"
echo ""

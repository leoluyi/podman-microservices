#!/bin/bash
# ============================================================================
# 啟動所有服務
# ============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

info "啟動所有微服務..."

# 啟動順序（遵循依賴關係）
SERVICES=(
    "internal-net"
    "api-user"
    "api-order"
    "api-product"
    "bff"
    "frontend"
    "ssl-proxy"
)

for service in "${SERVICES[@]}"; do
    info "啟動 $service..."
    systemctl --user start "$service"
    
    # 等待服務啟動
    sleep 2
    
    if systemctl --user is-active --quiet "$service"; then
        success "  ✓ $service 已啟動"
    else
        echo "  ✗ $service 啟動失敗"
        echo "  查看日誌: systemctl --user status $service"
    fi
done

echo ""
success "所有服務啟動完成！"
echo ""
info "檢查服務狀態："
echo "  ./scripts/status.sh"
echo ""
info "測試連通性："
echo "  ./scripts/test-connectivity.sh"

exit 0

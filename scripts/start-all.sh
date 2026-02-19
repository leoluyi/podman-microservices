#!/bin/bash
# ============================================================================
# 啟動所有服務
# ============================================================================

set -e

source "$(dirname "$0")/lib.sh"

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

    if wait_for_service "$service" 30; then
        success "  ✓ $service 已啟動"
    else
        error "  ✗ $service 啟動失敗"
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

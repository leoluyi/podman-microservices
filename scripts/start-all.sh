#!/bin/bash
# ============================================================================
# 啟動所有服務（含多副本）
# ============================================================================

set -e

source "$(dirname "$0")/lib.sh"

info "啟動所有微服務..."
echo ""

# 啟動順序（遵循依賴關係）
# 1. 網路基礎設施
info "啟動 internal-net..."
systemctl --user start internal-net
if wait_for_service internal-net 10; then
    success "  ✓ internal-net 已啟動"
else
    error "  ✗ internal-net 啟動失敗"
    exit 1
fi

# 2. Backend API 服務（可並行，但逐一啟動較安全）
for service in api-user api-order api-product; do
    start_service "$service"
done

# 3. BFF Gateway
start_service bff

# 4. Frontend
start_service frontend

# 5. SSL Proxy（singleton，最後啟動）
info "啟動 ssl-proxy..."
systemctl --user start ssl-proxy
if wait_for_service ssl-proxy 30; then
    success "  ✓ ssl-proxy 已啟動"
else
    error "  ✗ ssl-proxy 啟動失敗"
fi

echo ""
success "所有服務啟動完成！"
echo ""
info "檢查服務狀態："
echo "  ./scripts/status.sh"
echo ""
info "測試連通性："
echo "  ./scripts/test-connectivity.sh"

exit 0

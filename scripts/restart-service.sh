#!/bin/bash
# 重啟單一服務

source "$(dirname "$0")/lib.sh"

VALID_SERVICES=("ssl-proxy" "frontend" "bff" "api-user" "api-order" "api-product")

if [ $# -eq 0 ]; then
    echo "使用方式: $0 <service-name>"
    echo ""
    echo "可用服務："
    for s in "${VALID_SERVICES[@]}"; do echo "  - $s"; done
    exit 1
fi

SERVICE=$1

# 驗證服務名稱
is_valid=false
for s in "${VALID_SERVICES[@]}"; do
    [ "$s" = "$SERVICE" ] && is_valid=true && break
done

if ! $is_valid; then
    error "未知的服務: $SERVICE"
    echo "可用服務: ${VALID_SERVICES[*]}"
    exit 1
fi

info "重啟 $SERVICE..."
systemctl --user restart "$SERVICE"

if wait_for_service "$SERVICE" 30; then
    success "✓ $SERVICE 已重啟"
else
    error "✗ $SERVICE 重啟失敗"
    systemctl --user status "$SERVICE"
    exit 1
fi

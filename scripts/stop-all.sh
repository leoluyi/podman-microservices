#!/bin/bash
# 停止所有服務
set -e
source "$(dirname "$0")/lib.sh"
info "停止所有微服務..."
SERVICES=("ssl-proxy" "frontend" "bff" "api-product" "api-order" "api-user" "internal-net")
for service in "${SERVICES[@]}"; do
    info "停止 $service..."
    systemctl --user stop "$service" 2>/dev/null || true
done
info "所有服務已停止"
exit 0

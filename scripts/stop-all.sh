#!/bin/bash
# ============================================================================
# 停止所有服務（含多副本）
# ============================================================================

set -e

source "$(dirname "$0")/lib.sh"

info "停止所有微服務..."

# 停止順序（反向依賴）
# 1. SSL Proxy
info "停止 ssl-proxy..."
systemctl --user stop ssl-proxy 2>/dev/null || true

# 2. Frontend, BFF
for service in frontend bff; do
    stop_service "$service"
done

# 3. Backend API 服務
for service in api-product api-order api-user; do
    stop_service "$service"
done

# 4. 網路
info "停止 internal-net..."
systemctl --user stop internal-net 2>/dev/null || true

echo ""
info "所有服務已停止"
exit 0

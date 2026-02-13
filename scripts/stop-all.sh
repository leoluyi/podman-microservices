#!/bin/bash
# ============================================================================
# 停止所有微服務
# ============================================================================

set -e

RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

stopped() {
    echo -e "${RED}[STOPPED]${NC} $1"
}

info "停止所有微服務..."
echo ""

# 反向順序停止
SERVICES=(
    "frontend"
    "bff"
    "public-nginx"
    "api-product"
    "api-order"
    "api-user"
    "internal-net"
)

for service in "${SERVICES[@]}"; do
    info "停止 ${service}..."
    systemctl --user stop ${service}.service 2>/dev/null || true
    stopped "${service} 已停止"
done

echo ""
stopped "所有服務已停止"

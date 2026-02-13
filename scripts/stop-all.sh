#!/bin/bash
# 停止所有服務
set -e
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
info "停止所有微服務..."
SERVICES=("ssl-proxy" "frontend" "bff" "api-product" "api-order" "api-user" "internal-net")
for service in "${SERVICES[@]}"; do
    info "停止 $service..."
    systemctl --user stop "$service" 2>/dev/null || true
done
echo -e "${RED}所有服務已停止${NC}"
exit 0

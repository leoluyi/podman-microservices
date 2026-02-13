#!/bin/bash
# ============================================================================
# 查看所有服務狀態
# ============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}微服務狀態總覽${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 檢查服務狀態
systemctl --user status 'internal-net.service' 'api-*.service' 'bff.service' 'public-nginx.service' 'frontend.service' --no-pager | grep -E "●|Active:" || true

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}容器狀態${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}網路狀態${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

podman network ls --format "table {{.Name}}\t{{.Driver}}\t{{.NetworkInterface}}"

echo ""
echo -e "${BLUE}詳細查看單一服務：${NC}"
echo "  systemctl --user status <service-name>.service"
echo ""
echo -e "${BLUE}查看即時日誌：${NC}"
echo "  ./scripts/logs.sh <service-name>"
echo ""

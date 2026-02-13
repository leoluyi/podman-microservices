#!/bin/bash
# ============================================================================
# 重啟單一服務
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

if [ $# -eq 0 ]; then
    echo "用法: $0 <service-name>"
    echo ""
    echo "可用的服務："
    echo "  - api-user"
    echo "  - api-order"
    echo "  - api-product"
    echo "  - public-nginx"
    echo "  - bff"
    echo "  - frontend"
    echo ""
    echo "範例："
    echo "  $0 api-order"
    exit 1
fi

SERVICE=$1

info "重啟 ${SERVICE}..."
systemctl --user restart ${SERVICE}.service

# 等待服務啟動
sleep 2

# 檢查狀態
if systemctl --user is-active --quiet ${SERVICE}.service; then
    success "${SERVICE} 重啟成功"
    echo ""
    info "查看狀態："
    systemctl --user status ${SERVICE}.service --no-pager | head -20
else
    echo ""
    echo "⚠️  ${SERVICE} 可能未正常啟動，請查看日誌："
    echo "  ./scripts/logs.sh ${SERVICE}"
fi

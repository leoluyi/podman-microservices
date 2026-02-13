#!/bin/bash
# 重啟單一服務
if [ $# -eq 0 ]; then
    echo "使用方式: $0 <service-name>"
    echo ""
    echo "可用服務："
    echo "  - ssl-proxy"
    echo "  - frontend"
    echo "  - bff"
    echo "  - api-user"
    echo "  - api-order"
    echo "  - api-product"
    exit 1
fi
SERVICE=$1
echo "重啟 $SERVICE..."
systemctl --user restart "$SERVICE"
sleep 2
if systemctl --user is-active --quiet "$SERVICE"; then
    echo "✓ $SERVICE 已重啟"
else
    echo "✗ $SERVICE 重啟失敗"
    systemctl --user status "$SERVICE"
fi
exit 0

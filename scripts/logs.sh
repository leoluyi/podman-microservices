#!/bin/bash
# 查看服務日誌
if [ $# -eq 0 ]; then
    echo "使用方式: $0 <service-name> [lines]"
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
LINES=${2:-50}
echo "查看 $SERVICE 日誌（最近 $LINES 行）..."
journalctl --user -u "$SERVICE" -n "$LINES" -f

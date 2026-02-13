#!/bin/bash
# ============================================================================
# 查看服務日誌
# ============================================================================

if [ $# -eq 0 ]; then
    echo "用法: $0 <service-name> [lines]"
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
    echo "  $0 api-order          # 查看即時日誌"
    echo "  $0 api-order 100      # 查看最近 100 行"
    echo "  $0 all                # 查看所有 API 服務日誌"
    exit 1
fi

SERVICE=$1
LINES=${2:-50}

if [ "$SERVICE" == "all" ]; then
    echo "查看所有 API 服務日誌..."
    journalctl --user -u 'api-*.service' -f
else
    echo "查看 ${SERVICE} 服務日誌（最近 ${LINES} 行）..."
    journalctl --user -u ${SERVICE}.service -n ${LINES} -f
fi

#!/bin/bash
# 查看服務日誌（支援多副本）
source "$(dirname "$0")/lib.sh"

if [ $# -eq 0 ]; then
    echo "使用方式: $0 <service-name> [instance] [lines]"
    echo ""
    echo "範例："
    echo "  $0 api-user         # 查看 api-user 所有副本日誌"
    echo "  $0 api-user 1       # 查看 api-user@1 日誌"
    echo "  $0 api-user 1 100   # 查看 api-user@1 最近 100 行"
    echo "  $0 ssl-proxy        # 查看 ssl-proxy 日誌"
    echo ""
    echo "可用服務："
    for s in "${SCALABLE_SERVICES[@]}"; do echo "  - $s（可指定 instance）"; done
    for s in "${SINGLETON_SERVICES[@]}"; do echo "  - $s"; done
    exit 1
fi

SERVICE=$1

if is_scalable "$SERVICE"; then
    if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
        INSTANCE=$2
        LINES=${3:-50}
        echo "查看 ${SERVICE}@${INSTANCE} 日誌（最近 $LINES 行）..."
        journalctl --user -u "${SERVICE}@${INSTANCE}" -n "$LINES" -f
    else
        LINES=${2:-50}
        replicas=$(get_replicas "$SERVICE")
        echo "查看 ${SERVICE} 所有副本日誌（最近 $LINES 行）..."
        # 使用 glob pattern 查看所有 instance
        journalctl --user -u "${SERVICE}@*" -n "$LINES" -f
    fi
else
    LINES=${2:-50}
    echo "查看 $SERVICE 日誌（最近 $LINES 行）..."
    journalctl --user -u "$SERVICE" -n "$LINES" -f
fi

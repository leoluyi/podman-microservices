#!/bin/bash
# ============================================================================
# 動態調整服務副本數
# ============================================================================
# 使用方式：
#   ./scripts/scale-service.sh api-user 3    # 將 api-user 擴展到 3 副本
#   ./scripts/scale-service.sh bff 1         # 將 bff 縮減到 1 副本
#
# 注意：此腳本會自動更新 configs/ha.conf，但不會更新 upstream.conf
#       調整副本後，請同步修改 configs/ssl-proxy/conf.d/upstream.conf
#       並重新載入 ssl-proxy：
#         podman exec ssl-proxy nginx -s reload

set -e

source "$(dirname "$0")/lib-deploy.sh"

if [ $# -lt 2 ]; then
    echo "使用方式: $0 <service-name> <replicas>"
    echo ""
    echo "可擴展服務："
    for s in "${SCALABLE_SERVICES[@]}"; do
        replicas=$(get_replicas "$s")
        echo "  - $s（目前 ${replicas} 副本）"
    done
    exit 1
fi

SERVICE=$1
TARGET=$2

# 驗證
if ! is_scalable "$SERVICE"; then
    error "$SERVICE 不支援擴展（singleton 服務）"
    exit 1
fi

if ! [[ "$TARGET" =~ ^[1-9][0-9]*$ ]]; then
    error "副本數必須是正整數: $TARGET"
    exit 1
fi

if [ "$TARGET" -gt 10 ]; then
    error "單機環境建議副本數不超過 10"
    exit 1
fi

CURRENT=$(get_replicas "$SERVICE")
info "調整 $SERVICE: ${CURRENT} → ${TARGET} 副本"

# Scale up: 啟動新的 instance
if [ "$TARGET" -gt "$CURRENT" ]; then
    for i in $(seq $((CURRENT + 1)) "$TARGET"); do
        info "  啟動 ${SERVICE}@${i}..."
        systemctl --user start "${SERVICE}@${i}" 2>/dev/null || true
        if wait_for_service "${SERVICE}@${i}" 30; then
            success "  ✓ ${SERVICE}@${i} 已啟動"
        else
            error "  ✗ ${SERVICE}@${i} 啟動失敗"
        fi
    done
fi

# Scale down: 停止多餘的 instance
if [ "$TARGET" -lt "$CURRENT" ]; then
    for i in $(seq "$CURRENT" -1 $((TARGET + 1))); do
        info "  停止 ${SERVICE}@${i}..."
        systemctl --user stop "${SERVICE}@${i}" 2>/dev/null || true
        success "  ✓ ${SERVICE}@${i} 已停止"
    done
fi

# 更新 ha.conf
VAR_NAME="$(echo "$SERVICE" | tr '[:lower:]-' '[:upper:]_')_REPLICAS"
if [ -f "$HA_CONF" ]; then
    if grep -q "^${VAR_NAME}=" "$HA_CONF"; then
        sed -i.bak "s/^${VAR_NAME}=.*/${VAR_NAME}=${TARGET}/" "$HA_CONF"
        rm -f "${HA_CONF}.bak"
    else
        echo "${VAR_NAME}=${TARGET}" >> "$HA_CONF"
    fi
fi

echo ""
success "$SERVICE 已調整為 ${TARGET} 副本"
echo ""
warning "請記得同步更新 upstream.conf 並重新載入 ssl-proxy："
echo "  1. 編輯 configs/ssl-proxy/conf.d/upstream.conf"
echo "  2. podman exec ssl-proxy nginx -s reload"

exit 0

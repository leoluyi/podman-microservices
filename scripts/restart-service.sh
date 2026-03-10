#!/bin/bash
# ============================================================================
# 重啟單一服務（支援多副本）
# ============================================================================

source "$(dirname "$0")/lib.sh"

if [ $# -eq 0 ]; then
    echo "使用方式: $0 <service-name> [instance-number]"
    echo ""
    echo "可用服務："
    for s in "${SCALABLE_SERVICES[@]}"; do echo "  - $s（可指定 instance，如: $0 $s 1）"; done
    for s in "${SINGLETON_SERVICES[@]}"; do echo "  - $s"; done
    exit 1
fi

SERVICE=$1
INSTANCE=$2

# 驗證服務名稱
is_valid=false
for s in "${ALL_SERVICES[@]}"; do
    [ "$s" = "$SERVICE" ] && is_valid=true && break
done

if ! $is_valid; then
    error "未知的服務: $SERVICE"
    echo "可用服務: ${ALL_SERVICES[*]}"
    exit 1
fi

if is_scalable "$SERVICE"; then
    if [ -n "$INSTANCE" ]; then
        # 重啟指定 instance
        info "重啟 ${SERVICE}@${INSTANCE}..."
        systemctl --user restart "${SERVICE}@${INSTANCE}"
        if wait_for_service "${SERVICE}@${INSTANCE}" 30; then
            success "✓ ${SERVICE}@${INSTANCE} 已重啟"
        else
            error "✗ ${SERVICE}@${INSTANCE} 重啟失敗"
            systemctl --user status "${SERVICE}@${INSTANCE}"
            exit 1
        fi
    else
        # 重啟所有副本（rolling restart）
        replicas=$(get_replicas "$SERVICE")
        info "Rolling restart $SERVICE（${replicas} 副本）..."
        for i in $(seq 1 "$replicas"); do
            info "  重啟 ${SERVICE}@${i}..."
            systemctl --user restart "${SERVICE}@${i}"
            if wait_for_service "${SERVICE}@${i}" 30; then
                success "  ✓ ${SERVICE}@${i} 已重啟"
            else
                error "  ✗ ${SERVICE}@${i} 重啟失敗"
            fi
            # Rolling restart：等前一個就緒再重啟下一個
            [ "$i" -lt "$replicas" ] && sleep 2
        done
    fi
else
    info "重啟 $SERVICE..."
    systemctl --user restart "$SERVICE"
    if wait_for_service "$SERVICE" 30; then
        success "✓ $SERVICE 已重啟"
    else
        error "✗ $SERVICE 重啟失敗"
        systemctl --user status "$SERVICE"
        exit 1
    fi
fi

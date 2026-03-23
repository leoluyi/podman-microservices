#!/bin/bash
# 共用工具函數，供其他腳本 source 使用
# 使用方式：source "$(dirname "$0")/lib.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================================
# HA 配置
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HA_CONF="$PROJECT_ROOT/configs/ha.conf"

# 可擴展的服務清單（template units，使用 @ 格式）
SCALABLE_SERVICES=("api-user" "api-order" "api-product" "api-auth" "bff" "frontend")

# 不可擴展的服務（singleton）
SINGLETON_SERVICES=("ssl-proxy" "postgres")

# 所有服務
ALL_SERVICES=("${SCALABLE_SERVICES[@]}" "${SINGLETON_SERVICES[@]}")

# 讀取服務的副本數
# 用法：get_replicas <service-name>
# 回傳：副本數（預設 2）
get_replicas() {
    local service=$1
    local var_name
    var_name="$(echo "$service" | tr '[:lower:]-' '[:upper:]_')_REPLICAS"

    if [ -f "$HA_CONF" ]; then
        local value
        value=$(grep "^${var_name}=" "$HA_CONF" 2>/dev/null | cut -d= -f2)
        echo "${value:-2}"
    else
        echo "2"
    fi
}

# 判斷服務是否為可擴展類型
is_scalable() {
    local service=$1
    for s in "${SCALABLE_SERVICES[@]}"; do
        [ "$s" = "$service" ] && return 0
    done
    return 1
}

# 等待 systemd 服務進入 active 狀態
# 用法：wait_for_service <service-name> [timeout-seconds]
# 回傳：0 成功，1 逾時
wait_for_service() {
    local service=$1
    local timeout=${2:-30}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if systemctl --user is-active --quiet "$service" 2>/dev/null; then
            return 0
        fi
        sleep 1
        ((elapsed++))
    done
    return 1
}

# 啟動一個服務的所有副本
# 用法：start_service <service-name>
start_service() {
    local service=$1

    if is_scalable "$service"; then
        local replicas
        replicas=$(get_replicas "$service")
        info "啟動 $service（${replicas} 副本）..."
        for i in $(seq 1 "$replicas"); do
            systemctl --user start "${service}@${i}" 2>/dev/null || true
            if wait_for_service "${service}@${i}" 30; then
                success "  ✓ ${service}@${i} 已啟動"
            else
                error "  ✗ ${service}@${i} 啟動失敗"
            fi
        done
    else
        info "啟動 $service..."
        systemctl --user start "$service"
        if wait_for_service "$service" 30; then
            success "  ✓ $service 已啟動"
        else
            error "  ✗ $service 啟動失敗"
        fi
    fi
}

# 停止一個服務的所有副本
# 用法：stop_service <service-name>
stop_service() {
    local service=$1

    if is_scalable "$service"; then
        local replicas
        replicas=$(get_replicas "$service")
        info "停止 $service（${replicas} 副本）..."
        for i in $(seq 1 "$replicas"); do
            systemctl --user stop "${service}@${i}" 2>/dev/null || true
        done
        # 也停止可能超出當前設定的殘留 instance
        for i in $(seq $((replicas + 1)) 10); do
            systemctl --user stop "${service}@${i}" 2>/dev/null || true
        done
    else
        info "停止 $service..."
        systemctl --user stop "$service" 2>/dev/null || true
    fi
}

# 查詢一個服務所有副本的狀態
# 用法：show_service_status <service-name>
show_service_status() {
    local service=$1

    if is_scalable "$service"; then
        local replicas
        replicas=$(get_replicas "$service")
        for i in $(seq 1 "$replicas"); do
            local unit="${service}@${i}"
            local status
            status=$(systemctl --user is-active "$unit" 2>/dev/null || echo "inactive")
            if [ "$status" = "active" ]; then
                echo "  ✓ ${unit}: ACTIVE"
            else
                echo "  ✗ ${unit}: $status"
            fi
        done
    else
        local status
        status=$(systemctl --user is-active "$service" 2>/dev/null || echo "inactive")
        if [ "$status" = "active" ]; then
            echo "  ✓ ${service}: ACTIVE"
        else
            echo "  ✗ ${service}: $status"
        fi
    fi
}

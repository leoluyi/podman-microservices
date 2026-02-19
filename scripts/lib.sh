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

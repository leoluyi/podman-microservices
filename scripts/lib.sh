#!/bin/bash
# ============================================================================
# lib.sh - Shared utilities for all scripts
# ============================================================================
# Usage: source "$(dirname "$0")/lib.sh"
#
# Provides: colors, logging, paths, HA config helpers.
# Systemd-specific functions are in deploy/lib-deploy.sh.
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ─── Paths ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HA_CONF="$PROJECT_ROOT/configs/shared/ha.conf"

# ─── Service lists ───────────────────────────────────────────────────────────
SCALABLE_SERVICES=("api-user" "api-order" "api-product" "api-auth" "bff" "frontend")
SINGLETON_SERVICES=("ssl-proxy" "postgres")
ALL_SERVICES=("${SCALABLE_SERVICES[@]}" "${SINGLETON_SERVICES[@]}")

# ─── HA config helpers ───────────────────────────────────────────────────────

# Get replica count for a service from ha.conf
# Usage: get_replicas <service-name>
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

# Check if a service supports multiple replicas
is_scalable() {
    local service=$1
    for s in "${SCALABLE_SERVICES[@]}"; do
        [ "$s" = "$service" ] && return 0
    done
    return 1
}

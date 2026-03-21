#!/bin/bash
# ============================================================================
# local-stop.sh - Stop and remove all containers + network (no systemd)
# ============================================================================
# Counterpart to local-start.sh. Stops services in reverse dependency order,
# removes containers, and tears down the network.
#
# Usage: ./scripts/local-stop.sh
# ============================================================================

set -euo pipefail

source "$(dirname "$0")/lib.sh"

NETWORK="internal-net"
LABEL="app=microservices"

CYAN='\033[0;36m'
section() { echo -e "\n${CYAN}== $* ==${NC}"; }

# Remove a container by name (stop + rm). No-op if it doesn't exist.
remove_container() {
    local name=$1
    if podman container exists "$name" 2>/dev/null; then
        podman rm -f "$name" >/dev/null 2>&1 || true
        success "  Removed $name"
    fi
}

# Stop all replicas of a scalable service, including extras beyond configured count.
stop_replicas() {
    local service=$1
    local replicas
    replicas=$(get_replicas "$service")
    info "Stopping $service ..."

    # Stop configured replicas + scan up to 10 for leftovers
    local max=$((replicas > 10 ? replicas : 10))
    for i in $(seq 1 "$max"); do
        remove_container "${service}-${i}"
    done
}

# ─── Main ───────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${CYAN}+--------------------------------------+${NC}"
    echo -e "${CYAN}|  Podman Microservices - Local Stop   |${NC}"
    echo -e "${CYAN}+--------------------------------------+${NC}"
    echo ""

    # 1. SSL Proxy (singleton)
    section "SSL Proxy"
    info "Stopping ssl-proxy ..."
    remove_container ssl-proxy

    # 2. Frontend, BFF
    section "Frontend & BFF"
    stop_replicas frontend
    stop_replicas bff

    # 3. Backend API services
    section "API Services"
    stop_replicas api-product
    stop_replicas api-order
    stop_replicas api-user

    # 4. Catch any remaining labeled containers
    local remaining
    remaining=$(podman ps -a --filter "label=$LABEL" --format "{{.Names}}" 2>/dev/null || true)
    if [[ -n "$remaining" ]]; then
        section "Leftover Containers"
        while IFS= read -r name; do
            remove_container "$name"
        done <<< "$remaining"
    fi

    # 5. Network
    section "Network"
    if podman network exists "$NETWORK" 2>/dev/null; then
        podman network rm "$NETWORK" >/dev/null 2>&1 || true
        success "  Removed network $NETWORK"
    else
        info "Network $NETWORK does not exist, nothing to remove"
    fi

    echo ""
    success "All services stopped and cleaned up."
}

main "$@"

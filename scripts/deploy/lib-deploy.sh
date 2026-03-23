#!/bin/bash
# ============================================================================
# lib-deploy.sh - Systemd/Quadlet deployment helpers (RHEL only)
# ============================================================================
# Usage: source "$(dirname "$0")/lib-deploy.sh"
#
# Provides systemd-based service management functions used by deploy scripts.
# Requires systemctl --user (Quadlet/systemd user units).
# ============================================================================

# Source the common lib for colors, paths, and HA config
DEPLOY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DEPLOY_SCRIPT_DIR/../lib.sh"

# Wait for a systemd service to become active
# Usage: wait_for_service <service-name> [timeout-seconds]
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

# Start all replicas of a service via systemd
# Usage: start_service <service-name>
start_service() {
    local service=$1

    if is_scalable "$service"; then
        local replicas
        replicas=$(get_replicas "$service")
        info "Starting $service ($replicas replicas) ..."
        for i in $(seq 1 "$replicas"); do
            systemctl --user start "${service}@${i}" 2>/dev/null || true
            if wait_for_service "${service}@${i}" 30; then
                success "  ${service}@${i} started"
            else
                error "  ${service}@${i} failed to start"
            fi
        done
    else
        info "Starting $service ..."
        systemctl --user start "$service"
        if wait_for_service "$service" 30; then
            success "  $service started"
        else
            error "  $service failed to start"
        fi
    fi
}

# Stop all replicas of a service via systemd
# Usage: stop_service <service-name>
stop_service() {
    local service=$1

    if is_scalable "$service"; then
        local replicas
        replicas=$(get_replicas "$service")
        info "Stopping $service ($replicas replicas) ..."
        for i in $(seq 1 "$replicas"); do
            systemctl --user stop "${service}@${i}" 2>/dev/null || true
        done
        for i in $(seq $((replicas + 1)) 10); do
            systemctl --user stop "${service}@${i}" 2>/dev/null || true
        done
    else
        info "Stopping $service ..."
        systemctl --user stop "$service" 2>/dev/null || true
    fi
}

# Show status of all replicas of a service
# Usage: show_service_status <service-name>
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
                echo "  ${unit}: ACTIVE"
            else
                echo "  ${unit}: $status"
            fi
        done
    else
        local status
        status=$(systemctl --user is-active "$service" 2>/dev/null || echo "inactive")
        if [ "$status" = "active" ]; then
            echo "  ${service}: ACTIVE"
        else
            echo "  ${service}: $status"
        fi
    fi
}

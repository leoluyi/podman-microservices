#!/bin/bash
# ============================================================================
# 查看所有服務狀態（含多副本）
# ============================================================================

source "$(dirname "$0")/lib-deploy.sh"

echo "服務狀態："
echo "=========================================="

# 網路
status=$(systemctl --user is-active "internal-net" 2>/dev/null || echo "inactive")
if [ "$status" = "active" ]; then
    echo "  ✓ internal-net: ACTIVE"
else
    echo "  ✗ internal-net: $status"
fi

echo "---"

# 可擴展服務
for service in "${SCALABLE_SERVICES[@]}"; do
    show_service_status "$service"
done

echo "---"

# Singleton 服務
for service in "${SINGLETON_SERVICES[@]}"; do
    show_service_status "$service"
done

echo "=========================================="
echo ""

# 副本配置摘要
echo "副本配置（configs/shared/ha.conf）："
for service in "${SCALABLE_SERVICES[@]}"; do
    replicas=$(get_replicas "$service")
    echo "  $service: ${replicas} 副本"
done
echo ""

echo "詳細狀態："
echo "  systemctl --user status <service-name>@<instance>"
exit 0

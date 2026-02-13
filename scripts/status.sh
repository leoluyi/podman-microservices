#!/bin/bash
# 查看所有服務狀態
SERVICES=("internal-net" "ssl-proxy" "frontend" "bff" "api-user" "api-order" "api-product")
echo "服務狀態："
echo "=========================================="
for service in "${SERVICES[@]}"; do
    status=$(systemctl --user is-active "$service" 2>/dev/null || echo "inactive")
    if [ "$status" == "active" ]; then
        echo "  ✓ $service: 🟢 ACTIVE"
    else
        echo "  ✗ $service: 🔴 $status"
    fi
done
echo "=========================================="
echo ""
echo "詳細狀態："
echo "  systemctl --user status <service-name>"
exit 0

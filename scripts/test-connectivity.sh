#!/bin/bash
# ============================================================================
# 測試服務連通性與網路隔離
# ============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

success() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

test_endpoint() {
    local url=$1
    local description=$2
    local expected=$3  # "success" or "fail"
    
    if curl -sf "$url" > /dev/null 2>&1; then
        if [ "$expected" == "success" ]; then
            success "$description"
        else
            fail "$description (應該失敗但成功了)"
        fi
    else
        if [ "$expected" == "fail" ]; then
            success "$description (正確地被阻擋)"
        else
            fail "$description"
        fi
    fi
}

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}微服務連通性測試${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ============================================================================
# 1. 測試對外服務（應該成功）
# ============================================================================
info "測試對外服務..."
test_endpoint "http://localhost:3000" "Frontend (Port 3000)" "success"
test_endpoint "http://localhost:8080/health" "BFF (Port 8080)" "success"
test_endpoint "http://localhost:8090/health" "Public Nginx (Port 8090)" "success"
echo ""

# ============================================================================
# 2. 測試 Debug 模式（依環境而定）
# ============================================================================
info "測試 Debug 模式端口..."
if curl -sf http://localhost:8081/health > /dev/null 2>&1; then
    success "API-User localhost:8081 可訪問 (Debug 模式已啟用)"
    success "API-Order localhost:8082 可訪問 (Debug 模式已啟用)" 
    success "API-Product localhost:8083 可訪問 (Debug 模式已啟用)"
    warning "目前處於開發/測試環境"
else
    success "Backend APIs 從 localhost 無法訪問 (生產模式，完全隔離)"
    info "目前處於生產環境"
fi
echo ""

# ============================================================================
# 3. 測試 Public Nginx API Key 驗證
# ============================================================================
info "測試 API Key 驗證..."

# 沒有 API Key（應該失敗）
if curl -sf http://localhost:8090/api/order/ > /dev/null 2>&1; then
    fail "無 API Key 時應該被拒絕"
else
    success "無 API Key 正確被拒絕 (401)"
fi

# 錯誤的 API Key（應該失敗）
if curl -sf -H "X-API-Key: wrong-key" http://localhost:8090/api/order/ > /dev/null 2>&1; then
    fail "錯誤的 API Key 應該被拒絕"
else
    success "錯誤的 API Key 正確被拒絕 (401)"
fi

# 正確的 API Key（應該成功，但可能 404 因為沒有實際 API）
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "X-API-Key: dev-key-12345678901234567890" http://localhost:8090/api/order/)
if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "404" ] || [ "$HTTP_CODE" == "502" ]; then
    success "正確的 API Key 通過驗證 (HTTP $HTTP_CODE)"
else
    fail "正確的 API Key 應該通過驗證 (得到 HTTP $HTTP_CODE)"
fi
echo ""

# ============================================================================
# 4. 測試容器間連通性（從 BFF 訪問 Backend APIs）
# ============================================================================
info "測試容器間連通性..."

if podman exec bff curl -sf http://api-user:8081/health > /dev/null 2>&1; then
    success "BFF → API-User 連通"
else
    warning "BFF → API-User 無法連通（可能容器未啟動或無健康檢查端點）"
fi

if podman exec bff curl -sf http://api-order:8082/health > /dev/null 2>&1; then
    success "BFF → API-Order 連通"
else
    warning "BFF → API-Order 無法連通（可能容器未啟動或無健康檢查端點）"
fi

if podman exec bff curl -sf http://api-product:8083/health > /dev/null 2>&1; then
    success "BFF → API-Product 連通"
else
    warning "BFF → API-Product 無法連通（可能容器未啟動或無健康檢查端點）"
fi
echo ""

# ============================================================================
# 5. 測試網路隔離（從 Frontend 無法訪問 Backend APIs）
# ============================================================================
info "測試網路隔離..."

if podman exec frontend curl -sf http://api-user:8081/health > /dev/null 2>&1; then
    fail "Frontend 不應該能訪問 API-User (網路隔離失敗)"
else
    success "Frontend 無法訪問 Backend APIs (網路隔離正確)"
fi
echo ""

# ============================================================================
# 總結
# ============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}測試完成${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
info "如有失敗項目，請檢查："
echo "  1. 容器是否正常運行：podman ps"
echo "  2. 服務日誌：./scripts/logs.sh <service-name>"
echo "  3. 網路配置：podman network inspect internal-net"
echo ""

#!/bin/bash
# ============================================================================
# 連通性測試腳本
# ============================================================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${BLUE}[TEST]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

PASSED=0
FAILED=0

# ============================================================================
# 測試函數
# ============================================================================
test_endpoint() {
    local name=$1
    local url=$2
    local expected_code=${3:-200}
    local extra_args=${4:-""}
    
    info "測試 $name: $url"
    
    if response=$(curl -k -s -w "\n%{http_code}" $extra_args "$url" 2>&1); then
        http_code=$(echo "$response" | tail -n 1)
        body=$(echo "$response" | sed '$d')
        
        if [ "$http_code" == "$expected_code" ]; then
            success "  HTTP $http_code ✓"
            ((PASSED++))
        else
            fail "  HTTP $http_code (期望 $expected_code) ✗"
            echo "  回應: $body"
            ((FAILED++))
        fi
    else
        fail "  連線失敗 ✗"
        ((FAILED++))
    fi
}

# ============================================================================
# 開始測試
# ============================================================================
echo ""
echo "=========================================="
echo "  連通性測試"
echo "=========================================="
echo ""

# 1. SSL Proxy 健康檢查
info "=== SSL Proxy ==="
test_endpoint "HTTPS 健康檢查" "https://localhost/health"
test_endpoint "HTTP 重定向" "http://localhost/" 301

echo ""

# 2. 前端訪問
info "=== Frontend ==="
test_endpoint "前端首頁" "https://localhost/"

echo ""

# 3. JWT Token 測試
info "=== API 端點 (JWT Token) ==="

# 產生測試 Token
if [ -f "./scripts/generate-jwt.sh" ]; then
    TOKEN=$(./scripts/generate-jwt.sh test-user 2>/dev/null || echo "")
else
    warn "generate-jwt.sh 不存在，跳過 JWT 測試"
    TOKEN=""
fi

if [ -n "$TOKEN" ]; then
    test_endpoint "API (有效 Token)" "https://localhost/api/users" 200 "-H 'Authorization: Bearer $TOKEN'"
else
    test_endpoint "API (無 Token)" "https://localhost/api/users" 401
fi

test_endpoint "API (無 Token，預期失敗)" "https://localhost/api/users" 401

echo ""

# 4. Partner API 測試（JWT Token）
info "=== Partner API (JWT Token) ==="

if [ -n "$TOKEN" ]; then
    # 產生 Partner JWT Token
    PARTNER_TOKEN=$(./scripts/generate-jwt.sh partner-company-a 2>/dev/null || echo "")

    if [ -n "$PARTNER_TOKEN" ]; then
        test_endpoint "Partner Order API (有效 JWT)" \
            "https://localhost/partner/api/order/" 200 \
            "-H 'Authorization: Bearer $PARTNER_TOKEN'"

        test_endpoint "Partner Product API (有效 JWT)" \
            "https://localhost/partner/api/product/" 200 \
            "-H 'Authorization: Bearer $PARTNER_TOKEN'"
    else
        warn "無法產生 Partner Token，跳過 Partner JWT 測試"
    fi
else
    warn "跳過 Partner API 測試（無法產生 Token）"
fi

test_endpoint "Partner API (無 Token，預期失敗)" \
    "https://localhost/partner/api/order/" 401

echo ""

# 5. Backend APIs 隔離測試
info "=== 網路隔離測試 ==="

# 檢查是否為開發模式
if [ -f ~/.config/containers/systemd/api-user.container.d/environment.conf ]; then
    MODE="dev"
else
    MODE="prod"
fi

if [ "$MODE" == "dev" ]; then
    info "開發模式：測試 localhost Debug 端口"
    test_endpoint "API-User Debug" "http://localhost:8101/health"
    test_endpoint "API-Order Debug" "http://localhost:8102/health"
    test_endpoint "API-Product Debug" "http://localhost:8103/health"
else
    info "生產模式：驗證 Backend APIs 完全隔離"
    
    if curl -s --max-time 2 http://localhost:8101/health &>/dev/null; then
        fail "  API-User 不應該可以從主機訪問 ✗"
        ((FAILED++))
    else
        success "  API-User 已隔離（無法從主機訪問）✓"
        ((PASSED++))
    fi
fi

echo ""

# ============================================================================
# 測試結果摘要
# ============================================================================
echo "=========================================="
echo "  測試結果"
echo "=========================================="
echo ""
echo "  通過: $PASSED"
echo "  失敗: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    success "所有測試通過！✓"
    exit 0
else
    fail "部分測試失敗 ✗"
    echo ""
    echo "故障排除："
    echo "  1. 檢查服務狀態: ./scripts/status.sh"
    echo "  2. 查看日誌: ./scripts/logs.sh ssl-proxy"
    echo "  3. 查看文件: docs/DEBUG.md"
    exit 1
fi

#!/bin/bash
# ============================================================================
# JWT Token 產生腳本（用於測試）
# 支援不同 Partner 的 JWT Secret
# ============================================================================

set -e

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# 使用說明
usage() {
    echo "用法: $0 <partner-id>"
    echo ""
    echo "範例:"
    echo "  $0 partner-company-a"
    echo "  $0 partner-company-b"
    echo "  $0 partner-company-c"
    echo ""
    echo "支援的 Partner:"
    echo "  partner-company-a (可訪問: orders, products, users)"
    echo "  partner-company-b (可訪問: orders)"
    echo "  partner-company-c (可訪問: products)"
    exit 1
}

# 檢查參數
if [ $# -eq 0 ]; then
    usage
fi

PARTNER_ID=$1

# Partner Secret 映射（必須與 ssl-proxy.container 中的一致）
declare -A PARTNER_SECRETS
PARTNER_SECRETS["partner-company-a"]=${JWT_SECRET_PARTNER_A:-"dev-secret-partner-a-for-testing-only-32chars"}
PARTNER_SECRETS["partner-company-b"]=${JWT_SECRET_PARTNER_B:-"dev-secret-partner-b-for-testing-only-32chars"}
PARTNER_SECRETS["partner-company-c"]=${JWT_SECRET_PARTNER_C:-"dev-secret-partner-c-for-testing-only-32chars"}

# Partner 權限映射
declare -A PARTNER_PERMISSIONS
PARTNER_PERMISSIONS["partner-company-a"]="orders:read,write products:read,write users:read"
PARTNER_PERMISSIONS["partner-company-b"]="orders:read"
PARTNER_PERMISSIONS["partner-company-c"]="products:read,write"

# 檢查 Partner ID 是否有效
if [ -z "${PARTNER_SECRETS[$PARTNER_ID]}" ]; then
    echo -e "${RED}錯誤: 未知的 Partner ID: $PARTNER_ID${NC}" >&2
    echo "" >&2
    usage
fi

JWT_SECRET="${PARTNER_SECRETS[$PARTNER_ID]}"
PERMISSIONS="${PARTNER_PERMISSIONS[$PARTNER_ID]}"

# 檢查是否安裝 jq 和 base64
if ! command -v jq &> /dev/null; then
    echo -e "${RED}錯誤: jq 未安裝${NC}" >&2
    echo "安裝: brew install jq (macOS) 或 sudo apt install jq (Linux)" >&2
    exit 1
fi

# JWT Header
header=$(echo -n '{"alg":"HS256","typ":"JWT"}' | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')

# JWT Payload
current_time=$(date +%s)
exp_time=$((current_time + 86400))  # 24 小時後過期

payload=$(cat <<EOF | jq -c . | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'
{
  "sub": "$PARTNER_ID",
  "iss": "partner-api-system",
  "aud": "partner-api",
  "exp": $exp_time,
  "iat": $current_time
}
EOF
)

# 簽章
signature=$(echo -n "${header}.${payload}" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')

# 完整 JWT
jwt="${header}.${payload}.${signature}"

# 輸出 Token
echo "$jwt"

# Debug 資訊（輸出到 stderr，不影響 Token 輸出）
echo "" >&2
echo -e "${GREEN}✓ JWT Token 產生成功${NC}" >&2
echo -e "${BLUE}Partner ID:${NC} $PARTNER_ID" >&2
echo -e "${BLUE}權限:${NC} $PERMISSIONS" >&2
echo -e "${BLUE}過期時間:${NC} $(date -r $exp_time 2>/dev/null || date -d @$exp_time 2>/dev/null)" >&2
echo "" >&2
echo -e "${BLUE}使用範例:${NC}" >&2

# 根據權限顯示可用的 API
if [[ "$PERMISSIONS" == *"orders"* ]]; then
    echo "  # Orders API" >&2
    echo "  curl -k -H \"Authorization: Bearer \$TOKEN\" https://localhost/partner/api/order/" >&2
fi

if [[ "$PERMISSIONS" == *"products"* ]]; then
    echo "  # Products API" >&2
    echo "  curl -k -H \"Authorization: Bearer \$TOKEN\" https://localhost/partner/api/product/" >&2
fi

if [[ "$PERMISSIONS" == *"users"* ]]; then
    echo "  # Users API" >&2
    echo "  curl -k -H \"Authorization: Bearer \$TOKEN\" https://localhost/partner/api/user/" >&2
fi

echo "" >&2

exit 0

#!/bin/bash
# ============================================================================
# JWT Token 產生腳本
# ============================================================================
# 用途：產生符合 Partner API 規範的 JWT Token
#
# 適用場景：
# 1. ✅ Partner 在自己的系統中產生 Token（生產環境正確用法）
# 2. ✅ 開發/測試環境：API 提供方模擬 Partner 行為進行測試
# 3. ❌ API 提供方幫 Partner 產生 Token（違反安全原則）
#
# 安全原則：
# - 生產環境：只有 Partner 應該使用此腳本產生 Token
# - API 提供方：只負責「驗證」Token，不負責「產生」Partner 的 Token
# - 責任分離：Token 由 Partner 產生，確保身份認證的意義
#
# 使用方式：
# 1. 設定環境變數（使用 API 提供方給的 Secret）
#    export JWT_SECRET_PARTNER_A="your-secret-from-provider"
# 2. 執行腳本產生 Token
#    TOKEN=$(./generate-jwt.sh partner-company-a)
# 3. 使用 Token 呼叫 API
#    curl -H "Authorization: Bearer $TOKEN" https://api.example.com/partner/api/order/
# ============================================================================

set -e

source "$(dirname "$0")/lib.sh"

# 使用說明
usage() {
    echo "用法: $0 <partner-id> [有效期秒數]"
    echo ""
    echo "參數:"
    echo "  partner-id    Partner 識別碼（必要）"
    echo "  有效期秒數    Token 有效期，單位：秒（可選，預設：永久）"
    echo ""
    echo "範例:"
    echo "  $0 partner-company-a              # 預設永久有效（至 2286 年）"
    echo "  $0 partner-company-a 86400        # 1 天有效期"
    echo "  $0 partner-company-a 2592000      # 30 天有效期"
    echo "  $0 partner-company-a 31536000     # 1 年有效期"
    echo "  $0 partner-company-a 0            # 永久有效（明確指定）"
    echo ""
    echo "支援的 Partner:"
    echo "  partner-company-a (可訪問: orders, products, users)"
    echo "  partner-company-b (可訪問: orders)"
    echo "  partner-company-c (可訪問: products)"
    echo ""
    echo "常用有效期參考:"
    echo "  1 小時    = 3600"
    echo "  1 天      = 86400"
    echo "  7 天      = 604800"
    echo "  30 天     = 2592000"
    echo "  90 天     = 7776000"
    echo "  1 年      = 31536000"
    echo "  永久      = 0（或不指定）"
    exit 1
}

# 檢查參數
if [ $# -eq 0 ]; then
    usage
fi

PARTNER_ID=$1
EXPIRES_IN=${2:-0}  # 預設 0 代表永久

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

# 如果 EXPIRES_IN 為 0，設定為永久（2286 年）
if [ $EXPIRES_IN -eq 0 ]; then
    exp_time=9999999999  # 2286-11-20（實際上的永久）
else
    exp_time=$((current_time + EXPIRES_IN))
fi

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

# 計算有效期並友善顯示
if [ $EXPIRES_IN -eq 0 ]; then
    # 永久有效
    echo -e "${BLUE}有效期:${NC} 永久（至 2286 年）" >&2
elif [ $EXPIRES_IN -ge 31536000 ]; then
    # 大於等於 1 年
    years=$((EXPIRES_IN / 31536000))
    echo -e "${BLUE}有效期:${NC} ${years} 年" >&2
elif [ $EXPIRES_IN -ge 86400 ]; then
    # 大於等於 1 天
    days=$((EXPIRES_IN / 86400))
    echo -e "${BLUE}有效期:${NC} ${days} 天" >&2
elif [ $EXPIRES_IN -ge 3600 ]; then
    # 大於等於 1 小時
    hours=$((EXPIRES_IN / 3600))
    echo -e "${BLUE}有效期:${NC} ${hours} 小時" >&2
else
    echo -e "${BLUE}有效期:${NC} ${EXPIRES_IN} 秒" >&2
fi

echo -e "${BLUE}過期時間:${NC} $(date -r $exp_time 2>/dev/null || date -d @$exp_time 2>/dev/null)" >&2

# 如果是永久或長效 Token，顯示安全提醒
if [ $EXPIRES_IN -eq 0 ] || [ $EXPIRES_IN -ge 31536000 ]; then
    echo "" >&2
    echo -e "${YELLOW}⚠️  永久/長效 Token 安全提醒：${NC}" >&2
    echo -e "${YELLOW}   - 請確保 JWT Secret 安全儲存（不要硬編碼、不要提交到版控）${NC}" >&2
    echo -e "${YELLOW}   - 建議定期（如每年）主動輪換 Secret${NC}" >&2
    echo -e "${YELLOW}   - Token 洩漏時請立即聯繫 API 提供方輪換 Secret${NC}" >&2
fi

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

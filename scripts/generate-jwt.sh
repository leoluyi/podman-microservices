#!/bin/bash
# ============================================================================
# JWT Token 產生腳本（用於測試）
# ============================================================================

set -e

# JWT Secret（必須與 ssl-proxy.container 中的一致）
JWT_SECRET=${JWT_SECRET:-"your-super-secret-key-change-me-in-production-at-least-32-chars"}

# 使用者 ID（從參數取得）
USER_ID=${1:-"test-user"}

# 檢查是否安裝 jq 和 base64
if ! command -v jq &> /dev/null; then
    echo "錯誤: jq 未安裝" >&2
    echo "安裝: sudo zypper install jq" >&2
    exit 1
fi

# JWT Header
header=$(echo -n '{"alg":"HS256","typ":"JWT"}' | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')

# JWT Payload
current_time=$(date +%s)
exp_time=$((current_time + 86400))  # 24 小時後過期

payload=$(cat <<EOF | jq -c . | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'
{
  "sub": "$USER_ID",
  "email": "${USER_ID}@example.com",
  "client_type": "web",
  "roles": ["user"],
  "iss": "your-auth-service",
  "aud": "your-api",
  "exp": $exp_time,
  "iat": $current_time
}
EOF
)

# 簽章
signature=$(echo -n "${header}.${payload}" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')

# 完整 JWT
jwt="${header}.${payload}.${signature}"

# 輸出
echo "$jwt"

# Debug 資訊（輸出到 stderr）
if [ "${DEBUG}" == "1" ]; then
    echo "" >&2
    echo "JWT Token 產生成功" >&2
    echo "使用者: $USER_ID" >&2
    echo "過期時間: $(date -d @$exp_time)" >&2
    echo "" >&2
    echo "使用範例:" >&2
    echo "  curl -H \"Authorization: Bearer $jwt\" https://localhost/api/users" >&2
fi

exit 0

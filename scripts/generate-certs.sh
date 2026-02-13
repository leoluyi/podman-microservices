#!/bin/bash
# ============================================================================
# SSL 自簽憑證產生腳本
# ============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

CERT_DIR="/opt/app/certs"

info "產生自簽 SSL 憑證..."

# 建立憑證目錄
mkdir -p "$CERT_DIR"

# 檢查是否已存在憑證
if [ -f "$CERT_DIR/server.crt" ] && [ -f "$CERT_DIR/server.key" ]; then
    warn "憑證已存在"
    read -p "是否覆蓋現有憑證？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "保留現有憑證"
        exit 0
    fi
    
    # 備份舊憑證
    info "備份舊憑證..."
    mv "$CERT_DIR/server.crt" "$CERT_DIR/server.crt.backup.$(date +%Y%m%d_%H%M%S)"
    mv "$CERT_DIR/server.key" "$CERT_DIR/server.key.backup.$(date +%Y%m%d_%H%M%S)"
fi

# 建立 OpenSSL 配置（支援 SAN）
info "建立 OpenSSL 配置..."

cat > "$CERT_DIR/openssl.cnf" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C = TW
ST = Taiwan
L = Taipei
O = Development
OU = IT Department
CN = localhost

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = *.localhost
DNS.3 = yourdomain.local
DNS.4 = *.yourdomain.local
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

# 產生自簽憑證（有效期 10 年）
info "產生憑證（有效期 3650 天）..."

openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout "$CERT_DIR/server.key" \
    -out "$CERT_DIR/server.crt" \
    -config "$CERT_DIR/openssl.cnf" \
    -extensions req_ext

# 設定權限
chmod 644 "$CERT_DIR/server.crt"
chmod 600 "$CERT_DIR/server.key"

# 驗證憑證
info "驗證憑證..."
openssl x509 -in "$CERT_DIR/server.crt" -text -noout | grep -A 5 "Subject Alternative Name"

# 顯示憑證資訊
echo ""
success "憑證產生成功！"
echo ""
echo "憑證位置："
echo "  公鑰: $CERT_DIR/server.crt"
echo "  私鑰: $CERT_DIR/server.key"
echo ""
echo "憑證資訊："
openssl x509 -in "$CERT_DIR/server.crt" -noout -subject
openssl x509 -in "$CERT_DIR/server.crt" -noout -dates
echo ""
warn "這是自簽憑證，瀏覽器會顯示安全警告"
info "客戶端信任設定請參考 docs/DEPLOYMENT.md"

exit 0

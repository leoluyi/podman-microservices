#!/bin/bash
# ============================================================================
# 初始化部署腳本
# 用途：準備環境、配置 Debug 模式、部署 Quadlet 配置
# ============================================================================

set -e

source "$(dirname "$0")/lib.sh"

# 檢查參數
if [ $# -eq 0 ]; then
    error "使用方式: $0 {dev|prod}"
    echo ""
    echo "  dev  - 開發模式（啟用 Debug 端口）"
    echo "  prod - 生產模式（完全網路隔離）"
    exit 1
fi

MODE=$1

if [[ "$MODE" != "dev" && "$MODE" != "prod" ]]; then
    error "無效的模式: $MODE"
    error "使用方式: $0 {dev|prod}"
    exit 1
fi

info "初始化部署環境（模式: $MODE）"

# ============================================================================
# 1. 檢查前置需求
# ============================================================================
info "檢查前置需求..."

# 檢查 Podman
if ! command -v podman &> /dev/null; then
    error "Podman 未安裝"
    exit 1
fi

# 檢查 systemd
if ! command -v systemctl &> /dev/null; then
    error "systemctl 未安裝"
    exit 1
fi

# 檢查 Podman 版本
PODMAN_VERSION=$(podman version --format "{{.Version}}")
info "Podman 版本: $PODMAN_VERSION"

# ============================================================================
# 2. 建立必要目錄
# ============================================================================
info "建立必要目錄..."

# 建立 systemd 配置目錄
mkdir -p ~/.config/containers/systemd

# 建立應用目錄結構
mkdir -p /opt/app/certs
mkdir -p /opt/app/logs/{ssl-proxy,frontend,bff}
mkdir -p /opt/app/configs/ssl-proxy/conf.d
mkdir -p /opt/app/configs/frontend

# 設定目錄權限
chmod 755 /opt/app
chmod 700 /opt/app/certs
chmod 755 /opt/app/logs
chmod 755 /opt/app/configs

success "目錄建立完成"

# ============================================================================
# 3. 檢查 SSL 憑證
# ============================================================================
info "檢查 SSL 憑證..."

if [ ! -f "/opt/app/certs/server.crt" ] || [ ! -f "/opt/app/certs/server.key" ]; then
    warning "SSL 憑證不存在"
    info "執行憑證產生腳本..."
    ./scripts/generate-certs.sh
else
    success "SSL 憑證已存在"
fi

# ============================================================================
# 4. 複製配置檔
# ============================================================================
info "複製配置檔..."

# SSL Proxy 配置
cp -r "configs/ssl-proxy/"* "/opt/app/configs/ssl-proxy/"

# Frontend 配置
cp "configs/frontend/nginx.conf" "/opt/app/configs/frontend/"

success "配置檔複製完成"

# ============================================================================
# 5. 配置 Partner Secrets（混合方案）
# ============================================================================
info "配置 Partner Secrets..."

if [ "$MODE" == "dev" ]; then
    info "開發模式：使用環境檔案配置"

    # 複製 SSL Proxy 開發環境配置
    mkdir -p ~/.config/containers/systemd/ssl-proxy.container.d
    cp "quadlet/ssl-proxy.container.d/environment.conf.example" \
       "$HOME/.config/containers/systemd/ssl-proxy.container.d/environment.conf"

    success "已部署開發環境 Partner Secrets"
    info "使用固定測試 Secrets（jwt-secret-partner-a/b/c）"

else
    info "生產模式：使用 Podman Secrets"

    # 移除開發環境配置（如果存在）
    rm -rf ~/.config/containers/systemd/ssl-proxy.container.d

    # 檢查 Podman Secrets 是否存在
    MISSING_SECRETS=()
    for partner in a b c; do
        secret_name="jwt-secret-partner-$partner"
        if ! podman secret exists "$secret_name" 2>/dev/null; then
            MISSING_SECRETS+=("$secret_name")
        fi
    done

    if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
        warning "以下 Podman Secrets 尚未創建："
        for secret in "${MISSING_SECRETS[@]}"; do
            echo "  - $secret"
        done
        echo ""
        info "請使用以下命令創建 Partner Secrets："
        echo ""
        echo "  ./scripts/manage-partner-secrets.sh create a"
        echo "  ./scripts/manage-partner-secrets.sh create b"
        echo "  ./scripts/manage-partner-secrets.sh create c"
        echo ""
        warning "或執行快速創建（自動產生隨機 Secret）："
        read -p "是否立即創建缺少的 Secrets？(y/N) " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for partner in a b c; do
                secret_name="jwt-secret-partner-$partner"
                if ! podman secret exists "$secret_name" 2>/dev/null; then
                    info "創建 $secret_name..."
                    SECRET_VALUE=$(openssl rand -base64 32)
                    echo -n "$SECRET_VALUE" | podman secret create "$secret_name" -

                    # 保存到臨時文件
                    SECRET_FILE="/opt/app/configs/ssl-proxy/partner-secret-${partner}-$(date +%Y%m%d-%H%M%S).txt"
                    echo "Partner ID: partner-company-$partner" > "$SECRET_FILE"
                    echo "JWT Secret: $SECRET_VALUE" >> "$SECRET_FILE"
                    chmod 600 "$SECRET_FILE"

                    success "已創建並保存到: $SECRET_FILE"
                done
            done

            warning "請將 Secret 檔案內容安全地提供給 Partner，然後刪除檔案"
        else
            warning "跳過 Secret 創建，ssl-proxy 將使用 fallback 環境變數"
        fi
    else
        success "所有 Podman Secrets 已存在"
    fi
fi

# ============================================================================
# 6. 部署 Quadlet 配置
# ============================================================================
info "部署 Quadlet 配置..."

# 複製所有 .container 和 .network 檔案
cp quadlet/*.{container,network} ~/.config/containers/systemd/ 2>/dev/null || true

success "Quadlet 配置已部署"

# ============================================================================
# 7. 配置 Debug 模式
# ============================================================================
info "配置 $MODE 模式..."

# API 服務列表
APIS=("api-user" "api-order" "api-product")

if [ "$MODE" == "dev" ]; then
    info "啟用 Debug 模式（localhost 端口映射）"

    for api in "${APIS[@]}"; do
        mkdir -p "$HOME/.config/containers/systemd/${api}.container.d"
        cp "quadlet/${api}.container.d/environment.conf.example" \
           "$HOME/.config/containers/systemd/${api}.container.d/environment.conf"
        success "  $api: Debug 端口已啟用"
    done
    
    success "開發模式配置完成"
    info "Backend APIs 可透過 localhost 訪問："
    info "  - API-User:    http://localhost:8101"
    info "  - API-Order:   http://localhost:8102"
    info "  - API-Product: http://localhost:8103"
    
else
    info "生產模式（完全網路隔離）"
    
    for api in "${APIS[@]}"; do
        rm -rf ~/.config/containers/systemd/${api}.container.d
        success "  $api: Debug 端口已禁用"
    done
    
    success "生產模式配置完成"
    info "Backend APIs 完全隔離，只能透過 SSL Proxy 訪問"
fi

# ============================================================================
# 8. 重新載入 systemd
# ============================================================================
info "重新載入 systemd daemon..."
systemctl --user daemon-reload

success "systemd daemon 已重新載入"

# ============================================================================
# 9. 檢查容器鏡像
# ============================================================================
info "檢查容器鏡像..."

IMAGES=("localhost/api-user:latest" "localhost/api-order:latest" "localhost/api-product:latest" "localhost/bff:latest")
MISSING_IMAGES=()

for img in "${IMAGES[@]}"; do
    if ! podman image exists "$img"; then
        warning "  鏡像不存在: $img"
        MISSING_IMAGES+=("$img")
    else
        success "  鏡像存在: $img"
    fi
done

if [ ${#MISSING_IMAGES[@]} -gt 0 ]; then
    warning "發現缺少的鏡像"
    info "請先建置鏡像："
    echo ""
    echo "  cd dockerfiles/api-user && podman build -t localhost/api-user:latest ."
    echo "  cd dockerfiles/api-order && podman build -t localhost/api-order:latest ."
    echo "  cd dockerfiles/api-product && podman build -t localhost/api-product:latest ."
    echo "  cd dockerfiles/bff && podman build -t localhost/bff:latest ."
    echo ""
    warning "或使用 Nginx 替代（用於快速測試）："
    info "  修改 quadlet/*.container 中的 Image 為 nginx:alpine"
fi

# ============================================================================
# 10. 顯示後續步驟
# ============================================================================
echo ""
success "============================================"
success "初始化完成！"
success "============================================"
echo ""
info "後續步驟："
echo ""
echo "  1. 啟動服務："
echo "     ./scripts/start-all.sh"
echo ""
echo "  2. 檢查狀態："
echo "     ./scripts/status.sh"
echo ""
echo "  3. 測試連通性："
echo "     ./scripts/test-connectivity.sh"
echo ""
if [ "$MODE" == "dev" ]; then
    echo "  4. Debug 端口測試："
    echo "     curl http://localhost:8101/health"
    echo "     curl http://localhost:8102/health"
    echo "     curl http://localhost:8103/health"
    echo ""
fi
echo "  5. HTTPS 訪問："
echo "     curl -k https://localhost/"
echo ""

exit 0

#!/bin/bash
# ============================================================================
# Partner Secrets 管理腳本
# 用於管理生產環境的 Podman Secrets
# ============================================================================

set -e

source "$(dirname "$0")/lib.sh"

usage() {
    echo "Partner Secrets 管理工具"
    echo ""
    echo "用法: $0 <command> [partner-id]"
    echo ""
    echo "Commands:"
    echo "  list                  - 列出所有 Partner Secrets"
    echo "  create <partner-id>   - 創建新的 Partner Secret"
    echo "  rotate <partner-id>   - 輪換 Partner Secret（停用舊 Token）"
    echo "  delete <partner-id>   - 刪除 Partner Secret"
    echo "  show <partner-id>     - 查看 Secret 詳細資訊（不含值）"
    echo ""
    echo "Partner IDs:"
    echo "  a  - partner-company-a (完整權限)"
    echo "  b  - partner-company-b (訂單唯讀)"
    echo "  c  - partner-company-c (產品讀寫)"
    echo ""
    echo "範例:"
    echo "  $0 list              # 列出所有 Secrets"
    echo "  $0 create a          # 創建 Partner A 的 Secret"
    echo "  $0 rotate b          # 輪換 Partner B 的 Secret"
    exit 1
}

# 檢查參數
if [ $# -eq 0 ]; then
    usage
fi

COMMAND=$1
PARTNER_ID=$2

# ============================================================================
# 列出所有 Secrets
# ============================================================================
list_secrets() {
    info "Partner Secrets 列表"
    echo ""

    printf "%-25s %-10s %-30s\n" "Secret Name" "Status" "Created At"
    printf "%-25s %-10s %-30s\n" "-----------" "------" "----------"

    for partner in a b c; do
        secret_name="jwt-secret-partner-$partner"

        if podman secret exists $secret_name 2>/dev/null; then
            created=$(podman secret inspect $secret_name --format '{{.CreatedAt}}' 2>/dev/null || echo "N/A")
            printf "%-25s ${GREEN}%-10s${NC} %-30s\n" "$secret_name" "✓ EXISTS" "$created"
        else
            printf "%-25s ${RED}%-10s${NC} %-30s\n" "$secret_name" "✗ MISSING" "N/A"
        fi
    done
    echo ""

    # 顯示使用該 Secret 的容器
    info "使用 Secrets 的容器："
    if systemctl --user is-active --quiet ssl-proxy 2>/dev/null; then
        echo "  ssl-proxy: ${GREEN}RUNNING${NC}"
    else
        echo "  ssl-proxy: ${YELLOW}STOPPED${NC}"
    fi
}

# ============================================================================
# 創建 Secret
# ============================================================================
create_secret() {
    if [ -z "$PARTNER_ID" ]; then
        error "請指定 Partner ID (a, b, c)"
        usage
    fi

    secret_name="jwt-secret-partner-$PARTNER_ID"

    # 檢查是否已存在
    if podman secret exists $secret_name 2>/dev/null; then
        error "Secret 已存在: $secret_name"
        info "如需更換，請使用 rotate 命令"
        exit 1
    fi

    info "創建 Partner Secret: $secret_name"
    echo ""

    # 生成強隨機 Secret
    SECRET_VALUE=$(openssl rand -base64 32)

    # 創建 Podman Secret
    echo -n "$SECRET_VALUE" | podman secret create $secret_name -

    success "Secret 已創建: $secret_name"
    echo ""
    warning "請將以下 Secret 安全地提供給 Partner："
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Partner ID: partner-company-$PARTNER_ID"
    echo "JWT Secret: $SECRET_VALUE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    warning "此 Secret 不會再次顯示，請妥善保管或記錄"
    echo ""

    # 可選：保存到臨時文件
    read -p "是否保存到安全文件？(y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        SECRET_FILE="/opt/app/configs/ssl-proxy/partner-secret-${PARTNER_ID}-$(date +%Y%m%d).txt"
        echo "Partner ID: partner-company-$PARTNER_ID" > "$SECRET_FILE"
        echo "JWT Secret: $SECRET_VALUE" >> "$SECRET_FILE"
        chmod 600 "$SECRET_FILE"
        success "Secret 已保存到: $SECRET_FILE"
        warning "提供給 Partner 後，請刪除此文件"
    fi
}

# ============================================================================
# 輪換 Secret
# ============================================================================
rotate_secret() {
    if [ -z "$PARTNER_ID" ]; then
        error "請指定 Partner ID (a, b, c)"
        usage
    fi

    secret_name="jwt-secret-partner-$PARTNER_ID"

    # 檢查是否存在
    if ! podman secret exists $secret_name 2>/dev/null; then
        error "Secret 不存在: $secret_name"
        info "請使用 create 命令先創建"
        exit 1
    fi

    echo ""
    warning "輪換 Secret 的影響："
    echo "  - 使用舊 Secret 的所有 JWT Token 將立即失效"
    echo "  - ssl-proxy 服務需要重啟"
    echo "  - Partner 需要使用新 Secret 重新產生 Token"
    echo ""
    read -p "確定要輪換 Secret: $secret_name? (y/N) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "已取消"
        exit 0
    fi

    # 先生成新 Secret 值（確保 openssl 可用）
    info "生成新 Secret 值..."
    SECRET_VALUE=$(openssl rand -base64 32)
    if [ -z "$SECRET_VALUE" ]; then
        error "生成 Secret 失敗"
        exit 1
    fi

    # 停止 SSL Proxy
    info "停止 ssl-proxy 服務..."
    systemctl --user stop ssl-proxy 2>/dev/null || warning "ssl-proxy 未運行"

    # 刪除舊 Secret
    info "刪除舊 Secret..."
    if ! podman secret rm $secret_name 2>/dev/null; then
        error "刪除舊 Secret 失敗"
        # 嘗試重啟服務
        systemctl --user start ssl-proxy 2>/dev/null
        exit 1
    fi

    # 創建新 Secret（使用預先生成的值）
    info "創建新 Secret..."
    if ! echo -n "$SECRET_VALUE" | podman secret create $secret_name - 2>/dev/null; then
        error "創建新 Secret 失敗"
        warning "Secret 值已保存，請手動創建："
        echo ""
        echo "  echo -n \"$SECRET_VALUE\" | podman secret create $secret_name -"
        echo ""
        exit 1
    fi

    # 重新載入 systemd 並啟動服務
    info "重新啟動 ssl-proxy 服務..."
    systemctl --user daemon-reload

    if ! systemctl --user start ssl-proxy; then
        error "啟動服務失敗"
        info "請查看日誌: ./scripts/logs.sh ssl-proxy"
        exit 1
    fi

    if wait_for_service ssl-proxy 30; then
        success "Secret 已輪換，服務運行正常"
    else
        error "Secret 已輪換，但服務啟動失敗"
        info "請查看日誌: ./scripts/logs.sh ssl-proxy"
        exit 1
    fi

    echo ""
    warning "新 Secret 值（請提供給 Partner）："
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Partner ID: partner-company-$PARTNER_ID"
    echo "JWT Secret: $SECRET_VALUE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    warning "Partner 需要更新其應用程式以使用新 Secret"
}

# ============================================================================
# 刪除 Secret
# ============================================================================
delete_secret() {
    if [ -z "$PARTNER_ID" ]; then
        error "請指定 Partner ID (a, b, c)"
        usage
    fi

    secret_name="jwt-secret-partner-$PARTNER_ID"

    # 檢查是否存在
    if ! podman secret exists $secret_name 2>/dev/null; then
        error "Secret 不存在: $secret_name"
        exit 1
    fi

    echo ""
    warning "刪除 Secret 的影響："
    echo "  - 該 Partner 將無法訪問 API"
    echo "  - 所有該 Partner 的 Token 將失效"
    echo "  - ssl-proxy 服務需要重啟"
    echo ""
    read -p "確定要刪除 Secret: $secret_name? (y/N) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "已取消"
        exit 0
    fi

    # 停止 SSL Proxy
    info "停止 ssl-proxy 服務..."
    systemctl --user stop ssl-proxy 2>/dev/null || warning "ssl-proxy 未運行"

    # 刪除 Secret
    info "刪除 Secret..."
    if ! podman secret rm $secret_name 2>/dev/null; then
        error "刪除 Secret 失敗"
        systemctl --user start ssl-proxy 2>/dev/null
        exit 1
    fi

    # 重啟服務
    info "重新啟動 ssl-proxy 服務..."
    systemctl --user daemon-reload

    systemctl --user start ssl-proxy || { error "啟動服務失敗"; info "請查看日誌: ./scripts/logs.sh ssl-proxy"; exit 1; }

    if wait_for_service ssl-proxy 30; then
        success "Secret 已刪除: $secret_name"
        warning "Partner partner-company-$PARTNER_ID 無法再訪問 API"
    else
        warning "Secret 已刪除，但服務啟動異常"
        info "請查看日誌: ./scripts/logs.sh ssl-proxy"
    fi
}

# ============================================================================
# 查看 Secret 詳細資訊
# ============================================================================
show_secret() {
    if [ -z "$PARTNER_ID" ]; then
        error "請指定 Partner ID (a, b, c)"
        usage
    fi

    secret_name="jwt-secret-partner-$PARTNER_ID"

    # 檢查是否存在
    if ! podman secret exists $secret_name 2>/dev/null; then
        error "Secret 不存在: $secret_name"
        exit 1
    fi

    info "Secret 詳細資訊: $secret_name"
    echo ""

    podman secret inspect $secret_name --format "ID:         {{.ID}}
Name:       {{.Spec.Name}}
Created At: {{.CreatedAt}}
Updated At: {{.UpdatedAt}}"

    echo ""
    warning "注意：Podman Secrets 無法導出實際值（這是安全設計）"
    info "如需重新提供 Secret，請使用 rotate 命令"
}

# ============================================================================
# 執行命令
# ============================================================================
case $COMMAND in
    list)
        list_secrets
        ;;
    create)
        create_secret
        ;;
    rotate)
        rotate_secret
        ;;
    delete)
        delete_secret
        ;;
    show)
        show_secret
        ;;
    *)
        error "未知命令: $COMMAND"
        usage
        ;;
esac

exit 0

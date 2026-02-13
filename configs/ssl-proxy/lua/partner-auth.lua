-- /usr/local/openresty/nginx/lua/partner-auth.lua
-- ============================================================================
-- Partner JWT 驗證和權限檢查模組
-- ============================================================================

local _M = {}

-- 驗證 Partner JWT 並檢查權限
-- api: "orders", "products", "users"
-- action: "read", "write", "delete"
function _M.verify_and_check_permission(api, action)
    local auth_header = ngx.var.http_authorization

    -- 1. 檢查 Authorization Header
    if not auth_header then
        ngx.log(ngx.ERR, "Partner API (", api, "): Missing Authorization from ", ngx.var.remote_addr)
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error":"Unauthorized","message":"Missing Authorization header"}')
        return ngx.exit(ngx.HTTP_UNAUTHORIZED)
    end

    -- 2. 提取 Bearer Token
    local _, _, token = string.find(auth_header, "Bearer%s+(.+)")
    if not token then
        ngx.log(ngx.ERR, "Partner API (", api, "): Invalid format from ", ngx.var.remote_addr)
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error":"Unauthorized","message":"Invalid Authorization format"}')
        return ngx.exit(ngx.HTTP_UNAUTHORIZED)
    end

    -- 3. 先用任意 secret 解析 JWT 以獲取 Partner ID（sub claim）
    -- 這裡只是解析，不驗證簽章
    local jwt_obj = jwt:load_jwt(token)
    if not jwt_obj.payload or not jwt_obj.payload.sub then
        ngx.log(ngx.ERR, "Partner API (", api, "): Invalid JWT structure")
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error":"Unauthorized","message":"Invalid token structure"}')
        return ngx.exit(ngx.HTTP_UNAUTHORIZED)
    end

    local partner_id = jwt_obj.payload.sub

    -- 4. 獲取該 Partner 專屬的 Secret
    local partner_secret = partners.get_secret(partner_id)
    if not partner_secret then
        ngx.log(ngx.ERR, "Partner API (", api, "): Unknown partner: ", partner_id)
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error":"Unauthorized","message":"Unknown partner"}')
        return ngx.exit(ngx.HTTP_UNAUTHORIZED)
    end

    -- 5. 使用 Partner 專屬 Secret 驗證 JWT
    jwt_obj = jwt:verify(partner_secret, token)
    if not jwt_obj.verified then
        ngx.log(ngx.ERR, "Partner API (", api, "): JWT verification failed for ", partner_id, " - ", jwt_obj.reason)
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error":"Unauthorized","message":"Invalid or expired token"}')
        return ngx.exit(ngx.HTTP_UNAUTHORIZED)
    end

    -- 6. 檢查 API 訪問權限
    if not partners.has_permission(partner_id, api, action) then
        local partner_name = partners.get_name(partner_id)
        ngx.log(ngx.WARN, "Partner API (", api, "): Access denied for ", partner_id, " (", partner_name, ") - missing ", action, " permission")
        ngx.status = ngx.HTTP_FORBIDDEN
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error":"Forbidden","message":"Insufficient permissions for this API"}')
        return ngx.exit(ngx.HTTP_FORBIDDEN)
    end

    -- 7. 設定變數和 Headers
    ngx.var.jwt_user_id = partner_id
    ngx.var.jwt_client_type = "partner"

    local partner_name = partners.get_name(partner_id)
    ngx.req.set_header("X-Partner-ID", partner_id)
    ngx.req.set_header("X-Partner-Name", partner_name)

    ngx.log(ngx.INFO, "Partner API (", api, "): Authenticated ", partner_id, " (", partner_name, ") with ", action, " permission")
end

return _M

-- /usr/local/openresty/nginx/lua/partner-auth.lua
-- ============================================================================
-- Partner JWT 驗證和權限檢查模組
-- 支援 Endpoint 層級的精細權限控制（API + 路徑 + HTTP 方法）
-- ============================================================================

-- 依賴模組（由 nginx.conf 的 init_by_lua_block 初始化）
-- 這些變數必須在 nginx.conf 中設定為全域變數
local jwt = jwt or require "resty.jwt"
local partners = partners or require "partners-loader"

local _M = {}

-- 驗證 JWT Token 並返回 Partner ID
-- 返回: partner_id (string) or nil
local function verify_jwt_token()
    local auth_header = ngx.var.http_authorization

    -- 1. 檢查 Authorization Header
    if not auth_header then
        ngx.log(ngx.ERR, "Missing Authorization header from ", ngx.var.remote_addr)
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error":"Unauthorized","message":"Missing Authorization header"}')
        ngx.exit(ngx.HTTP_UNAUTHORIZED)
        return nil
    end

    -- 2. 提取 Bearer Token
    local _, _, token = string.find(auth_header, "Bearer%s+(.+)")
    if not token then
        ngx.log(ngx.ERR, "Invalid Authorization format from ", ngx.var.remote_addr)
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error":"Unauthorized","message":"Invalid Authorization format"}')
        ngx.exit(ngx.HTTP_UNAUTHORIZED)
        return nil
    end

    -- 3. 先用任意 secret 解析 JWT 以獲取 Partner ID（sub claim）
    local jwt_obj = jwt:load_jwt(token)
    if not jwt_obj.payload or not jwt_obj.payload.sub then
        ngx.log(ngx.ERR, "Invalid JWT structure")
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error":"Unauthorized","message":"Invalid token structure"}')
        ngx.exit(ngx.HTTP_UNAUTHORIZED)
        return nil
    end

    local partner_id = jwt_obj.payload.sub

    -- 4. 獲取該 Partner 專屬的 Secret
    local partner_secret = partners.get_secret(partner_id)
    if not partner_secret then
        ngx.log(ngx.ERR, "Unknown partner: ", partner_id)
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error":"Unauthorized","message":"Unknown partner"}')
        ngx.exit(ngx.HTTP_UNAUTHORIZED)
        return nil
    end

    -- 5. 使用 Partner 專屬 Secret 驗證 JWT
    jwt_obj = jwt:verify(partner_secret, token)
    if not jwt_obj.verified then
        ngx.log(ngx.ERR, "JWT verification failed for ", partner_id, " - ", jwt_obj.reason)
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error":"Unauthorized","message":"Invalid or expired token"}')
        ngx.exit(ngx.HTTP_UNAUTHORIZED)
        return nil
    end

    return partner_id
end

-- ============================================================================
-- Endpoint 層級權限驗證（推薦使用）
-- ============================================================================
-- 驗證 Partner JWT 並檢查 Endpoint 權限
-- api: "orders", "products", "users"
-- path: 實際請求路徑，例如 "/list", "/123", "/detail/abc"
-- 如果不提供 path，會自動從 ngx.var.request_uri 提取
function _M.verify_and_check_endpoint(api, path)
    -- 1. 驗證 JWT Token
    local partner_id = verify_jwt_token()
    if not partner_id then
        return  -- verify_jwt_token 已經處理錯誤回應
    end

    -- 2. 提取實際請求路徑（如果未提供）
    if not path then
        -- 從完整 URI 中提取路徑部分
        -- 例如：/partner/api/order/list?id=123 -> /list
        local full_uri = ngx.var.request_uri

        -- 構建 API 前綴（將 orders -> order, products -> product, users -> user）
        local api_singular = string.gsub(api, "s$", "")
        local api_prefix = "/partner/api/" .. api_singular .. "/"

        -- 移除查詢字串
        local uri_without_query = string.gsub(full_uri, "%?.*$", "")

        -- 使用字串比對而非 pattern matching（避免特殊字元問題）
        if string.sub(uri_without_query, 1, #api_prefix) == api_prefix then
            -- 提取 API 前綴之後的路徑
            path = "/" .. string.sub(uri_without_query, #api_prefix + 1)

            -- 處理空路徑的情況
            if path == "/" or path == "//" then
                path = "/"
            end
        else
            -- 如果前綴不匹配，使用整個路徑（不應該發生，但作為後備）
            path = uri_without_query
        end
    end

    -- 3. 獲取 HTTP 方法
    local method = ngx.req.get_method()

    -- 4. 檢查 Endpoint 權限（API + 路徑 + HTTP 方法）
    if not partners.has_endpoint_permission(partner_id, api, path, method) then
        local partner_name = partners.get_name(partner_id)
        ngx.log(ngx.WARN, "Partner (", partner_id, ") access denied: ", method, " ", api, path)
        ngx.status = ngx.HTTP_FORBIDDEN
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error":"Forbidden","message":"Insufficient permissions for this endpoint"}')
        ngx.exit(ngx.HTTP_FORBIDDEN)
        return
    end

    -- 5. 設定變數和 Headers
    ngx.var.jwt_user_id = partner_id
    ngx.var.jwt_client_type = "partner"

    local partner_name = partners.get_name(partner_id)
    ngx.req.set_header("X-Partner-ID", partner_id)
    ngx.req.set_header("X-Partner-Name", partner_name)

    ngx.log(ngx.INFO, "Partner (", partner_id, ") authenticated: ", method, " ", api, path)
end

-- ============================================================================
-- API 層級權限驗證（向後兼容，建議遷移到 verify_and_check_endpoint）
-- ============================================================================
-- 驗證 Partner JWT 並檢查 API 層級權限
-- api: "orders", "products", "users"
-- action: "read", "write", "delete"
function _M.verify_and_check_permission(api, action)
    ngx.log(ngx.WARN, "verify_and_check_permission() is deprecated, use verify_and_check_endpoint() for fine-grained control")

    -- 1. 驗證 JWT Token
    local partner_id = verify_jwt_token()
    if not partner_id then
        return  -- verify_jwt_token 已經處理錯誤回應
    end

    -- 2. 檢查 API 層級權限（向後兼容）
    if not partners.has_permission(partner_id, api, action) then
        local partner_name = partners.get_name(partner_id)
        ngx.log(ngx.WARN, "Partner API (", api, "): Access denied for ", partner_id, " (", partner_name, ") - missing ", action, " permission")
        ngx.status = ngx.HTTP_FORBIDDEN
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error":"Forbidden","message":"Insufficient permissions for this API"}')
        ngx.exit(ngx.HTTP_FORBIDDEN)
        return
    end

    -- 3. 設定變數和 Headers
    ngx.var.jwt_user_id = partner_id
    ngx.var.jwt_client_type = "partner"

    local partner_name = partners.get_name(partner_id)
    ngx.req.set_header("X-Partner-ID", partner_id)
    ngx.req.set_header("X-Partner-Name", partner_name)

    ngx.log(ngx.INFO, "Partner API (", api, "): Authenticated ", partner_id, " (", partner_name, ") with ", action, " permission")
end

return _M

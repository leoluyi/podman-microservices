-- /usr/local/openresty/nginx/conf.d/partners-loader.lua
-- ============================================================================
-- Partner 配置載入模組
-- 用於載入和快取 Partner Secrets 及權限配置
-- 支援 Endpoint 層級的精細權限控制（API + 路徑 + HTTP 方法）
-- ============================================================================

local cjson = require "cjson"
local _M = {}

-- Partner 配置（從環境變數載入）
-- 權限結構：
-- permissions = {
--     api_name = {
--         endpoints = {
--             { pattern = "/exact/path", methods = {"GET", "POST"} },
--             { pattern = "^/users/%d+$", methods = {"GET"}, regex = true },
--             { pattern = "/orders/", methods = {"GET"}, prefix = true }
--         }
--     }
-- }
_M.partners = {
    ["partner-company-a"] = {
        secret = os.getenv("JWT_SECRET_PARTNER_A") or "dev-secret-partner-a-for-testing-only-32chars",
        name = "Company A Corp",
        -- 完整權限範例
        permissions = {
            orders = {
                endpoints = {
                    -- 完全匹配：只允許這個路徑
                    { pattern = "/", methods = {"GET"} },
                    { pattern = "/list", methods = {"GET"} },
                    { pattern = "/search", methods = {"GET", "POST"} },
                    { pattern = "/create", methods = {"POST"} },
                    -- 前綴匹配：允許 /detail/* 下的所有路徑
                    { pattern = "/detail/", methods = {"GET"}, prefix = true },
                    -- 正則匹配：允許 /123, /456 等數字 ID
                    { pattern = "^/%d+$", methods = {"GET", "PUT", "PATCH"}, regex = true },
                    { pattern = "^/%d+/cancel$", methods = {"POST"}, regex = true },
                    { pattern = "^/%d+/items$", methods = {"GET"}, regex = true }
                }
            },
            products = {
                endpoints = {
                    { pattern = "/", methods = {"GET"} },
                    { pattern = "/list", methods = {"GET"} },
                    { pattern = "/search", methods = {"GET", "POST"} },
                    { pattern = "/create", methods = {"POST"} },
                    { pattern = "/detail/", methods = {"GET"}, prefix = true },
                    { pattern = "^/%d+$", methods = {"GET", "PUT", "PATCH", "DELETE"}, regex = true }
                }
            },
            users = {
                endpoints = {
                    { pattern = "/", methods = {"GET"} },
                    { pattern = "/list", methods = {"GET"} },
                    { pattern = "^/%d+$", methods = {"GET"}, regex = true }
                }
            }
        }
    },
    ["partner-company-b"] = {
        secret = os.getenv("JWT_SECRET_PARTNER_B") or "dev-secret-partner-b-for-testing-only-32chars",
        name = "Company B Ltd",
        -- 僅訂單唯讀
        permissions = {
            orders = {
                endpoints = {
                    { pattern = "/", methods = {"GET"} },
                    { pattern = "/list", methods = {"GET"} },
                    { pattern = "/search", methods = {"GET"} },
                    { pattern = "^/%d+$", methods = {"GET"}, regex = true }
                    -- 注意：沒有 POST/PUT/DELETE 方法，完全唯讀
                }
            }
        }
    },
    ["partner-company-c"] = {
        secret = os.getenv("JWT_SECRET_PARTNER_C") or "dev-secret-partner-c-for-testing-only-32chars",
        name = "Company C Inc",
        -- 產品讀寫，但不能刪除
        permissions = {
            products = {
                endpoints = {
                    { pattern = "/", methods = {"GET"} },
                    { pattern = "/list", methods = {"GET"} },
                    { pattern = "/search", methods = {"GET", "POST"} },
                    { pattern = "/create", methods = {"POST"} },
                    { pattern = "/detail/", methods = {"GET"}, prefix = true },
                    { pattern = "^/%d+$", methods = {"GET", "PUT", "PATCH"}, regex = true }
                    -- 注意：沒有 DELETE 方法
                }
            }
        }
    }
}

-- 獲取 Partner Secret
function _M.get_secret(partner_id)
    local partner = _M.partners[partner_id]
    if not partner then
        return nil
    end
    return partner.secret
end

-- 獲取 Partner 名稱
function _M.get_name(partner_id)
    local partner = _M.partners[partner_id]
    if not partner then
        return "Unknown"
    end
    return partner.name
end

-- 檢查路徑是否匹配模式
-- path: "/list", "/123", "/detail/abc"
-- pattern: "/list", "/detail/", "^/%d+$"
-- prefix: true/false (是否為前綴匹配)
-- regex: true/false (是否為正則匹配)
local function match_pattern(path, pattern, prefix, regex)
    if regex then
        -- 正則匹配
        return ngx.re.match(path, pattern) ~= nil
    elseif prefix then
        -- 前綴匹配
        return string.sub(path, 1, string.len(pattern)) == pattern
    else
        -- 完全匹配（預設）
        return path == pattern
    end
end

-- 檢查 Endpoint 權限
-- partner_id: "partner-company-a"
-- api: "orders", "products", "users"
-- path: "/list", "/123", "/detail/abc"
-- method: "GET", "POST", "PUT", "PATCH", "DELETE"
function _M.has_endpoint_permission(partner_id, api, path, method)
    local partner = _M.partners[partner_id]
    if not partner then
        ngx.log(ngx.WARN, "Partner not found: ", partner_id)
        return false
    end

    local api_perms = partner.permissions[api]
    if not api_perms or not api_perms.endpoints then
        ngx.log(ngx.WARN, "No permissions for API: ", api, " partner: ", partner_id)
        return false
    end

    -- 遍歷所有 endpoint 規則
    for _, endpoint in ipairs(api_perms.endpoints) do
        local match = match_pattern(path, endpoint.pattern, endpoint.prefix, endpoint.regex)

        -- 如果路徑匹配，檢查 HTTP 方法
        if match then
            for _, allowed_method in ipairs(endpoint.methods) do
                if allowed_method == method then
                    ngx.log(ngx.INFO, "Permission granted: ", partner_id, " -> ", api, path, " [", method, "]")
                    return true
                end
            end
            -- 路徑匹配但方法不允許
            ngx.log(ngx.WARN, "Method not allowed: ", partner_id, " -> ", api, path, " [", method, "]")
            return false
        end
    end

    -- 沒有匹配的規則
    ngx.log(ngx.WARN, "No matching endpoint rule: ", partner_id, " -> ", api, path, " [", method, "]")
    return false
end

-- 向後兼容：檢查 API 層級權限（已棄用，建議使用 has_endpoint_permission）
-- api: "orders", "products", "users"
-- action: "read", "write", "delete"
function _M.has_permission(partner_id, api, action)
    ngx.log(ngx.WARN, "has_permission() is deprecated, use has_endpoint_permission() instead")

    local partner = _M.partners[partner_id]
    if not partner then
        return false
    end

    local api_perms = partner.permissions[api]
    if not api_perms then
        return false
    end

    -- 如果使用新的 endpoint 結構，無法用舊方法判斷
    if api_perms.endpoints then
        ngx.log(ngx.ERR, "Cannot use has_permission() with endpoint-level permissions")
        return false
    end

    -- 舊結構支援
    for _, perm in ipairs(api_perms) do
        if perm == action then
            return true
        end
    end

    return false
end

-- 獲取所有權限（用於日誌和調試）
function _M.get_permissions(partner_id)
    local partner = _M.partners[partner_id]
    if not partner then
        return {}
    end
    return partner.permissions
end

-- 列出 Partner 的所有可訪問路徑（調試用）
function _M.list_allowed_endpoints(partner_id)
    local partner = _M.partners[partner_id]
    if not partner then
        return {}
    end

    local result = {}
    for api, api_perms in pairs(partner.permissions) do
        if api_perms.endpoints then
            result[api] = {}
            for _, endpoint in ipairs(api_perms.endpoints) do
                table.insert(result[api], {
                    pattern = endpoint.pattern,
                    methods = endpoint.methods,
                    type = endpoint.regex and "regex" or (endpoint.prefix and "prefix" or "exact")
                })
            end
        end
    end
    return result
end

return _M

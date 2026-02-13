-- /usr/local/openresty/nginx/conf.d/partners-loader.lua
-- ============================================================================
-- Partner 配置載入模組
-- 用於載入和快取 Partner Secrets 及權限配置
-- ============================================================================

local cjson = require "cjson"
local _M = {}

-- Partner 配置（從環境變數載入）
_M.partners = {
    ["partner-company-a"] = {
        secret = os.getenv("JWT_SECRET_PARTNER_A") or "dev-secret-partner-a-change-in-production-32chars",
        name = "Company A Corp",
        permissions = {
            orders = { "read", "write" },
            products = { "read", "write" },
            users = { "read" }
        }
    },
    ["partner-company-b"] = {
        secret = os.getenv("JWT_SECRET_PARTNER_B") or "dev-secret-partner-b-change-in-production-32chars",
        name = "Company B Ltd",
        permissions = {
            orders = { "read" }
        }
    },
    ["partner-company-c"] = {
        secret = os.getenv("JWT_SECRET_PARTNER_C") or "dev-secret-partner-c-change-in-production-32chars",
        name = "Company C Inc",
        permissions = {
            products = { "read", "write" }
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

-- 檢查權限
-- api: "orders", "products", "users"
-- action: "read", "write", "delete"
function _M.has_permission(partner_id, api, action)
    local partner = _M.partners[partner_id]
    if not partner then
        return false
    end

    local api_perms = partner.permissions[api]
    if not api_perms then
        return false
    end

    -- 檢查是否有該操作權限
    for _, perm in ipairs(api_perms) do
        if perm == action then
            return true
        end
    end

    return false
end

-- 獲取所有權限（用於日誌）
function _M.get_permissions(partner_id)
    local partner = _M.partners[partner_id]
    if not partner then
        return {}
    end
    return partner.permissions
end

return _M

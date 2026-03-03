-- partners-loader.lua
-- Loads partner configuration from an external JSON file.
-- File path is controlled by PARTNERS_CONFIG_FILE env var
-- (default: /etc/nginx/conf.d/partners.json).

local cjson = require "cjson"
local _M = {}

local CONFIG_FILE = os.getenv("PARTNERS_CONFIG_FILE") or "/etc/nginx/conf.d/partners.json"

-- ============================================================================
-- Security: reject known dev secrets in production
-- ============================================================================
local DEV_SECRETS = {
    ["dev-secret-partner-a-for-testing-only-32chars"] = true,
    ["dev-secret-partner-b-for-testing-only-32chars"] = true,
    ["dev-secret-partner-c-for-testing-only-32chars"] = true,
    ["dev-secret-partner-a-fallback-32chars"] = true,
    ["dev-secret-partner-b-fallback-32chars"] = true,
    ["dev-secret-partner-c-fallback-32chars"] = true,
}

local function is_production()
    local env = os.getenv("ENVIRONMENT") or os.getenv("ENV")
    if not env then
        ngx.log(ngx.WARN, "ENVIRONMENT variable not set, defaulting to development mode")
        return false
    end
    return env == "production" or env == "prod"
end

local function validate_secret_security(partner_id, secret)
    if is_production() and DEV_SECRETS[secret] then
        ngx.log(ngx.EMERG,
            "SECURITY CRITICAL: Partner ", partner_id, " is using a development secret in production! ",
            "This allows anyone to forge JWT tokens. ",
            "Please create a production secret using: ./scripts/manage-partner-secrets.sh create")
        error("CRITICAL SECURITY VIOLATION: Development secrets are not allowed in production")
    elseif DEV_SECRETS[secret] then
        ngx.log(ngx.WARN, "Partner ", partner_id, " is using a development secret (OK for dev/test only)")
    end
end

-- ============================================================================
-- Config loading
-- ============================================================================
local function load_config()
    local f, err = io.open(CONFIG_FILE, "r")
    if not f then
        ngx.log(ngx.EMERG, "Cannot open partners config: ", CONFIG_FILE, " (", err, ")")
        error("Failed to load partners config: " .. tostring(err))
    end
    local content = f:read("*a")
    f:close()

    local ok, decoded = pcall(cjson.decode, content)
    if not ok then
        ngx.log(ngx.EMERG, "Invalid partners config JSON: ", decoded)
        error("Invalid partners config JSON: " .. tostring(decoded))
    end

    if not decoded.partners then
        error("partners config missing top-level 'partners' key in: " .. CONFIG_FILE)
    end

    return decoded.partners
end

local function build_partners(raw)
    local resolved = {}
    for partner_id, cfg in pairs(raw) do
        local secret
        if cfg.secret_env then
            secret = os.getenv(cfg.secret_env)
            if not secret or secret == "" then
                ngx.log(ngx.WARN,
                    "Env var ", cfg.secret_env, " not set for partner ", partner_id, ", using fallback")
                secret = "dev-secret-" .. partner_id .. "-fallback"
            end
        else
            ngx.log(ngx.WARN, "No secret_env defined for partner ", partner_id)
            secret = ""
        end
        validate_secret_security(partner_id, secret)
        resolved[partner_id] = {
            secret      = secret,
            name        = cfg.name or partner_id,
            permissions = cfg.permissions or {},
        }
    end
    return resolved
end

_M.partners = build_partners(load_config())

-- ============================================================================
-- Public API
-- ============================================================================
function _M.get_secret(partner_id)
    local partner = _M.partners[partner_id]
    if not partner then return nil end
    return partner.secret
end

function _M.get_name(partner_id)
    local partner = _M.partners[partner_id]
    if not partner then return "Unknown" end
    return partner.name
end

-- path matching helpers
local function match_pattern(path, pattern, prefix, regex)
    if regex then
        return ngx.re.match(path, pattern) ~= nil
    elseif prefix then
        return string.sub(path, 1, string.len(pattern)) == pattern
    else
        return path == pattern
    end
end

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

    for _, endpoint in ipairs(api_perms.endpoints) do
        local match = match_pattern(path, endpoint.pattern, endpoint.prefix, endpoint.regex)
        if match then
            for _, allowed_method in ipairs(endpoint.methods) do
                if allowed_method == method then
                    ngx.log(ngx.INFO, "Permission granted: ", partner_id, " -> ", api, path, " [", method, "]")
                    return true
                end
            end
            ngx.log(ngx.WARN, "Method not allowed: ", partner_id, " -> ", api, path, " [", method, "]")
            return false
        end
    end

    ngx.log(ngx.WARN, "No matching endpoint rule: ", partner_id, " -> ", api, path, " [", method, "]")
    return false
end

function _M.get_permissions(partner_id)
    local partner = _M.partners[partner_id]
    if not partner then return {} end
    return partner.permissions
end

function _M.list_allowed_endpoints(partner_id)
    local partner = _M.partners[partner_id]
    if not partner then return {} end
    local result = {}
    for api, api_perms in pairs(partner.permissions) do
        if api_perms.endpoints then
            result[api] = {}
            for _, endpoint in ipairs(api_perms.endpoints) do
                table.insert(result[api], {
                    pattern = endpoint.pattern,
                    methods = endpoint.methods,
                    type    = endpoint.regex and "regex" or (endpoint.prefix and "prefix" or "exact"),
                })
            end
        end
    end
    return result
end

return _M

local unpack = table.unpack or unpack

local registry = {} ---@type table<string, table>
local current_namespace
local fallback_namespace

---@class Say
---@field protected _COPYRIGHT string
---@field protected _DESCRIPTION string
---@field protected _VERSION string
local s = {
  _COPYRIGHT = "Copyright (c) 2012 Olivine Labs, LLC.",
  _DESCRIPTION = "A simple string key/value store for i18n or any other case where you want namespaced strings.",
  _VERSION = "Say 1.2",
}

---@param namespace string
function s:set_namespace(namespace)
  current_namespace = namespace
  if not registry[current_namespace] then
    registry[current_namespace] = {}
  end
end

---@param namespace string
function s:set_fallback(namespace)
  fallback_namespace = namespace
  if not registry[fallback_namespace] then
    registry[fallback_namespace] = {}
  end
end

---@param key string
---@param value any
function s:set(key, value)
  registry[current_namespace][key] = value
end

s:set_fallback("en")
s:set_namespace("en")

s._registry = registry

local M = setmetatable(s, { ---@type Say|fun(key: string|integer, args: any[]): str: string|nil|?
  __index = function(_, key)
    return registry[key]
  end,
  __call = function(_, key, vars)
    local str = registry[current_namespace][key] or registry[fallback_namespace][key]
    if str then
      str = tostring(str)
      local strings = {} ---@type string[]
      for _, v in ipairs(vars or {}) do
        table.insert(strings, tostring(v))
      end
      return #strings > 0 and str:format(unpack(strings)) or str
    end
  end,
}) --[[@as Say]]

return M

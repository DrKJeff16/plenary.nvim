-- Lazy load everything into plenary.
---@class plenary
---@field busted plenary.Busted
---@field context_manager plenary.ContextManager
---@field debug_utils plenary.DebugUtils
---@field enum plenary.Enum
---@field errors plenary.Errors
---@field filetype plenary.Filetype
---@field fun plenary.Fun
---@field functional plenary.Functional
---@field path plenary.Path
return setmetatable({}, {
  ---@param t plenary
  ---@param k string|integer
  __index = function(t, k)
    local ok, val = pcall(require, ("plenary.%s"):format(k))
    if ok and val then
      rawset(t, k, val)
    end
    return val
  end,
})

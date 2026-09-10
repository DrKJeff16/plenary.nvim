-- Lazy load everything into plenary.

---@class plenary
---@field bit plenary.Bit
---@field busted plenary.Busted
---@field class Object
---@field compat plenary.Compat
---@field context_manager plenary.ContextManager
---@field curl plenary.Curl
---@field debug_utils plenary.DebugUtils
---@field enum plenary.Enum
---@field errors plenary.Errors
---@field filetype plenary.Filetype
---@field fun plenary.Fun
---@field functional plenary.Functional
---@field iterators plenary.Iterators
---@field job Job
---@field json plenary.Json
---@field log plenary.Log
---@field nvim_meta plenary.NvimMeta
---@field operators plenary.Operators
---@field path plenary.Path
---@field profile plenary.Profile
---@field reload plenary.Reload
---@field run plenary.Run
---@field scandir plenary.Scandir
---@field strings plenary.Strings
---@field tbl plenary.Tbl
---@field test_harness plenary.TestHarness
local M = setmetatable({}, {
  ---@param self plenary
  ---@param k string|integer
  __index = function(self, k)
    if pcall(require, "plenary." .. k) then
      rawset(self, k, require("plenary." .. k))
      return require("plenary." .. k)
    end
    return rawget(self, k)
  end,
})

return M

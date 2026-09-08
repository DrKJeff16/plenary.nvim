---@class plenary.NvimMeta
local M = {}

-- Is run in `--headless` mode.
M.is_headless = #vim.api.nvim_list_uis() == 0
M.lua_jit = (function()
  if jit then
    return {
      lua = _VERSION:gsub("Lua ", ""),
      jit = not not jit.version:find("LuaJIT"),
      version = jit.version:gsub("LuaJIT ", ""),
    }
  end

  error("NEOROCKS: Unsupported Lua Versions", _VERSION)
end)()

return M

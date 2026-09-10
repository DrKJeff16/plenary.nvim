---@class plenary.NvimMeta
local M = {}

-- Is run in `--headless` mode.
M.is_headless = #vim.api.nvim_list_uis() == 0

if not jit then
  error("NEOROCKS: Unsupported Lua Versions: " .. _VERSION)
end

---@class plenary.NvimMeta.LuaJIT
M.lua_jit = {}

M.lua_jit.lua = _VERSION:gsub("Lua ", "")
M.lua_jit.jit = not not jit.version:find("LuaJIT")
M.lua_jit.version = jit.version:gsub("LuaJIT ", "")

return M

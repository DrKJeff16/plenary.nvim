---@class plenary.Errors
local M = {}

---@param s string
---@param level vim.log.levels
function M.traceback_error(s, level)
  error(debug.traceback() .. "\n" .. s, (level or 1) + 1)
end

---@param s string
---@param func_info function
---@param level vim.log.levels
function M.info_error(s, func_info, level)
  error(debug.getinfo(func_info) .. "\n" .. s, (level or 1) + 1)
end

return M

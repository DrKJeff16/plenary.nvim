---@class plenary.DebugUtils
local M = {}

---@return string filepath
function M.sourced_filepath()
  return debug.getinfo(2, "S").source:sub(2)
end

---@return string sourced
function M.sourced_filename()
  local str = M.sourced_filepath()
  return str:match("^.*/(.*).lua$") or str
end

return M

---@class plenary.Compat
local M = {}

---@param t table
---@return table flattened_tbl
function M.flatten(t)
  return vim.fn.has("nvim-0.11") == 1 and vim.iter(t):flatten():totable() or vim.tbl_flatten(t) ---@diagnostic disable-line:deprecated
end

M.islist = vim.islist or vim.tbl_islist

return M

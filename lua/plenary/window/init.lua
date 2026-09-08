---@class plenary.Window
local M = {}

---@param win_id integer
---@param force? boolean
function M.try_close(win_id, force)
  if force == nil then
    force = true
  end

  pcall(vim.api.nvim_win_close, win_id, force)
end

---@param parent_win_id integer
---@param child_win_id integer
function M.close_related_win(parent_win_id, child_win_id)
  M.try_close(parent_win_id, true)
  M.try_close(child_win_id, true)
end

return M

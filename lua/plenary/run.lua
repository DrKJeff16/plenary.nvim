---@class plenary.Run
local M = {}

---@param title_text string
---@param cmd string
---@return integer bufnr
---@return integer win_id
function M.with_displayed_output(title_text, cmd, _)
  local views = require("plenary.window.float").centered_with_top_win(title_text)
  local job_id = vim.fn.jobstart(cmd, { term = true })
  local count = 0
  while count < 10 and not vim.wait(1000, function()
    return vim.fn.jobwait({ job_id }, 0)[1] == -1
  end) do
    vim.cmd.normal({ args = { "G" }, bang = true })
    count = count + 1
  end

  vim.fn.win_gotoid(views.win_id)
  vim.cmd.startinsert()

  return views.bufnr, views.win_id
end

return M

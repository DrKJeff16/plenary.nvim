local Border = require("plenary.window.border")
local tbl = require("plenary.tbl")

_AssociatedBufs = {} ---@type table<integer, { [1]: integer, [2]: integer, [3]: integer, [4]: integer }>

---@param win integer
---@param option string
---@param value any
local function win_optset(win, option, value)
  if vim.fn.has("nvim-0.10") == 1 then
    vim.api.nvim_set_option_value(option, value, { win = win })
  else
    vim.api.nvim_win_set_option(win, option, value) ---@diagnostic disable-line:deprecated
  end
end

---@class plenary.Window.Float
---@field default_options table<string, any>
local win_float = {}

---@param bufnr integer
local function clear_buf_on_leave(bufnr)
  vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave", "BufDelete" }, {
    buffer = bufnr,
    once = true,
    nested = true,
    callback = function(ev)
      win_float.clear(ev.buf)
    end,
  })
end

win_float.default_options = { percentage = 0.9, winblend = 15 }

---@param options table<string, any>
---@return vim.api.keyset.win_config opts
function win_float.default_opts(options)
  options = tbl.apply_defaults(options, win_float.default_options)

  local width = math.floor(vim.o.columns * options.percentage)
  local height = math.floor(vim.o.lines * options.percentage)
  local top = math.floor(((vim.o.lines - height) / 2) - 1)
  local left = math.floor((vim.o.columns - width) / 2)
  return { col = left, height = height, relative = "editor", row = top, style = "minimal", width = width }
end

---@param options table<string, any>
---@return { bufnr: integer, win_id: integer } res
function win_float.centered(options)
  options = tbl.apply_defaults(options, win_float.default_options)

  local bufnr = options.bufnr or vim.api.nvim_create_buf(false, true)
  local win_id = vim.api.nvim_open_win(bufnr, true, win_float.default_opts(options))

  -- vim.cmd("setlocal nocursorcolumn")
  win_optset(win_id, "cursorcolumn", false)
  win_optset(win_id, "winblend", options.winblend)

  vim.api.nvim_exec_autocmds("WinLeave", { buffer = bufnr })
  vim.cmd.bdelete({ args = { tostring(bufnr) }, bang = true, mods = { silent = true } })
  -- vim.cmd(string.format("autocmd WinLeave <buffer> silent! execute 'bdelete! %s'", bufnr))

  return { bufnr = bufnr, win_id = win_id }
end

---@param top_text string[]
---@param options table<string, any>
function win_float.centered_with_top_win(top_text, options)
  options = tbl.apply_defaults(options, win_float.default_options)

  table.insert(top_text, 1, ("="):rep(80))
  table.insert(top_text, ("="):rep(80))

  local primary_win_opts = win_float.default_opts(options)
  local minor_win_opts = vim.deepcopy(primary_win_opts)

  primary_win_opts.height = primary_win_opts.height - #top_text - 1
  primary_win_opts.row = primary_win_opts.row + #top_text + 1

  minor_win_opts.height = #top_text

  local minor_bufnr = vim.api.nvim_create_buf(false, true)
  local minor_win_id = vim.api.nvim_open_win(minor_bufnr, true, minor_win_opts)

  -- vim.cmd("setlocal nocursorcolumn")
  win_optset(minor_win_id, "cursorcolumn", false)
  win_optset(minor_win_id, "winblend", options.winblend)

  vim.api.nvim_buf_set_lines(minor_bufnr, 0, -1, false, top_text)

  local primary_bufnr = vim.api.nvim_create_buf(false, true)
  local primary_win_id = vim.api.nvim_open_win(primary_bufnr, true, primary_win_opts)

  -- vim.cmd("setlocal nocursorcolumn")
  win_optset(primary_win_id, "cursorcolumn", false)
  win_optset(primary_win_id, "winblend", options.winblend)

  -- vim.cmd(
  --   string.format(
  --     "autocmd WinLeave,BufDelete,BufLeave <buffer=%s> ++once ++nested silent! execute 'bdelete! %s'",
  --     primary_buf,
  --     minor_buf
  --   )
  -- )

  -- vim.cmd(
  --   string.format(
  --     "autocmd WinLeave,BufDelete,BufLeave <buffer> ++once ++nested silent! execute 'bdelete! %s'",
  --     primary_buf
  --   )
  -- )

  local primary_border = Border:new(primary_bufnr, primary_win_id, primary_win_opts, {})
  local minor_border = Border:new(minor_bufnr, minor_win_id, minor_win_opts, {})

  _AssociatedBufs[primary_bufnr] = {
    primary_win_id,
    minor_win_id,
    primary_border.win_id,
    minor_border.win_id,
  }

  clear_buf_on_leave(primary_bufnr)

  return {
    bufnr = primary_bufnr,
    win_id = primary_win_id,

    minor_bufnr = minor_bufnr,
    minor_win_id = minor_win_id,
  }
end

--- Create window that takes up certain percentags of the current screen.
---
--- Works regardless of current buffers, tabs, splits, etc.
--@param col_range number | Table:
--                  If number, then center the window taking up this percentage of the screen.
--                  If table, first index should be start, second_index should be end
--@param row_range number | Table:
--                  If number, then center the window taking up this percentage of the screen.
--                  If table, first index should be start, second_index should be end
--@param win_opts Table
--@param border_opts Table
---@param col_range integer[]|integer
---@param row_range integer[]|integer
---@param win_opts vim.api.keyset.win_config
---@param border_opts? table<string, any>
---@return { border_bufnr: integer, border_win_id: integer, bufnr: integer, win_id: integer } res
function win_float.percentage_range_window(col_range, row_range, win_opts, border_opts)
  win_opts = tbl.apply_defaults(win_opts, win_float.default_options)

  local default_win_opts = win_float.default_opts(win_opts)
  default_win_opts.relative = "editor"

  local height_percentage, row_start_percentage
  if type(row_range) == "number" then
    assert(row_range <= 1)
    assert(row_range > 0)
    height_percentage = row_range
    row_start_percentage = (1 - height_percentage) / 2
  elseif type(row_range) == "table" then
    height_percentage = row_range[2] - row_range[1]
    row_start_percentage = row_range[1]
  else
    error(("Invalid type for 'row_range': %p"):format(row_range))
  end

  default_win_opts.height = math.ceil(vim.o.lines * height_percentage)
  default_win_opts.row = math.ceil(vim.o.lines * row_start_percentage)

  local width_percentage, col_start_percentage
  if type(col_range) == "number" then
    assert(col_range <= 1)
    assert(col_range > 0)
    width_percentage = col_range
    col_start_percentage = (1 - width_percentage) / 2
  elseif type(col_range) == "table" then
    width_percentage = col_range[2] - col_range[1]
    col_start_percentage = col_range[1]
  else
    error(("Invalid type for 'col_range': %p"):format(col_range))
  end

  default_win_opts.col = math.floor(vim.o.columns * col_start_percentage)
  default_win_opts.width = math.floor(vim.o.columns * width_percentage)

  local bufnr = win_opts.bufnr or vim.api.nvim_create_buf(false, true)
  local win_id = vim.api.nvim_open_win(bufnr, true, default_win_opts)
  vim.api.nvim_win_set_buf(win_id, bufnr)

  -- vim.cmd("setlocal nocursorcolumn")
  win_optset(win_id, "cursorcolumn", false)
  win_optset(win_id, "winblend", win_opts.winblend)

  local border = Border:new(bufnr, win_id, default_win_opts, border_opts or {})

  _AssociatedBufs[bufnr] = { win_id, border.win_id }

  clear_buf_on_leave(bufnr)

  return { border_bufnr = border.bufnr, border_win_id = border.win_id, bufnr = bufnr, win_id = win_id }
end

function win_float.clear(bufnr)
  if _AssociatedBufs[bufnr] == nil then
    return
  end

  for _, win_id in ipairs(_AssociatedBufs[bufnr]) do
    if vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
    end
  end

  _AssociatedBufs[bufnr] = nil
end

return win_float

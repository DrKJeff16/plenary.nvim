local strings = require("plenary.strings")

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

---@param bufnr integer
---@param option string
---@param value any
local function buf_optset(bufnr, option, value)
  if vim.fn.has("nvim-0.10") == 1 then
    vim.api.nvim_set_option_value(option, value, { buf = bufnr })
  else
    vim.api.nvim_buf_set_option(bufnr, option, value) ---@diagnostic disable-line:deprecated
  end
end

---@param bufnr integer
---@param ns_id integer
---@param hl_group string
---@param line integer
---@param col_start integer
---@param col_end integer
local function buf_add_hl(bufnr, ns_id, hl_group, line, col_start, col_end)
  if vim.fn.has("nvim-0.11") == 1 then
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, col_start, { end_col = col_end, hl_group = hl_group })
  else
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl_group, line, col_start, col_end) ---@diagnostic disable-line:deprecated
  end
end

---@class plenary.Window.Border
---@field bufnr integer
---@field content_win_id integer
---@field win_id integer
local Border = {}

Border.__index = Border

---@enum plenary.Window.Border.Thickness
Border._default_thickness = { bot = 1, left = 1, right = 1, top = 1 }

---@param title_pos "NW"|"N"|"NE"|"SW"|"S"|"SE"
---@param title_len integer
---@param total_width integer
---@return integer left_start
local function calc_left_start(title_pos, title_len, total_width)
  if title_pos:find("W") then
    return 0
  end
  if title_pos:find("E") then
    return total_width - title_len
  end
  return math.floor((total_width - title_len) / 2)
end

---@param title string
---@param pos "NW"|"N"|"NE"|"SW"|"S"|"SE"
---@param left_char string
---@param mid_char string
---@param right_char string
---@return string horizontal_line
---@return integer[][] ranges
local function create_horizontal_line(title, pos, width, left_char, mid_char, right_char)
  local title_len
  if title == "" then
    title_len = 0
  else
    local len = strings.strdisplaywidth(title)
    if len > (width - 2) then
      title = strings.truncate(title, width - 2)
      len = strings.strdisplaywidth(title)
    end
    title = (" %s "):format(title)
    title_len = len + 2
  end

  local left_start = calc_left_start(pos, title_len, width)
  local horizontal_line = ("%s%s%s%s%s"):format(
    left_char,
    mid_char:rep(left_start),
    title,
    mid_char:rep(width - title_len - left_start),
    right_char
  )
  local ranges = {} ---@type integer[][]
  if title_len ~= 0 then
    -- Need to calculate again due to multi-byte characters
    local r_start = left_char:len() + math.max(left_start, 0) * mid_char:len()
    ranges = { { r_start, r_start + title:len() } }
  end
  return horizontal_line, ranges
end

---@param content_win_id integer
---@param content_win_options table<string, any>
---@param border_win_options table<string, any>
function Border._create_lines(content_win_id, content_win_options, border_win_options)
  local content_pos = vim.api.nvim_win_get_position(content_win_id)
  local content_height = vim.api.nvim_win_get_height(content_win_id)
  local content_width = vim.api.nvim_win_get_width(content_win_id)
  local thickness = border_win_options.border_thickness -- TODO: Handle border width, which I haven't right here.
  local top_enabled = thickness.top == 1
  local right_enabled = thickness.right == 1 and content_pos[2] + content_width < vim.o.columns
  local bot_enabled = thickness.bot == 1
  local left_enabled = thickness.left == 1 and content_pos[2] > 0

  border_win_options.border_thickness.left = left_enabled and 1 or 0
  border_win_options.border_thickness.right = right_enabled and 1 or 0

  local border_lines = {} ---@type string[]
  local ranges = {} ---@type integer[][]

  -- border_win_options.title should have be a list with entries of the
  -- form: { pos = foo, text = bar }.
  -- pos can take values in { "NW", "N", "NE", "SW", "S", "SE" }
  ---@type { pos: "NW"|"N"|"NE"|"SW"|"S"|"SE", text: string }[]|string
  local titles = type(border_win_options.title) == "string" and { { pos = "N", text = border_win_options.title } }
    or border_win_options.title
    or {}

  local topline = nil ---@type string|nil|?
  local topleft = (left_enabled and border_win_options.topleft) or "" --[[@as string]]
  local topright = (right_enabled and border_win_options.topright) or "" --[[@as string]]
  -- Only calculate the topline if there is space above the first content row (relative to the editor)
  if content_pos[1] > 0 then
    for _, title in ipairs(titles) do
      if title.pos:find("N") then
        local top_ranges
        topline, top_ranges = create_horizontal_line(
          title.text,
          title.pos,
          content_win_options.width,
          topleft,
          border_win_options.top or "",
          topright
        )
        for _, r in ipairs(top_ranges) do
          table.insert(ranges, { 0, r[1], r[2] })
        end
        break
      end
    end
    if not topline and top_enabled then
      topline = topleft .. border_win_options.top:rep(content_win_options.width) .. topright
    end
  else
    border_win_options.border_thickness.top = 0
  end

  if topline then
    table.insert(border_lines, topline)
  end

  local middle_line = ("%s%s%s"):format(
    (left_enabled and border_win_options.left) or "",
    (" "):rep(content_win_options.width),
    (right_enabled and border_win_options.right) or ""
  )

  for _ = 1, content_win_options.height do
    table.insert(border_lines, middle_line)
  end

  local botline = nil ---@type string|nil|?
  local botleft = (left_enabled and border_win_options.botleft) or "" --[[@as string]]
  local botright = (right_enabled and border_win_options.botright) or "" --[[@as string]]
  if content_pos[1] + content_height < vim.o.lines then
    for _, title in ipairs(titles) do
      if title.pos:find("S") then
        local bot_ranges
        botline, bot_ranges = create_horizontal_line(
          title.text,
          title.pos,
          content_win_options.width,
          botleft,
          border_win_options.bot or "",
          botright
        )
        for _, r in pairs(bot_ranges) do
          table.insert(ranges, { content_win_options.height + thickness.top, r[1], r[2] })
        end
        break
      end
    end
    if not botline and bot_enabled then
      botline = botleft .. border_win_options.bot:rep(content_win_options.width) .. botright
    end
  else
    border_win_options.border_thickness.bot = 0
  end

  if botline then
    table.insert(border_lines, botline)
  end

  return border_lines, ranges
end

---@param bufnr integer
---@param ranges integer[][]
---@param hl string
local function set_title_highlights(bufnr, ranges, hl)
  local ns = vim.api.nvim_create_namespace("plenary.window")
  -- Check if both `hl` and `ranges` are provided, and `ranges` is not the empty table.
  if hl and ranges then
    for _, r in ipairs(ranges) do
      buf_add_hl(bufnr, ns, hl, r[1], r[2], r[3])
    end
  end
end

---@param pos? "NW"|"N"|"NE"|"SW"|"S"|"SE"
function Border:change_title(new_title, pos)
  if self._border_win_options.title ~= new_title then
    pos = pos
      or (
        self._border_win_options.title
        and self._border_win_options.title[1]
        and self._border_win_options.title[1].pos
      )

    self._border_win_options.title = not pos and new_title or { { text = new_title, pos = pos } }
    self.contents, self.title_ranges =
      Border._create_lines(self.content_win_id, self.content_win_options, self._border_win_options)

    vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, self.contents)

    set_title_highlights(self.bufnr, self.title_ranges, self._border_win_options.titlehighlight)
  end
end

-- Updates characters for border lines, and returns nvim_win_config
-- (generally used in conjunction with `move` or `new`)
---@param content_win_options table<string, any>
---@param border_win_options table<string, any>
---@return vim.api.keyset.win_config config
function Border:__align_calc_config(content_win_options, border_win_options)
  border_win_options = vim.tbl_deep_extend("keep", border_win_options, {
    border_thickness = Border._default_thickness,

    -- Border options, could be passed as a list?
    topleft = "╔",
    topright = "╗",
    top = "═",
    left = "║",
    right = "║",
    botleft = "╚",
    botright = "╝",
    bot = "═",
  })

  -- Ensure the relevant contents and border win_options are set
  self._border_win_options = border_win_options
  self.content_win_options = content_win_options
  -- Update border characters and title_ranges
  self.contents, self.title_ranges = Border._create_lines(self.content_win_id, content_win_options, border_win_options)

  buf_optset(self.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, self.contents)

  local thickness = border_win_options.border_thickness
  return {
    anchor = content_win_options.anchor,
    border = "none",
    col = content_win_options.col - thickness.left,
    focusable = vim.nonnil(border_win_options.focusable, false),
    height = content_win_options.height + thickness.top + thickness.bot,
    noautocmd = content_win_options.noautocmd,
    relative = content_win_options.relative,
    row = content_win_options.row - thickness.top,
    style = "minimal",
    width = content_win_options.width + thickness.left + thickness.right,
    zindex = content_win_options.zindex or 50,
  }
end

-- Sets the size and position of the given Border.
-- Can be used to create a new window (with `create_window = true`)
-- or change an existing one
function Border:move(content_win_options, border_win_options)
  -- Update lines in border buffer, and get config for border window
  local nvim_win_config = self:__align_calc_config(content_win_options, border_win_options)

  -- Set config for border window
  vim.api.nvim_win_set_config(self.win_id, nvim_win_config)

  set_title_highlights(self.bufnr, self.title_ranges, self._border_win_options.titlehighlight)
end

---@param content_bufnr integer
---@param content_win_id integer
---@param content_win_options table<string, any>
---@param border_win_options table<string, any>
---@return plenary.Window.Border obj
function Border:new(content_bufnr, content_win_id, content_win_options, border_win_options)
  assert(type(content_win_id) == "number", "Must supply a valid win_id. It's possible you forgot to call with ':'")

  ---@diagnostic disable-next-line:missing-fields
  local obj = { ---@type plenary.Window.Border
    bufnr = vim.api.nvim_create_buf(false, true),
    content_win_id = content_win_id,
  }
  assert(obj.bufnr, "Failed to create border buffer")
  buf_optset(obj.bufnr, "bufhidden", "wipe")

  -- Create a border window and buffer, with border characters around the edge
  local nvim_win_config = Border.__align_calc_config(obj, content_win_options, border_win_options)
  obj.win_id = vim.api.nvim_open_win(obj.bufnr, false, nvim_win_config)

  if border_win_options.highlight then
    win_optset(obj.win_id, "winhl", border_win_options.highlight)
  end

  set_title_highlights(obj.bufnr, obj.title_ranges, obj._border_win_options.titlehighlight)

  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = content_bufnr,
    once = true,
    nested = true,
    callback = function()
      require("plenary.window").close_related_win(content_win_id, obj.win_id)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = content_bufnr,
    once = true,
    nested = true,
    callback = function()
      require("plenary.window").try_close(content_win_id, true)
    end,
  })

  setmetatable(obj, Border)
  return obj
end

return Border

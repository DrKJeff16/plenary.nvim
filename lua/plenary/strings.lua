local path = require("plenary.path").path

---@class plenary.Strings
local M = {}

M.strdisplaywidth = (function()
  ---@param str string
  ---@param col? integer
  ---@return integer res
  local function fallback(str, col)
    str = tostring(str)
    return vim.in_fast_event() and (str:len() - (col or 0)) or vim.fn.strdisplaywidth(str, col)
  end

  if jit and path.sep ~= [[\]] then
    local ffi = require("ffi")
    ffi.cdef([[
      typedef unsigned char char_u;
      int linetabsize_col(int startcol, char_u *s);
    ]])

    ---@param str string
    ---@param col? integer
    ---@return integer res
    local function ffi_func(str, col)
      str = tostring(str)
      local s = ffi.new("char[?]", str:len() + 1)
      ffi.copy(s, str)
      return ffi.C.linetabsize_col(col or 0, s) - (col or 0)
    end

    return (pcall(ffi_func, "hello")) and ffi_func or fallback
  end
  return fallback
end)()

M.strcharpart = (function()
  ---@param str string
  ---@param nchar integer
  ---@param charlen integer
  ---@return string res
  local function fallback(str, nchar, charlen)
    return vim.in_fast_event() and str:sub(nchar + 1, charlen) or vim.fn.strcharpart(str, nchar, charlen)
  end

  if jit and path.sep ~= [[\]] then
    local ffi = require("ffi")
    ffi.cdef([[
      typedef unsigned char char_u;
      int utf_ptr2len(const char_u *const p);
    ]])

    ---@param str string
    ---@return function func
    local function utf_ptr2len(str)
      local c_str = ffi.new("char[?]", #str + 1)
      ffi.copy(c_str, str)
      return ffi.C.utf_ptr2len(c_str)
    end

    if not (pcall(utf_ptr2len, "🔭")) then
      return fallback
    end

    ---@param str string
    ---@param nchar integer
    ---@param charlen integer
    ---@return string res
    return function(str, nchar, charlen)
      local nbyte = 0
      if nchar > 0 then
        while nchar > 0 and nbyte < #str do
          nbyte = nbyte + utf_ptr2len(str:sub(nbyte + 1))
          nchar = nchar - 1
        end
      else
        nbyte = nchar
      end

      local len = 0
      if charlen then
        while charlen > 0 and nbyte + len < #str do
          local off = nbyte + len
          if off < 0 then
            len = len + 1
          else
            len = len + utf_ptr2len(str:sub(off + 1))
          end
          charlen = charlen - 1
        end
      else
        len = str:len() - nbyte
      end

      if nbyte < 0 then
        len = len + nbyte
        nbyte = 0
      elseif nbyte > str:len() then
        nbyte = str:len()
      end
      len = len < 0 and 0 or ((nbyte + len > str:len()) and (str:len() - nbyte) or len)

      return str:sub(nbyte + 1, nbyte + len)
    end
  end
  return fallback
end)()

---@param a string
---@param b string
---@param dir integer
---@return string res
local function concat(a, b, dir)
  return dir > 0 and (a .. b) or (b .. a)
end

---@param str string
---@param len integer
---@param dots string
---@param direction integer
---@return string result
local function truncate(str, len, dots, direction)
  if M.strdisplaywidth(str) <= len then
    return str
  end

  local start, current, result = direction > 0 and 0 or str:len(), 0, ""
  local len_of_dots = M.strdisplaywidth(dots)
  while true do
    local part = M.strcharpart(str, start, 1)
    current = current + M.strdisplaywidth(part)
    if (current + len_of_dots) > len then
      result = concat(result, dots, direction)
      break
    end
    result = concat(result, part, direction)
    start = start + direction
  end
  return result
end

---@param str string
---@param len integer
---@param dots? string
---@param direction? integer
function M.truncate(str, len, dots, direction)
  str = tostring(str) -- We need to make sure its an actually a string and not a number
  dots = dots or "…"
  direction = direction or 1

  if direction ~= 0 then
    return truncate(str, len, dots, direction)
  end
  if M.strdisplaywidth(str) <= len then
    return str
  end

  local s1 = truncate(str, math.floor((len + M.strdisplaywidth(dots)) / 2), dots, 1)
  return s1 .. truncate(str, len - M.strdisplaywidth(s1) + M.strdisplaywidth(dots), dots, -1):sub(dots:len() + 1)
end

---@param str string
---@param width integer
---@param right_justify boolean
function M.align_str(str, width, right_justify)
  local str_len = M.strdisplaywidth(str)
  return right_justify and (" "):rep(width - str_len) .. str or str .. (" "):rep(width - str_len)
end

---@param str string
---@param leave_indent? integer
function M.dedent(str, leave_indent)
  -- Check each line and detect the minimum indent.
  local indent ---@type integer|nil|?
  local info = {} ---@type { chars: integer, line: string, width: integer }[]
  for line in str:gmatch("[^\n]*\n?") do
    -- It matches '' for the last line.
    if line ~= "" then
      local chars, width ---@type integer, integer
      local line_indent = line:match("^[ \t]+") --[[@as string|nil|?]]
      if line_indent then
        chars = line_indent:len()
        width = M.strdisplaywidth(line_indent)
        if not indent or width < indent then
          indent = width
        end
        -- Ignore empty lines
      elseif line ~= "\n" then
        indent = 0
      end
      table.insert(info, { line = line, chars = chars, width = width })
    end
  end

  -- Build up the result
  leave_indent = leave_indent or 0
  local result = {} ---@type string[]
  for _, i in ipairs(info) do
    table.insert(
      result,
      i.chars and ((" "):rep(i.width - indent + leave_indent) .. i.line:sub(i.chars + 1))
        or (i.line == "\n" and "\n" or ((" "):rep(leave_indent) .. i.line))
    )
  end
  return table.concat(result)
end

return M

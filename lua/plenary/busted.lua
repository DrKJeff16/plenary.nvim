---@class plenary.Busted.Info : debuginfo
---@field traceback? string
---@field message? string

---@param p string
---@return string dirname
local function dirname(p)
  return vim.fn.fnamemodify(p, ":h")
end

---@param info plenary.Busted.Info
---@return plenary.Busted.Info info
local function trimTrace(info)
  local index = info.traceback:find("\n%s*%[C]")
  info.traceback = info.traceback:sub(1, index)
  return info
end

---@param level integer
---@param msg string
local function get_trace(_, level, msg)
  level = level or 3

  local thisdir = dirname(debug.getinfo(1, "Sl").source)
  local info = debug.getinfo(level, "Sl") --[[@as plenary.Busted.Info]]
  while
    info.what == "C"
    or info.short_src:match("luassert[/\\].*%.lua$")
    or (info.source:sub(1, 1) == "@" and thisdir == dirname(info.source))
  do
    level = level + 1
    info = debug.getinfo(level, "Sl") --[[@as plenary.Busted.Info]]
  end

  info.traceback = debug.traceback("", level)
  info.message = msg

  -- local file = busted.getFile(element)
  local file = false
  return file and file.getTrace(file.name, info) or trimTrace(info)
end

local is_headless = require("plenary.nvim_meta").is_headless

-- We are shadowing print so people can reliably print messages
print = function(...)
  for _, v in ipairs({ ... }) do
    io.stdout:write(tostring(v))
    io.stdout:write("\t")
  end

  io.stdout:write("\r\n")
end

---@class plenary.Busted
local mod = {}

local results = {} ---@type { errs: { descriptions: string[], msg: string }[], fail: table, pass: table }
local current_description = {} ---@type string[]
local current_before_each = {} ---@type table<integer, function[]>
local current_after_each = {} ---@type table<integer, function[]>

---@param desc string
---@return string[] current_description
local add_description = function(desc)
  table.insert(current_description, desc)

  return vim.deepcopy(current_description)
end

---@return string res
local function pop_description()
  local res = current_description[#current_description]
  current_description[#current_description] = nil
  return res
end

local function add_new_each()
  current_before_each[#current_description] = {}
  current_after_each[#current_description] = {}
end

local function clear_last_each()
  current_before_each[#current_description] = nil
  current_after_each[#current_description] = nil
end

---@param desc string
---@param func function
---@return boolean ok
---@return string msg
---@return string[] desc_stack
local function call_inner(desc, func)
  local desc_stack = add_description(desc)
  add_new_each()
  local ok, msg = xpcall(func, function(msg)
    -- debug.traceback
    -- return vim.inspect(get_trace(nil, 3, msg))
    local trace = get_trace(nil, 3, msg)
    return trace.message .. "\n" .. trace.traceback
  end)
  clear_last_each()
  pop_description()

  return ok, msg, desc_stack
end

local color_table = {
  yellow = 33,
  green = 32,
  red = 31,
}

---@param color "green"|"red"|"yellow"
---@param str string
---@return string str
local function color_string(color, str)
  local char = string.char(27)
  return is_headless and str or ("%s[%sm%s%s[%sm"):format(char, color_table[color] or 0, str, char, 0)
end

local SUCCESS = color_string("green", "Success")
local FAIL = color_string("red", "Fail")
local PENDING = color_string("yellow", "Pending")
local HEADER = ("="):rep(40)

---@param res { errs: { descriptions: string[], msg: string }[], fail: table, pass: table }
function mod.format_results(res)
  print("")
  print(color_string("green", "Success: "), #res.pass)
  print(color_string("red", "Failed : "), #res.fail)
  print(color_string("red", "Errors : "), #res.errs)
  print(HEADER)
end

---@param desc string
---@param func function
function mod.describe(desc, func)
  results.pass = results.pass or {}
  results.fail = results.fail or {}
  results.errs = results.errs or {}

  describe = mod.inner_describe
  local ok, msg, desc_stack = call_inner(desc, func)
  describe = mod.describe

  if not ok then
    table.insert(results.errs, {
      descriptions = desc_stack,
      msg = msg,
    })
  end
end

---@param desc string
---@param func function
function mod.inner_describe(desc, func)
  local ok, msg, desc_stack = call_inner(desc, func)
  if not ok then
    table.insert(results.errs, {
      descriptions = desc_stack,
      msg = msg,
    })
  end
end

---@param fn function
function mod.before_each(fn)
  table.insert(current_before_each[#current_description], fn)
end

mod.after_each = function(fn)
  table.insert(current_after_each[#current_description], fn)
end

function mod.clear()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
end

---@param msg string
---@param spaces? integer
local function indent(msg, spaces)
  spaces = spaces or 4

  local prefix = (" "):rep(spaces)
  return prefix .. msg:gsub("\n", "\n" .. prefix)
end

---@param tbl function[][]
local function run_each(tbl)
  for _, v in ipairs(tbl) do
    for _, w in ipairs(v) do
      if type(w) == "function" then
        w()
      end
    end
  end
end

---@param desc string
---@param func function
function mod.it(desc, func)
  run_each(current_before_each)
  local ok, msg, desc_stack = call_inner(desc, func)
  run_each(current_after_each)

  local test_result = {
    descriptions = desc_stack,
    msg = nil,
  }

  -- TODO: We should figure out how to determine whether
  -- and assert failed or whether it was an error...

  local to_insert = {}
  if not ok then
    to_insert = results.fail
    test_result.msg = msg

    print(FAIL, "||", table.concat(test_result.descriptions, " "))
    print(indent(msg, 12))
  else
    to_insert = results.pass
    print(SUCCESS, "||", table.concat(test_result.descriptions, " "))
  end

  table.insert(to_insert, test_result)
end

---@param desc string
function mod.pending(desc, _)
  local curr_stack = vim.deepcopy(current_description)
  table.insert(curr_stack, desc)
  print(PENDING, "||", table.concat(curr_stack, " "))
end

_PlenaryBustedOldAssert = _PlenaryBustedOldAssert or assert

describe = mod.describe
it = mod.it
pending = mod.pending
before_each = mod.before_each
after_each = mod.after_each
clear = mod.clear
assert = require("luassert") ---@type Luassert

---@param file string
function mod.run(file)
  file = file:gsub("\\", "/")

  print("\n" .. HEADER)
  print("Testing: ", file)

  local loaded, msg = loadfile(file)
  if not loaded then
    print(HEADER)
    print("FAILED TO LOAD FILE")
    print(color_string("red", msg))
    print(HEADER)

    return is_headless and vim.cmd("2cq") or nil
  end

  coroutine.wrap(function()
    loaded()

    -- If nothing runs (empty file without top level describe)
    if not results.pass then
      return is_headless and vim.cmd("0cq") or nil
    end

    mod.format_results(results)

    if #results.errs ~= 0 then
      print("We had an unexpected error: ", vim.inspect(results.errs), vim.inspect(results))
      if is_headless then
        return vim.cmd("2cq")
      end
    elseif #results.fail > 0 then
      print("Tests Failed. Exit: 1")

      if is_headless then
        return vim.cmd("1cq")
      end
    elseif is_headless then
      return vim.cmd("0cq")
    end
  end)()
end

return mod

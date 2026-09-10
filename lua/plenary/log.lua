-- M.lua
-- Does only support logging source files.
--
-- Inspired by rxi/M.lua
-- Modified by tjdevries and can be found at github.com/tjdevries/vM.nvim
--
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the MIT license. See LICENSE for details.

local Path = require("plenary.path")

local p_debug = vim.fn.getenv("DEBUG_PLENARY") ---@type string|boolean
if p_debug == vim.NIL then
  p_debug = false
end

---@alias plenary.LogLevel "debug"|"info"|"trace"|"warn"|"error"|"fatal"

---User configuration section.
---@class plenary.LogConfig
---Can limit the number of decimals displayed for floats.
---@field float_precision? number
---Adjust content as needed, but must keep function parameters to be filled by library code.
---@field fmt_msg? fun(is_console: boolean, mode_name: string, src_path: string, src_line: integer, msg: string): str: string
---Should highlighting be used in console (using echohl).
---@field highlights? boolean
---@field info_level? integer
---Any messages above this level will be logged.
---@field level? plenary.LogLevel
---Level configuration.
---@field modes? { name: plenary.LogLevel, hl: string }[]
---Output file has precedence over plugin, if not nil.
---Used for the logging file, if not nil and use_file == true.
---@field outfile? string|nil
---Name of the plugin. Prepended to log messages.
---@field plugin? string
---Should print the output to neovim while running.
---
---Accepted values are `"async"` and `"sync"`.
---@field use_console? boolean|string
---Should write to a file.
---
---Default output for logging file is `stdpath("log")/plugin.log`.
---@field use_file? boolean
---Should write to the quickfix list.
---@field use_quickfix? boolean

---@class plenary.LogDefaults: plenary.LogConfig
---@field float_precision number
---@field highlights boolean
---@field info_level integer
---@field level plenary.LogLevel
---@field modes { name: plenary.LogLevel, hl: string }[]
---@field outfile string|nil
---@field plugin string
---@field use_console boolean|string
---@field use_file boolean
---@field use_quickfix boolean
local default_config = {
  plugin = "plenary",
  use_console = "async",
  highlights = true,
  use_file = true,
  outfile = nil,
  use_quickfix = false,
  level = p_debug and "debug" or "info",
  modes = {
    { name = "trace", hl = "Comment" },
    { name = "debug", hl = "Comment" },
    { name = "info", hl = "None" },
    { name = "warn", hl = "WarningMsg" },
    { name = "error", hl = "ErrorMsg" },
    { name = "fatal", hl = "ErrorMsg" },
  },
  float_precision = 0.01,
  ---@param is_console boolean
  ---@param mode_name string
  ---@param src_path string
  ---@param src_line integer
  ---@param msg string
  ---@return string str
  fmt_msg = function(is_console, mode_name, src_path, src_line, msg)
    local nameupper = mode_name:upper()
    local lineinfo = src_path .. ":" .. src_line
    return ("[%-6s%s] %s: %s%s"):format(
      nameupper,
      os.date(is_console and "%H:%M:%S" or nil),
      lineinfo,
      msg,
      is_console and "" or "\n"
    )
  end,
}

---@class plenary.Log
---@field debug fun(...: any)
---@field error fun(...: any)
---@field fatal fun(...: any)
---@field info fun(...: any)
---@field trace fun(...: any)
---@field warn fun(...: any)
local M = {}

local unpack = unpack or table.unpack

---@param config plenary.LogConfig
---@param standalone boolean
---@return plenary.Log|plenary.LogConfig obj
function M.new(config, standalone)
  config = vim.tbl_deep_extend("force", default_config, config)

  local outfile = vim.nonnil(
    config.outfile,
    Path:new(vim.api.nvim_call_function("stdpath", { "log" }), config.plugin .. ".log").filename
  )

  local obj = standalone and M or config
  local levels = {} ---@type table<string, integer>
  for i, v in ipairs(config.modes) do
    levels[v.name] = i
  end

  ---@param x number
  ---@param increment number
  ---@return number rounded_num
  local function round(x, increment)
    if x == 0 then
      return x
    end
    increment = increment or 1
    x = x / increment --[[@as integer]]
    return (x > 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)) * increment
  end

  ---@param ... any
  ---@return string str
  local function make_string(...)
    local t = {}
    for i = 1, select("#", ...) do
      local x = select(i, ...)
      table.insert(
        t,
        type(x) == "number" and config.float_precision and tostring(round(x, config.float_precision))
          or (type(x) == "table" and vim.inspect(x) or tostring(x))
      )
    end
    return table.concat(t, " ")
  end

  ---@param level integer
  ---@param level_config { name: plenary.LogLevel, hl: string }
  ---@param message_maker fun(...: fun(...: any): ...): str: string
  ---@return ...
  local function log_at_level(level, level_config, message_maker, ...)
    if level < levels[config.level] then -- Return early if we're below the config.level
      return
    end

    local msg = message_maker(...)
    local info = debug.getinfo(config.info_level or 2, "Sl")
    local src_path = info.source:sub(2)
    local src_line = info.currentline
    if config.use_console then -- Output to console
      local function log_to_console()
        local console_string = config.fmt_msg(true, level_config.name, src_path, src_line, msg)
        if config.highlights and level_config.hl then
          vim.cmd.echohl(level_config.hl)
        end

        local split_console = vim.split(console_string, "\n")
        for _, v in ipairs(split_console) do
          if not (pcall(vim.cmd.echom, ("[%s] %s"):format(config.plugin, vim.fn.escape(v, [["\]])))) then
            if vim.fn.has("nvim-0.11") == 1 then
              vim.notify(msg .. "\n")
            else
              vim.api.nvim_out_write(msg .. "\n") ---@diagnostic disable-line:deprecated
            end
          end
        end

        if config.highlights and level_config.hl then
          vim.cmd.echohl("NONE")
        end
      end
      if config.use_console == "sync" and not vim.in_fast_event() then
        log_to_console()
      else
        vim.schedule(log_to_console)
      end
    end

    -- Output to log file
    if config.use_file then
      local outfile_parent_path = Path:new(outfile):parent()
      if not outfile_parent_path:exists() then
        outfile_parent_path:mkdir({ parents = true })
      end
      local fp = assert(io.open(outfile, "a"))
      local str = config.fmt_msg(false, level_config.name, src_path, src_line, msg)
      fp:write(str)
      fp:close()
    end

    -- Output to quickfix
    if config.use_quickfix then
      local qf_entry = {
        -- remove the @ getinfo adds to the file path
        col = 1,
        filename = info.source:sub(2),
        lnum = info.currentline,
        text = ("[%s] %s"):format(level_config.name:upper(), msg),
      }
      vim.fn.setqflist({ qf_entry }, "a")
    end
  end

  for i, x in ipairs(config.modes) do
    -- M.info("these", "are", "separated")
    obj[x.name] = function(...)
      return log_at_level(i, x, make_string, ...)
    end

    -- M.fmt_info("These are %s strings", "formatted")
    obj[("fmt_%s"):format(x.name)] = function(...)
      return log_at_level(i, x, function(...)
        local passed = { ... }
        local fmt = table.remove(passed, 1) --[[@as string]]
        local inspected = {}
        for _, v in ipairs(passed) do
          table.insert(inspected, vim.inspect(v))
        end
        return fmt:format(unpack(inspected))
      end, ...)
    end

    -- M.lazy_info(expensive_to_calculate)
    obj[("lazy_%s"):format(x.name)] = function()
      return log_at_level(i, x, function(f)
        return f()
      end)
    end

    -- M.file_info("do not print")

    ---@param vals any[]
    ---@param override plenary.LogConfig
    obj[("file_%s"):format(x.name)] = function(vals, override)
      local original_console = config.use_console
      config.use_console = false
      config.info_level = override.info_level
      log_at_level(i, x, make_string, unpack(vals))
      config.use_console = original_console
      config.info_level = nil
    end
  end

  return obj
end

M.new(default_config, true)

return M

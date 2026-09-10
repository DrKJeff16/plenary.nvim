local Path = require("plenary.path")
local os_sep = Path.path.sep

---@class plenary.Filetype
local M = {}

---@class plenary.Filetype.FtTable
---@field extension table<string, string>
---@field file_name table<string, string>
---@field shebang table<string, string>
local filetype_table = {
  extension = {},
  file_name = {},
  shebang = {},
}

---@param new_filetypes plenary.Filetype.FtTable
function M.add_table(new_filetypes)
  local valid_keys = { "extension", "file_name", "shebang" }
  local new_keys = {} ---@type table<string, boolean>

  -- Validate keys
  for k, _ in pairs(new_filetypes) do
    new_keys[k] = true
  end
  for _, k in ipairs(valid_keys) do
    new_keys[k] = nil
  end

  for k, v in pairs(new_keys) do
    error(debug.traceback("Invalid key / value:" .. tostring(k) .. " / " .. tostring(v)))
  end

  if new_filetypes.extension then
    filetype_table.extension = vim.tbl_extend("force", filetype_table.extension, new_filetypes.extension)
  end

  if new_filetypes.file_name then
    filetype_table.file_name = vim.tbl_extend("force", filetype_table.file_name, new_filetypes.file_name)
  end

  if new_filetypes.shebang then
    filetype_table.shebang = vim.tbl_extend("force", filetype_table.shebang, new_filetypes.shebang)
  end
end

---@param filename string
function M.add_file(filename)
  local filetype_files = vim.api.nvim_get_runtime_file(("data/plenary/filetypes/%s.lua"):format(filename), true)
  for _, file in ipairs(filetype_files) do
    local ok, msg = pcall(M.add_table, dofile(file))
    if not ok then
      error("Unable to add file " .. file .. ":\n" .. msg)
    end
  end
end

local filename_regex = "[^" .. os_sep .. "].*"

---@param filename string
---@return string[] possibilities
function M._get_extension_parts(filename)
  local current_match = filename:match(filename_regex) --[[@as string|nil]]
  local possibilities = {} ---@type string[]
  while current_match do
    current_match = current_match:match("[^.]%.(.*)") --[[@as string|nil]]
    if not current_match then
      break
    end
    table.insert(possibilities, current_match:lower())
  end
  return possibilities
end

---@param tail string
---@return string modeline
function M._parse_modeline(tail)
  return tail:find("vim:") and (tail:match(".*:ft=([^: ]*):.*$") or "") or ""
end

---@param head string
---@return string match
function M._parse_shebang(head)
  return head:sub(1, 2) == "#!" and (filetype_table.shebang[head:sub(3, head:len())] or "") or ""
end

local done_adding = false

---@return nil|true added
local function extend_tbl_with_ext_eq_ft_entries()
  if done_adding or vim.in_fast_event() then
    return
  end
  for _, v in ipairs(vim.fn.getcompletion("", "filetype")) do
    filetype_table.extension[v] = filetype_table.extension[v] or v
  end
  done_adding = true
  return true
end

---@param filepath string
---@return string match
function M.detect_from_extension(filepath)
  local exts = M._get_extension_parts(filepath)
  for _, ext in ipairs(exts) do
    local match = ext and filetype_table.extension[ext]
    if match then
      return match
    end
  end
  if extend_tbl_with_ext_eq_ft_entries() then
    for _, ext in ipairs(exts) do
      local match = ext and filetype_table.extension[ext]
      if match then
        return match
      end
    end
  end
  return ""
end

---@param filepath string
---@return string|nil match
function M.detect_from_name(filepath)
  if not filepath then
    return ""
  end

  local split_path = vim.split(filepath:lower(), os_sep, { trimempty = true })
  local match = filetype_table.file_name[split_path[#split_path]] --[[@as string|nil]]
  return match or ""
end

---@param filepath string
---@return string match
function M.detect_from_modeline(filepath)
  local tail = Path:new(filepath):readbyterange(-256, 256)
  if not tail then
    return ""
  end
  local lines = vim.split(tail, "\n")
  local idx = lines[#lines] ~= "" and #lines or #lines - 1
  return idx >= 1 and M._parse_modeline(lines[idx]) or ""
end

---@param filepath string
---@return string match
function M.detect_from_shebang(filepath)
  local head = Path:new(filepath):readbyterange(0, 256)
  return head and M._parse_shebang(vim.split(head, "\n")[1]) or ""
end

--- Detect a filetype from a path.
---
---`opts` is a table with optional keys:
---
--- - `fs_access` (bool, default=`true`) - Should check a file if it exists
---@param filepath string
---@param opts { fs_access?: boolean }
function M.detect(filepath, opts)
  opts = opts or {}
  opts.fs_access = opts.fs_access or true
  filepath = type(filepath) == "string" and filepath or tostring(filepath)

  local match = M.detect_from_name(filepath)
  if match ~= "" then
    return match
  end

  match = M.detect_from_extension(filepath)

  if not (opts.fs_access and Path:new(filepath):exists()) then
    return match
  end
  if match == "" then
    match = M.detect_from_shebang(filepath)
    if match ~= "" then
      return match
    end
  end

  if match == "text" or match == "" then
    match = M.detect_from_modeline(filepath)
    if match ~= "" then
      return match
    end
  end
end

M.add_file("base")
M.add_file("builtin")

return M

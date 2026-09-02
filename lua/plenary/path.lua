--- Path.lua
---
--- Goal: Create objects that are extremely similar to Python's `Path` Objects.
--- Reference: https://docs.python.org/3/library/pathlib.html

local bit = require("plenary.bit")
local uv = vim.uv or vim.loop

local F = require("plenary.functional")

---@enum plenary.Path.S_IF
local S_IF = {
  DIR = 0x4000, -- S_IFDIR  = 0o040000  # directory
  REG = 0x8000, -- S_IFREG  = 0o100000  # regular file
}

---@class Path
---@field home string
---@field sep "\\"|"/"
local path = {}
path.home = (uv.os_homedir())

path.sep = (function()
  if jit then
    return jit.os:lower() == "windows" and "\\" or "/"
  end
  return package.config:sub(1, 1)
end)()

path.root = (function()
  if path.sep == "/" then
    return function()
      return "/"
    end
  end
  ---@param base? string
  return function(base)
    return (base or uv.cwd()):sub(1, 1) .. ":\\"
  end
end)()

path.S_IF = S_IF

---@param reg integer
---@param value integer
---@return boolean res
local function band(reg, value)
  return bit.band(reg, value) == reg
end

---@param ... string
---@return string path_str
local function concat_paths(...)
  return table.concat({ ... }, path.sep)
end

---@param pathname string
---@return boolean is_root
local function is_root(pathname)
  return path.sep == "\\" and (pathname:match("^[A-Z]:\\?$") ~= nil) or (pathname == "/")
end

---@param filepath string
---@return string[] t
local function _split_by_separator(filepath)
  local t = {} ---@type string[]
  for str in filepath:gmatch(("([^%s]+)"):format(path.sep)) do
    table.insert(t, str)
  end
  return t
end

---@param filename string
---@return boolean uri
local function is_uri(filename)
  return filename:match("^%a[%w+-.]*://") ~= nil
end

---@param filename string
---@param sep string
local function is_absolute(filename, sep)
  return sep == "\\" and (filename:match("^[%a]:[\\/].*$") ~= nil) or (filename:sub(1, 1) == sep)
end

---@param filename string
---@param cwd string
---@return string path
local function _normalize_path(filename, cwd)
  if is_uri(filename) then
    return filename
  end

  -- handles redundant `./` in the middle
  local redundant = path.sep .. "%." .. path.sep
  if filename:match(redundant) then
    filename = filename:gsub(redundant, path.sep)
  end

  local out_file = filename
  if filename:find(path.sep .. "..", 1, true) or filename:find(".." .. path.sep, 1, true) then
    local is_abs = is_absolute(filename, path.sep)
    local function split_without_disk_name(filename_local)
      local parts = _split_by_separator(filename_local)
      -- Remove disk name part on Windows
      if path.sep == "\\" and is_abs then
        table.remove(parts, 1)
      end
      return parts
    end

    local parts = split_without_disk_name(filename)
    local idx = 1
    local initial_up_count = 0
    repeat
      if parts[idx] == ".." then
        if idx == 1 then
          initial_up_count = initial_up_count + 1
        end
        table.remove(parts, idx)
        table.remove(parts, idx - 1)

        idx = idx - (idx > 1 and 2 or 1)
      end
      idx = idx + 1
    until idx > #parts

    out_file = ((is_abs or #split_without_disk_name(cwd) == initial_up_count) and path.root(filename) or "")
      .. table.concat(parts, path.sep)
  end

  return out_file
end

---@param pathname string
local function clean(pathname)
  if is_uri(pathname) then
    return pathname
  end

  -- Remove double path seps, it's annoying
  pathname = pathname:gsub(path.sep .. path.sep, path.sep)

  -- Remove trailing path sep if not root
  return (not is_root(pathname) and pathname:sub(-1) == path.sep) and pathname:sub(1, -2) or pathname
end

-- S_IFCHR  = 0o020000  # character device
-- S_IFBLK  = 0o060000  # block device
-- S_IFIFO  = 0o010000  # fifo (named pipe)
-- S_IFLNK  = 0o120000  # symbolic link
-- S_IFSOCK = 0o140000  # socket file

---@class plenary.Path
---@field _sep "/"|"\\"
---@field filename string
local Path = {
  path = path,
}

local function check_self(self)
  return type(self) == "string" and Path:new(self) or self
end

function Path:__index(k)
  local raw = rawget(Path, k)
  if raw then
    return raw
  end

  if k == "_cwd" then
    self._cwd = uv.fs_realpath(".")
    return self._cwd
  end

  if k == "_absolute" then
    self._absolute = uv.fs_realpath(self.filename)
    return self._absolute
  end
end

-- TODO: Could use this to not have to call new... not sure
-- Path.__call = Path:new

function Path:__div(other)
  assert(Path.is_path(self))
  assert(Path.is_path(other) or type(other) == "string")

  return self:joinpath(other)
end

---@return string str
function Path:__tostring()
  return clean(self.filename)
end

-- TODO: See where we concat the table, and maybe we could make this work.
--
---@param other string
---@return string str
function Path:__concat(other)
  return self.filename .. other
end

---@param a plenary.Path
---@return boolean is_path
function Path.is_path(a)
  return getmetatable(a) == Path
end

---@param ... string[]|string|Path|plenary.Path
function Path:new(...)
  local args = { ... }
  if type(self) == "string" then
    table.insert(args, 1, self)
    self = Path -- luacheck: ignore
  end

  local path_input = #args == 1 and args[1] or args
  if Path.is_path(path_input) then
    ---@cast path_input plenary.Path
    -- If we already have a Path, it's fine.
    --   Just return it
    return path_input
  end

  -- TODO: Should probably remove and dumb stuff like double seps, periods in the middle, etc.

  local sep = path.sep
  if type(path_input) == "table" then
    sep = path_input.sep or path.sep
    path_input.sep = nil
  end

  local path_string
  if type(path_input) == "table" then
    -- TODO: It's possible this could be done more elegantly with __concat
    --       But I'm unsure of what we'd do to make that happen
    local path_objs = {} ---@type string[]
    for _, v in ipairs(path_input) do
      if type(v) == "table" and Path.is_path(v) then
        table.insert(path_objs, v.filename)
      elseif type(v) == "string" then
        table.insert(path_objs, v)
      end
    end

    path_string = table.concat(path_objs, sep)
  else
    assert(type(path_input) == "string", vim.inspect(path_input))
    path_string = path_input
  end

  return setmetatable({ _sep = sep, filename = path_string }, Path) --[[@as plenary.Path]]
end

---@return string fname
function Path:_fs_filename()
  return self:absolute() or self.filename
end

---@return uv.fs_stat.result stat
function Path:_stat()
  return uv.fs_stat(self:_fs_filename()) or {}
  -- local stat = uv.fs_stat(self:absolute())
  -- if not self._absolute then return {} end

  -- if not self._stat_result then
  --   self._stat_result =
  -- end

  -- return self._stat_result
end

---@return integer mode
function Path:_st_mode()
  return self:_stat().mode or 0
end

---@param ... string
---@return plenary.Path path
function Path:joinpath(...)
  return Path:new(self.filename, ...)
end

---@return string abs
function Path:absolute()
  return _normalize_path(
    self:is_absolute() and self.filename or self._absolute or table.concat({ self._cwd, self.filename }, self._sep),
    self._cwd
  )
end

---@return boolean exists
function Path:exists()
  return not vim.tbl_isempty(self:_stat())
end

---@return string str
function Path:expand()
  if is_uri(self.filename) then
    return self.filename
  end

  -- TODO support windows
  local expanded
  if self.filename:find("~") then
    expanded = self.filename:gsub("^~", uv.os_homedir())
  elseif self.filename:find("^%.") then
    expanded = uv.fs_realpath(self.filename)
    if expanded == nil then
      expanded = vim.fn.fnamemodify(self.filename, ":p")
    end
  elseif self.filename:find("%$") then
    local rep = self.filename:match("([^%$][^/]*)") --[[@as string]]
    local val = os.getenv(rep)
    expanded = val and self.filename:gsub(rep, val):gsub("%$", "") or nil
  else
    expanded = self.filename
  end
  if not expanded then
    error("Path not valid")
  end
  return expanded
end

---@param cwd string
---@return string relative_path
function Path:make_relative(cwd)
  if is_uri(self.filename) then
    return self.filename
  end

  self.filename = clean(self.filename)
  cwd = clean(F.if_nil(cwd, self._cwd, cwd))
  if self.filename == cwd then
    self.filename = "."
  else
    if cwd:sub(cwd:len(), cwd:len()) ~= path.sep then
      cwd = cwd .. path.sep
    end

    if self.filename:sub(1, cwd:len()) == cwd then
      self.filename = self.filename:sub(cwd:len() + 1, -1)
    end
  end
  return self.filename
end

---@param cwd string
---@return string normalized_path
function Path:normalize(cwd)
  if is_uri(self.filename) then
    return self.filename
  end

  self:make_relative(cwd)

  -- Substitute home directory w/ "~"
  -- string.gsub is not useful here because usernames with dashes at the end
  -- will be seen as a regexp pattern rather than a raw string
  local home = path.home
  if path.home:sub(-1) ~= path.sep then
    home = home .. path.sep
  end
  local start, finish = self.filename:find(home, 1, true)
  if start == 1 then
    self.filename = "~" .. path.sep .. self.filename:sub(finish + 1, -1)
  end
  return _normalize_path(clean(self.filename), self._cwd)
end

---@param filename string
---@param len? integer
---@param exclude? integer[]
---@return string str
local function shorten_len(filename, len, exclude)
  len = len or 1
  exclude = exclude or { -1 }
  local exc = {} ---@type table<integer, boolean>
  local parts = {} ---@type string[]
  local empty_pos = {} ---@type integer[]
  for m in (filename .. path.sep):gmatch("(.-)" .. path.sep) do
    if m ~= "" then
      table.insert(parts, m)
    else
      table.insert(empty_pos, #parts + 1)
    end
  end

  for _, v in pairs(exclude) do
    exc[v + (v < 0 and (#parts + 1) or 0)] = true
  end

  local final_path_components, count = {}, 1 ---@type string[], integer
  for _, match in ipairs(parts) do
    table.insert(final_path_components, (not exc[count] and #match > len) and match:sub(1, len) or match)
    table.insert(final_path_components, path.sep)
    count = count + 1
  end

  table.remove(final_path_components, #final_path_components) -- remove final slash

  -- add back empty positions
  for i = #empty_pos, 1, -1 do
    table.insert(final_path_components, empty_pos[i], path.sep)
  end

  return table.concat(final_path_components)
end

local shorten = (function()
  ---@param filename string
  ---@return string str
  local function fallback(filename)
    return shorten_len(filename, 1)
  end

  if jit and path.sep ~= "\\" then
    local ffi = require("ffi")
    ffi.cdef([[
    typedef unsigned char char_u;
    void shorten_dir(char_u *str);
    ]])

    ---@param filename string
    ---@return string str
    local function ffi_func(filename)
      if not filename or is_uri(filename) then
        return filename
      end

      local c_str = ffi.new("char[?]", #filename + 1)
      ffi.copy(c_str, filename)
      ffi.C.shorten_dir(c_str)
      return ffi.string(c_str)
    end
    return (pcall(ffi_func, "/tmp/path/file.lua")) and ffi_func or fallback
  end
  return fallback
end)()

---@param len? integer
---@param exclude? integer[]
function Path:shorten(len, exclude)
  assert(len ~= 0, "len must be at least 1")
  return (len and len > 1) or exclude ~= nil and shorten_len(self.filename, len, exclude) or shorten(self.filename)
end

---@param opts { mode: integer, parents?: boolean, exists_ok?: boolean }
---@return boolean success
function Path:mkdir(opts)
  opts = opts or {}

  local mode = opts.mode or tonumber("700", 8) -- 0700 -> decimal
  local parents = F.if_nil(opts.parents, false, opts.parents) --[[@as boolean]]
  local exists_ok = F.if_nil(opts.exists_ok, true, opts.exists_ok) --[[@as boolean]]
  local exists = self:exists()
  if not exists_ok and exists then
    error("FileExistsError:" .. self:absolute())
  end

  -- fs_mkdir returns nil if folder exists
  local ok = (uv.fs_mkdir(self:_fs_filename(), mode)) or exists
  if not (ok or parents) then
    error("FileNotFoundError")
  end

  local processed = ""
  for _, dir in ipairs(self:_split()) do
    if dir ~= "" then
      local joined = (processed == "" and self._sep == "\\") and dir or concat_paths(processed, dir)
      local stat = uv.fs_stat(joined)
      local file_mode = stat and stat.mode or 0
      if band(S_IF.REG, file_mode) then
        error(("%s is a regular file so we can't mkdir it"):format(joined))
      end
      if not (band(S_IF.DIR, file_mode) or uv.fs_mkdir(joined, mode)) then
        error("We couldn't mkdir: " .. joined)
      end
      processed = joined
    end
  end
  return true
end

function Path:rmdir()
  if self:exists() then
    uv.fs_rmdir(self:absolute())
  end
end

---@param opts? { new_name?: string[]|string }
function Path:rename(opts)
  opts = opts or {}
  if not opts.new_name or opts.new_name == "" then
    error("Please provide the new name!")
  end

  -- handles `.`, `..`, `./`, and `../`
  if opts.new_name:match("^%.%.?/?\\?.+") then
    opts.new_name = {
      uv.fs_realpath(opts.new_name:sub(1, 3)),
      opts.new_name:sub(4, opts.new_name:len()),
    }
  end

  local new_path = Path:new(opts.new_name)
  if new_path:exists() then
    error("File or directory already exists!")
  end

  local status = uv.fs_rename(self:absolute(), new_path:absolute())
  self.filename = new_path.filename
  return status
end

--- Copy files or folders with defaults akin to GNU's `cp`.
---@param opts { destination: string[]|string|plenary.Path, recursive?: boolean, override?: boolean, interactive?: boolean, respect_gitignore?: boolean, hidden?: boolean, parents?: boolean, exists_ok?: boolean }
---@return table<string, boolean> success Table indicating success of copy; nested tables constitute sub dirs
function Path:copy(opts)
  opts = opts or {}
  opts.recursive = F.if_nil(opts.recursive, false, opts.recursive)
  opts.override = F.if_nil(opts.override, true, opts.override)

  local dest = opts.destination
  -- handles `.`, `..`, `./`, and `../`
  if not Path.is_path(dest) then
    if type(dest) == "string" and dest:match("^%.%.?/?\\?.+") then
      dest = {
        uv.fs_realpath(dest:sub(1, 3)),
        dest:sub(4, #dest),
      }
    end
    dest = Path:new(dest)
  end
  -- success is true in case file is copied, false otherwise
  local success = {} ---@type table<string, boolean>
  if not self:is_dir() then
    ---@diagnostic disable:missing-fields
    if opts.interactive and dest:exists() then
      vim.ui.select({ "Yes", "No" }, { prompt = ("Overwrite existing %s?"):format(dest:absolute()) }, function(_, idx)
        success[dest] = uv.fs_copyfile(self:absolute(), dest:absolute(), { excl = idx ~= 1 }) or false
      end)
    else
      -- nil: not overriden if `override = false`
      success[dest] = uv.fs_copyfile(self:absolute(), dest:absolute(), { excl = not opts.override }) or false
    end
    ---@diagnostic enable:missing-fields
    return success
  end
  -- dir
  if opts.recursive then
    dest:mkdir({
      parents = F.if_nil(opts.parents, false, opts.parents),
      exists_ok = F.if_nil(opts.exists_ok, true, opts.exists_ok),
    })
    local data = require("plenary.scandir").scan_dir(self.filename, {
      respect_gitignore = F.if_nil(opts.respect_gitignore, false, opts.respect_gitignore),
      hidden = F.if_nil(opts.hidden, true, opts.hidden),
      depth = 1,
      add_dirs = true,
    })
    for _, entry in ipairs(data) do
      local entry_path = Path:new(entry)
      local suffix = table.remove(entry_path:_split())
      local new_dest = dest:joinpath(suffix)
      -- clear destination as it might be Path table otherwise failing w/ extend
      opts.destination = nil
      local new_opts = vim.tbl_deep_extend("force", opts, { destination = new_dest })
      -- nil: not overriden if `override = false`
      success[new_dest] = entry_path:copy(new_opts) or false
    end
    return success
  else
    error(string.format("Warning: %s was not copied as `recursive=false`", self:absolute()))
  end
end

function Path:touch(opts)
  opts = opts or {}

  local mode = opts.mode or 420
  local parents = F.if_nil(opts.parents, false, opts.parents)

  if self:exists() then
    local new_time = os.time()
    uv.fs_utime(self:_fs_filename(), new_time, new_time)
    return
  end

  if parents then
    Path:new(self:parent()):mkdir({ parents = true })
  end

  local fd = uv.fs_open(self:_fs_filename(), "w", mode)
  if not fd then
    error("Could not create file: " .. self:_fs_filename())
  end
  uv.fs_close(fd)

  return true
end

function Path:rm(opts)
  opts = opts or {}

  local recursive = F.if_nil(opts.recursive, false, opts.recursive)
  if recursive then
    local scan = require("plenary.scandir")
    local abs = self:absolute()
    scan.scan_dir(abs, { -- first unlink all files
      hidden = true,
      on_insert = function(file)
        uv.fs_unlink(file)
      end,
    })

    local dirs = scan.scan_dir(abs, { add_dirs = true, hidden = true })
    for i = #dirs, 1, -1 do -- iterate backwards to clean up remaining dirs
      uv.fs_rmdir(dirs[i])
    end

    -- now only abs is missing
    uv.fs_rmdir(abs)
  else
    uv.fs_unlink(self:absolute())
  end
end

-- Path:is_* {{{
---@return boolean is_dir
function Path:is_dir()
  -- TODO: I wonder when this would be better, if ever.
  -- return self:_stat().type == 'directory'

  return band(S_IF.DIR, self:_st_mode())
end

---@return boolean is_absolute
function Path:is_absolute()
  return is_absolute(self.filename, self._sep)
end
-- }}}

---@return string[] split
function Path:_split()
  return vim.split(self:absolute(), self._sep)
end

local function _get_parent(abs_path)
  local parent = abs_path:match(("^(.+)%s[^%s]+"):format(path.sep, path.sep))
  if parent ~= nil and not parent:find(path.sep) then
    return parent .. path.sep
  end
  return parent
end

function Path:parent()
  return Path:new(_get_parent(self:absolute()) or path.root(self:absolute()))
end

function Path:parents()
  local results = {}
  local cur = self:absolute()
  repeat
    cur = _get_parent(cur)
    table.insert(results, cur)
  until not cur
  table.insert(results, path.root(self:absolute()))
  return results
end

function Path:is_file()
  return self:_stat().type == "file" and true or nil
end

-- TODO:
--  Maybe I can use libuv for this?
function Path:open() end

function Path:close() end

function Path:write(txt, flag, mode)
  assert(flag, [[Path:write_text requires a flag! For example: 'w' or 'a']])

  mode = mode or 438

  local fd = assert(uv.fs_open(self:_fs_filename(), flag, mode))
  assert(uv.fs_write(fd, txt, -1))
  assert(uv.fs_close(fd))
end

-- TODO: Asyncify this and use vim.wait in the meantime.
--  This will allow other events to happen while we're waiting!
function Path:_read()
  self = check_self(self)

  local fd = assert(uv.fs_open(self:_fs_filename(), "r", 438)) -- for some reason test won't pass with absolute
  local stat = assert(uv.fs_fstat(fd))
  local data = assert(uv.fs_read(fd, stat.size, 0))
  assert(uv.fs_close(fd))

  return data
end

function Path:_read_async(callback)
  uv.fs_open(self.filename, "r", 438, function(err_open, fd)
    if err_open then
      print("We tried to open this file but couldn't. We failed with following error message: " .. err_open)
      return
    end
    uv.fs_fstat(fd, function(err_fstat, stat)
      assert(not err_fstat, err_fstat)
      if stat then
        if stat.type ~= "file" then
          return callback("")
        end
        uv.fs_read(fd, stat.size, 0, function(err_read, data)
          assert(not err_read, err_read)
          uv.fs_close(fd, function(err_close)
            assert(not err_close, err_close)
            return callback(data)
          end)
        end)
      end
    end)
  end)
end

function Path:read(callback)
  if callback then
    return self:_read_async(callback)
  end
  return self:_read()
end

function Path:head(lines)
  lines = lines or 10
  self = check_self(self)
  local chunk_size = 256

  local fd = uv.fs_open(self:_fs_filename(), "r", 438)
  if not fd then
    return
  end
  local stat = assert(uv.fs_fstat(fd))
  if stat.type ~= "file" then
    uv.fs_close(fd)
    return nil
  end

  local data = ""
  local index, count = 0, 0
  while count < lines and index < stat.size do
    local read_chunk = assert(uv.fs_read(fd, chunk_size, index))

    local i = 0
    for char in read_chunk:gmatch(".") do
      if char == "\n" then
        count = count + 1
        if count >= lines then
          break
        end
      end
      index = index + 1
      i = i + 1
    end
    data = data .. read_chunk:sub(1, i)
  end
  assert(uv.fs_close(fd))

  -- Remove potential newline at end of file
  if data:sub(-1) == "\n" then
    data = data:sub(1, -2)
  end

  return data
end

function Path:tail(lines)
  lines = lines or 10
  self = check_self(self)
  local chunk_size = 256

  local fd = uv.fs_open(self:_fs_filename(), "r", 438)
  if not fd then
    return
  end
  local stat = assert(uv.fs_fstat(fd))
  if stat.type ~= "file" then
    uv.fs_close(fd)
    return nil
  end

  local data = ""
  local index, count = stat.size - 1, 0
  while count < lines and index > 0 do
    local real_index = index - chunk_size
    if real_index < 0 then
      chunk_size = chunk_size + real_index
      real_index = 0
    end

    local read_chunk = assert(uv.fs_read(fd, chunk_size, real_index))

    local i = #read_chunk
    while i > 0 do
      local char = read_chunk:sub(i, i)
      if char == "\n" then
        count = count + 1
        if count >= lines then
          break
        end
      end
      index = index - 1
      i = i - 1
    end
    data = read_chunk:sub(i + 1, #read_chunk) .. data
  end
  assert(uv.fs_close(fd))

  return data
end

function Path:readlines()
  self = check_self(self)

  local data = self:read()

  data = data:gsub("\r", "")
  return vim.split(data, "\n")
end

function Path:iter()
  local data = self:readlines()
  local i = 0
  local n = #data
  return function()
    i = i + 1
    if i <= n then
      return data[i]
    end
  end
end

function Path:readbyterange(offset, length)
  self = check_self(self)

  local fd = uv.fs_open(self:_fs_filename(), "r", 438)
  if not fd then
    return
  end
  local stat = assert(uv.fs_fstat(fd))
  if stat.type ~= "file" then
    uv.fs_close(fd)
    return nil
  end

  if offset < 0 then
    offset = stat.size + offset
    -- Windows fails if offset is < 0 even though offset is defined as signed
    -- http://docs.libuv.org/en/v1.x/fs.html#c.uv_fs_read
    if offset < 0 then
      offset = 0
    end
  end

  local data = ""
  while #data < length do
    local read_chunk = assert(uv.fs_read(fd, length - #data, offset))
    if #read_chunk == 0 then
      break
    end
    data = data .. read_chunk
    offset = offset + #read_chunk
  end

  assert(uv.fs_close(fd))

  return data
end

function Path:find_upwards(filename)
  local folder = Path:new(self)
  local root = path.root(folder:absolute())

  while true do
    local p = folder:joinpath(filename)
    if p:exists() then
      return p
    end
    if folder:absolute() == root then
      break
    end
    folder = folder:parent()
  end
  return nil
end

return Path

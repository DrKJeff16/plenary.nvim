local Path = require("plenary.path")
local os_sep = Path.path.sep
local F = require("plenary.functional")
local compat = require("plenary.compat")

local uv = vim.uv or vim.loop

local m = {}

local function make_gitignore(basepath)
  local patterns = {}
  local valid = false
  for _, v in ipairs(basepath) do
    local p = Path:new(v .. os_sep .. ".gitignore")
    if p:exists() then
      valid = true
      patterns[v] = { ignored = {}, negated = {} }
      for l in p:iter() do
        local prefix = l:sub(1, 1)
        local negated = prefix == "!"
        if negated then
          l = l:sub(2)
          prefix = l:sub(1, 1)
        end
        if prefix == "/" then
          l = v .. l
        end
        if not (prefix == "" or prefix == "#") then
          local el = (
            vim
              .trim(l)
              :gsub("%-", "%%-")
              :gsub("%.", "%%.")
              :gsub("/%*%*/", "/%%w+/")
              :gsub("%*%*", "")
              :gsub("%*", "%%w+")
              :gsub("%?", "%%w")
          )
          if el ~= "" then
            table.insert(negated and patterns[v].negated or patterns[v].ignored, el)
          end
        end
      end
    end
  end
  if not valid then
    return
  end

  ---@param bp string[]
  ---@param entry string
  return function(bp, entry)
    for _, v in ipairs(bp) do
      if entry:find(v, 1, true) then
        local negated = false
        for _, w in ipairs(patterns[v].ignored) do
          if not negated and entry:match(w) then
            for _, inverse in ipairs(patterns[v].negated) do
              if not negated and entry:match(inverse) then
                negated = true
              end
            end
            if not negated then
              return false
            end
          end
        end
      end
    end
    return true
  end
end
-- exposed for testing
m.__make_gitignore = make_gitignore

local handle_depth = function(base_paths, entry, depth)
  for _, v in ipairs(base_paths) do
    if entry:find(v, 1, true) then
      local cut = entry:sub(#v + 1, -1)
      cut = cut:sub(1, 1) == os_sep and cut:sub(2, -1) or cut
      local _, count = cut:gsub(os_sep, "")
      if depth <= (count + 1) then
        return nil
      end
    end
  end
  return entry
end

local gen_search_pat = function(pattern)
  if type(pattern) == "string" then
    return function(entry)
      return entry:match(pattern)
    end
  elseif type(pattern) == "table" then
    return function(entry)
      for _, v in ipairs(pattern) do
        if entry:match(v) then
          return true
        end
      end
      return false
    end
  elseif type(pattern) == "function" then
    return pattern
  end
end

local process_item = function(opts, name, typ, current_dir, next_dir, bp, data, giti, msp)
  if opts.hidden or name:sub(1, 1) ~= "." then
    if typ == "directory" then
      local entry = current_dir .. os_sep .. name
      if opts.depth then
        table.insert(next_dir, handle_depth(bp, entry, opts.depth))
      else
        table.insert(next_dir, entry)
      end
      if opts.add_dirs or opts.only_dirs then
        if not giti or giti(bp, entry .. "/") then
          if not msp or msp(entry) then
            table.insert(data, entry)
            if opts.on_insert then
              opts.on_insert(entry, typ)
            end
          end
        end
      end
    elseif not opts.only_dirs then
      local entry = current_dir .. os_sep .. name
      if not giti or giti(bp, entry) then
        if not msp or msp(entry) then
          table.insert(data, entry)
          if opts.on_insert then
            opts.on_insert(entry, typ)
          end
        end
      end
    end
  end
end

--- m.scan_dir
-- Search directory recursive and syncronous
-- @param path: string or table
--   string has to be a valid path
--   table has to be a array of valid paths
-- @param opts: table to change behavior
--   opts.hidden (bool):              if true hidden files will be added
--   opts.add_dirs (bool):            if true dirs will also be added to the results
--   opts.only_dirs (bool):           if true only dirs will be added to the results
--   opts.respect_gitignore (bool):   if true will only add files that are not ignored by the git
--   opts.depth (int):                depth on how deep the search should go
--   opts.search_pattern (regex):     regex for which files will be added, string, table of strings, or fn(e) -> bool
--   opts.on_insert(entry):           Will be called for each element
--   opts.silent (bool):              if true will not echo messages that are not accessible
-- @return array with files
---@param path string[]|string
m.scan_dir = function(path, opts)
  opts = opts or {}

  local data = {} ---@type string[]
  local base_paths = compat.flatten({ path }) --[[@as string[]\]]
  local next_dir = compat.flatten({ path })

  local gitignore = opts.respect_gitignore and make_gitignore(base_paths) or nil
  local match_search_pat = opts.search_pattern and gen_search_pat(opts.search_pattern) or nil

  for i = #base_paths, 1, -1 do
    if uv.fs_access(base_paths[i], "X") == false then
      if not F.if_nil(opts.silent, false, opts.silent) then
        print(("%s is not accessible by the current user!"):format(base_paths[i]))
      end
      table.remove(base_paths, i)
    end
  end
  if #base_paths == 0 then
    return {}
  end

  repeat
    local current_dir = table.remove(next_dir, 1)
    local fd = uv.fs_scandir(current_dir)
    if fd then
      while true do
        local name, typ = uv.fs_scandir_next(fd)
        if name == nil then
          break
        end
        process_item(opts, name, typ, current_dir, next_dir, base_paths, data, gitignore, match_search_pat)
      end
    end
  until #next_dir == 0
  return data
end

---Search directory recursive and asyncronous
---@param path string[]|string
---@param opts? { hidden?: boolean, add_dirs?: boolean, only_dirs?: boolean, respect_gitignore?: boolean, depth?: integer, search_pattern?: (string[]|string|fun(e: any): boolean), on_insert?: fun(...: any), on_exit?: fun(results: any), silent?: boolean }
function m.scan_dir_async(path, opts)
  opts = opts or {}

  local data = {}
  local base_paths = compat.flatten({ path })
  local next_dir = compat.flatten({ path })
  local current_dir = table.remove(next_dir, 1)

  -- TODO(conni2461): get gitignore is not async
  local gitignore = opts.respect_gitignore and make_gitignore(base_paths) or nil
  local match_search_pat = opts.search_pattern and gen_search_pat(opts.search_pattern) or nil

  -- TODO(conni2461): is not async. Shouldn't be that big of a problem but still
  -- Maybe obers async pr can take me out of callback hell
  for i = #base_paths, 1, -1 do
    if uv.fs_access(base_paths[i], "X") == false then
      if not F.if_nil(opts.silent, false, opts.silent) then
        print(("%s is not accessible by the current user!"):format(base_paths[i]))
      end
      table.remove(base_paths, i)
    end
  end
  if #base_paths == 0 then
    return {}
  end

  ---@param err? string
  ---@param fd uv.uv_fs_t
  local function read_dir(err, fd)
    if err then
      return
    end

    while true do
      local name, typ = uv.fs_scandir_next(fd)
      if not name then
        break
      end
      process_item(opts, name, typ, current_dir, next_dir, base_paths, data, gitignore, match_search_pat)
    end
    if #next_dir == 0 and opts.on_exit then
      opts.on_exit(data)
    else
      current_dir = table.remove(next_dir, 1)
      uv.fs_scandir(current_dir, read_dir)
    end
  end
  uv.fs_scandir(current_dir, read_dir)
end

local gen_permissions = (function()
  ---@param nr integer
  ---@return integer octal
  local function conv_to_octal(nr)
    local octal, i = 0, 1
    while nr ~= 0 do
      octal = octal + (nr % 8) * i
      nr = math.floor(nr / 8)
      i = i * 10
    end
    return octal
  end

  local type_tbl = { [1] = "p", [2] = "c", [4] = "d", [6] = "b", [10] = ".", [12] = "l", [14] = "s" }
  local permissions_tbl = { [0] = "---", "--x", "-w-", "-wx", "r--", "r-x", "rw-", "rwx" }
  local bit_tbl = { 4, 2, 1 }

  ---@generic T
  ---@param cache table<T, string>
  ---@param mode T
  ---@return string permissions
  return function(cache, mode)
    if cache[mode] then
      return cache[mode]
    end

    local octal = ("%6d"):format(conv_to_octal(mode))
    local l4 = octal:sub(octal:len() - 3, -1)
    local bit = tonumber(l4:sub(1, 1))
    local result = type_tbl[tonumber(octal:sub(1, 2))] or "-" ---@type string
    for i = 2, l4:len() do
      result = result .. permissions_tbl[tonumber(l4:sub(i, i))]
      if bit - bit_tbl[i - 1] >= 0 then
        result = result:sub(1, -2) .. (bit_tbl[i - 1] == 1 and "T" or "S") --[[@as string]]
        bit = bit - bit_tbl[i - 1]
      end
    end

    cache[mode] = result
    return result
  end
end)()

local gen_size = (function()
  local size_types = { "", "K", "M", "G", "T", "P", "E", "Z" }

  ---@param size number
  ---@return string size_str
  return function(size)
    -- TODO(conni2461): If type directory we could just return 4.0K
    for _, v in ipairs(size_types) do
      if math.abs(size) < 1024 then
        return math.abs(size) > 9 and ("%3d%s"):format(size, v) or ("%3.1f%s"):format(size, v)
      end
      size = size / 1024
    end
    return ("%.1f%s"):format(size, "Y")
  end
end)()

local gen_date = (function()
  local current_year = os.date("%Y")
  ---@param mtime integer
  ---@return string date
  return function(mtime)
    return current_year ~= os.date("%Y", mtime) and os.date("%b %d  %Y", mtime) or os.date("%b %d %H:%M", mtime)
  end
end)()

local get_username = (function()
  ---@generic T
  ---@param tbl table<T, string>
  ---@param id T
  ---@return T|string res
  local function fallback(tbl, id)
    if not tbl then
      return id
    end
    if tbl[id] then
      return tbl[id]
    end
    tbl[id] = tostring(id)
    return id
  end

  if jit and os_sep ~= "\\" then
    local ffi = require("ffi")
    ffi.cdef([[
      typedef unsigned int __uid_t;
      typedef __uid_t uid_t;
      typedef unsigned int __gid_t;
      typedef __gid_t gid_t;

      typedef struct {
        char *pw_name;
        char *pw_passwd;
        __uid_t pw_uid;
        __gid_t pw_gid;
        char *pw_gecos;
        char *pw_dir;
        char *pw_shell;
      } passwd;

      passwd *getpwuid(uid_t uid);
    ]])

    ---@generic T
    ---@param tbl table<T, string>
    ---@param id T
    local function ffi_func(tbl, id)
      if tbl[id] then
        return tbl[id]
      end
      local struct = ffi.C.getpwuid(id)
      local name = struct and ffi.string(struct.pw_name) or tostring(id)
      tbl[id] = name
      return name
    end
    return (pcall(ffi_func, {}, 1000)) and ffi_func or fallback
  end
  return fallback
end)()

local get_groupname = (function()
  ---@generic T, V
  ---@param tbl table<T, V>
  ---@param id T
  ---@return T|V res
  local function fallback(tbl, id)
    if not tbl then
      return id
    end
    if tbl[id] then
      return tbl[id]
    end
    tbl[id] = tostring(id)
    return id
  end

  if jit and os_sep ~= "\\" then
    local ffi = require("ffi")
    ffi.cdef([[
      typedef unsigned int __gid_t;
      typedef __gid_t gid_t;

      typedef struct {
        char *gr_name;
        char *gr_passwd;
        __gid_t gr_gid;
        char **gr_mem;
      } group;
      group *getgrgid(gid_t gid);
    ]])

    ---@generic T, V
    ---@param tbl table<T, V>
    ---@param id T
    ---@return string res
    local function ffi_func(tbl, id)
      if tbl[id] then
        return tbl[id]
      end

      local struct = ffi.C.getgrgid(id)
      local name = struct and ffi.string(struct.gr_name) or tostring(id)
      tbl[id] = name
      return name
    end
    return (pcall(ffi_func, {}, 1000)) and ffi_func or fallback
  end
  return fallback
end)()

---@param tbl table<string|integer, table>
---@return integer max_len
local function get_max_len(tbl)
  if not tbl then
    return 0
  end
  local max_len = 0
  for _, v in pairs(tbl) do
    if #v > max_len then
      max_len = #v
    end
  end
  return max_len
end

---@param data string[]
---@param path string
local function gen_ls(data, path, opts)
  if not data or #data == 0 then
    return {}, {}
  end

  local check_link = function(per, file)
    if per:sub(1, 1) == "l" then
      local resolved = uv.fs_realpath(path .. os_sep .. file)
      if not resolved then
        return file
      end
      if resolved:sub(1, #path) == path then
        resolved = resolved:sub(#path + 2, -1)
      end
      return ("%s -> %s"):format(file, resolved)
    end
    return file
  end

  local results, sections = {}, {}
  local users_tbl = os_sep ~= "\\" and {} or nil
  local groups_tbl = os_sep ~= "\\" and {} or nil

  local stats, permissions_cache = {}, {}
  for _, v in ipairs(data) do
    local stat = uv.fs_lstat(v)
    if stat then
      stats[v] = stat
      get_username(users_tbl, stat.uid)
      get_groupname(groups_tbl, stat.gid)
    end
  end

  local insert_in_results = (function()
    if not users_tbl and not groups_tbl then
      local section_spacing_tbl = { [5] = 2, [6] = 0 }
      return function(...)
        local args = { ... }
        local section = {
          { start_index = 01, end_index = 11 }, -- permissions, hardcoded indexes
          { start_index = 12, end_index = 17 }, -- size, hardcoded indexes
        }
        local cur_index = 19
        for k = 5, 6 do
          local v = section_spacing_tbl[k]
          local end_index = cur_index + #args[k]
          table.insert(section, { start_index = cur_index, end_index = end_index })
          cur_index = end_index + v
        end
        table.insert(sections, section)
        table.insert(results, ("%10s %5s  %s  %s"):format(args[1], args[2], args[5], check_link(args[1], args[6])))
      end
    end

    local max_user_len = get_max_len(users_tbl)
    local max_group_len = get_max_len(groups_tbl)
    local section_spacing_tbl = {
      [3] = { max = max_user_len, add = 1 },
      [4] = { max = max_group_len, add = 2 },
      [5] = { add = 2 },
      [6] = { add = 0 },
    }
    local fmt_str = "%10s %5s %-" .. max_user_len .. "s %-" .. max_group_len .. "s  %s  %s"
    return function(...)
      local args = { ... }
      local section = {
        { start_index = 01, end_index = 11 }, -- permissions, hardcoded indexes
        { start_index = 12, end_index = 17 }, -- size, hardcoded indexes
      }
      local cur_index = 18
      for k = 3, 6 do
        local v = section_spacing_tbl[k]
        local end_index = cur_index + #args[k]
        table.insert(section, { start_index = cur_index, end_index = end_index })
        cur_index = v.max and (cur_index + v.max + v.add) or (end_index + v.add)
      end
      table.insert(sections, section)
      table.insert(results, fmt_str:format(args[1], args[2], args[3], args[4], args[5], check_link(args[1], args[6])))
    end
  end)()

  for name, stat in pairs(stats) do
    insert_in_results(
      gen_permissions(permissions_cache, stat.mode),
      gen_size(stat.size),
      get_username(users_tbl, stat.uid),
      get_groupname(groups_tbl, stat.gid),
      gen_date(stat.mtime.sec),
      name:sub(#path + 2, -1)
    )
  end

  if opts and opts.group_directories_first then
    local sorted_results = {}
    local sorted_sections = {}
    for k, v in ipairs(results) do
      if v:sub(1, 1) == "d" then
        table.insert(sorted_results, v)
        table.insert(sorted_sections, sections[k])
      end
    end
    for k, v in ipairs(results) do
      if v:sub(1, 1) ~= "d" then
        table.insert(sorted_results, v)
        table.insert(sorted_sections, sections[k])
      end
    end
    return sorted_results, sorted_sections
  end
  return results, sections
end

-- List directory contents. Will always apply --long option.  Use scan_dir for without --long
---@param path string
---@param opts? { hidden: boolean, add_dirs?: boolean, respect_gitignore: boolean, depth?: integer, group_directories_first: boolean }
---@return table
function m.ls(path, opts)
  opts = opts or {}
  opts.depth = opts.depth or 1
  opts.add_dirs = opts.add_dirs or true
  return (gen_ls(m.scan_dir(path, opts), path, opts))
end

---List directory contents. Will always apply --long option. Use scan_dir for without --long
---@param path string
---@param opts? { hidden: boolean, add_dirs?: boolean, respect_gitignore: boolean, depth?: integer, group_directories_first: boolean, on_exit: fun(...: any) }
function m.ls_async(path, opts)
  opts = opts or {}
  opts.depth = opts.depth or 1
  opts.add_dirs = opts.add_dirs or true

  local opts_copy = vim.deepcopy(opts)
  opts_copy.on_exit = function(data)
    if opts.on_exit then
      opts.on_exit(gen_ls(data, path, opts_copy))
    end
  end

  m.scan_dir_async(path, opts_copy)
end

return m

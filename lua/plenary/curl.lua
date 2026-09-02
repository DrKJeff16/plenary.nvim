--[[
Curl Wrapper

all curl methods accepts

  url          = "The url to make the request to.", (string)
  query        = "url query, append after the url", (table)
  body         = "The request body" (string/filepath/table)
  auth         = "Basic request auth, 'user:pass', or {"user", "pass"}" (string/array)
  form         = "request form" (table)
  raw          = "any additonal curl args, it must be an array/list." (array)
  dry_run      = "whether to return the args to be ran through curl." (boolean)
  output       = "where to download something." (filepath)
  timeout      = "request timeout in mseconds" (number)
  http_version = "HTTP version to use: 'HTTP/0.9', 'HTTP/1.0', 'HTTP/1.1', 'HTTP/2', or 'HTTP/3'" (string)
  proxy        = "[protocol://]host[:port] Use this proxy" (string)
  insecure     = "Allow insecure server connections" (boolean)

and returns table:

  exit    = "The shell process exit code." (number)
  status  = "The https response status." (number)
  headers = "The https response headers." (array)
  body    = "The http response body." (string)

see test/plenary/curl_spec.lua for examples.

author = github.com/tami5
--]]

local uv = vim.uv or vim.loop

local util, parse = {}, {}

-- Helpers --------------------------------------------------
-------------------------------------------------------------
local F = require("plenary.functional")
local J = require("plenary.job")
local P = require("plenary.path")
local compat = require("plenary.compat")

-- Utils ----------------------------------------------------
-------------------------------------------------------------

---@param str string|number
---@return string|number str
function util.url_encode(str)
  if type(str) ~= "number" then
    str = str
      :gsub("\r?\n", "\r\n")
      :gsub("([^%w%-%.%_%~ ])", function(c)
        return ("%%%02X"):format(c:byte())
      end)
      :gsub(" ", "+")
  end
  return str
end

---@param kv table
---@param sep string
---@param prefix string
---@return table list
function util.kv_to_list(kv, prefix, sep)
  return compat.flatten(F.kv_map(function(kvp) ---@param kvp string[]
    return { prefix, kvp[1] .. sep .. kvp[2] }
  end, kv))
end

---@param kv table
---@param sep? string
---@param kvsep string
function util.kv_to_str(kv, sep, kvsep)
  return F.join(
    F.kv_map(function(kvp)
      return kvp[1] .. kvsep .. util.url_encode(kvp[2])
    end, kv),
    sep
  )
end

function util.gen_dump_path()
  local id = ("xxxx4xxx"):gsub("[xy]", function(l)
    local v = (l == "x") and math.random(0, 0xf) or math.random(0, 0xb)
    return ("%x"):format(v)
  end)

  return {
    "-D",
    P.path.sep == "\\" and ("%s\\AppData\\Local\\Temp\\plenary_curl_%s.headers"):format(os.getenv("USERPROFILE"), id)
      or (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/plenary_curl_" .. id .. ".headers",
  }
end

-- Parsers ----------------------------------------------------
---------------------------------------------------------------

---@param str string
---@return string upper
local function upper(str)
  return (" %s"):format(str):gsub("%W%l", string.upper):sub(2)
end

---@param t? table
---@return table|nil headers
function parse.headers(t)
  return t
      and util.kv_to_list(
        (function()
          local normilzed = {}
          for k, v in pairs(t) do
            normilzed[upper(k:gsub("_", "%-"))] = v
          end
          return normilzed
        end)(),
        "-H",
        ": "
      )
    or nil
end

---@param t? table
---@return table|nil body
function parse.data_body(t)
  return t and util.kv_to_list(t, "-d", "=") or nil
end

---@param xs? any
---@return table|nil
function parse.raw_body(xs)
  if not xs then
    return
  end
  return type(xs) == "table" and parse.data_body(xs) or { "--data-raw", xs }
end

---@param t? table
---@return table|nil form
function parse.form(t)
  return t and util.kv_to_list(t, "-F", "=") or nil
end

---@param t? table
---@return table|nil query
function parse.curl_query(t)
  return t and util.kv_to_str(t, "&", "=") or nil
end

---@param s? string
---@return string[]|nil method
function parse.method(s)
  return s and (s ~= "head" and { "-X", s:upper() } or { "-I" }) or nil
end

---@return table|nil file
function parse.file(p)
  return p and { "-d", "@" .. P.expand(P.new(p)) } or nil
end

---@return string[]|nil auth
function parse.auth(xs)
  return xs and { "-u", type(xs) == "table" and util.kv_to_str(xs, nil, ":") or xs } or nil
end

function parse.url(xs, q)
  if not xs then
    return
  end
  q = parse.curl_query(q)
  if type(xs) == "string" then
    return q and xs .. "?" .. q or xs
  elseif type(xs) == "table" then
    error("Low level URL definition is not supported.")
  end
end

---@param s? string
---@return string[]|nil header
function parse.accept_header(s)
  return s and { "-H", "Accept: " .. s } or nil
end

---@param s? string
---@return string[]|nil version
function parse.http_version(s)
  if not s then
    return
  end
  if s == "HTTP/0.9" or s == "HTTP/1.0" or s == "HTTP/1.1" or s == "HTTP/2" or s == "HTTP/3" then
    return { "--" .. s:lower():gsub("/", "") }
  end
  error("Unknown HTTP version.")
end

-- Parse Request -------------------------------------------
------------------------------------------------------------
parse.request = function(opts)
  if opts.body then
    local b = opts.body
    local silent_is_file = function()
      local status, result = pcall(P.is_file, P.new(b))
      return status and result
    end
    opts.body = nil
    if type(b) == "table" then
      opts.data = b
    elseif silent_is_file() then
      opts.in_file = b
    elseif type(b) == "string" then
      opts.raw_body = b
    end
  end
  local result = { "-sSL", opts.dump }
  local append = function(v)
    if v then
      table.insert(result, v)
    end
  end

  if opts.insecure then
    table.insert(result, "--insecure")
  end
  if opts.proxy then
    table.insert(result, { "--proxy", opts.proxy })
  end
  if opts.compressed then
    table.insert(result, "--compressed")
  end
  append(parse.method(opts.method))
  append(parse.headers(opts.headers))
  append(parse.accept_header(opts.accept))
  append(parse.raw_body(opts.raw_body))
  append(parse.data_body(opts.data))
  append(parse.form(opts.form))
  append(parse.file(opts.in_file))
  append(parse.auth(opts.auth))
  append(parse.http_version(opts.http_version))
  append(opts.raw)
  if opts.output then
    table.insert(result, { "-o", opts.output })
  end
  table.insert(result, parse.url(opts.url, opts.query))
  return compat.flatten(result), opts
end

-- Parse response ------------------------------------------
------------------------------------------------------------
parse.response = function(lines, dump_path, code)
  local headers = P.readlines(dump_path)
  local status = nil
  local processed_headers = {}

  -- Process headers in a single pass
  for _, line in ipairs(headers) do
    local status_match = line:match("^HTTP/%S*%s+(%d+)")
    if status_match then
      status = tonumber(status_match)
    elseif line ~= "" then
      table.insert(processed_headers, line)
    end
  end

  local body = F.join(lines, "\n")
  uv.fs_unlink(dump_path)

  return {
    status = status or 0,
    headers = processed_headers,
    body = body,
    exit = code,
  }
end

local request = function(specs)
  local response = {}
  local args, opts = parse.request(vim.tbl_extend("force", {
    compressed = package.config:sub(1, 1) ~= "\\",
    dry_run = false,
    dump = util.gen_dump_path(),
  }, specs))

  if opts.dry_run then
    return args
  end

  local job_opts = {
    command = vim.g.plenary_curl_bin_path or "curl",
    args = args,
  }

  if opts.stream then
    job_opts.on_stdout = opts.stream
  end

  job_opts.on_exit = function(j, code)
    if code ~= 0 then
      local stderr = vim.inspect(j:stderr_result())
      local message = string.format("%s %s - curl error exit_code=%s stderr=%s", opts.method, opts.url, code, stderr)
      if opts.on_error then
        return opts.on_error({
          message = message,
          stderr = stderr,
          exit = code,
        })
      else
        error(message)
      end
    end
    local output = parse.response(j:result(), opts.dump[2], code)
    if opts.callback then
      return opts.callback(output)
    else
      response = output
    end
  end
  local job = J:new(job_opts)

  if opts.callback or opts.stream then
    job:start()
    return job
  else
    local timeout = opts.timeout or 10000
    job:sync(timeout)
    return response
  end
end

-- Main ----------------------------------------------------
------------------------------------------------------------
return (function()
  local partial = function(method)
    return function(url, opts)
      local spec = {}
      opts = opts or {}
      if type(url) == "table" then
        opts = url
        spec.method = method
      else
        spec.url = url
        spec.method = method
      end
      opts = method == "request" and opts or (vim.tbl_extend("keep", opts, spec))
      return request(opts)
    end
  end
  return {
    get = partial("get"),
    post = partial("post"),
    put = partial("put"),
    head = partial("head"),
    patch = partial("patch"),
    delete = partial("delete"),
    request = partial("request"),
  }
end)()

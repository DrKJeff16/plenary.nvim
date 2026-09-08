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

---@class plenary.CurlResult
---@field body string
---@field exit integer
---@field headers string[]
---@field status number

---@class plenary.CurlOpts
---@field accept? string
---@field auth? string[]|string
---@field body? string[]|string
---@field compressed? boolean
---@field method? string
---@field headers? table<string, string>
---@field data? string[]|string
---@field on_stdout? function
---@field on_error? function
---@field callback? function
---@field stream? function
---@field dry_run? boolean
---@field dump? string[]|string
---@field form? string[]
---@field http_version? 'HTTP/0.9'|'HTTP/1.0'|'HTTP/1.1'|'HTTP/2'|'HTTP/3'
---@field in_file? string
---@field insecure? boolean
---@field output? string
---@field proxy? string
---@field query? table<string, string>
---@field raw? string[]
---@field raw_body? string
---@field timeout? integer
---@field url? string

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

---@param str string|integer
---@return string|integer str
function util.url_encode(str)
  if type(str) == "string" then
    return (
      str
        :gsub("\r?\n", "\r\n")
        :gsub("([^%w%-%.%_%~ ])", function(c)
          return ("%%%02X"):format(c:byte())
        end)
        :gsub(" ", "+")
    )
  end
  return str
end

---@generic T: table
---@param kv T
---@param sep string
---@param prefix string
---@return string[] list
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
    return ("%x"):format(math.random(0, l == "x" and 0xf or 0xb))
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

---@param t? table<string, string>
---@return string[]|nil|? headers
function parse.headers(t)
  return t
      and util.kv_to_list(
        (function()
          local normilzed = {} ---@type table<string, string>
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

---@param t? string[]
---@return string[]|nil|? body
function parse.data_body(t)
  return t and util.kv_to_list(t, "-d", "=") or nil
end

---@param xs? string[]|string
---@return string[]|nil|? raw_body
function parse.raw_body(xs)
  return xs and (type(xs) == "table" and parse.data_body(xs) or { "--data-raw", xs }) or nil
end

---@param t? string[]
---@return string[]|nil|? form
function parse.form(t)
  return t and util.kv_to_list(t, "-F", "=") or nil
end

---@param t? string[]
---@return string[]|nil|? query
function parse.curl_query(t)
  return t and util.kv_to_str(t, "&", "=") or nil
end

---@param s? string
---@return string[]|nil|? method
function parse.method(s)
  return s and (s ~= "head" and { "-X", s:upper() } or { "-I" }) or nil
end

---@param p? string
---@return string[]|nil|? file
function parse.file(p)
  return p and { "-d", "@" .. P:new(p):expand() } or nil
end

---@param xs string[]|string
---@return string[]|nil|? auth
function parse.auth(xs)
  return xs and { "-u", type(xs) == "table" and util.kv_to_str(xs, nil, ":") or xs } or nil
end

---@param xs string
---@param q string[]
---@return string|nil|? url
function parse.url(xs, q)
  if xs then
    q = parse.curl_query(q)
    if type(xs) == "string" then
      return q and (xs .. "?" .. q) or xs
    end
    if type(xs) == "table" then
      error("Low level URL definition is not supported.")
    end
  end
end

---@param s string
---@return string[]|nil|? header
---@overload fun(): header: nil
---@overload fun(s: nil): header: nil
---@overload fun(s: string): string[]
function parse.accept_header(s)
  return s and { "-H", "Accept: " .. s } or nil
end

---@param s? string
---@return string[]|nil|? version
function parse.http_version(s)
  if not s then
    return
  end
  if s == "HTTP/0.9" or s == "HTTP/1.0" or s == "HTTP/1.1" or s == "HTTP/2" or s == "HTTP/3" then
    return { ("--" .. s:lower():gsub("/", "")) }
  end
  error("Unknown HTTP version.")
end

---@param opts plenary.CurlOpts
---@return string[]|string request
---@return plenary.CurlOpts opts
function parse.request(opts)
  if opts.body then
    local b = opts.body

    ---@return boolean is_file
    local function silent_is_file()
      local obj = P.new(b)
      local status, result = pcall(obj.is_file, obj)
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
  local result = { "-sSL", opts.dump } ---@type string[][]|string[]

  ---@param v? string[]|string
  local function append(v)
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
  local request = compat.flatten(result) --[[@as string[]|string]]
  return request, opts
end

-- Parse response ------------------------------------------
------------------------------------------------------------
---@param lines string[]
---@param dump_path plenary.Path|string
---@param code integer
---@return plenary.CurlResult result
function parse.response(lines, dump_path, code)
  local headers = P.readlines(dump_path)
  local status = nil ---@type integer|nil|?
  local processed_headers = {} ---@type string[]

  -- Process headers in a single pass
  for _, line in ipairs(headers) do
    local status_match = line:match("^HTTP/%S*%s+(%d+)") --[[@as string|nil|?]]
    if status_match then
      status = tonumber(status_match, 10)
    elseif line ~= "" then
      table.insert(processed_headers, line)
    end
  end

  local body = F.join(lines, "\n")
  uv.fs_unlink(dump_path)

  return { ---@type plenary.CurlResult
    body = body,
    exit = code,
    headers = processed_headers,
    status = status or 0,
  }
end

---@param specs plenary.CurlOpts
---@return Job|string[]
local function request(specs)
  local response = {} ---@type string[]
  local args, opts = parse.request(
    vim.tbl_extend(
      "force",
      { compressed = package.config:sub(1, 1) ~= "\\", dry_run = false, dump = util.gen_dump_path() },
      specs
    )
  )

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

  ---@param j Job
  ---@param code integer
  function job_opts.on_exit(j, code)
    if code ~= 0 then
      local stderr = vim.inspect(j:stderr_result())
      local message = ("%s %s - curl error exit_code=%s stderr=%s"):format(opts.method, opts.url, code, stderr)
      if opts.on_error then
        return opts.on_error({ exit = code, message = message, stderr = stderr })
      end
      error(message)
    end

    local output = parse.response(j:result(), opts.dump[2], code)
    if opts.callback then
      return opts.callback(output)
    end
    response = output
  end

  local job = J:new(job_opts)
  if opts.callback or opts.stream then
    job:start()
    return job
  end

  job:sync(opts.timeout or 10000)
  return response
end

-- Main ----------------------------------------------------
------------------------------------------------------------

local function partial(method)
  ---@param url string[]|string
  ---@param opts? plenary.CurlOpts
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

---@return { delete: string[]|Job, get: string[]|Job, head: string[]|Job, patch: string[]|Job, post: string[]|Job, put: string[]|Job, request: string[]|Job }
return function()
  return {
    delete = partial("delete"),
    get = partial("get"),
    head = partial("head"),
    patch = partial("patch"),
    post = partial("post"),
    put = partial("put"),
    request = partial("request"),
  }
end

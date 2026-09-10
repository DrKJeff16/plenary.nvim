---@class plenary.Profile
local M = {}

---start profiling using LuaJIT profiler
---@param out? string name and path of log file
---@param opts? { flame?: boolean }
function M.start(out, opts)
  out = out or "profile.log"
  opts = opts or {}
  local popts = "10,i1,s,m0"
  if opts.flame then
    popts = popts .. ",G"
  end
  require("plenary.profile.p").start(popts, out)
end

---stop profiling
M.stop = require("plenary.profile.p").stop

---@generic V
---@param iterations integer
---@param f fun(...: V)
---@param ... V
---@return number time
function M.benchmark(iterations, f, ...)
  local uv = vim.uv or vim.loop
  local start_time = uv.hrtime()
  for _ = 1, iterations do
    f(...)
  end
  return (uv.hrtime() - start_time) / 1E9
end

return M

local uv = vim.uv or vim.loop

local stat = require("plenary.benchmark.stat")

---@param results number[]
---@return { max: number, mean: number, median: number, std: number }
local function get_stats(results)
  local ret = {}

  ret.max, ret.min = stat.maxmin(results)
  ret.mean = stat.mean(results)
  ret.median = stat.median(results)
  ret.std = stat.std_dev(results)

  return ret
end

local get_output = function(index, res, runs)
  -- divine with a sutable one / 1e3, 1e6, 1e9
  local time_types = { "ns", "μs", "ms" }

  local get_leading = function(time)
    time = math.floor(time)
    local count = 0
    repeat
      time = math.floor(time / 10)
      count = count + 1
    until time <= 0
    return count
  end

  local get_best_fmt = function(time)
    for _, v in ipairs(time_types) do
      if math.abs(time) < 1000.0 then
        return ("%s%3.1f %s"):format((" "):rep(3 - get_leading(time)), time, v)
      end
      time = time / 1000.0
    end
    return ("%.1f %s"):format(time, "s")
  end

  return ("Benchmark #%d: '%s'\n  Time(mean ± σ):    %s ± %s\n  Range(min … max):  %s … %s  %d runs\n"):format(
    index,
    res.name,
    get_best_fmt(res.stats.mean),
    get_best_fmt(res.stats.std),
    get_best_fmt(res.stats.min),
    get_best_fmt(res.stats.max),
    runs
  )
end

local get_summary = function(res)
  if #res == 1 then
    return ""
  end

  local fastest_mean = math.huge
  local fastest_index = 1
  for i, benchmark in ipairs(res) do
    if benchmark.stats.mean < fastest_mean then
      fastest_mean = benchmark.stats.mean
      fastest_index = i
    end
  end

  if fastest_mean == math.huge then
    return ""
  end

  local output = {}
  local fastest = res[fastest_index].stats
  for i, benchmark in ipairs(res) do
    if i ~= fastest_index then
      local result = benchmark.stats
      local ratio = result.mean / fastest.mean

      -- // https://en.wikipedia.org/wiki/Propagation_of_uncertainty#Example_formulas
      -- // Covariance asssumed to be 0, i.e. variables are assumed to be independent
      local ratio_std = ratio
        * math.sqrt(math.pow(result.std / result.mean, 2) + math.pow(fastest.std / fastest.mean, 2))

      table.insert(output, ("  %.1f ± %.1f times faster than '%s'\n"):format(ratio, ratio_std, benchmark.name))
    end
  end

  return ("Summary\n  '%s' ran\n%s"):format(res[fastest_index].name, table.concat(output, ""))
end

---@class benchmark_run_opts
---@field warmup number @number of initial runs before starting to track time.
---@field runs number @number of runs to make
---@field fun table<table<string, function>> @functions to execute

---Benchmark a function
---@param name string @benchmark name
---@param opts benchmark_run_opts
local function bench(name, opts)
  vim.validate({
    opts = { opts, "table" },
    fun = { opts.fun, "table" },
  })
  opts.warmup = vim.nonnil(opts.warmup, 3)
  opts.runs = vim.nonnil(opts.runs, 5)

  opts.fun = type(opts.fun) == "function" and { opts.fun } or opts.fun
  local output = { ("Benchmark Group: '%s' -----------------------\n"):format(name) }
  local res = {}
  for i, fun in ipairs(opts.fun) do
    res[i] = { name = fun[1], results = {} }
    for _ = 1, opts.warmup do
      fun[2]()
    end
    for j = 1, opts.runs do
      local start = uv.hrtime()
      fun[2]()
      res[i].results[j] = uv.hrtime() - start
    end
    res[i].stats = get_stats(res[i].results)
    table.insert(output, get_output(i, res[i], opts.runs))
  end

  print(("%s\n%s"):format(table.concat(output, ""), get_summary(res)))

  return res
end

return bench

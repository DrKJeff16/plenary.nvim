---@alias plenary.Fun.Wrapper fun(fn: plenary.Fun.Wrapper): wrapper: plenary.Fun.Wrapper

---@class plenary.Fun
local M = {}

M.bind = require("plenary.functional").partial

---@param fn fun(...: any)
---@param argc integer
function M.arify(fn, argc)
  return function(...)
    if select("#", ...) ~= argc then
      error(("Expected %s number of arguments"):format(argc))
    end

    fn(...)
  end
end

---@param map plenary.Fun.Wrapper
---@return plenary.Fun.Wrapper wrapper
function M.create_wrapper(map)
  return function(to_wrap)
    return function(...)
      return map(to_wrap(...))
    end
  end
end

return M

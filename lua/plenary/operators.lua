---@brief [[
---Operators that are functions.
---This is useful when you want to pass operators to higher order functions.
---Lua has no currying so we have to make a function for each operator.
---@brief ]]

---@class plenary.Operators
local M = {}

function M.lt(a, b)
  return a < b
end

function M.le(a, b)
  return a <= b
end

function M.eq(a, b)
  return a == b
end

function M.ne(a, b)
  return a ~= b
end

function M.ge(a, b)
  return a >= b
end

function M.gt(a, b)
  return a > b
end

function M.add(a, b)
  return a + b
end

function M.div(a, b)
  return a / b
end

function M.floordiv(a, b)
  return math.floor(a / b)
end

function M.intdiv(a, b)
  return a >= 0 and math.floor(a / b) or math.ceil(a / b)
end

function M.mod(a, b)
  return a % b
end

function M.mul(a, b)
  return a * b
end

function M.neq(a)
  return -a
end

M.unm = M.neq

function M.pow(a, b)
  return a ^ b
end

function M.sub(a, b)
  return a - b
end

function M.truediv(a, b)
  return a / b
end

function M.concat(a, b)
  return a .. b
end

function M.len(a)
  return #a
end

M.length = M.len

function M.land(a, b)
  return a and b
end

function M.lor(a, b)
  return a or b
end

function M.lnot(a)
  return not a
end

function M.truth(a)
  return not not a
end

return M

---@class plenary.Functional
local M = {}

---@generic K, V
---@param t table<K, V>
---@return { [1]: K, [2]: V }[] pairs
function M.kv_pairs(t)
  local results = {}
  for k, v in pairs(t) do
    table.insert(results, { k, v })
  end
  return results
end

---@generic K, V
---@param fun fun(value: { [1]: K, [2]: V }): any
---@param t table<K, V>
---@return table map
function M.kv_map(fun, t)
  return vim.tbl_map(fun, M.kv_pairs(t))
end

---@param array any[]
---@param sep string
---@return string str
function M.join(array, sep)
  return table.concat(vim.tbl_map(tostring, array), sep)
end

---@generic T
---@param fn fun(a: T, ...: any): any
---@param n integer
---@param a T
---@param ... any
---@return fun(...: any): fun(a: T, ...: any)
local function bind_n(fn, n, a, ...)
  return n == 0 and fn or bind_n(function(...)
    return fn(a, ...)
  end, n - 1, ...)
end

---@param fun function
---@param ... any
---@return fun(...: any): fun(a: any, ...: any)
function M.partial(fun, ...)
  return bind_n(fun, select("#", ...), ...)
end

---@param fun fun(k: string|integer, v: any): boolean
---@param iterable table
---@return boolean any
function M.any(fun, iterable)
  for k, v in pairs(iterable) do
    if fun(k, v) then
      return true
    end
  end

  return false
end

---@param fun fun(k: string|integer, v: any): boolean
---@param iterable table
---@return boolean all
function M.all(fun, iterable)
  for k, v in pairs(iterable) do
    if not fun(k, v) then
      return false
    end
  end

  return true
end

---@generic T, V
---@param val any
---@param was_nil T
---@param was_not_nil V
---@return T|V res
function M.if_nil(val, was_nil, was_not_nil)
  return val == nil and was_nil or was_not_nil
end

---@param n integer
---@return fun(...: any): x: any
function M.select_only(n)
  return function(...)
    local x = select(n, ...)
    return x
  end
end

M.first = M.select_only(1)
M.second = M.select_only(2)
M.third = M.select_only(3)

---@param ... any
---@return any x
function M.last(...)
  return select(select("#", ...), ...)
end

return M

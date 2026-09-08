---@class plenary.Functional
local f = {}

---@generic K, V
---@param t table<K, V>
---@return { [1]: K, [2]: V }[] pairs
function f.kv_pairs(t)
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
function f.kv_map(fun, t)
  return vim.tbl_map(fun, f.kv_pairs(t))
end

---@param array any[]
---@param sep string
---@return string str
function f.join(array, sep)
  return table.concat(vim.tbl_map(tostring, array), sep)
end

---@generic T
---@param fn fun(a: any, ...: any): any
---@param n integer
---@param a T
---@param ... any
---@return fun(...: any): fun(a: any, ...: any)
local function bind_n(fn, n, a, ...)
  if n == 0 then
    return fn
  end
  return bind_n(function(...)
    return fn(a, ...)
  end, n - 1, ...)
end

---@param fun function
---@param ... any
---@return fun(...: any): fun(a: any, ...: any)
function f.partial(fun, ...)
  return bind_n(fun, select("#", ...), ...)
end

---@param fun fun(k: string|integer, v: any): boolean
---@param iterable table
---@return boolean any
function f.any(fun, iterable)
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
function f.all(fun, iterable)
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
function f.if_nil(val, was_nil, was_not_nil)
  return val == nil and was_nil or was_not_nil
end

---@param n integer
---@return fun(...: any): x: any
function f.select_only(n)
  return function(...)
    local x = select(n, ...)
    return x
  end
end

f.first = f.select_only(1)
f.second = f.select_only(2)
f.third = f.select_only(3)

---@param ... any
---@return any x
function f.last(...)
  local length = select("#", ...)
  local x = select(length, ...)
  return x
end

return f

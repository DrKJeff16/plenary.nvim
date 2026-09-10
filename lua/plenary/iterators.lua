---@class plenary.Iterators: Iterator
local M = {}

---@generic R
---@class Iterator
---@field gen fun(param: string, state: integer): result: R
---@field param string
---@field partition? fun(predicate: function): list1: List, list2: List
---@field state integer
---@overload fun(param: string, state: integer): result: R
local Iterator = {}

Iterator.__index = Iterator

---Makes a for loop work
---If not called without param or state, will just generate with the starting state
---This is useful because the original luafun will also return param and state in addition to the iterator as a multival
---This can cause problems because when using iterators as expressions the multivals can bleed
---For example i.iter { 1, 2, i.iter { 3, 4 } } will not work because the inner iterator returns a multival thus
---polluting the list with internal values.
---So instead we do not return param and state as multivals when doing wrap
---This causes the first loop iteration to call param and state with nil because we didn't return them as multivals
---We have to use or to check for nil and default to interal starting state and param
---@generic R
---@param param? string
---@param state? integer
---@return R result
function Iterator:__call(param, state)
  return self.gen(param or self.param, state or self.state)
end

---@return string str
function Iterator:__tostring()
  return "<iterator>"
end

-- A special hack for zip/chain to skip last two state, if a wrapped iterator
-- has been passed
---@param ... any
---@return integer nargs
local function numargs(...)
  local n = select("#", ...) --[[@as integer]]
  if n >= 3 then
    local it = select(n - 2, ...) -- Fix last argument
    if
      type(it) == "table"
      and getmetatable(it) == Iterator
      and it.param == select(n - 1, ...)
      and it.state == select(n, ...)
    then
      return n - 2
    end
  end
  return n
end

---@param state_x? integer
---@param ... any
local function return_if_not_empty(state_x, ...)
  if state_x ~= nil then
    return ...
  end
end

---@param fun fun(...: any): result: boolean|nil
---@param state_x? integer
---@param ... any
---@return integer|nil|? state_x
---@return boolean|nil|? res
local function call_if_not_empty(fun, state_x, ...)
  if state_x == nil then
    return state_x, fun(...)
  end
end

--------------------------------------------------------------------------------
-- Basic Functions
--------------------------------------------------------------------------------

local function nil_gen() end

local pairs_gen = pairs({})

---@generic K, V
---@param map table<K, V>
---@param key K
---@return K key
---@return K key
---@return any value
local function map_gen(map, key)
  local value
  key, value = pairs_gen(map, key)
  return key, key, value
end

---@param param string
---@param state integer
---@return integer|nil|? state
---@return string|nil|? str
local function string_gen(param, state)
  state = state + 1
  if state > param:len() then
    return
  end
  return state, param:sub(state, state)
end

---@param obj { gen: function, param: string, state: integer }|string|fun(param: string, state: integer)
---@param param? string
---@param state? integer
---@return { gen: function, param: string, state: integer }|string|fun(param: string, state: integer) obj
---@return { gen: function, param: string, state: integer }|string|fun(param: string, state: integer)|nil|? param_or_obj
---@return integer|nil|? state
local function rawiter(obj, param, state)
  assert(obj ~= nil, "invalid iterator")

  if type(obj) == "table" then
    local mt = getmetatable(obj)
    if mt and mt == Iterator then
      return obj.gen, obj.param, obj.state
    end
    if require("plenary.compat").islist(obj) then
      return (ipairs(obj))
    end
    return map_gen, obj -- hash
  end
  if type(obj) == "function" then
    return obj, param, state
  end
  if type(obj) == "string" then
    if obj:len() == 0 then
      return nil_gen
    end
    return string_gen, obj, 0
  end

  error(('object %s of type "%s" is not iterable'):format(obj, type(obj)))
end

---Create an iterator from an object
---@param obj any
---@param param? string (optional)
---@param state? integer (optional)
---@return Iterator
function M.iter(obj, param, state)
  return M.wrap(rawiter(obj, param, state))
end

---Wraps the iterator triplet into a table to allow metamethods and calling with method form
---Important! We do not return param and state as multivals like the original luafun
---See the __call metamethod for more information
---@param gen function|table
---@param param? any
---@param state? integer|{ [1]: integer|(fun(param: string, state: integer): result: integer), [2]: string, [3]: integer }
---@return Iterator iterator
function M.wrap(gen, param, state)
  return setmetatable({ gen = gen, param = param, state = state }, Iterator)
end

function M:unwrap()
  return self.gen, self.param, self.state
end

---@param fn function
function Iterator:for_each(fn)
  local param, state = self.param, self.state
  repeat
    state = call_if_not_empty(fn, self.gen(param, state))
  until state == nil
end

function Iterator:stateful()
  return M.wrap(
    coroutine.wrap(function()
      self:for_each(function(...)
        coroutine.yield(require("plenary.functional").first(...), ...)
      end)

      -- too make sure that we always return nil if there are no more
      while true do
        coroutine.yield()
      end
    end),
    nil,
    nil
  )
end

---@param param integer[]
---@param state integer
---@return integer|nil|? state
---@return integer|nil|? state
local function range_gen(param, state)
  state = state + param[2]
  if state <= param[1] then
    return state, state
  end
end

---@param param integer[]
---@param state integer
---@return integer|nil|? state
---@return integer|nil|? state
local function range_rev_gen(param, state)
  state = state + param[2]
  if state < param[1] then
    return
  end
  return state, state
end

---Creates a range iterator
---@param start integer
---@param stop? integer
---@param step? integer
---@return Iterator|fun(...: any)|nil|?
function M.range(start, stop, step)
  if not step then
    if not stop then
      if start == 0 then
        return nil_gen
      end
      stop = start
      start = stop > 0 and 1 or -1
    end
    step = start <= stop and 1 or -1
  end

  assert(type(start) == "number", "start must be a number")
  assert(type(stop) == "number", "stop must be a number")
  assert(type(step) == "number", "step must be a number")
  assert(step ~= 0, "step must not be zero")

  if step > 0 then
    return M.wrap(range_gen, { stop, step }, start - step)
  end
  if step < 0 then
    return M.wrap(range_rev_gen, { stop, step }, start - step)
  end
end

---@param param_x table
---@param state_x integer
local function duplicate_table_gen(param_x, state_x)
  return state_x + 1, unpack(param_x)
end

---@param param_x fun(state: integer): any
---@param state_x integer
local function duplicate_fun_gen(param_x, state_x)
  return state_x + 1, param_x(state_x)
end

---@generic P
---@param param_x P
---@param state_x integer
---@return integer state_x
---@return P param_x
local function duplicate_gen(param_x, state_x)
  return state_x + 1, param_x
end

---Creates an infinite iterator that will yield the arguments
---If multiple arguments are passed, the args will be packed and unpacked
---@param ... any: the arguments to duplicate
---@return Iterator iterator
function M.duplicate(...)
  return select("#", ...) <= 1 and M.wrap(duplicate_gen, select(1, ...), 0) or M.wrap(duplicate_table_gen, { ... }, 0)
end

---Creates an iterator from a function
---NOTE: if the function is a closure and modifies state, the resulting iterator will not be stateless
---
---@param fun function
---@return Iterator iterator
function M.from_fun(fun)
  assert(type(fun) == "function")
  return M.wrap(duplicate_fun_gen, fun, 0)
end

---Creates an infinite iterator that will yield zeros.
---This is an alias to calling duplicate(0)
---@return Iterator iterator
function M.zeros()
  return M.wrap(duplicate_gen, 0, 0)
end

---Creates an infinite iterator that will yield ones.
---This is an alias to calling duplicate(1)
---@return Iterator iterator
function M.ones()
  return M.wrap(duplicate_gen, 1, 0)
end

---@param param_x { [1]: integer, [2]: integer }
local function rands_gen(param_x, _)
  return 0, math.random(param_x[1], param_x[2])
end

local function rands_nil_gen(_, _)
  return 0, math.random()
end

---Creates an infinite iterator that will yield random values.
---@param n? integer
---@param m? integer
---@return Iterator
function M.rands(n, m)
  if not (n or m) then
    return M.wrap(rands_nil_gen, 0, 0)
  end
  assert(type(n) == "number", "invalid first arg to rands")
  if not m then
    m = n
    n = 0
  else
    assert(type(m) == "number", "invalid second arg to rands")
  end
  assert(n < m, "empty interval")
  return M.wrap(rands_gen, { n, m - 1 }, 0)
end

---@param param { [1]: string, [2]: string }
---@param state integer
local function split_gen(param, state)
  local input, sep = param[1], param[2]
  local input_len = input:len()
  if state > input_len + 1 then
    return
  end

  local start, finish = input:find(sep, state, true)
  if not start then
    start = input_len + 1
    finish = input_len + 1
  end

  return finish + 1, input:sub(state, start - 1)
end

---Return an iterator of substrings separated by a string
---@param input string: the string to split
---@param sep string: the separator to find and split based on
---@return Iterator iterator
function M.split(input, sep)
  return M.wrap(split_gen, { input, sep }, 1)
end

---Splits a string based on a single space
---An alias for split(input, " ")
---@param input string
---@return Iterator iterator
function M.words(input)
  return M.split(input, " ")
end

---@param input string
---@return Iterator iterator
function M.lines(input)
  -- TODO: platform specific linebreaks
  return M.split(input, "\n")
end

--------------------------------------------------------------------------------
-- Transformations
--------------------------------------------------------------------------------
local function map_gen2(param, state)
  local gen_x, param_x, fun = param[1], param[2], param[3]
  return call_if_not_empty(fun, gen_x(param_x, state))
end

---Iterator adapter that maps the previous iterator with a function
---@param fun function: The function to map with. Will be called on each element
---@return Iterator iterator
function Iterator:map(fun)
  return M.wrap(map_gen2, { self.gen, self.param, fun }, self.state)
end

local flatten_gen1
do
  ---@param new_iter Iterator
  ---@param state_x? integer
  ---@return Iterator|nil|? iterator
  ---@return ...
  local function it(new_iter, state_x, ...)
    if not state_x then
      return
    end
    return { new_iter.gen, new_iter.param, state_x }, ...
  end

  ---@param state table
  ---@param state_x? integer
  ---@param ... any
  ---@return Iterator|nil|?
  ---@return ...
  function flatten_gen1(state, state_x, ...)
    if not state_x then
      return
    end

    local first_arg = require("plenary.functional").first(...)
    if getmetatable(first_arg) == Iterator then -- experimental part
      local new_iter = (first_arg .. M.wrap(state[1], state[2], state_x)):flatten() -- attach the iterator to the rest
      return it(new_iter, new_iter.gen(new_iter.param, new_iter.state)) -- advance the iterator by one
    end
    return { state[1], state[2], state_x }, ...
  end
end

---@param _ boolean
---@param state? { [1]: (fun(param: string, state: integer): result: integer), [2]: string, [3]: integer }
---@return Iterator|nil|? iterator
---@return ...
local function flatten_gen(_, state)
  if state then
    return flatten_gen1(state, state[1](state[2], state[3]))
  end
end

---Iterator adapter that will recursivley flatten nested iterator structure
---@return Iterator iterator
function Iterator:flatten()
  return M.wrap(flatten_gen, false, { self.gen, self.param, self.state })
end

--------------------------------------------------------------------------------
-- Filtering
--------------------------------------------------------------------------------

---@generic A, T, V, R
---@param fun fun(...: any): res: boolean
---@param gen_x fun(param: string, state: integer): result: R
---@param param_x T
---@param state_x V
---@param a A
---@return V state_x
---@return A a
local function filter1_gen(fun, gen_x, param_x, state_x, a)
  while true do
    if not state_x or fun(a) then
      break
    end
    state_x, a = gen_x(param_x, state_x)
  end
  return state_x, a
end

-- call each other
-- because we can't assign a vararg mutably in a while loop like filter1_gen
-- so we have to use recursion in calling both of these functions
local filterm_gen
local function filterm_gen_shrink(fun, gen_x, param_x, state_x)
  return filterm_gen(fun, gen_x, param_x, gen_x(param_x, state_x))
end

---@param fun fun(...: any): res: boolean
filterm_gen = function(fun, gen_x, param_x, state_x, ...)
  if not state_x then
    return
  end
  if fun(...) then
    return state_x, ...
  end

  return filterm_gen_shrink(fun, gen_x, param_x, state_x)
end

local function filter_detect(fun, gen_x, param_x, state_x, ...)
  if select("#", ...) < 2 then
    return filter1_gen(fun, gen_x, param_x, state_x, ...)
  end
  return filterm_gen(fun, gen_x, param_x, state_x, ...)
end

local function filter_gen(param, state_x)
  local gen_x, param_x, fun = param[1], param[2], param[3]
  return filter_detect(fun, gen_x, param_x, gen_x(param_x, state_x))
end

---Iterator adapter that will filter values
---@param fun function: The function to filter values with. If the function returns true, the value will be kept.
---@return Iterator
function Iterator:filter(fun)
  return M.wrap(filter_gen, { self.gen, self.param, fun }, self.state)
end

---Iterator adapter that will provide numbers from 1 to n as the first multival
---@return Iterator iterator
function Iterator:enumerate()
  local i = 0
  return self:map(function(...)
    i = i + 1
    return i, ...
  end)
end

--------------------------------------------------------------------------------
-- Reducing
--------------------------------------------------------------------------------

---Returns true if any of the values in the iterator satisfy a predicate
---@param fun function
---@return boolean any
function Iterator:any(fun)
  local r
  local state, param, gen = self.state, self.param, self.gen
  repeat
    state, r = call_if_not_empty(fun, gen(param, state))
  until state == nil or r
  return r
end

---Returns true if all of the values in the iterator satisfy a predicate
---@param fun function
---@return boolean all
function Iterator:all(fun)
  local r
  local state, param, gen = self.state, self.param, self.gen
  repeat
    state, r = call_if_not_empty(fun, gen(param, state))
  until state == nil or not r
  return state == nil
end

---Finds a value that is equal to the provided value of satisfies a predicate.
---@param val_or_fn any
---@return any
function Iterator:find(val_or_fn)
  local gen, param, state = self.gen, self.param, self.state
  if type(val_or_fn) == "function" then
    return return_if_not_empty(filter_detect(val_or_fn, gen, param, gen(param, state)))
  end

  for _, r in gen, param, state do
    if r == val_or_fn then
      return r
    end
  end
end

---Folds an iterator into a single value using a function.
---@param init any
---@param fun fun(acc: any, val: any): any
---@return any fold
function Iterator:fold(init, fun)
  local acc = init
  local gen, param, state = self.gen, self.param, self.state
  for _, r in gen, param, state do
    acc = fun(acc, r)
  end
  return acc
end

---Turns an iterator into a list.
---If the iterator yields multivals only the first multival will be used.
---@return table list
function Iterator:tolist()
  local list = {}
  self:for_each(function(a)
    table.insert(list, a)
  end)
  return list
end

---Turns an iterator into a list.
---If the iterator yields multivals all multivals will be used and packed into a table.
---@return table n_list
function Iterator:tolistn()
  local list = {}
  self:for_each(function(...)
    table.insert(list, { ... })
  end)
  return list
end

---Turns an iterator into a map.
---The first multival that the iterator yields will be the key.
---The second multival that the iterator yields will be the value.
---@return table map
function Iterator:tomap()
  local map = {}
  self:for_each(function(key, value)
    map[key] = value
  end)
  return map
end

--------------------------------------------------------------------------------
-- Compositions
--------------------------------------------------------------------------------
-- call each other
local chain_gen_r1
local chain_gen_r2 = function(param, state, state_x, ...)
  if state_x == nil then
    local i = state[1] + 1
    if param[3 * i - 1] == nil then
      state_x = param[3 * i]
      return chain_gen_r1(param, { i, state_x })
    end
  end
  return { state[1], state_x }, ...
end

chain_gen_r1 = function(param, state)
  local i, state_x = state[1], state[2]
  local gen_x, param_x = param[3 * i - 2], param[3 * i - 1]
  return chain_gen_r2(param, state, gen_x(param_x, state_x))
end

---Make an iterator that returns elements from the first iterator until it is exhausted,
---then proceeds to the next iterator,
---until all of the iterators are exhausted.
---Used for treating consecutive iterators as a single iterator.
---Infinity iterators are supported, but are not recommended.
---@param ... any: the iterators to chain
---@return Iterator
function Iterator.chain(...)
  local n = numargs(...)
  if n == 0 then
    return M.wrap(nil_gen)
  end

  local param = { [3 * n] = 0 } ---@type table<integer, integer|function|string>

  for i = 1, n, 1 do
    local elem = select(i, ...)
    local gen_x, param_x, state_x = M.unwrap(elem)
    param[3 * i - 2] = gen_x
    param[3 * i - 1] = param_x
    param[3 * i] = state_x
  end

  return M.wrap(chain_gen_r1, param, { 1, param[3] })
end

Iterator.__concat = Iterator.chain

M.chain = Iterator.chain

local function zip_gen_r(param, state, state_new, ...)
  if #state_new == #param / 2 then
    return state_new, ...
  end

  local i = #state_new + 1
  local gen_x, param_x = param[2 * i - 1], param[2 * i]
  local state_x, r = gen_x(param_x, state[i])
  if state_x == nil then
    return
  end
  table.insert(state_new, state_x)
  return zip_gen_r(param, state, state_new, r, ...)
end

local function zip_gen(param, state)
  return zip_gen_r(param, state, {})
end

---Return a new iterator where i-th return value contains the i-th element from each of the iterators.
---The returned iterator is truncated in length to the length of the shortest iterator.
---For multi-return iterators only the first variable is used.
---@param ... any: the iterators to zip
---@return Iterator
function Iterator.zip(...)
  local n = numargs(...)
  if n == 0 then
    return M.wrap(nil_gen)
  end

  local param = { [2 * n] = 0 } ---@type table<integer, integer|function|string>
  local state = { [n] = 0 } ---@type table<integer, integer>
  for i = 1, n, 1 do
    local it = select(n - i + 1, ...)
    local gen_x, param_x, state_x = rawiter(it)
    param[2 * i - 1] = gen_x
    param[2 * i] = param_x
    state[i] = state_x
  end

  return M.wrap(zip_gen, param, state)
end

Iterator.__div = Iterator.zip

M.zip = Iterator.zip

return M

--- This module defines an idiomatic way to create enum classes, similar to
--- those in java or kotlin. There are two ways to create an enum, one is with
--- the exported `make_enum` function, or calling the module directly with the
--- enum spec.
---
--- The enum spec consists of a list-like table whose members can be either a
--- string or a tuple of the form {string, number}. In the former case, the enum
--- member will take the next available value, while in the latter, the member
--- will take the string as it's name and the number as it's value. In both
--- cases, the name must start with a capital letter.
---
--- Here is an example:
---
--- <pre>
--- local Enum = require 'plenary.enum'
--- local myEnum = Enum {
---     'Foo',          -- Takes value 1
---     'Bar',          -- Takes value 2
---     {'Qux', 10},    -- Takes value 10
---     'Baz',          -- Takes value 11
--- }
--- </pre>
---
--- In case of name or value clashing, the call will fail. For this reason, it's
--- best if you define the members in ascending order.
---@class plenary.EnumType
local Enum = {}

---@alias Enum table<integer, { value: integer }|string>

---@class Variant

---@param name string
---@return string|nil name
local function validate_member_name(name)
  if name ~= "" and name:sub(1, 1):match("%u") then
    return name
  end
  error(('"%s" should start with a capital letter'):format(name))
end

---@param i integer
---@param mt_variant table
---@return { value: integer } variant
local function newVariant(i, mt_variant)
  return setmetatable({ value = i }, mt_variant)
end

local Variant = {}
Variant.__index = Variant

-- we don't need __eq because the __eq metamethod will only ever be
-- invoked when they both have the same metatable

function Variant:__lt(o)
  return self.value < o.value
end

function Variant:__gt(o)
  return self.value > o.value
end

function Variant:__tostring()
  return tostring(self.value)
end

---@param e Enum
---@param i integer
---@return integer|nil index
local function find_next_idx(e, i)
  if not e[i + 1] then
    return i + 1
  end
  error("Overlapping index: " .. tostring(i + 1))
end

---@param tbl table
---@return Enum: A new enum
local function make_enum(tbl)
  local enum = {} ---@type Enum
  local i = 0

  for _, v in ipairs(tbl) do
    if type(v) == "string" then
      local name = validate_member_name(v)
      if not name then
        error("Invalid member name!")
      end

      local idx = find_next_idx(enum, i)
      if not idx then
        error("Invalid index value!")
      end
      enum[idx] = name
      if enum[name] then
        error("Duplicate enum member name: " .. name)
      end
      enum[name] = newVariant(idx, Variant)
      i = idx
    elseif type(v) == "table" and type(v[1]) == "string" and type(v[2]) == "number" then
      local name = validate_member_name(v[1])
      if not name then
        error("Invalid member name!")
      end
      local idx = v[2] --[[@as integer]]
      if enum[idx] then
        error("Overlapping index: " .. tostring(idx))
      end
      enum[idx] = name
      if enum[name] then
        error("Duplicate name: " .. name)
      end
      enum[name] = newVariant(idx, Variant)
      i = idx
    else
      error("Invalid way to specify an enum variant")
    end
  end

  return require("plenary.tbl").freeze(setmetatable(enum, Enum))
end

---Checks whether the enum has a member with the given name
---@param key string: The element to check for
---@return boolean has: True if key is present
function Enum:has_key(key)
  if rawget(getmetatable(self).__index, key) then
    return true
  end
  return false
end

---If there is a member named 'key', return it, otherwise return nil
---@param key string: The element to check for
---@return Variant|nil variant: The element named by key, or nil if not present
function Enum:from_str(key)
  if self:has_key(key) then
    return self[key]
  end
end

---If there is a member of value 'num', return it, otherwise return nil
---@param num number: The value of the element to check for
---@return Variant|nil variant: The element whose value is num
function Enum:from_num(num)
  if self[num] then
    return self[self[num]]
  end
end

--- @param tbl table: The object to be checked
--- @return boolean enum: True if tbl is an Enum
local function is_enum(tbl)
  return getmetatable(getmetatable(tbl).__index) == Enum
end

---@class plenary.Enum : plenary.EnumType
---Checks whether the given object corresponds to an instance of Enum
--- ---
---@field is_enum fun(tbl: table): enum: boolean
---Creates an enum from the given list-like table, like so:
---<pre>
---local enum = Enum.make_enum{
---    'Foo',
---    'Bar',
---    {'Qux', 10}
---}
---</pre>
---@field make_enum fun(tbl: table): enum: Enum
---@overload fun(tbl: table): enum: table<integer, string|{ value: integer }>
return setmetatable({ is_enum = is_enum, make_enum = make_enum }, {
  ---@param key string
  __index = function(_, key)
    if Enum[key] then
      return Enum[key]
    end
    error("Invalid enum key: " .. tostring(key))
  end,
  __call = function(_, tbl) ---@param tbl table
    return make_enum(tbl)
  end,
})

---@brief [[
---classic
---
---Copyright (c) 2014, rxi
---@brief ]]

---@class Object
local M = {}
M.__index = M

---Does nothing.
---You have to implement this yourself for extra functionality when initializing
---@param ... any
function M:new(...) end

---Create a new class/object by extending the base Object class.
---The extended object will have a field called `super` that will access the super class.
---@return Object cls
function M:extend()
  local cls = {}
  for k, v in pairs(self) do
    if k:find("__") == 1 then
      cls[k] = v
    end
  end
  cls.__index = cls
  cls.super = self
  setmetatable(cls, self)
  return cls
end

---Implement a mixin onto this Object.
---@param ... any
function M:implement(...)
  for _, cls in pairs({ ... }) do
    ---@cast cls table<string, function>
    for k, v in pairs(cls) do
      if not self[k] and type(v) == "function" then
        self[k] = v
      end
    end
  end
end

---Checks if the object is an instance
---This will start with the lowest class and loop over all the superclasses.
---@param T Object
---@return boolean is
function M:is(T)
  local mt = getmetatable(self)
  while mt do
    if mt == T then
      return true
    end
    mt = getmetatable(mt)
  end
  return false
end

---The default tostring implementation for an object.
---You can override this to provide a different tostring.
---@return string str
function M:__tostring()
  return "Object"
end

---You can call the class the initialize it without using `Object:new`.
---@param ... any
---@return Object obj
function M:__call(...)
  local obj = setmetatable({}, self)
  obj:new(...)
  return obj
end

return M

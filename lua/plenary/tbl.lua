---@class plenary.Tbl
local M = {}

---@generic T: table
---@param original? table
---@param defaults T
---@return T original
function M.apply_defaults(original, defaults)
  original = original or {}
  for k, v in pairs(defaults) do
    if not original[k] then
      original[k] = v
    end
  end
  return original
end

---@param ... any
---@return table|{ n: integer } packed_tbl
function M.pack(...)
  return { n = select("#", ...), ... }
end

---@param t table|{ n: integer }
---@param i? integer
---@param j? integer
function M.unpack(t, i, j)
  return unpack(t, i or 1, j or t.n or #t)
end

---Freeze a table. A frozen table is not able to be modified.
---http://lua-users.org/wiki/ReadOnlyTables
---@generic T: table
---@param t T
---@return T t
function M.freeze(t)
  return setmetatable({}, {
    __index = t,
    __newindex = function()
      error("Attempt to modify frozen table")
    end,
  })
end

return M

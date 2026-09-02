---@class plenary.Reload
local M = {}

---@param module_name string
function M.reload_module(module_name, starts_with_only)
  -- Default to starts with only
  if starts_with_only == nil then
    starts_with_only = true
  end

  -- TODO: Might need to handle cpath / compiled lua packages? Not sure.
  --
  ---@param pack string
  ---@return integer|nil|?
  local function matcher(pack)
    if not starts_with_only then
      return (pack:find(module_name, 1, true))
    end
    return (pack:find("^" .. vim.pesc(module_name)))
  end

  -- Handle impatient.nvim automatically.
  local luacache = (_G.__luacache or {}).cache
  for pack in pairs(package.loaded) do
    ---@cast pack string
    if matcher(pack) then
      package.loaded[pack] = nil

      if luacache then
        luacache[pack] = nil
      end
    end
  end
end

return M

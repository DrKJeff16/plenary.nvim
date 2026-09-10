---@class plenary.Reload
local M = {}

-- TODO: Might need to handle cpath / compiled lua packages? Not sure.
--
---@param starts_with_only boolean
---@param module_name string
---@param pack string
---@return integer|nil|? match
local function matcher(starts_with_only, module_name, pack)
  return starts_with_only and (pack:find("^" .. vim.pesc(module_name))) or (pack:find(module_name, 1, true))
end

---@param module_name string
---@param starts_with_only boolean
function M.reload_module(module_name, starts_with_only)
  -- Default to starts with only
  if starts_with_only == nil then
    starts_with_only = true
  end

  ---Handle impatient.nvim automatically.
  ---@diagnostic disable-next-line:undefined-field
  local luacache = (_G.__luacache or {}).cache --[[@as table<string, any>|nil|?]]
  for pack in pairs(package.loaded) do
    ---@cast pack string
    if matcher(starts_with_only, module_name, pack) then
      package.loaded[pack] = nil
      if luacache then
        luacache[pack] = nil
      end
    end
  end
end

return M

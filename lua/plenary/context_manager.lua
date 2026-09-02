--- I like context managers for Python
--- I want them in Lua.

---@class plenary.ContextManager
local context_manager = {}

---@param obj function|thread|table
function context_manager.with(obj, callable)
  -- Wrap functions for people since we're nice
  if type(obj) == "function" then
    obj = coroutine.create(obj)
  elseif type(obj) == "thread" then
    local ok, context = coroutine.resume(obj)
    assert(ok, "Should have yielded in coroutine.")

    local succeeded, result = pcall(callable, context)
    local done = coroutine.resume(obj)
    assert(done, "Should be done")
    assert(not coroutine.resume(obj), "Should not yield anymore, otherwise that would make things complicated")
    assert(succeeded, result)
    return result
  end

  assert(obj.enter)
  assert(obj.exit)

  -- TODO: Callable can be string for vimL function or a lua callable
  local succeeded, result = pcall(callable, obj:enter())
  obj:exit()

  assert(succeeded, result)
  return result
end

--- @param filename string|{ filename: string } -- If string, used as `io.open(filename)`. Else, should be a table with `filename` as an attribute
--- @param mode openmode
function context_manager.open(filename, mode)
  if type(filename) == "table" and filename.filename then
    filename = filename.filename
  end

  local file_io = assert(io.open(filename, mode))
  return coroutine.create(function()
    coroutine.yield(file_io)
    file_io:close()
  end)
end

return context_manager

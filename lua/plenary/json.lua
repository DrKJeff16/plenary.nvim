-- based on https://github.com/sindresorhus/strip-json-comments

local singleComment = "singleComment"
local multiComment = "multiComment"
local function stripWithoutWhitespace()
  return ""
end

local function slice(str, from, to)
  from = from or 1
  to = to or #str
  return str:sub(from, to)
end

local function stripWithWhitespace(str, from, to)
  return slice(str, from, to):gsub("%S", " ")
end

local function isEscaped(json_string, quotePosition)
  local index = quotePosition - 1
  local backslashCount = 0
  while json_string:sub(index, index) == "\\" do
    index = index - 1
    backslashCount = backslashCount + 1
  end
  return backslashCount % 2 == 1 and true or false
end

---@class plenary.Json
local M = {}

-- Strips any json comments from a json string.
-- The resulting string can then be used by `vim.fn.json_decode`
--
---@param json_string string
---@param options? { whitespace?: boolean, trailing_commas?: boolean }
---@return string json_data
function M.json_strip_comments(json_string, options)
  options = options or {}
  local strip = options.whitespace == false and stripWithoutWhitespace or stripWithWhitespace
  local omitTrailingCommas = not options.trailing_commas

  local insideString = false
  local insideComment = false ---@type boolean|string
  local offset = 1
  local result = ""
  local skip = false
  local lastComma = 0

  for i = 1, #json_string, 1 do
    if skip then
      skip = false
    else
      local currentCharacter = json_string:sub(i, i)
      local nextCharacter = json_string:sub(i + 1, i + 1)
      if not insideComment and currentCharacter == '"' and not isEscaped(json_string, i) then
        insideString = not insideString
      end

      if not insideString then
        if not insideComment and currentCharacter .. nextCharacter == "//" then
          result = result .. slice(json_string, offset, i - 1)
          offset = i
          insideComment = singleComment
          skip = true
        elseif insideComment == singleComment and currentCharacter .. nextCharacter == "\r\n" then
          i = i + 1
          skip = true
          insideComment = false
          result = result .. strip(json_string, offset, i - 1)
          offset = i
        elseif insideComment == singleComment and currentCharacter == "\n" then
          insideComment = false
          result = result .. strip(json_string, offset, i - 1)
          offset = i
        elseif not insideComment and currentCharacter .. nextCharacter == "/*" then
          result = result .. slice(json_string, offset, i - 1)
          offset = i
          insideComment = multiComment
          skip = true
        elseif insideComment == multiComment and currentCharacter .. nextCharacter == "*/" then
          i = i + 1
          skip = true
          insideComment = false
          result = result .. strip(json_string, offset, i)
          offset = i + 1
        elseif omitTrailingCommas and not insideComment then
          if currentCharacter == "," then
            lastComma = i
          elseif (currentCharacter == "]" or currentCharacter == "}") and lastComma > 0 then
            result = result .. slice(json_string, offset, lastComma - 1) .. slice(json_string, lastComma + 1, i)
            offset = i + 1
            lastComma = 0
          elseif currentCharacter:match("%S") then
            lastComma = 0
          end
        end
      end
    end
  end

  return result .. (insideComment and strip(slice(json_string, offset)) or slice(json_string, offset))
end

return M

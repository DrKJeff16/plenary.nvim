---@param str string
---@return string|nil|? fmt_str
return function(str)
  if type(str) ~= "string" then
    return
  end

  local result, i, hex, chr = "Binary string length; " .. tostring(str:len()) .. " bytes\n", 1, "", ""
  while i <= str:len() do
    local byte = str:byte(i)
    hex = ("%s%2x "):format(hex, byte)
    if byte < 32 then
      byte = ("."):byte()
    end
    chr = chr .. string.char(byte) --[[@as string]]
    if math.floor(i / 16) == i / 16 or i == str:len() then
      -- reached end of line
      hex = hex .. (" "):rep(16 * 3 - hex:len())
      chr = chr .. (" "):rep(16 - chr:len())

      result = result
        .. hex:sub(1, 8 * 3)
        .. "  "
        .. hex:sub(8 * 3 + 1, -1)
        .. " "
        .. chr:sub(1, 8)
        .. " "
        .. chr:sub(9, -1)
        .. "\n"

      hex, chr = "", ""
    end
    i = i + 1
  end
  return result
end

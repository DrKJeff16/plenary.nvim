-- Shortcircuit to returning bit if it already exists
if bit then
  return bit
end

--[[

Credit: https://github.com/davidm/lua-bit-numberlua/blob/master/lmod/bit/numberlua.lua

LUA MODULE

  bit.numberlua - Bitwise operations implemented in pure Lua as numbers,
    with Lua 5.2 'bit32' and (LuaJIT) LuaBitOp 'bit' compatibility interfaces.

SYNOPSIS

  local bit = require 'bit.numberlua'
  print(bit.band(0xff00ff00, 0x00ff00ff)) --> 0xffffffff

  -- Interface providing strong (LuaJIT) LuaBitOp 'bit' compatibility
  local bit = require 'plenary.bit'
  assert(bit.tobit(0xffffffff) == -1)

  REMOVED!
  -- Interface providing strong Lua 5.2 'bit32' compatibility
  local bit32 = require 'bit.numberlua'.bit32
  assert(bit32.band(-1) == 0xffffffff)


DESCRIPTION

  This library implements bitwise operations entirely in Lua.
  This module is typically intended if for some reasons you don't want
  to or cannot  install a popular C based bit library like BitOp 'bit' [1]
  (which comes pre-installed with LuaJIT) or 'bit32' (which comes
  pre-installed with Lua 5.2) but want a similar interface.

  This modules represents bit arrays as non-negative Lua numbers. [1]
  It can represent 32-bit bit arrays when Lua is compiled
  with lua_Number as double-precision IEEE 754 floating point.

  The module is nearly the most efficient it can be but may be a few times
  slower than the C based bit libraries and is orders or magnitude
  slower than LuaJIT bit operations, which compile to native code.  Therefore,
  this library is inferior in performane to the other modules.

  The `xor` function in this module is based partly on Roberto Ierusalimschy's
  post in http://lua-users.org/lists/lua-l/2002-09/msg00134.html .

  The included BIT.bit32 and BIT.bit sublibraries aims to provide 100%
  compatibility with the Lua 5.2 "bit32" and (LuaJIT) LuaBitOp "bit" library.
  This compatbility is at the cost of some efficiency since inputted
  numbers are normalized and more general forms (e.g. multi-argument
  bitwise operators) are supported.

STATUS

  WARNING: Not all corner cases have been tested and documented.
  Some attempt was made to make these similar to the Lua 5.2 [2]
  and LuaJit BitOp [3] libraries, but this is not fully tested and there
  are currently some differences.  Addressing these differences may
  be improved in the future but it is not yet fully determined how to
  resolve these differences.

  The BIT.bit32 library passes the Lua 5.2 test suite (bitwise.lua)
  http://www.lua.org/tests/5.2/ .  The BIT.bit library passes the LuaBitOp
  test suite (bittest.lua).  However, these have not been tested on
  platforms with Lua compiled with 32-bit integer numbers.

API

  Module's return

    This table contains functions that aim to provide 100% compatibility
    with the LuaBitOp "bit" library (from LuaJIT).

    bit.tobit(x) --> y
    bit.tohex(x [,n]) --> y
    bit.bnot(x) --> y
    bit.bor(x1 [,x2...]) --> y
    bit.band(x1 [,x2...]) --> y
    bit.bxor(x1 [,x2...]) --> y
    bit.lshift(x, n) --> y
    bit.rshift(x, n) --> y
    bit.arshift(x, n) --> y
    bit.rol(x, n) --> y
    bit.ror(x, n) --> y
    bit.bswap(x) --> y

DEPENDENCIES

  None (other than Lua 5.1 or 5.2).

REFERENCES

  [1] http://lua-users.org/wiki/FloatingPoint
  [2] http://www.lua.org/manual/5.2/
  [3] http://bitop.luajit.org/

LICENSE

  (c) 2008-2011 David Manura.  Licensed under the same terms as Lua (MIT).

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.
  (end license)

  Some modifications by plenary team.

--]]

local M = { _TYPE = "module", _NAME = "bit.numberlua", _VERSION = "0.3.1.20120131" }

local MOD = 2 ^ 32
local MODM = MOD - 1

local function memoize(f)
  local t = setmetatable({}, {
    __index = function(self, k)
      local v = f(k)
      rawset(self, k, v)
      return v
    end,
  })
  return t
end

local function make_bitop_uncached(t, m)
  return function(a, b)
    local res, p = 0, 1
    while a ~= 0 and b ~= 0 do
      local am, bm = a % m, b % m
      res = res + t[am][bm] * p
      a = (a - am) / m
      b = (b - bm) / m
      p = p * m
    end
    res = res + (a + b) * p
    return res
  end
end

local function make_bitop(t)
  local op1 = make_bitop_uncached(t, 2 ^ 1)
  local op2 = memoize(function(a)
    return memoize(function(b)
      return op1(a, b)
    end)
  end)
  return make_bitop_uncached(op2, 2 ^ (t.n or 1))
end

-- ok?  probably not if running on a 32-bit int Lua number type platform
function M.tobit(x)
  return x % 2 ^ 32
end

M.bxor = make_bitop({ [0] = { [0] = 0, [1] = 1 }, [1] = { [0] = 1, [1] = 0 }, n = 4 })

function M.bnot(a)
  return MODM - a
end

function M.band(a, b)
  return ((a + b) - M.bxor(a, b)) / 2
end

function M.bor(a, b)
  return MODM - M.band(MODM - a, MODM - b)
end

function M.rshift(a, disp) -- Lua5.2 insipred
  if disp < 0 then
    return M.lshift(a, -disp)
  end
  return math.floor(a % 2 ^ 32 / 2 ^ disp)
end

function M.lshift(a, disp) -- Lua5.2 inspired
  return disp < 0 and M.rshift(a, -disp) or ((a * 2 ^ disp) % 2 ^ 32)
end

function M.tohex(x, n) -- BitOp style
  n = n or 8
  local up
  if n <= 0 then
    if n == 0 then
      return ""
    end
    up = true
    n = -n
  end
  x = M.band(x, 16 ^ n - 1)
  return ("%0" .. n .. (up and "X" or "x")):format(x)
end

function M.extract(n, field, width) -- Lua5.2 inspired
  return M.band(M.rshift(n, field), 2 ^ (width or 1) - 1)
end

function M.replace(n, v, field, width) -- Lua5.2 inspired
  local mask1 = 2 ^ (width or 1) - 1
  v = M.band(v, mask1) -- required by spec?
  local mask = M.bnot(M.lshift(mask1, field))
  return M.band(n, mask) + M.lshift(v, field)
end

function M.bswap(x) -- BitOp style
  local a = M.band(x, 0xff)
  x = M.rshift(x, 8)
  local b = M.band(x, 0xff)
  x = M.rshift(x, 8)
  local c = M.band(x, 0xff)
  x = M.rshift(x, 8)
  local d = M.band(x, 0xff)
  return M.lshift(M.lshift(M.lshift(a, 8) + b, 8) + c, 8) + d
end

function M.rrotate(x, disp) -- Lua5.2 inspired
  disp = disp % 32
  return M.rshift(x, disp) + M.lshift(M.band(x, 2 ^ disp - 1), 32 - disp)
end

function M.lrotate(x, disp) -- Lua5.2 inspired
  return M.rrotate(x, -disp)
end

M.rol = M.lrotate -- LuaOp inspired
M.ror = M.rrotate -- LuaOp insipred

function M.arshift(x, disp) -- Lua5.2 inspired
  local z = M.rshift(x, disp)
  if x >= 0x80000000 then
    z = z + M.lshift(2 ^ disp - 1, 32 - disp)
  end
  return z
end

function M.btest(x, y) -- Lua5.2 inspired
  return M.band(x, y) ~= 0
end

--
-- Start LuaBitOp "bit" compat section.
--

---@class plenary.Bit: bitlib
M.bit = {} -- LuaBitOp "bit" compatibility

function M.bit.tobit(x)
  x = x % MOD
  if x >= 0x80000000 then
    x = x - MOD
  end
  return x
end

function M.bit.tohex(x, ...)
  return M.tohex(x % MOD, ...)
end

function M.bit.bnot(x)
  return M.bit.tobit(M.bnot(x % MOD))
end

function M.bit.bor(a, b, c, ...)
  if c then
    return M.bit.bor(M.bit.bor(a, b), c, ...)
  end
  if b then
    return M.bit.tobit(M.bor(a % MOD, b % MOD))
  end
  return M.bit.tobit(a)
end

function M.bit.band(a, b, c, ...)
  if c then
    return M.bit_band(M.bit_band(a, b), c, ...)
  end
  if b then
    return M.bit_tobit(M.band(a % MOD, b % MOD))
  end
  return M.bit_tobit(a)
end

function M.bit.bxor(a, b, c, ...)
  if c then
    return M.bit.bxor(M.bit.bxor(a, b), c, ...)
  end
  if b then
    return M.bit.tobit(M.bxor(a % MOD, b % MOD))
  end
  return M.bit.tobit(a)
end

function M.bit.lshift(x, n)
  return M.bit.tobit(M.lshift(x % MOD, n % 32))
end

function M.bit.rshift(x, n)
  return M.bit.tobit(M.rshift(x % MOD, n % 32))
end

function M.bit.arshift(x, n)
  return M.bit.tobit(M.arshift(x % MOD, n % 32))
end

function M.bit.rol(x, n)
  return M.bit.tobit(M.lrotate(x % MOD, n % 32))
end

function M.bit.ror(x, n)
  return M.bit.tobit(M.rrotate(x % MOD, n % 32))
end

function M.bit.bswap(x)
  return M.bit.tobit(M.bswap(x % MOD))
end

return M.bit

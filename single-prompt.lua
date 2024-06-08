-- Copyright (c) 2022,2024 ARATA Mizuki
-- Distributed under MIT License (see LICENSE)

local sk_meta = {}
local function run(c, ...)
  local status, a, b = coroutine.resume(c, ...)
  if status then
    if a == "return" then
      return b
    elseif a == "capture" then
      return b(setmetatable({c=c, done=false}, sk_meta))
    else
      error("unexpected result from coroutine: "..tostring(a))
    end
  else
    error(a)
  end
end
function prompt0(f)
  local c = coroutine.create(function()
    return "return", f()
  end)
  return run(c)
end
function control0(f)
  local command, g = coroutine.yield("capture", f)
  if command == "resume" then
    return g()
  else
    error("unexpected command to coroutine: "..tostring(command))
  end
end
function pushSubCont(subcont, f)
  if subcont.done then
    error("cannot resume continuation multiple times")
  end
  subcont.done = true
  return run(subcont.c, "resume", f)
end
function sk_meta:__call(a)
  return pushSubCont(self, function() return a end)
end
reset = prompt0
function shift(f)
  return control0(function(k)
    return prompt0(function()
      return f(function(x)
        return prompt0(function()
          return k(x)
        end)
      end)
    end)
  end)
end

---

local result = reset(function()
  return 3 * shift(function(k)
    return 1 + k(5)
  end)
end)
print("result1", result) -- 16

local result = reset(function()
  return 1 + shift(function(k)
    -- k = 1 + _
    return 2 * shift(function(l)
      -- l = 2 * _
      return k(l(5))
    end)
  end)
end)
print("result2", result) -- 11

local k = reset(function()
  local f = shift(function(k) return k end)
  return 3 * f()
end)
print("result3", k(function() return 7 end)) -- 21

local k = reset(function()
  local f = shift(function(k) return k end)
  return 3 * f()
end)
print("result4", k(function() return shift(function(l) return 4 end) end)) -- 4

local k = reset(function()
  local f = shift(function(k) return k end)
  return 3 * f()
end)
print("result4", k(function() return shift(function(l) return l(4) end) end)) -- 12

local status, message = pcall(function()
  return reset(function()
    error("Yay")
  end)
end)
print("result5", status, message) -- false, "Yay"

local k = reset(function()
  local status, a = pcall(function()
    local f = shift(function(k) return k end)
    return 3 * f()
  end)
  if status then
    return a
  else
    print("Caught", a)
    local g = shift(function(k) return k end)
    return 7 * g()
  end
end)
print("result6", k(function() return shift(function(l) return 4 end) end)) -- 4

local k = reset(function()
  local status, a = pcall(function()
    local f = shift(function(k) return k end)
    return 3 * f()
  end)
  if status then
    return a
  else
    print("Caught", a)
    local g = shift(function(k) return k end)
    return 7 * g()
  end
end)
print("result7", k(function() return shift(function(l) return l(4) end) end)) -- 12

local k = reset(function()
  local status, a = pcall(function()
    local f = shift(function(k) return k end)
    return 3 * f()
  end)
  if status then
    return a
  else
    print("Caught", a)
    local g = shift(function(k) return k end)
    return 7 * g()
  end
end)
print("result8", k(function() error("Hello") end)) -- function

--[[
C stack overflow:
local function recur(n)
  if n == 0 then
    return "Yes!!!"
  else
    return reset(function()
      return recur(n - 1)
    end)
  end
end
local result = recur(500)
print("Does not consume C stack?", result) -- Yes!!!
]]

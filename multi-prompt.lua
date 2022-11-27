function newPromptTag()
  return {}
end
local sk_meta = {}
local function runWithTag(tag, co, ...)
  local status, a, b, c = coroutine.resume(co, ...)
  if status then
    if a == "return" then
      return b
    elseif a == "capture" then
      -- b: tag
      -- c: callback
      if b == tag then
        return c(setmetatable({co=co, done=false}, sk_meta))
      else
        return runWithTag(tag, co, coroutine.yield("capture", b, c))
      end
    else
      error("unexpected result from the function: "..tostring(a))
    end
  else
    error(a)
  end
end
function pushPrompt(tag, f)
  local co = coroutine.create(function()
    return "return", f()
  end)
  return runWithTag(tag, co)
end
function withSubCont(tag, f)
  local command, a = coroutine.yield("capture", tag, f)
  if command == "resume" then
    return a()
  else
    error("unexpected command to coroutine: "..tostring(command))
  end
end
function pushSubCont(subcont, f)
  if subcont.done then
    error("cannot resume captured continuation multiple times")
  end
  subcont.done = true
  return runWithTag(nil, subcont.co, "resume", f)
end
function sk_meta:__call(a)
  return pushSubCont(self, function() return a end)
end
resetAt = pushPrompt
function shiftAt(tag, f)
  return withSubCont(tag, function(k)
    return pushPrompt(tag, function()
      return f(function(x)
        return pushPrompt(tag, function()
          return k(x)
        end)
      end)
    end)
  end)
end

---

local tag = newPromptTag()
local function reset(f)
  return resetAt(tag, f)
end
local function shift(f)
  return shiftAt(tag, f)
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

---

local tagX = newPromptTag()
local function resetX(f)
  return resetAt(tagX, f)
end
local function shiftX(f)
  return shiftAt(tagX, f)
end

local tagY = newPromptTag()
local function resetY(f)
  return resetAt(tagY, f)
end
local function shiftY(f)
  return shiftAt(tagY, f)
end

local k = resetX(function()
  return 1 + resetY(function()
    return 3 * shiftX(function(k) return k end)
  end)
end)
print("result9", k(5)) -- 16

local k = resetX(function()
  return 1 + resetY(function()
    local a = shiftX(function(k) return k end)
    assert(a == 5)
    local b = shiftY(function(k) return k end)
    assert(b == 3)
    return a * b
  end)(3)
end)
print("result10", k(5)) -- 16

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

function newPromptTag()
  return {}
end
function pushPrompt(tag, f)
  local co = coroutine.create(function()
    return "return", f()
  end)
  local status, a = coroutine.yield("prompt", tag, co)
  if status then
    return a
  else
    error(a)
  end
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
  local slice = subcont.slice
  subcont.slice = nil
  local status, a = coroutine.yield("push-subcont", slice, f)
  if status then
    return a
  else
    error(a)
  end
end
local sk_meta = {}
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

function pcallX(f)
  local co = coroutine.create(function()
    return "return", f()
  end)
  local success, result = coroutine.yield("handle", co)
  return success, result
end

function runMain(f)
  local co = coroutine.create(function()
    return "return", f()
  end)
  local stack = {{co, nil}}
  -- stack[i][1]: coroutine, stack[i][2]: prompt tag or nil
  local values = {}
  while true do
    ::continue::
    local status, a, b, c = coroutine.resume(stack[#stack][1], table.unpack(values))
    if status then
      if a == "return" then
        if #stack == 1 then
          return b
        else
          table.remove(stack)
          values = {true, b}
        end
      elseif a == "handle" then
        -- b: the new coroutine
        table.insert(stack, {b, nil})
        values = {}
      elseif a == "prompt" then
        -- b: tag
        -- c: the new coroutine
        table.insert(stack, {c, b})
        values = {}
      elseif a == "capture" then
        -- b: tag
        -- c: callback
        for i = #stack, 1, -1 do
          if stack[i][2] == b then
            local slice = {}
            table.move(stack, i, #stack, 1, slice)
            -- slice[1], ... = stack[i+1], ..., stack[#stack]
            for j = i, #stack do
              stack[j] = nil
            end
            local subcont = setmetatable({slice=slice, done=false}, sk_meta)
            local co = coroutine.create(function()
              return "return", c(subcont)
            end)
            table.insert(stack, {co, nil})
            values = {}
            goto continue
          end
        end
        error("prompt not found")
      elseif a == "push-subcont" then
        -- b: slice
        -- c: action
        for _, v in ipairs(b) do
          table.insert(stack, v)
        end
        values = {"resume", c}
      else
        error("unexpected result from coroutine: "..tostring(a))
      end
    else
      if #stack == 1 then
        error(a)
      else
        table.remove(stack)
        values = {false, a}
      end
    end
  end
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

runMain(function()
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

  local status, message = pcallX(function()
    return reset(function()
      error("Yay")
    end)
  end)
  print("result5", status, message) -- false, "Yay"

  local k = reset(function()
    local status, a = pcallX(function()
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
    local status, a = pcallX(function()
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
    local status, a = pcallX(function()
      local f = shift(function(k) return k end)
      return 3 * f()
    end)
    if status then
      return a
    else
      print("Caught", a)
      local g = shift(function(k) return k end)
      return 7 * g
    end
  end)
  print("result8", k(function() error("Hello") end)(10)) -- 70
end)

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

runMain(function()
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
end)

runMain(function()
  local result = resetX(function()
    return 1 + resetY(function()
      return 2 + withSubCont(tagX, function(k)
        -- k: 1 + resetY(function() return 2 + _ end)
        return pushSubCont(k, function()
          return withSubCont(tagY, function(l)
            -- l: 2 + _
            return 3 * pushSubCont(l, function()
              return 5
            end)
          end)
        end)
      end)
    end)
  end)
  print("result11", result) -- 1 + 3 * (2 + 5) = 22

  local result = resetY(function()
    return 7 * resetX(function()
      return 2 + withSubCont(tagX, function(k)
        -- k: 2 + _
        return pushSubCont(k, function()
          return withSubCont(tagY, function(l)
            -- l: 7 * (2 + _)
            return 3 + pushSubCont(l, function()
              return 5
            end)
          end)
        end)
      end)
    end)
  end)
  print("result12", result) -- 3 + (7 * (2 + 5)) = 52
end)

---

local result = runMain(function()
  return 42
end)
print("result13", result) -- 42

---

runMain(function()
  local function recur(n)
    if n == 0 then
      return "Yes!!!"
    else
      local success, a = pcallX(function()
        return recur(n - 1)
      end)
      if success then
        return a
      else
        return "error"
      end
    end
  end
  local result = recur(500)
  print("result14", result) -- Yes!!!
end)

runMain(function()
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
  print("result15", result) -- Yes!!!
end)

--[[ Copyright (c) 2026 CorsixTH iOS port contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE. --]]

--! Small JSON encoder and decoder for the native UI bridge.
-- Tables with keys 1..n (and empty tables) become arrays; other tables
-- become objects with string keys. JSON null decodes to nil.
local json = {}

local escapes = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encode_string(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return escapes[c] or ("\\u%04x"):format(c:byte())
  end) .. '"'
end

local function is_array(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

local encode_value

local function encode_table(t, out)
  if is_array(t) then
    out[#out + 1] = "["
    for i, v in ipairs(t) do
      if i > 1 then out[#out + 1] = "," end
      encode_value(v, out)
    end
    out[#out + 1] = "]"
  else
    out[#out + 1] = "{"
    local first = true
    for k, v in pairs(t) do
      if not first then out[#out + 1] = "," end
      first = false
      out[#out + 1] = encode_string(tostring(k))
      out[#out + 1] = ":"
      encode_value(v, out)
    end
    out[#out + 1] = "}"
  end
end

-- CorsixTH's localised strings (_S) are proxy objects; this gets their text.
local has_th, TH = pcall(require, "TH")
local unwrap = has_th and TH.stringProxy and TH.stringProxy._unwrap

encode_value = function(v, out)
  if unwrap and type(v) ~= "string" then
    local text, was_proxy = unwrap(v)
    if was_proxy then
      v = text
    end
  end
  local kind = type(v)
  if kind == "table" then
    encode_table(v, out)
  elseif kind == "string" then
    out[#out + 1] = encode_string(v)
  elseif kind == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      out[#out + 1] = "null"
    elseif math.type and math.type(v) == "float" and v == math.floor(v) and
        math.abs(v) < 2^53 then
      out[#out + 1] = ("%d"):format(v)
    else
      out[#out + 1] = tostring(v)
    end
  elseif kind == "boolean" then
    out[#out + 1] = v and "true" or "false"
  else
    out[#out + 1] = "null"
  end
end

--! The plain text of a string or a CorsixTH localised string (_S).
function json.text(v)
  if unwrap and type(v) ~= "string" then
    local text, was_proxy = unwrap(v)
    if was_proxy then
      return tostring(text)
    end
  end
  return tostring(v)
end

--! Encodes a Lua value as JSON text.
function json.encode(value)
  local out = {}
  encode_value(value, out)
  return table.concat(out)
end

local decode_value

local function skip_space(s, i)
  return s:find("[^ \t\r\n]", i) or #s + 1
end

local function decode_string(s, i)
  -- s:sub(i, i) is the opening quote.
  local out = {}
  i = i + 1
  while true do
    local c = s:sub(i, i)
    if c == "" then
      error("unterminated string")
    elseif c == '"' then
      return table.concat(out), i + 1
    elseif c == "\\" then
      local e = s:sub(i + 1, i + 1)
      local simple = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
      if e == "u" then
        local code = tonumber(s:sub(i + 2, i + 5), 16)
        if not code then error("bad \\u escape") end
        i = i + 6
        -- Surrogate pairs (characters outside the Basic Multilingual Plane).
        if code >= 0xD800 and code <= 0xDBFF and s:sub(i, i + 1) == "\\u" then
          local low = tonumber(s:sub(i + 2, i + 5), 16)
          if low and low >= 0xDC00 and low <= 0xDFFF then
            code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
            i = i + 6
          end
        end
        out[#out + 1] = utf8.char(code)
      else
        out[#out + 1] = simple[e] or e
        i = i + 2
      end
    else
      local j = s:find('["\\]', i) or #s + 1
      out[#out + 1] = s:sub(i, j - 1)
      i = j
    end
  end
end

decode_value = function(s, i)
  i = skip_space(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local t = {}
    i = skip_space(s, i + 1)
    if s:sub(i, i) == "}" then return t, i + 1 end
    while true do
      i = skip_space(s, i)
      if s:sub(i, i) ~= '"' then error("expected a key at " .. i) end
      local key
      key, i = decode_string(s, i)
      i = skip_space(s, i)
      if s:sub(i, i) ~= ":" then error("expected ':' at " .. i) end
      t[key], i = decode_value(s, i + 1)
      i = skip_space(s, i)
      local sep = s:sub(i, i)
      if sep == "}" then return t, i + 1 end
      if sep ~= "," then error("expected ',' or '}' at " .. i) end
      i = i + 1
    end
  elseif c == "[" then
    local t = {}
    i = skip_space(s, i + 1)
    if s:sub(i, i) == "]" then return t, i + 1 end
    while true do
      t[#t + 1], i = decode_value(s, i)
      i = skip_space(s, i)
      local sep = s:sub(i, i)
      if sep == "]" then return t, i + 1 end
      if sep ~= "," then error("expected ',' or ']' at " .. i) end
      i = i + 1
    end
  elseif c == '"' then
    return decode_string(s, i)
  elseif s:sub(i, i + 3) == "true" then
    return true, i + 4
  elseif s:sub(i, i + 4) == "false" then
    return false, i + 5
  elseif s:sub(i, i + 3) == "null" then
    return nil, i + 4
  else
    local number = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if not number or number == "" then error("unexpected '" .. c .. "' at " .. i) end
    return tonumber(number), i + #number
  end
end

--! Decodes JSON text. Returns the value, or nil and an error message.
function json.decode(text)
  local ok, value = pcall(decode_value, text, 1)
  if not ok then
    return nil, value
  end
  return value
end

return json

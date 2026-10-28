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

--! Suggests where a room could go, for Quick Build (lua/quick_build.lua).
-- It only proposes; the engine's room editor (UIEditRoom) has the final say
-- on every outline, door and object, exactly as when the player clicks.

local planner = {}

--! Whether a room may cover this tile. The same rule as is_valid() in
-- CorsixTH's th_lua_map.cpp, which UIEditRoom:setBlueprintRect uses.
function planner.tileOk(app, x, y, player_id)
  local map = app.map
  if x < 1 or y < 1 or x > map.width or y > map.height then
    return false
  end
  local flags = map.th:getCellFlags(x, y)
  return not flags.room and flags.buildable and
      (player_id == 0 or flags.owner == player_id) or false
end

function planner.rectOk(app, x, y, w, h, player_id)
  for ty = y, y + h - 1 do
    for tx = x, x + w - 1 do
      if not planner.tileOk(app, tx, ty, player_id) then
        return false
      end
    end
  end
  return true
end

--! Finds a free outline for the room as close as possible to tile (cx, cy).
-- A size one bigger than the minimum is preferred (room to move the
-- furniture), then the minimum, then two bigger.
function planner.findRect(app, room_type, cx, cy, player_id)
  local min = room_type.minimum_size or 3
  local sizes = { min + 1, min, min + 2 }
  for radius = 0, 20 do
    for _, size in ipairs(sizes) do
      local x0 = cx - math.floor(size / 2)
      local y0 = cy - math.floor(size / 2)
      -- The ring of positions at this distance (Chebyshev) from the centre.
      for dy = -radius, radius do
        for dx = -radius, radius do
          if math.max(math.abs(dx), math.abs(dy)) == radius and
              planner.rectOk(app, x0 + dx, y0 + dy, size, size, player_id) then
            return { x = x0 + dx, y = y0 + dy, w = size, h = size }
          end
        end
      end
    end
  end
  return nil
end

--! Possible doors for an outline, best first. Each is the floor tile inside
-- the room and the wall it is in, as UIEditRoom:setDoorBlueprint takes them.
-- Doors that open onto a corridor come first, nearest the centre (cx, cy).
function planner.doorCandidates(app, rect, cx, cy, player_id)
  local map = app.map.th
  local doors = {}
  local function add(x, y, wall, ox, oy)
    local opens_onto_corridor = false
    if ox >= 1 and oy >= 1 and ox <= app.map.width and oy <= app.map.height then
      local flags = map:getCellFlags(ox, oy)
      opens_onto_corridor = flags.passable and not flags.room and
          (player_id == 0 or flags.owner == player_id)
    end
    doors[#doors + 1] = { x = x, y = y, wall = wall,
      score = (opens_onto_corridor and 0 or 1000) + (ox - cx) ^ 2 + (oy - cy) ^ 2 }
  end
  local x1, y1 = rect.x, rect.y
  local x2, y2 = rect.x + rect.w - 1, rect.y + rect.h - 1
  for x = x1 + 1, x2 - 1 do
    add(x, y1, "north", x, y1 - 1)
    add(x, y2, "south", x, y2 + 1)
  end
  for y = y1 + 1, y2 - 1 do
    add(x1, y, "west", x1 - 1, y)
    add(x2, y, "east", x2 + 1, y)
  end
  table.sort(doors, function(a, b) return a.score < b.score end)
  return doors
end

return planner

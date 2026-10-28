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

--! Quick Build: propose a room, let the player adjust it with native handles,
-- then build it by driving CorsixTH's own room editor (UIEditRoom) through
-- the same steps a player's clicks take. The editor does all the checking,
-- charging and building; if it refuses a step, the player carries on in it
-- by hand.

local json = corsixth.require("ios.json")
local planner = corsixth.require("ios.room_planner")
local SDL = require("sdl")

local QuickBuild = {}
QuickBuild.__index = QuickBuild

-- Furniture placement preferences: higher scores are tried first.
local function far_from_door(rect, door)
  return function(x, y)
    return (x - door.x) ^ 2 + (y - door.y) ^ 2
  end
end

local function against_wall(rect)
  return function(x, y)
    local edge = (x == rect.x or y == rect.y or x == rect.x + rect.w - 1 or
        y == rect.y + rect.h - 1) and 100 or 0
    return edge - ((x - rect.x - rect.w / 2) ^ 2 + (y - rect.y - rect.h / 2) ^ 2) / 100
  end
end

--! Starts a Quick Build of room_type near the middle of the screen. Returns
-- the QuickBuild, or nil and a message for the player.
function QuickBuild.start(native, room_type)
  local app = native.app
  local ui = app.ui
  local hospital = ui.hospital
  local player = hospital:getPlayerIndex()
  local cx, cy = ui:ScreenToWorld(app.config.width / 2, app.config.height / 2)
  local rect = planner.findRect(app, room_type, math.floor(cx), math.floor(cy), player)
  if not rect then
    return nil, ("There's no free space for a %s near here. Move the map to an empty part of " ..
        "your hospital, or place it by hand."):format(json.text(room_type.name))
  end

  local self = setmetatable({}, QuickBuild)
  self.native = native
  self.app = app
  self.ui = ui
  self.room_type = room_type
  self.player = player
  self.rect = rect
  -- CorsixTH's own editor, hidden while the native overlay drives it.
  self.edit = UIEditRoom(ui, room_type)
  ui:addWindow(self.edit)
  self.edit.visible = false
  self.edit:setBlueprintRect(rect.x, rect.y, rect.w, rect.h)
  -- Bring the room into the middle of the screen.
  local sx, sy = app.map:WorldToScreen(rect.x + rect.w / 2, rect.y + rect.h / 2)
  ui:scrollMapTo(sx, sy)
  self:sendOverlay(true)
  return self
end

function QuickBuild:cost()
  local world = self.app.world
  if world.free_build_mode then return 0 end
  return self.ui.hospital.research.research_progress[self.room_type].build_cost
end

--! Whether the engine accepts the outline and the player can build now.
function QuickBuild:isValid()
  return self.edit.confirm_button.enabled and self.app.world.user_actions_allowed and
      (self.app.world.free_build_mode or self.ui.hospital.balance >= self:cost())
end

function QuickBuild:reason()
  if not self.app.world.user_actions_allowed then
    return "Paused"
  elseif not self.edit.confirm_button.enabled then
    return "Can't build here"
  elseif not self.app.world.free_build_mode and self.ui.hospital.balance < self:cost() then
    return "Not enough money"
  end
  return ""
end

--! Sends the overlay (handle positions in game pixels, labels) to the native
-- side when anything it shows has changed.
function QuickBuild:sendOverlay(force)
  if self.building then
    return
  end
  local ui, rect = self.ui, self.rect
  local function corner(x, y)
    local px, py = ui:WorldToScreen(x, y)
    return { px, py }
  end
  local cx, cy = ui:WorldToScreen(rect.x + rect.w / 2, rect.y + rect.h / 2)
  local state = {
    name = json.text(self.room_type.name),
    cost = self.native.formatMoney(self:cost()),
    valid = self:isValid() and true or false,
    reason = self:reason(),
    logical = { self.app.config.width, self.app.config.height },
    -- Corners of the outline on screen: top, right, bottom, left.
    corners = {
      corner(rect.x, rect.y),
      corner(rect.x + rect.w, rect.y),
      corner(rect.x + rect.w, rect.y + rect.h),
      corner(rect.x, rect.y + rect.h),
    },
    centre = { cx, cy },
  }
  local text = json.encode(state)
  if force or text ~= self.overlay_json then
    self.overlay_json = text
    SDL.native.setQuickBuild(text)
  end
end

--! A handle moved to (lx, ly) in game pixels. Handles: "move", or the corner
-- names "top", "right", "bottom", "left".
function QuickBuild:drag(handle, lx, ly, ended)
  if self.building or not self.app.world.user_actions_allowed then
    return
  end
  local wx, wy = self.ui:ScreenToWorld(lx, ly)
  local tx, ty = math.floor(wx), math.floor(wy)
  local r = self.rect
  local min = self.room_type.minimum_size or 3
  local x1, y1, x2, y2 = r.x, r.y, r.x + r.w - 1, r.y + r.h - 1

  if handle == "move" then
    if not self.grab then
      self.grab = { tx - r.x, ty - r.y }
    end
    x1, y1 = tx - self.grab[1], ty - self.grab[2]
    x2, y2 = x1 + r.w - 1, y1 + r.h - 1
  elseif handle == "top" then
    x1, y1 = math.min(tx, x2 - min + 1), math.min(ty, y2 - min + 1)
  elseif handle == "right" then
    x2, y1 = math.max(tx, x1 + min - 1), math.min(ty, y2 - min + 1)
  elseif handle == "bottom" then
    x2, y2 = math.max(tx, x1 + min - 1), math.max(ty, y1 + min - 1)
  elseif handle == "left" then
    x1, y2 = math.min(tx, x2 - min + 1), math.max(ty, y1 + min - 1)
  end
  if ended then
    self.grab = nil
  end
  local map = self.app.map
  if x1 < 1 or y1 < 1 or x2 > map.width or y2 > map.height then
    return
  end
  r.x, r.y, r.w, r.h = x1, y1, x2 - x1 + 1, y2 - y1 + 1
  self.edit:setBlueprintRect(r.x, r.y, r.w, r.h)
  self:sendOverlay(false)
end

--! Leaves the player in CorsixTH's own editor with the outline as it is.
function QuickBuild:byHand(message)
  self.finished = true
  self.edit.visible = true
  SDL.native.setQuickBuild(nil)
  if message then
    self.native:message(message)
  end
end

function QuickBuild:cancel()
  self.finished = true
  SDL.native.setQuickBuild(nil)
  if not self.edit.closed and self.edit.phase == "walls" then
    self.edit:cancel()
  end
end

--! Builds the room: the same steps as a player clicking through the editor.
function QuickBuild:build()
  if self.building or not self:isValid() then
    return
  end
  self.building = true
  SDL.native.setQuickBuild(nil)
  local edit = self.edit

  -- Walls. The editor refuses (and stays in "walls") if the room would cut
  -- off part of the hospital.
  edit:confirm()
  if edit.phase ~= "door" then
    return self:byHand(nil) -- The adviser has said why.
  end

  -- Door: the planner's suggestions, best first, until the editor accepts one.
  local centre_x, centre_y = self.ui:ScreenToWorld(self.app.config.width / 2,
      self.app.config.height / 2)
  local door
  for _, candidate in ipairs(planner.doorCandidates(self.app, self.rect,
      math.floor(centre_x), math.floor(centre_y), self.player)) do
    edit:setDoorBlueprint(candidate.x, candidate.y, candidate.wall)
    if edit.blueprint_door.valid then
      door = candidate
      break
    end
  end
  if not door then
    return self:byHand("Couldn't find a place for the door. Tap a wall to put it there.")
  end
  self.door = door
  edit:confirm(true) -- Door placed: now windows.
  edit:confirm(true) -- No windows: clear the area (people may need to walk out).
  self.waiting_for_objects = true
  self:onTick()
end

-- Places each needed object where the editor accepts it.
function QuickBuild:placeObjects()
  local edit, world, rect = self.edit, self.app.world, self.rect
  local preferences = {
    { id = "desk", score = far_from_door(rect, self.door) },
    { id = "chair", score = far_from_door(rect, self.door) },
    { id = "cabinet", score = against_wall(rect) },
  }
  -- Anything else the room needs goes against a wall, biggest first so the
  -- small things fit around it.
  local others = {}
  for id in pairs(self.room_type.objects_needed) do
    local known = false
    for _, p in ipairs(preferences) do
      if p.id == id then known = true end
    end
    if not known then
      others[#others + 1] = id
    end
  end
  local function footprint_size(id)
    local object = TheApp.objects[id]
    local orientation = object and object.orientations and object.orientations.north
    return orientation and #orientation.footprint or 1
  end
  table.sort(others, function(a, b)
    if footprint_size(a) ~= footprint_size(b) then
      return footprint_size(a) > footprint_size(b)
    end
    return a < b
  end)
  for _, id in ipairs(others) do
    preferences[#preferences + 1] = { id = id, score = against_wall(rect) }
  end

  local tiles = {}
  for y = rect.y, rect.y + rect.h - 1 do
    for x = rect.x, rect.x + rect.w - 1 do
      tiles[#tiles + 1] = { x = x, y = y }
    end
  end

  for _, pref in ipairs(preferences) do
    local needed = self.room_type.objects_needed[pref.id] or 0
    for _ = 1, needed do
      local index
      for i, entry in ipairs(edit.objects) do
        if entry.object.id == pref.id then index = i end
      end
      if not index then
        break
      end
      edit:setActiveIndex(index)
      table.sort(tiles, function(a, b) return pref.score(a.x, a.y) > pref.score(b.x, b.y) end)
      local placed = false
      for _, tile in ipairs(tiles) do
        for _, orientation in ipairs({ "north", "east", "south", "west" }) do
          if edit.objects[edit.active_index].object.orientations[orientation] then
            edit:setOrientation(orientation)
            edit:setBlueprintCell(tile.x, tile.y)
            if edit.object_blueprint_good and
                not world:anyHumanoidObscuringArea(tile.x, tile.y) then
              edit:placeObject()
              placed = true
              break
            end
          end
        end
        if placed then break end
      end
      if not placed then
        return false
      end
    end
  end
  return true
end

--! Called every game tick. Returns true once Quick Build is over.
function QuickBuild:onTick()
  if self.finished then
    return true
  end
  if self.edit.closed or not self.app.world or self.ui ~= self.app.ui then
    -- The editor went away (cancelled from elsewhere, or a game was loaded).
    self.finished = true
    SDL.native.setQuickBuild(nil)
    return true
  end
  if self.waiting_for_objects then
    if self.edit.phase ~= "objects" then
      return false -- Still waiting for people to leave the area.
    end
    self.waiting_for_objects = false
    if self:placeObjects() and self.edit.confirm_button.enabled then
      self.edit:confirm(true) -- Pays and opens the room, as clicking the tick does.
      self.finished = true
      return true
    end
    self:byHand("Couldn't fit all the furniture. Place the rest by hand.")
    return true
  end
  if not self.building then
    self:sendOverlay(false)
  end
  return false
end

return QuickBuild

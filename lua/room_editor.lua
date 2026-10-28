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

--! Native controls for CorsixTH's own room editor (door, windows, furniture)
-- and corridor furnishing.
--
-- The game's windows (UIEditRoom, UIFurnishCorridor, UIPlaceObjects) keep
-- doing all the work; they're just moved off screen. While placing, touches
-- act directly on the map (SDL.native.setPlacementTouch), so the game's own
-- mouse handling places, rotates and picks things up. These sessions add the
-- native bar, wall markers and item tray, and call the game's functions for
-- what those offer.

local json = corsixth.require("ios.json")
local planner = corsixth.require("ios.room_planner")
local SDL = require("sdl")

local OFFSCREEN = -100000

--! Moves one of the game's windows off screen (it keeps working).
local function hide(window)
  if window.x > OFFSCREEN / 2 then
    window.native_saved_x = window.x
  end
  window.x = OFFSCREEN
end

--! Brings a window moved off screen back.
local function unhide(window)
  if window.x <= OFFSCREEN / 2 then
    window.x = window.native_saved_x or 100
  end
end

local function button(id, title, symbol, enabled, prominent)
  return { id = id, title = title, symbol = symbol, enabled = enabled ~= false,
    prominent = prominent or false }
end

-- Rows for the tray's "to place" list from a UIPlaceObjects' list.
local function place_rows(native, window)
  local rows = {}
  for i, entry in ipairs(window.objects or {}) do
    rows[#rows + 1] = {
      index = i,
      name = json.text(entry.object.name),
      qty = entry.qty,
      active = i == window.active_index and window.place_objects ~= false,
      image = native:objectPicture(entry.object),
    }
  end
  return rows
end

-- Rows for the tray's "buy" list from a UIFurnishCorridor.
local function buy_rows(native, furnish)
  local rows = {}
  local hospital = native.app.ui.hospital
  for i, entry in ipairs(furnish.objects or {}) do
    rows[#rows + 1] = {
      index = i,
      name = json.text(entry.object.name),
      qty = entry.qty,
      min = entry.min_qty or 0,
      cost = native.formatMoney(hospital:getObjectBuildCost(entry.object.id)),
      image = native:objectPicture(entry.object),
    }
  end
  return rows
end

-------------------------------------------------------------------------------
-- Room editor

local RoomEditor = {}
RoomEditor.__index = RoomEditor

--! Takes over a UIEditRoom (in the door, windows or objects phase). door is
-- the door already suggested ({x, y, wall}), if any.
function RoomEditor.adopt(native, edit, door)
  local self = setmetatable({}, RoomEditor)
  self.door_choice = door
  self.native = native
  self.app = native.app
  self.ui = native.app.ui
  self.edit = edit
  edit.visible = true
  hide(edit)
  SDL.native.setPlacementTouch(true)
  self:sendState(true)
  return self
end

--! Wall segments of the outline where a door or window could go: every
-- floor tile on the edge (not corners) with the wall it's in.
function RoomEditor:wallSegments()
  local r = self.edit.blueprint_rect
  local segments = {}
  local x1, y1, x2, y2 = r.x, r.y, r.x + r.w - 1, r.y + r.h - 1
  for x = x1 + 1, x2 - 1 do
    segments[#segments + 1] = { x = x, y = y1, wall = "north" }
    segments[#segments + 1] = { x = x, y = y2, wall = "south" }
  end
  for y = y1 + 1, y2 - 1 do
    segments[#segments + 1] = { x = x1, y = y, wall = "west" }
    segments[#segments + 1] = { x = x2, y = y, wall = "east" }
  end
  return segments
end

local wall_midpoints = {
  north = { 0.5, 0 }, south = { 0.5, 1 }, west = { 0, 0.5 }, east = { 1, 0.5 },
}

local function segmentId(seg)
  return ("%d,%d,%s"):format(seg.x, seg.y, seg.wall)
end

--! What each wall segment can be in the windows stage, asked of the game:
-- "window" (has one), "door" (part of the door: no window), "wall" (a window
-- can go here) or "blocked" (it can't: say another wall meets it there).
function RoomEditor:windowOptions()
  local edit = self.edit
  local options = {}
  for _, seg in ipairs(self:wallSegments()) do
    local id = segmentId(seg)
    if edit:windowAt(seg.x, seg.y, seg.wall) then
      options[id] = "window"
    else
      -- The wall piece a window would replace, as setWindowBlueprint finds
      -- it; the door's pieces are tagged (swing doors have three).
      local x, y = seg.x, seg.y
      if seg.wall == "south" then
        y = y + 1
      elseif seg.wall == "east" then
        x = x + 1
      end
      local anim = edit.blueprint_wall_anims[x] and edit.blueprint_wall_anims[x][y]
      local tag = anim and anim:getTag()
      if tag and tag ~= "window" then
        options[id] = "door"
      else
        -- As hovering the mouse there: the game says if a window would fit.
        edit:setWindowBlueprint(seg.x, seg.y, seg.wall)
        options[id] = edit.blueprint_window.valid and "wall" or "blocked"
      end
    end
  end
  edit:setWindowBlueprint(nil, nil, nil)
  return options
end

function RoomEditor:markers()
  local edit, ui = self.edit, self.ui
  local markers = {}
  local door = edit.blueprint_door or {}
  if edit.phase == "windows" then
    -- Windows only change when the player taps a marker (see marker()).
    self.window_options = self.window_options or self:windowOptions()
  else
    self.window_options = nil
  end
  for _, seg in ipairs(self:wallSegments()) do
    local id = segmentId(seg)
    local m = wall_midpoints[seg.wall]
    local sx, sy = ui:WorldToScreen(seg.x + m[1], seg.y + m[2])
    -- Up the wall a little, where the door or window shows.
    sy = sy - 18 * ui.zoom_factor
    local state = "wall"
    if edit.phase == "door" and door.floor_x == seg.x and door.floor_y == seg.y then
      -- (Edge tiles that aren't corners have just the one outer wall.)
      state = door.valid and "door" or "bad"
    elseif edit.phase == "windows" then
      state = self.window_options[id] or "wall"
      -- The door is shown but can't be tapped in this stage.
      if state == "door" then
        state = "door_fixed"
      end
    end
    if state ~= "blocked" then
      markers[#markers + 1] = { id = id, x = sx, y = sy, state = state }
    end
  end
  return markers
end

function RoomEditor:sendState(force)
  local edit = self.edit
  local name = json.text(edit.room_type.name)
  local state = {
    title = name,
    logical = { self.app.config.width, self.app.config.height },
    markers = {},
    buttons = {},
  }
  local phase = edit.phase
  if self.buying then
    state.hint = "Choose extras"
    state.tray = { buy = buy_rows(self.native, self.buying),
      total = self.native.formatMoney(self.buying.total_price or 0), buying = true }
    state.buttons = {
      button("buy_cancel", "Cancel", "xmark"),
      button("buy_done", "Buy", "cart.fill", true, true),
    }
  elseif phase == "door" then
    state.hint = "Tap a wall for the door"
    state.markers = self:markers()
    state.buttons = {
      button("back", "Back", "chevron.left"),
      button("auto_door", "Suggest", "wand.and.stars"),
      button("next", "Next", "chevron.right", edit.blueprint_door and edit.blueprint_door.valid, true),
    }
  elseif phase == "windows" then
    state.hint = "Tap walls to add or remove windows"
    state.markers = self:markers()
    state.buttons = {
      button("back", "Back", "chevron.left"),
      button("next", "Next", "chevron.right", true, true),
    }
  elseif phase == "clear_area" then
    state.hint = "Waiting for people to leave…"
    state.buttons = { button("back", "Back", "chevron.left") }
  elseif phase == "objects" then
    local left = #edit.objects
    state.hint = left > 0 and "Tap the map to place" or
        "Long press an item to move it"
    state.tray = { place = place_rows(self.native, edit), buying = false }
    state.buttons = {
      button("rotate", "Rotate", "rotate.right", left > 0),
      button("place_rest", "Auto", "wand.and.stars", left > 0),
      button("buy", "Extras", "cart"),
      button("done", "Done", "checkmark", edit.confirm_button.enabled, true),
    }
  end
  -- Cancel is always there (first).
  table.insert(state.buttons, 1, button("cancel", nil, "trash"))
  local text = json.encode(state)
  if force or text ~= self.state_json then
    self.state_json = text
    SDL.native.setEditor(text)
  end
end

function RoomEditor:finish()
  self.finished = true
  SDL.native.setEditor(nil)
  SDL.native.setPlacementTouch(false)
end

--! Called every game tick. Returns true once the editor is done with.
function RoomEditor:onTick()
  if self.finished then
    return true
  end
  local edit = self.edit
  if edit.closed or self.ui ~= self.app.ui then
    self:finish()
    return true
  end
  if self.buying and self.buying.closed then
    self.buying = nil
  end
  if edit.phase == "walls" then
    -- Back at the outline: Quick Build's handles take over.
    self:finish()
    self.native.quick_build = corsixth.require("ios.quick_build").adopt(self.native, edit)
    return true
  end
  -- In the door stage the game puts the door where the pointer is, and clears
  -- it when the pointer isn't on a wall. Keep the player's chosen door then.
  local door = edit.blueprint_door
  if edit.phase == "door" and self.door_choice and door and not door.floor_x then
    local c = self.door_choice
    edit:setDoorBlueprint(c.x, c.y, c.wall)
  end
  -- Keep the game's windows off screen (some re-centre themselves).
  if edit.x > OFFSCREEN / 2 then
    hide(edit)
  end
  if self.buying and self.buying.x > OFFSCREEN / 2 then
    hide(self.buying)
  end
  self:sendState(false)
  return false
end

--! The furniture-buying window the editor opened (UIEditRoom:purchaseItems).
function RoomEditor:adoptBuying(window)
  self.buying = window
  hide(window)
  self:sendState(true)
end

function RoomEditor:marker(id)
  local edit = self.edit
  local x, y, wall = tostring(id):match("^(%d+),(%d+),(%a+)$")
  x, y = tonumber(x), tonumber(y)
  if not x or not self.app.world.user_actions_allowed then
    return
  end
  if edit.phase == "door" then
    -- As moving the mouse to the wall.
    edit:setDoorBlueprint(x, y, wall)
    if edit.blueprint_door.valid then
      self.door_choice = { x = x, y = y, wall = wall }
      self.ui:playSound("buildclk.wav")
    end
  elseif edit.phase == "windows" then
    if edit:windowAt(x, y, wall) then
      edit:removeWindowAt(x, y, wall) -- As a right click on it.
    else
      edit:setWindowBlueprint(x, y, wall) -- As moving the mouse there...
      edit:placeWindowBlueprint() -- ...and clicking.
    end
    self.window_options = nil -- Ask the game again.
  end
  self:sendState(true)
end

function RoomEditor:pressed(id)
  local edit = self.edit
  local world = self.app.world
  if id == "cancel" then
    if self.buying then
      self.buying:close()
      self.buying = nil
    end
    -- Step back through the editor until it's gone, as Cancel/Escape does.
    for _ = 1, 6 do
      if edit.closed then break end
      edit:cancel()
    end
    if not edit.closed and edit.phase == "walls" then
      edit:abortRoom()
    end
    self:finish()
    return
  end
  if not world.user_actions_allowed then
    self.native:message("The game is paused.")
    return
  end
  if id == "back" then
    edit:cancel()
  elseif id == "next" then
    if edit.phase == "door" then
      if edit.blueprint_door.valid then
        self.ui:playSound("buildclk.wav")
        edit:confirm(true) -- As clicking the door into place.
      end
    else
      edit:confirm()
    end
  elseif id == "auto_door" then
    local r = edit.blueprint_rect
    local cx, cy = self.ui:ScreenToWorld(self.app.config.width / 2, self.app.config.height / 2)
    for _, c in ipairs(planner.doorCandidates(self.app, r, math.floor(cx), math.floor(cy),
        self.ui.hospital:getPlayerIndex())) do
      edit:setDoorBlueprint(c.x, c.y, c.wall)
      if edit.blueprint_door.valid then
        self.door_choice = c
        break
      end
    end
  elseif id == "rotate" then
    edit:tryNextOrientation()
  elseif id == "place_rest" then
    local door = edit.room and edit.room.door
    local QuickBuild = corsixth.require("ios.quick_build")
    if not QuickBuild.placeRemaining(edit, edit.blueprint_rect,
        door and { x = door.tile_x, y = door.tile_y }) then
      self.native:message("Not everything fits. Place the rest by hand, or move something.")
    end
    edit:checkEnableConfirm()
  elseif id == "buy" then
    edit:purchaseItems() -- Opens the game's buying window, which we adopt.
  elseif id == "buy_done" and self.buying then
    self.buying:confirm()
    self.buying = nil
  elseif id == "buy_cancel" and self.buying then
    self.buying:close()
    self.buying = nil
  elseif id == "done" then
    if edit.confirm_button.enabled then
      edit:confirm()
    end
  end
  self:sendState(true)
end

function RoomEditor:select(index)
  local edit = self.edit
  if edit.objects[index] then
    -- As clicking the item in the list.
    edit.place_objects = true
    if index == edit.active_index then
      edit:nextOrientation()
    else
      edit:setActiveIndex(index)
    end
    if edit.in_pickup_mode then
      edit:stopPickupItems()
    end
  end
  self:sendState(true)
end

function RoomEditor:buy(index, delta)
  if not self.buying then return end
  local ok, message = self.buying:purchaseItem(index, delta)
  if not ok and message then
    self.native:message(json.text(message))
  end
  self:sendState(true)
end

-------------------------------------------------------------------------------
-- Corridor furnishing

local Furnisher = {}
Furnisher.__index = Furnisher

--! Takes over the game's Furnish Corridor window (buying), or a
-- UIPlaceObjects (placing bought or picked-up corridor items).
function Furnisher.adopt(native, window)
  local self = setmetatable({}, Furnisher)
  self.native = native
  self.app = native.app
  self.ui = native.app.ui
  self:take(window)
  return self
end

function Furnisher:take(window)
  self.window = window
  self.placing = class.is(window, UIPlaceObjects)
  hide(window)
  SDL.native.setPlacementTouch(self.placing)
  self:sendState(true)
end

function Furnisher:sendState(force)
  local window = self.window
  local state = {
    title = self.placing and "Place Items" or "Furnish Corridor",
    logical = { self.app.config.width, self.app.config.height },
    markers = {},
  }
  if self.placing then
    local left = #window.objects
    state.hint = left > 0 and "Tap the map to place" or "All placed"
    state.tray = { place = place_rows(self.native, window), buying = false }
    state.buttons = {
      button("cancel", nil, "trash"),
      button("rotate", "Rotate", "rotate.right", left > 0),
      button("done", "Done", "checkmark", true, true),
    }
  else
    state.hint = "Choose items to buy"
    state.tray = { buy = buy_rows(self.native, window),
      total = self.native.formatMoney(window.total_price or 0), buying = true }
    state.buttons = {
      button("cancel", nil, "xmark"),
      button("buy_done", "Buy", "cart.fill", true, true),
    }
  end
  local text = json.encode(state)
  if force or text ~= self.state_json then
    self.state_json = text
    SDL.native.setEditor(text)
  end
end

function Furnisher:finish()
  self.finished = true
  SDL.native.setEditor(nil)
  SDL.native.setPlacementTouch(false)
end

function Furnisher:onTick()
  if self.finished then return true end
  if self.window.closed or self.ui ~= self.app.ui then
    -- Buying done: the game opens a UIPlaceObjects, which NativeUI hands
    -- back to us (adoptPlacing); otherwise we're finished.
    if not self.next_window then
      self:finish()
      return true
    end
    local next_window = self.next_window
    self.next_window = nil
    self:take(next_window)
  end
  if self.window.x > OFFSCREEN / 2 then
    hide(self.window)
  end
  self:sendState(false)
  return false
end

function Furnisher:adoptPlacing(window)
  if self.window.closed then
    self:take(window)
  else
    self.next_window = window
  end
end

function Furnisher:pressed(id)
  local window = self.window
  if id == "cancel" or (id == "done" and self.placing) then
    -- Closing the game's window: unplaced purchases are refunded, as there.
    window:close()
    self:finish()
    return
  end
  if not self.app.world.user_actions_allowed then
    self.native:message("The game is paused.")
    return
  end
  if id == "buy_done" and not self.placing then
    window:confirm()
  elseif id == "rotate" and self.placing then
    window:tryNextOrientation()
  end
  self:sendState(true)
end

function Furnisher:select(index)
  local window = self.window
  if self.placing and window.objects[index] then
    window.place_objects = true
    if index == window.active_index then
      window:nextOrientation()
    else
      window:setActiveIndex(index)
    end
  end
  self:sendState(true)
end

function Furnisher:buy(index, delta)
  if self.placing then return end
  local ok, message = self.window:purchaseItem(index, delta)
  if not ok and message then
    self.native:message(json.text(message))
  end
  self:sendState(true)
end

function Furnisher:marker() end

-------------------------------------------------------------------------------
-- Choosing a room to edit (the game's edit mode, waiting for a tap on a room)

local RoomPicker = {}
RoomPicker.__index = RoomPicker

function RoomPicker.start(native)
  local self = setmetatable({}, RoomPicker)
  self.native = native
  self.app = native.app
  SDL.native.setPlacementTouch(true)
  SDL.native.setEditor(json.encode({
    title = "Edit Room",
    hint = "Tap the room you want to change",
    logical = { self.app.config.width, self.app.config.height },
    markers = {},
    buttons = { button("cancel", "Cancel", "xmark") },
  }))
  return self
end

function RoomPicker:finish()
  self.finished = true
  SDL.native.setEditor(nil)
  SDL.native.setPlacementTouch(false)
end

function RoomPicker:onTick()
  if self.finished then return true end
  local ui = self.app.ui
  if not ui or not ui.edit_room then
    self:finish()
    return true
  end
  return false
end

function RoomPicker:pressed(id)
  if id == "cancel" then
    self.app.ui:setEditRoom(false)
    self:finish()
  end
end

function RoomPicker:select() end
function RoomPicker:buy() end
function RoomPicker:marker() end

return {
  RoomPicker = RoomPicker,
  RoomEditor = RoomEditor,
  Furnisher = Furnisher,
  hide = hide,
  unhide = unhide,
  OFFSCREEN = OFFSCREEN,
}

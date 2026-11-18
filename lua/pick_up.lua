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

--! Picking people up by touch, and dropping them.
--
-- In the game a right click on a member of staff picks them up (they're
-- carried by a UIPlaceStaff) and a left click drops them. People are small
-- and quick, so in Pick Up mode (the pinching hand) everyone on screen gets
-- a tag that follows them; tapping it is that right click. Any UIPlaceStaff,
-- however it opened (Pick Up, a two-finger tap on someone, or a hire the
-- native panel couldn't place), is then carried by touch
-- (SDL.native.setPlacementTouch("carry")): a drag moves the person and a tap
-- anywhere drops them, a left click where they are, which the game only
-- accepts where they can go.

local json = corsixth.require("ios.json")
local SDL = require("sdl")

local roles = {
  Doctor = "doctor", Nurse = "nurse", Handyman = "handyman", Receptionist = "receptionist",
}

local function button(id, title, symbol, enabled, prominent)
  return { id = id, title = title, symbol = symbol, enabled = enabled ~= false,
    prominent = prominent or false }
end

local PickUp = {}
PickUp.__index = PickUp

--! Pick Up mode, from the toolbar: tags on the people on screen. It ends once
-- someone's been dropped (or put back), or with Done.
function PickUp.start(native)
  local self = setmetatable({}, PickUp)
  self.native = native
  self.app = native.app
  self.ui = native.app.ui
  self.ids = setmetatable({}, { __mode = "k" })
  self.people = setmetatable({}, { __mode = "v" })
  self.next_id = 1
  self:sendState(true)
  return self
end

--! A UIPlaceStaff opened some other way: drop that person, then finish.
function PickUp.adoptPlacer(native, placer)
  local self = PickUp.start(native)
  self:take(placer)
  return self
end

function PickUp:take(placer)
  self.placer = placer
  SDL.native.setPlacementTouch("carry")
  -- The person starts where they were picked up (a new hire: the middle).
  local staff = placer.staff
  local ui = self.ui
  if staff and staff.tile_x then
    local sx, sy = ui:WorldToScreen(staff.tile_x + 0.5, staff.tile_y + 0.5)
    SDL.native.movePointer(sx, sy - 14 * ui.zoom_factor) -- (UIPlaceStaff aims 14 below)
  end
  self:sendState(true)
end

--! A tag for each member of staff on screen, over their head.
function PickUp:tags()
  local ui, config = self.ui, self.app.config
  local zoom = ui.zoom_factor
  local tags = {}
  for _, staff in ipairs(ui.hospital.staff or {}) do
    if staff.tile_x and not staff.fired and not staff.pickup and staff.th then
      local x, y = ui:WorldToScreen(staff.tile_x, staff.tile_y)
      local px, py = staff.th:getSecondaryMarker()
      x, y = x + px * zoom, y + (py - 70) * zoom -- (just above their head)
      if x >= 0 and y >= 0 and x < config.width and y < config.height then
        local id = self.ids[staff]
        if not id then
          id = tostring(self.next_id)
          self.next_id = self.next_id + 1
          self.ids[staff] = id
          self.people[id] = staff
        end
        tags[#tags + 1] = {
          id = id, x = x, y = y,
          state = roles[staff.humanoid_class] or "doctor",
          label = json.text(staff.profile:getFullName()),
        }
      end
    end
  end
  return tags
end

function PickUp:sendState(force)
  if self.finished then
    return -- (Showing the bar again would leave it on screen.)
  end
  local placer = self.placer
  local state = {
    logical = { self.app.config.width, self.app.config.height },
    markers = {},
  }
  if placer then
    local name = placer.profile and self.native.titleCase(json.text(placer.profile:getFullName())) or ""
    local valid = placer:_isValidStaffPlacement()
    state.title = name
    state.hint = valid and "Drag them where they should go, then tap to drop" or
        "They can't go there: drag them somewhere else"
    state.buttons = { button("cancel", "Put Back", "arrow.uturn.backward") }
  else
    state.title = "Pick Up"
    state.hint = "Tap someone to pick them up"
    state.markers = self:tags()
    state.buttons = { button("done", "Done", "checkmark", true, true) }
  end
  local text = json.encode(state)
  if force or text ~= self.state_json then
    self.state_json = text
    SDL.native.setEditor(text)
  end
end

function PickUp:finish()
  self.finished = true
  SDL.native.setEditor(nil)
  SDL.native.setPlacementTouch(false)
end

--! Called every game tick. Returns true once it's done with.
function PickUp:onTick()
  if self.finished then return true end
  if self.ui ~= self.app.ui or not self.app.world then
    self:finish()
    return true
  end
  local placer = self.placer
  if placer and placer.closed then
    -- Dropped (or put back): that's it.
    self:finish()
    return true
  end
  if not self.placer then
    local window = self.ui:getWindow(UIPlaceStaff)
    if window and not window.closed then
      self:take(window)
    end
  end
  self:sendState(false)
  return false
end

function PickUp:marker(id)
  local staff = self.people[tostring(id)]
  if self.placer or not staff or staff.fired or staff.pickup then return end
  if not self.app.world.user_actions_allowed then
    self.native:message("The game is paused.")
    return
  end
  -- As right-clicking them: the game picks them up (a UIPlaceStaff opens,
  -- which onTick takes).
  staff:onClick(self.ui, "right")
end

function PickUp:pressed(id)
  local placer = self.placer
  if id == "done" then
    self:finish()
    return
  elseif id == "cancel" and placer and not placer.closed then
    placer:close() -- As right-clicking: the game puts them back to work.
  end
  self:sendState(true)
end

function PickUp:select() end
function PickUp:buy() end

return PickUp

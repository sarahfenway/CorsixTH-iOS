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

--! Hiring staff natively, in place of UIHireStaff: the candidates, hiring them
-- as UIHireStaff:hire does, and placing them where the game accepts. Part of
-- NativeUI (lua/native_ui.lua), which installs these methods and actions.

local json = corsixth.require("ios.json")
local SDL = require("sdl")

local NativeUI = {} -- Methods, added to the real NativeUI.
local actions = {} -- Actions from the native side, by name.

local staff_categories = {
  { id = "Doctor", title = "Doctors" },
  { id = "Nurse", title = "Nurses" },
  { id = "Handyman", title = "Handymen" },
  { id = "Receptionist", title = "Reception" },
}

--! The job candidates, as UIHireStaff shows them.
function NativeUI:hireState()
  local world, hospital = self.app.world, self.app.ui.hospital
  local categories, candidates = {}, {}
  for _, category in ipairs(staff_categories) do
    local list = {}
    for index, profile in ipairs(world.available_staff[category.id] or {}) do
      local rank
      if category.id == "Doctor" then
        rank = profile.is_consultant and "Consultant" or profile.is_junior and "Junior" or "Doctor"
      end
      list[#list + 1] = {
        index = index,
        name = json.text(profile:getFullName()),
        display_name = self.titleCase(json.text(profile:getFullName())),
        wage = self.formatMoney(profile.wage), -- A month.
        affordable = hospital.balance >= profile.wage,
        skill = profile.skill,
        rank = rank,
        surgeon = (profile.is_surgeon or 0) >= 1.0,
        psychiatrist = (profile.is_psychiatrist or 0) >= 1.0,
        researcher = (profile.is_researcher or 0) >= 1.0,
        description = profile.desc and json.text(profile.desc) or "",
        face = self:facePicture(profile),
      }
      if category.id == "Doctor" then
        local item = list[#list]
        item.surgeon_icon = item.surgeon and self:spritePicture("surgeon") or nil
        item.psychiatrist_icon = item.psychiatrist and self:spritePicture("psychiatrist") or nil
        item.researcher_icon = item.researcher and self:spritePicture("researcher") or nil
      end
    end
    categories[#categories + 1] = { id = category.id, title = category.title }
    candidates[category.id] = list
  end
  -- The tutorial asks for a receptionist, then a doctor: open on that tab.
  local suggested = self:tutorialAt(2, 2, 3, 4, 5) and "Receptionist" or
      self:tutorialAt(4, 2, 3) and "Doctor" or nil
  return { categories = categories, candidates = candidates, suggested = suggested,
    abacus = self:spritePicture("abacus"), computer = self:spritePicture("computer") }
end

--! Puts a newly hired person (in a UIPlaceStaff that's waiting for a click)
-- somewhere sensible, by "clicking" there: the game checks the tile and
-- does the rest. Receptionists go to an unstaffed reception desk if there is
-- one; everyone else to a corridor near the middle of the screen, from where
-- the game calls them to rooms that need them. Returns true if placed.
function NativeUI:placeStaff(placer)
  local app, ui, world = self.app, self.app.ui, self.app.world
  if not world.user_actions_allowed then
    return false
  end
  local function try(x, y)
    placer.tile_x, placer.tile_y = x, y
    if placer:_isValidStaffPlacement() then
      placer:onMouseUp("left", 0, 0)
      return true
    end
    return false
  end
  if placer.profile:isType("Receptionist") then
    for _, objects in pairs(world.objects) do
      for _, object in ipairs(objects) do
        if object.object_type.id == "reception_desk" and not object.receptionist and
            try(object.tile_x, object.tile_y) then
          return true
        end
      end
    end
  end
  local cx, cy = ui:ScreenToWorld(app.config.width / 2, app.config.height / 2)
  cx, cy = math.floor(cx), math.floor(cy)
  for radius = 0, 30 do
    for dy = -radius, radius do
      for dx = -radius, radius do
        if math.max(math.abs(dx), math.abs(dy)) == radius then
          local x, y = cx + dx, cy + dy
          if x >= 1 and y >= 1 and x <= app.map.width and y <= app.map.height and
              world:getRoom(x, y) == nil and try(x, y) then
            return true
          end
        end
      end
    end
  end
  return false
end

function actions.hire(self, p)
  local app = self.app
  local ui, world = app.ui, app.world
  if not world or not ui.hospital then return end
  local pool = world.available_staff[p.category]
  local profile = pool and pool[tonumber(p.index) or 0]
  -- The list changes every month; only hire the person the player saw.
  if not profile or json.text(profile:getFullName()) ~= p.name then
    self:refresh("That person is no longer available.")
    return
  end
  -- As UIHireStaff:hire. (The native panel has no tab or next/previous steps
  -- for the tutorial to wait for, so it moves on from any of them, but only
  -- for the person it asked for, as the game's tabs would.)
  if p.category == "Receptionist" then
    ui:tutorialStep(2, { 2, 3, 4, 5 }, 6)
  elseif p.category == "Doctor" then
    ui:tutorialStep(4, { 2, 3 }, 4)
  end
  if ui.hospital.balance < profile.wage then
    UIHireStaff.cannotAfford({ world = world })
    ui:playSound("wrong2.wav")
    return
  end
  ui:playSound("YesX.wav")
  table.remove(pool, tonumber(p.index))
  local placer = UIPlaceStaff(ui, profile, app.config.width / 2, app.config.height / 2)
  ui:addWindow(placer)
  if not self:placeStaff(placer) then
    -- Nowhere the game accepts (paused, say): the player drops them, as a
    -- picked-up person (lua/pick_up.lua takes the UIPlaceStaff).
    SDL.native.dismiss()
    return
  end
  self:refresh()
end

return { methods = NativeUI, actions = actions }

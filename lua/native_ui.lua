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

--! Native (SwiftUI) menus for the iOS build: the main menu, the in-game menu,
-- save/load, settings and text entry replace CorsixTH's PC-style windows.
-- See src/native_bridge.h for how the two sides talk.
--
-- Nothing here is stored in save games: the object lives in TheApp.native,
-- and App isn't persisted.

local json = corsixth.require("ios.json")
local QuickBuild = corsixth.require("ios.quick_build")
local editing = corsixth.require("ios.room_editor")
local SDL = require("sdl")
local TH = require("TH")
local pathsep = package.config:sub(1, 1)

local NativeUI = {}
NativeUI.__index = NativeUI

-- CorsixTH windows that the native UI replaces, by class name, and the
-- native screen shown instead (false: just don't show it).
local replaced_windows = {
  UIMainMenu = "main_menu",
  UINewGame = "main_menu",
  UICustomGame = "main_menu",
  UICustomCampaign = "main_menu",
  UITipOfTheDay = false,
  UISaveGame = "save",
  UILoadGame = "load",
  UIOptions = "settings",
  UISoundSettings = "settings",
  UICustomise = "settings",
  UIFolder = "settings",
  UIHotkeyAssign = "settings",
  UIBuildRoom = "room_catalog",
  UIHireStaff = "hire_staff",
}

-- Native screens that leave the game running (they don't cover the map).
local unpaused_screens = { main_menu = true, room_catalog = true, hire_staff = true }

local staff_categories = {
  { id = "Doctor", title = "Doctors" },
  { id = "Nurse", title = "Nurses" },
  { id = "Handyman", title = "Handymen" },
  { id = "Receptionist", title = "Reception" },
}

--! "TOXICITY" -> "Toxicity": Theme Hospital writes names in capitals.
local function title_case(text)
  if text ~= text:upper() then
    return text
  end
  return (text:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- Rooms that can be built with Quick Build (lua/quick_build.lua), by id: every
-- Theme Hospital room, each checked by tests/automation/09_quick_build_all.txt.
-- Others (e.g. from mods) use CorsixTH's own editor.
local quick_build_rooms = {}
for _, id in ipairs({ "blood_machine", "cardiogram", "decontamination", "dna_fixer",
    "electrolysis", "fracture_clinic", "general_diag", "gp", "hair_restoration", "inflation",
    "jelly_vat", "operating_theatre", "pharmacy", "psych", "research", "scanner",
    "slack_tongue", "staff_room", "toilets", "training", "ultrascan", "ward", "x_ray" }) do
  quick_build_rooms[id] = true
end

local room_categories = {
  { id = "diagnosis", title = "Diagnosis" },
  { id = "treatment", title = "Treatment" },
  { id = "clinics", title = "Clinics" },
  { id = "facilities", title = "Facilities" },
}

local speeds = {
  { id = "Pause", title = "Paused" },
  { id = "Slowest", title = "Slowest" },
  { id = "Slower", title = "Slower" },
  { id = "Normal", title = "Normal" },
  { id = "Max speed", title = "Fast" },
  { id = "And then some more", title = "Fastest" },
}

-- In-game windows a tap away from the menu.
local hospital_windows = {
  { id = "staff", picture = "staff", title = "Staff Management",
    open = function(ui) ui.bottom_panel:dialogStaffManagement(true) end },
  { id = "town_map", picture = "town_map", title = "Town Map",
    open = function(ui) ui.bottom_panel:dialogTownMap(true) end },
  { id = "research", picture = "research", title = "Research",
    open = function(ui) ui.bottom_panel:dialogResearch(true) end },
  { id = "casebook", picture = "casebook", title = "Casebook",
    open = function(ui) ui.bottom_panel:dialogDrugCasebook(true) end },
  { id = "status", picture = "status", title = "Hospital Status",
    open = function(ui) ui.bottom_panel:dialogStatus(true) end },
  { id = "charts", picture = "charts", title = "Graphs",
    open = function(ui) ui.bottom_panel:dialogCharts(true) end },
  { id = "policy", picture = "policy", title = "Policy",
    open = function(ui) ui.bottom_panel:dialogPolicy(true) end },
  { id = "bank", picture = "bank", title = "Bank Manager",
    open = function(ui) ui.bottom_panel:dialogBankManager(true) end },
  { id = "statement", picture = "bank", title = "Bank Statement",
    open = function(ui) ui.bottom_panel:dialogBankStats(true) end },
  { id = "adviser_history", title = "Adviser Messages",
    open = function(ui) ui:addWindow(UIAdviserHistory(ui)) end },
  { id = "briefing", title = "Level Briefing",
    open = function(ui) ui:showBriefing() end },
}

local autosave_options = {
  { id = "1", title = "Monthly" },
  { id = "2", title = "Weekly" },
  { id = "3", title = "Daily" },
}

--! Creates the native UI for the app, or returns nil when there isn't one
-- (desktop builds, including the desktop touch test mode).
function NativeUI.new(app)
  if not (SDL.native and SDL.native.available()) then
    return nil
  end
  local self = setmetatable({}, NativeUI)
  self.app = app
  self.text_callbacks = {}
  self.next_text_id = 1
  return self
end

--! Applies settings the native side keeps outside CorsixTH (at start-up).
function NativeUI:applyConfig()
  SDL.native.setCursorSpeed(tonumber(self.app.config.touch_cursor_speed) or 1)
end

-------------------------------------------------------------------------------
-- Showing screens

function NativeUI:show(screen)
  local app = self.app
  if app.world and not unpaused_screens[screen] then
    self:pauseGame()
  end
  SDL.native.show(screen, json.encode(self:state()))
  self:updateToolbar(true)
end

--! Sends fresh data to the screen that is showing, optionally with a message
-- for the player.
function NativeUI:refresh(message)
  local state = self:state()
  state.message = message
  SDL.native.update(json.encode(state))
end

--! Shows a native alert.
function NativeUI:message(text)
  SDL.native.show("alert", json.encode({ message = text }))
end

--! Ends a Quick Build or editing session in progress (a game is being
-- loaded or left).
function NativeUI:endQuickBuild()
  if self.quick_build then
    self.quick_build:cancel()
    self.quick_build = nil
  end
  SDL.native.setQuickBuild(nil)
  if self.editor then
    self.editor:finish()
    self.editor = nil
  end
  self.pending_adoptions = nil
end

--! Hands newly opened editor windows to the native controls.
function NativeUI:adoptWindows()
  local pending = self.pending_adoptions
  self.pending_adoptions = nil
  for _, window in ipairs(pending or {}) do
    local name = class.type(window)
    local editor = self.editor
    if window.closed then -- luacheck: ignore 542
    elseif name == "UIEditRoom" then
      if not (self.quick_build and self.quick_build.edit == window) then
        if editor then editor:finish() end
        if window.phase == "walls" then
          self.editor = nil
          self.quick_build = QuickBuild.adopt(self, window)
        else
          self.editor = editing.RoomEditor.adopt(self, window)
        end
      end
    elseif name == "UIFurnishCorridor" then
      if window.edit_dialog then
        if editor and editor.edit == window.edit_dialog then
          editor:adoptBuying(window)
        end
      else
        if editor then editor:finish() end
        self.editor = editing.Furnisher.adopt(self, window)
      end
    elseif name == "UIPlaceObjects" then
      if editor and getmetatable(editor) == editing.Furnisher and not editor.finished then
        editor:adoptPlacing(window)
      else
        if editor then editor:finish() end
        self.editor = editing.Furnisher.adopt(self, window)
      end
    end
  end
end

--! Closes the native screen and lets the game carry on.
function NativeUI:close()
  SDL.native.dismiss()
  self:resumeGame()
end

function NativeUI:pauseGame()
  local world = self.app.world
  if world and not self.resume_speed then
    self.resume_speed = world:getCurrentSpeed()
    world:setSpeed("Pause")
  end
end

function NativeUI:resumeGame()
  local world = self.app.world
  if world and self.resume_speed then
    world:setSpeed(self.resume_speed)
  end
  self.resume_speed = nil
end

--! Called by UI:addWindow. Returns true if the window was replaced by a native
-- screen (and so must not be shown).
function NativeUI:interceptWindow(ui, window)
  local name = class.type(window)
  if name == "UIConfirmDialog" and self.confirm_next then
    -- The player already confirmed this in a native dialog.
    self.confirm_next = false
    if window.callback_ok then
      window.callback_ok()
    end
    return true
  end
  if name == "UIEditRoom" or name == "UIFurnishCorridor" or name == "UIPlaceObjects" then
    -- Shown, but driven by native controls (lua/room_editor.lua) once open.
    self.pending_adoptions = self.pending_adoptions or {}
    self.pending_adoptions[#self.pending_adoptions + 1] = window
    return false
  end
  local screen = replaced_windows[name]
  if screen == nil then
    return false
  end
  -- The window was built but won't be shown: forget its text boxes.
  for i = #ui.textboxes, 1, -1 do
    local box = ui.textboxes[i]
    if box.panel and box.panel.window == window then
      table.remove(ui.textboxes, i)
    end
  end
  if screen then
    self:show(screen)
  end
  return true
end

--! Edits a CorsixTH text box with a native text field.
function NativeUI:editTextbox(textbox)
  local id = self.next_text_id
  self.next_text_id = id + 1
  self.text_callbacks[id] = function(text)
    if text == nil then
      textbox:abort()
      return
    end
    if textbox.char_limit then
      text = text:sub(1, textbox.char_limit)
    end
    textbox:setText(text)
    textbox:confirm()
  end
  local title = textbox.panel and textbox.panel.tooltip and textbox.panel.tooltip.text
  SDL.native.show("text_input", json.encode({
    id = id,
    title = type(title) == "string" and title or "",
    text = type(textbox.text) == "string" and textbox.text or "",
  }))
end

-------------------------------------------------------------------------------
-- What the screens show

local function is_inside(dir, path)
  return path:sub(1, #dir) == dir and not path:find("%.%.", #dir + 1)
end

function NativeUI:listSaves()
  local dir = self.app.savegame_dir
  local saves = {}
  local function add(folder, label)
    if lfs.attributes(folder, "mode") ~= "directory" then return end
    for file in lfs.dir(folder) do
      local name = file:match("^(.+)%.sav$")
      local path = folder .. file
      if name and lfs.attributes(path, "mode") == "file" then
        if label == "" and name == "Resume" then
          saves[#saves + 1] = { name = name, path = path, folder = "Resume",
            modified = lfs.attributes(path, "modification") }
        else
          saves[#saves + 1] = { name = name, path = path, folder = label,
            modified = lfs.attributes(path, "modification") }
        end
      end
    end
  end
  add(dir, "")
  add(dir .. "Autosaves" .. pathsep, "Autosave")
  table.sort(saves, function(a, b) return a.modified > b.modified end)
  return saves
end

function NativeUI:settingsState()
  local app, c = self.app, self.app.config
  local languages = {}
  local current_language = ""
  for _, lang in ipairs(app.strings.languages) do
    local english = app.strings.languages_english[lang]
    if app.gfx:hasLanguageFont(app.strings:getFont(lang)) then
      languages[#languages + 1] = { id = english, title = lang }
      if tostring(c.language):lower() == english:lower() then
        current_language = english
      end
    end
  end
  return {
    sound_volume = c.sound_volume or 1,
    announcement_volume = c.announcement_volume or 1,
    music_volume = c.music_volume or 1,
    play_sounds = not not c.play_sounds,
    play_announcements = not not c.play_announcements,
    play_music = not not c.play_music,
    has_music = not not app.audio.has_bg_music,
    adviser = not c.adviser_disabled,
    edge_scrolling = not c.prevent_edge_scrolling,
    twentyfour_hour_clock = not not c.twentyfour_hour_clock,
    touch_controls = c.touch_controls == "direct" and "direct" or "trackpad",
    cursor_speed = tonumber(c.touch_cursor_speed) or 1,
    autosave_frequency = tonumber(c.autosave_frequency) or 0,
    autosave_options = autosave_options,
    language = current_language,
    languages = languages,
  }
end

function NativeUI:levelName()
  local map = self.app.map
  if not map then return nil end
  local name = map.level_name and json.text(map.level_name)
  if name and name ~= "" then
    return title_case(name)
  end
  if tonumber(map.level_number) then
    return "Level " .. map.level_number
  end
  return nil
end

function NativeUI:findLevels()
  local app = self.app
  local levels = {}
  for _, dir in ipairs({ app.level_dir, app.user_level_dir }) do
    if dir and lfs.attributes(dir, "mode") == "directory" then
      for file in lfs.dir(dir) do
        if file:match("%.level$") then
          local info = app:readLevelFile(dir .. file)
          if info and info.name and info.map_file then
            levels[#levels + 1] = { name = info.name, description = info.briefing,
              level_file = dir .. file, map_file = info.map_file }
          end
        end
      end
    end
  end
  table.sort(levels, function(a, b) return a.name < b.name end)
  return levels
end

function NativeUI:findCampaigns()
  local app = self.app
  local campaigns, seen = {}, {}
  local function read(path)
    local info = app:readCampaignFile(path)
    if info and info.name and not seen[info.name] and info.levels and #info.levels > 0 then
      seen[info.name] = true
      campaigns[#campaigns + 1] = { name = info.name, path = path,
        description = app.strings:getLocalisedText(info.description, info.description_table) }
    end
  end
  for _, dir in ipairs({ app.campaign_dir, app.user_campaign_dir }) do
    if dir and lfs.attributes(dir, "mode") == "directory" then
      for item in lfs.dir(dir) do
        local path = dir .. item
        if lfs.attributes(path, "mode") == "directory" and not item:match("^%.") then
          for file in lfs.dir(path) do
            if file:match("%.campaign$") then read(path .. pathsep .. file) end
          end
        elseif item:match("%.campaign$") then
          read(path)
        end
      end
    end
  end
  table.sort(campaigns, function(a, b) return a.name < b.name end)
  return campaigns
end

--! Folder for pictures of the game's art made for native menus. They come
-- from the player's own Theme Hospital data, so they're made on the device
-- (once) rather than shipped.
function NativeUI:pictureDir()
  if not self.picture_dir then
    local caches = (os.getenv("HOME") or ".") .. "/Library/Caches"
    lfs.mkdir(caches)
    self.picture_dir = caches .. "/CorsixTH/"
    lfs.mkdir(self.picture_dir)
  end
  return self.picture_dir
end

--! A picture of the room, as Theme Hospital's Build Room window previews it.
-- Returns the PNG's path, or nil.
function NativeUI:roomPicture(room)
  local anim_id = room.build_preview_animation
  if not anim_id then
    return nil
  end
  local path = self:pictureDir() .. ("room_%s_v2.png"):format(room.id)
  if not lfs.attributes(path, "size") then
    local anim = TH.animation()
    anim:setAnimation(self.app.anims, anim_id)
    -- The same frame and anchor as the preview box in UIBuildRoom.
    local ok, err = SDL.native.renderToPNG(path, 140, 124, function()
      anim:draw(self.app.video, 70, 54)
    end)
    if not ok then
      print("Native UI: couldn't make a picture of " .. room.id .. ": " .. tostring(err))
      return nil
    end
  end
  return path
end

-- Pictures from the game's sprite sheets: {sheet folder, sheet, sprite, crop}.
-- The crop (x, y, w, h) is the part of the sprite to keep.
-- The hire window's background blues: the icons below sit on them, and
-- shades show through the abacus's frame and under the computer.
local panel_blue = { { 61, 174, 202 }, { 45, 146, 186 }, { 49, 154, 190 }, { 57, 166, 198 },
  { 36, 138, 178 }, { 69, 182, 206 }, { 28, 121, 170 }, { 0, 77, 113 }, { 0, 65, 109 },
  { 0, 93, 121 }, { 32, 130, 174 } }

local sprites = {
  -- Bottom panel buttons (UIBottomPanel:drawPanels), the face of each button.
  bank = { "Data", "Panel02V", 1, { 6, 6, 35, 36 } },
  build = { "Data", "Panel02V", 4, { 6, 6, 35, 36 } },
  furnish = { "Data", "Panel02V", 6, { 1, 6, 35, 36 } },
  edit = { "Data", "Panel02V", 8, { 1, 6, 35, 36 } },
  hire = { "Data", "Panel02V", 10, { 1, 6, 35, 36 } },
  staff = { "Data", "Panel02V", 15, { 6, 6, 35, 36 } },
  town_map = { "Data", "Panel02V", 17, { 1, 6, 35, 36 } },
  casebook = { "Data", "Panel02V", 19, { 1, 6, 35, 36 } },
  research = { "Data", "Panel02V", 21, { 1, 6, 35, 36 } },
  status = { "Data", "Panel02V", 23, { 1, 6, 35, 36 } },
  charts = { "Data", "Panel02V", 25, { 1, 6, 35, 36 } },
  policy = { "Data", "Panel02V", 27, { 1, 6, 35, 36 } },
  -- Fax messages on the bottom panel (UIMessage), one per kind.
  fax_emergency = { "Data", "Panel02V", 43 },
  fax_epidemy = { "Data", "Panel02V", 45 },
  fax_strike = { "Data", "Panel02V", 47 },
  fax_personality = { "Data", "Panel02V", 49 },
  fax_information = { "Data", "Panel02V", 51 },
  fax_disease = { "Data", "Panel02V", 53 },
  fax_report = { "Data", "Panel02V", 55 },
  -- The hire window (UIHireStaff, QData/Req11V): a doctor's qualifications,
  -- and the abacus and computer at the ends of the skill bar (on the panel's
  -- blue, which is keyed out).
  surgeon = { "QData", "Req11V", 292, nil, panel_blue, 3 },
  psychiatrist = { "QData", "Req11V", 293, nil, panel_blue, 3 },
  researcher = { "QData", "Req11V", 294, nil, panel_blue, 3 },
  abacus = { "QData", "Req11V", 259, { 0, 4, 16, 17 }, panel_blue, 4 },
  computer = { "QData", "Req11V", 259, { 66, 2, 17, 21 }, panel_blue, 4 },
}

--! A picture of one of the game's sprites (see `sprites`). Returns the PNG's
-- path, or nil.
function NativeUI:spritePicture(name)
  if not name then
    return nil
  end
  self.pictures = self.pictures or {}
  if self.pictures[name] ~= nil then
    return self.pictures[name] or nil
  end
  local info = sprites[name]
  -- info[6], if given, is the picture's own version (bump it when changing it).
  local path = info and self:pictureDir() .. ("sprite_%s_v%d.png"):format(name, info[6] or 2)
  if path and not lfs.attributes(path, "size") then
    local ok, err = pcall(function()
      local sheet = self.app.gfx:loadSpriteTable(info[1], info[2], true)
      -- The whole sprite unless a crop ({x, y, w, h}) is given.
      local crop = info[4] or { 0, 0, sheet:size(info[3]) }
      local done, why = SDL.native.renderToPNG(path, crop[3], crop[4], function()
        sheet:draw(self.app.video, info[3], -crop[1], -crop[2])
      end, info[5])
      if not done then error(why) end
    end)
    if not ok then
      print("Native UI: couldn't make a picture of " .. name .. ": " .. tostring(err))
      path = nil
    end
  end
  self.pictures[name] = path or false
  return path
end

--! A picture of a job candidate's face, drawn by the game as the hire window
-- does (StaffProfile:drawFace). Returns the PNG's path, or nil.
function NativeUI:facePicture(profile)
  if not (profile.hair_index and profile.face_index and profile.chin_index) then
    return nil
  end
  local path = self:pictureDir() .. ("face_%d_%d_%d_v1.png"):format(profile.hair_index,
      profile.face_index, profile.chin_index)
  if lfs.attributes(path, "size") then
    return path
  end
  local ok, err = pcall(function()
    -- The same face parts as UIHireStaff.
    self.face_parts = self.face_parts or self.app.gfx:loadRaw("Face01V", 65, 1350, nil, "Data",
        "MPalette.dat", false, { flags = DrawFlags.Nearest })
    local done, why = SDL.native.renderToPNG(path, 65, 75, function()
      profile:drawFace(self.app.video, 0, 0, self.face_parts, 1)
    end)
    if not done then error(why) end
  end)
  if not ok then
    print("Native UI: couldn't make a picture of a face: " .. tostring(err))
    return nil
  end
  return path
end

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
        display_name = title_case(json.text(profile:getFullName())),
        wage = NativeUI.formatMoney(profile.wage), -- A month.
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
  return { categories = categories, candidates = candidates,
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

--! A picture of an item (as the game's buying window previews it). Returns
-- the PNG's path, or nil.
function NativeUI:objectPicture(object)
  local anim_id = object and object.build_preview_animation
  if not anim_id then
    return nil
  end
  local path = self:pictureDir() .. ("object_%s_v1.png"):format(object.id)
  if not lfs.attributes(path, "size") then
    local anim = TH.animation()
    anim:setAnimation(self.app.anims, anim_id)
    -- UIFurnishCorridor draws it at (72, 57) in its preview box.
    local ok, err = SDL.native.renderToPNG(path, 160, 130, function()
      anim:draw(self.app.video, 80, 60)
    end)
    if not ok then
      print("Native UI: couldn't make a picture of " .. object.id .. ": " .. tostring(err))
      return nil
    end
  end
  return path
end

--! The rooms the player can build now, as UIBuildRoom lists them.
function NativeUI:roomList()
  local app = self.app
  local hospital = app.ui.hospital
  local world = app.world
  local rooms = {}
  for _, discovery in pairs(hospital.room_discoveries) do
    local room = discovery.room
    -- NB: Unimplemented rooms are hidden unless in debug mode (as UIBuildRoom)
    if discovery.is_discovered and (app.config.debug or room.class) then
      for _, category in ipairs(room_categories) do
        if room.categories[category.id] then
          local cost = world.free_build_mode and 0 or
              hospital.research.research_progress[room].build_cost
          rooms[#rooms + 1] = {
            id = room.id,
            name = json.text(room.name),
            category = category.title,
            order = room.categories[category.id],
            cost = NativeUI.formatMoney(cost),
            affordable = world.free_build_mode or hospital.balance >= cost,
            quick = quick_build_rooms[room.id] or false,
            image = self:roomPicture(room),
          }
          break
        end
      end
    end
  end
  local rank = {}
  for i, category in ipairs(room_categories) do rank[category.title] = i end
  table.sort(rooms, function(a, b)
    if a.category ~= b.category then return rank[a.category] < rank[b.category] end
    return a.order < b.order
  end)
  return rooms
end

function NativeUI:state()
  local app = self.app
  local world = app.world
  local saves = self:listSaves()
  local state = {
    in_game = world ~= nil,
    saves = saves,
    save_location = os.getenv("CORSIXTH_SAVE_DIR") and "iCloud Drive" or "On this device",
    settings = self:settingsState(),
  }
  if world then
    state.level_name = self:levelName()
    state.can_restart = app.map ~= nil
    state.rooms = self:roomList()
    state.hire = self:hireState()
  else
    local difficulties = {}
    if app.fs:fileExists("Levels", "Easy01.SAM") then
      difficulties[#difficulties + 1] = { id = "easy", title = "Easy" }
    end
    difficulties[#difficulties + 1] = { id = "full", title = "Medium" }
    if app.fs:fileExists("Levels", "Hard01.SAM") then
      difficulties[#difficulties + 1] = { id = "hard", title = "Hard" }
    end
    state.difficulties = difficulties
    state.default_difficulty = "full"
    state.can_tutorial = true
    state.can_continue = #saves > 0
    self.levels = self:findLevels()
    state.levels = self.levels
    state.campaigns = self:findCampaigns()
  end
  return state
end

-------------------------------------------------------------------------------
-- The in-game toolbar and status pill (replacing the bottom panel)

local function format_money(amount)
  local text = tostring(math.floor(math.abs(amount)))
  text = text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (amount < 0 and "-$" or "$") .. text
end
NativeUI.formatMoney = format_money

function NativeUI:toolbarState()
  local app = self.app
  local world, ui = app.world, app.ui
  local hospital = ui and ui.hospital
  if not world or not hospital then
    return nil
  end
  local date = world:date()
  local panel = ui.bottom_panel
  local faxes, waiting = self:faxState(panel)
  local windows = {}
  for _, w in ipairs(hospital_windows) do
    windows[#windows + 1] = { id = w.id, title = w.title, image = self:spritePicture(w.picture) }
  end
  local icons = {}
  for _, tool in ipairs({ "build", "furnish", "edit", "hire" }) do
    icons[tool] = self:spritePicture(tool)
  end
  return {
    icons = icons,
    money = format_money(hospital.balance),
    date = _S.date_format.daymonth:format(date:dayOfMonth(), date:monthOfYear()),
    reputation = (hospital.reputation or 500) / 1000,
    faxes = faxes,
    faxes_waiting = waiting,
    speed = world:getCurrentSpeed(),
    speeds = speeds,
    windows = windows,
  }
end

local fax_titles = {
  emergency = "Emergency", epidemy = "Epidemic", strike = "Pay demand", personality = "VIP visit",
  information = "Information", disease = "New disease", report = "Report",
}

-- How long each timed fax had when first seen (UIMessage only counts down).
local fax_timeouts = setmetatable({}, { __mode = "k" })

--! The fax messages on the bottom panel, as the game shows them (at most five,
-- one of each kind, oldest first), and how many more are waiting behind them.
function NativeUI:faxState(panel)
  local faxes = {}
  if not panel then
    return faxes, 0
  end
  for i, icon in ipairs(panel.message_windows) do
    local time_left
    if icon.timer then
      fax_timeouts[icon] = math.max(fax_timeouts[icon] or 0, icon.timer)
      -- In twentieths, so the toolbar isn't resent every tick.
      time_left = math.ceil(icon.timer / fax_timeouts[icon] * 20) / 20
    end
    faxes[#faxes + 1] = {
      index = i,
      kind = icon.type,
      title = fax_titles[icon.type] or "Message",
      image = self:spritePicture("fax_" .. tostring(icon.type)),
      open = icon.fax ~= nil,
      dismissable = icon.can_dismiss and true or false,
      time_left = time_left,
    }
  end
  return faxes, #panel.message_queue
end

--! Sends the toolbar's state when it changed (or always, when forced).
function NativeUI:updateToolbar(force)
  local state = self:toolbarState()
  local text = state and json.encode(state) or ""
  if force or text ~= self.toolbar_json then
    self.toolbar_json = text
    SDL.native.setToolbar(state and text or nil)
  end
end

--! Called every game tick (GameUI:onTick).
function NativeUI:onTick()
  self.tick_count = (self.tick_count or 0) + 1
  if self.pending_adoptions then
    self:adoptWindows()
  end
  if self.editor and self.editor:onTick() then
    self.editor = nil
  end
  if self.tick_count % 5 == 0 then
    self:updateToolbar(false)
    -- A game is running (resumed at launch, say), so the main menu is done.
    if SDL.native.screen() == "main_menu" then
      SDL.native.dismiss()
    end
  end
  if self.quick_build then
    if self.quick_build:onTick() then
      self.quick_build = nil
    end
  elseif self.tick_count % 5 == 0 then
    -- A room editor hidden by Quick Build but no longer driven by it (for
    -- example in a game saved mid-build) becomes CorsixTH's normal editor.
    local edit = self.app.ui and self.app.ui:getWindow(UIEditRoom)
    if edit and edit.visible == false then
      edit.visible = true
    end
    -- Likewise windows moved off screen for native controls.
    if not self.editor and self.app.ui then
      for _, window in ipairs(self.app.ui.windows or {}) do
        if window.x and window.x <= editing.OFFSCREEN / 2 then
          editing.unhide(window)
        end
      end
    end
  end
end

-------------------------------------------------------------------------------
-- Actions from the native side

local actions = {}

function actions.menu_button(self)
  self:show(self.app.world and "game_menu" or "main_menu")
end

-- The player closed the screen (Done, Resume or a swipe).
function actions.dismissed(self)
  self:resumeGame()
end

local tools = {
  build = function(panel) panel:dialogBuildRoom() end,
  furnish = function(panel) panel:dialogFurnishCorridor() end,
  edit = function(panel) panel:editRoom() end,
  hire = function(panel) panel:dialogHireStaff() end,
}

function actions.tool(self, p)
  local ui = self.app.ui
  local panel = ui and ui.bottom_panel
  if panel and tools[p.id] then
    tools[p.id](panel)
    if p.id == "edit" then
      -- The game is now waiting for a room to be clicked: touch picks it.
      if self.editor then
        self.editor:finish()
        self.editor = nil
      end
      if ui.edit_room == true then
        self.editor = editing.RoomPicker.start(self)
      end
    end
  end
end

function actions.editor_button(self, p)
  if self.editor then self.editor:pressed(p.id) end
end

function actions.editor_marker(self, p)
  if self.editor then self.editor:marker(p.id) end
end

function actions.editor_select(self, p)
  if self.editor then self.editor:select(tonumber(p.index)) end
end

function actions.editor_buy(self, p)
  if self.editor then self.editor:buy(tonumber(p.index), tonumber(p.delta) or 0) end
end

function actions.quick_build_customise(self)
  local qb = self.quick_build
  if not qb then return end
  local edit, door = qb:customise()
  if edit then
    self.quick_build = nil
    self.editor = editing.RoomEditor.adopt(self, edit, door)
  end
end

function actions.toolbar_speed(self, p)
  local world = self.app.world
  if world and p.speed then
    world:setSpeed(p.speed)
    self:updateToolbar(true)
  end
end

--! Opens (or closes, if open) a fax, as clicking its icon does.
function actions.open_message(self, p)
  local panel = self.app.ui and self.app.ui.bottom_panel
  local icon = panel and panel.message_windows[p.index or 1]
  if icon then
    icon:openMessage()
    self:updateToolbar(true)
  end
end

--! Dismisses a fax, as right-clicking its icon does (when the game allows).
function actions.dismiss_message(self, p)
  local panel = self.app.ui and self.app.ui.bottom_panel
  local icon = panel and panel.message_windows[p.index or 1]
  if icon then
    icon:dismissMessage()
    self:updateToolbar(true)
  end
end

function actions.pick_room(self, p)
  local app = self.app
  local ui = app.ui
  if not app.world or not ui.hospital then return end
  local room
  for _, discovery in pairs(ui.hospital.room_discoveries) do
    if discovery.room.id == p.id and discovery.is_discovered then
      room = discovery.room
    end
  end
  if not room then return end
  SDL.native.dismiss()
  self:endQuickBuild()
  -- The same checks as UIBuildRoom:buildRoom.
  local cost = app.world.free_build_mode and 0 or
      ui.hospital.research.research_progress[room].build_cost
  if not app.world.free_build_mode and ui.hospital.balance < cost then
    ui.adviser:say(_A.warnings.money_very_low_take_loan, false, true)
    ui:playSound("Wrong2.wav")
    return
  end
  local fullscreen = ui:getWindow(UIFullscreen)
  if fullscreen then
    fullscreen:close()
  end
  if quick_build_rooms[room.id] then
    local qb, message = QuickBuild.start(self, room)
    if qb then
      self.quick_build = qb
      return
    end
    self:message(message)
  end
  ui:addWindow(UIEditRoom(ui, room))
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
  -- As UIHireStaff:hire.
  ui:tutorialStep(2, { 3, 4, 5 }, 6)
  ui:tutorialStep(4, 3, 4)
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
    -- The game's own placement carries on: the person follows the cursor
    -- until the player taps where they should go.
    SDL.native.dismiss()
    self:message("Tap where " .. json.text(profile:getFullName()) .. " should start work.")
    return
  end
  self:refresh()
end

function actions.quick_build_drag(self, p)
  if self.quick_build then
    self.quick_build:drag(p.handle, tonumber(p.x) or 0, tonumber(p.y) or 0, p.ended)
  end
end

function actions.quick_build_build(self)
  if self.quick_build then
    self.quick_build:build()
  end
end


function actions.quick_build_cancel(self)
  self:endQuickBuild()
end

function actions.set_speed(self, p)
  if self.app.world and p.speed then
    self.resume_speed = p.speed
  end
end

function actions.open_window(self, p)
  local ui = self.app.ui
  self:close()
  for _, w in ipairs(hospital_windows) do
    if w.id == p.id and ui.bottom_panel then
      w.open(ui)
    end
  end
end

function actions.save(self, p)
  local app = self.app
  local name = tostring(p.name or ""):gsub("[/\\:]", "-"):gsub("^[%s%.]+", ""):gsub("%s+$", "")
  if name == "" or not app.world then return end
  -- Save the game running at the speed it had, not paused by this menu.
  local resume_speed = self.resume_speed
  self:resumeGame()
  local ok, err = pcall(app.save, app, app.savegame_dir .. name .. ".sav")
  if ok then
    SDL.native.dismiss()
  else
    self:pauseGame()
    self.resume_speed = resume_speed
    print("Could not save the game: " .. tostring(err))
    self:refresh("Couldn't save the game: " .. tostring(err))
  end
end

function actions.load(self, p)
  local app = self.app
  local path = tostring(p.path or "")
  if not is_inside(app.savegame_dir, path) then return end
  SDL.native.dismiss()
  self:endQuickBuild()
  self.resume_speed = nil
  local ok, err = pcall(app.load, app, path)
  if not ok then
    err = _S.errors.load_prefix .. tostring(err)
    print(err)
    app.ui:addWindow(UIInformation(app.ui, { err }))
  end
  self:updateToolbar(true)
end

function actions.delete_save(self, p)
  local path = tostring(p.path or "")
  if is_inside(self.app.savegame_dir, path) and path:match("%.sav$") then
    os.remove(path)
  end
  self:refresh()
end

function actions.rename_save(self, p)
  local path = tostring(p.path or "")
  local name = tostring(p.name or ""):gsub("[/\\:]", "-"):gsub("^[%s%.]+", ""):gsub("%s+$", "")
  local message
  if name ~= "" and is_inside(self.app.savegame_dir, path) and path:match("%.sav$") then
    local target = path:match("^(.*[/\\])") .. name .. ".sav"
    if lfs.attributes(target, "mode") then
      message = "There's already a save called " .. name .. "."
    else
      local ok, err = os.rename(path, target)
      if not ok then message = "Couldn't rename the save: " .. tostring(err) end
    end
  end
  self:refresh(message)
end

function actions.restart(self)
  local app = self.app
  SDL.native.dismiss()
  self:endQuickBuild()
  self.resume_speed = nil
  if app.map then
    self.confirm_next = true
    app:restart()
    self.confirm_next = false
  end
end

function actions.quit_to_menu(self)
  SDL.native.dismiss()
  self:endQuickBuild()
  self.resume_speed = nil
  self.app:loadMainMenu()
end

local settings = {
  sound_volume = function(app, v)
    app.audio:setSoundVolume(v)
  end,
  play_sounds = function(app, v)
    app.audio:playSoundEffects(v)
  end,
  announcement_volume = function(app, v)
    app.audio:setAnnouncementVolume(v)
  end,
  play_announcements = function(app, v)
    app.config.play_announcements = v
  end,
  music_volume = function(app, v)
    app.config.music_volume = v
    app.audio:setBackgroundVolume(v)
  end,
  play_music = function(app, v)
    app.config.play_music = v
    if v then
      app.audio:playRandomBackgroundTrack()
    else
      app.audio:stopBackgroundTrack()
    end
  end,
  adviser = function(app, v)
    app.config.adviser_disabled = not v
  end,
  edge_scrolling = function(app, v)
    app.config.prevent_edge_scrolling = not v
  end,
  twentyfour_hour_clock = function(app, v)
    app.config.twentyfour_hour_clock = v
  end,
  touch_controls = function(app, v)
    app.config.touch_controls = v == "direct" and "direct" or "trackpad"
    SDL.wm.setTouchControls(app.config.touch_controls)
  end,
  cursor_speed = function(app, v)
    app.config.touch_cursor_speed = v
    SDL.native.setCursorSpeed(v)
  end,
  autosave_frequency = function(app, v)
    app.config.autosave_frequency = v
  end,
  language = function(app, v)
    app.config.language = v
    app:initLanguage()
  end,
}

function actions.setting(self, p)
  local apply = settings[p.key]
  if apply and p.value ~= nil then
    apply(self.app, p.value)
    self.app:saveConfig()
    self:refresh()
  end
end

-- Starts a game from the main menu (the native screen goes first).
local function start(self, fn)
  SDL.native.dismiss()
  self:endQuickBuild()
  fn()
  if not self.app.world then
    -- Didn't work: CorsixTH has shown why; offer the menu again.
    self:show("main_menu")
  end
  self:updateToolbar(true)
end

function actions.new_game(self, p)
  local app = self.app
  start(self, function()
    local difficulty = p.difficulty ~= "" and p.difficulty or "full"
    if app:loadLevel(1, difficulty, nil, nil, nil, nil, _S.errors.load_level_prefix, nil) and
        app.world then
      app.moviePlayer:playAdvanceMovie(1)
      if not app.using_demo_files then
        app.world.campaign_info = "TH.campaign"
      end
      if p.tutorial then
        app.ui.start_tutorial = true
        app.ui:startTutorial()
      end
    end
  end)
end

function actions.continue(self)
  local saves = self:listSaves()
  if saves[1] then
    actions.load(self, { path = saves[1].path })
  end
end

function actions.start_campaign(self, p)
  local app = self.app
  local path = tostring(p.path or "")
  start(self, function() app:loadCampaign(path) end)
end

function actions.start_level(self, p)
  local app = self.app
  local level
  for _, l in ipairs(self.levels or {}) do
    if l.level_file == p.level_file then level = l end
  end
  if not level then return end
  start(self, function()
    local _, errors = app:readMapDataFile(level.map_file)
    if errors then
      app.ui:addWindow(UIInformation(app.ui, { errors }))
      return
    end
    app:loadLevel(level.level_file, nil, level.name, level.map_file, level.description, nil,
        _S.errors.load_level_prefix, nil)
  end)
end

function actions.text_input(self, p)
  local callback = self.text_callbacks[p.id]
  self.text_callbacks[p.id] = nil
  if callback then callback(tostring(p.text or "")) end
end

function actions.text_input_cancel(self, p)
  local callback = self.text_callbacks[p.id]
  self.text_callbacks[p.id] = nil
  if callback then callback(nil) end
end

--! Handles an action from the native UI (App:onNativeAction).
function NativeUI:onAction(action, payload)
  local handler = actions[action]
  if not handler then
    print("Native UI: unknown action " .. tostring(action))
    return
  end
  local p = json.decode(payload) or {}
  handler(self, type(p) == "table" and p or {})
end

return NativeUI

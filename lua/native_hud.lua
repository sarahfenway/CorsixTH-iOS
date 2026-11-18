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

--! The in-game toolbar and status pill, which replace the bottom panel: money,
-- date and reputation, the speed and Hospital menus, faxes, the adviser's
-- card, what the tutorial points at, and the game windows taps go straight
-- to. Part of NativeUI (lua/native_ui.lua), which installs these methods and
-- actions.

local json = corsixth.require("ios.json")
local editing = corsixth.require("ios.room_editor")
local PickUp = corsixth.require("ios.pick_up")
local SDL = require("sdl")

local NativeUI = {} -- Methods, added to the real NativeUI.
local actions = {} -- Actions from the native side, by name.

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

-- The bottom panel's buttons, as the tutorial numbers them, and the toolbar's.
local tutorial_tools = { [2] = "build", [3] = "furnish", [4] = "edit", [5] = "hire" }

--! The tutorial wants a button to blink (game_ui.lua's tutorial_blink), or
-- stops (nil). Bottom-panel buttons light up on the toolbar; the hire and
-- build panels follow the tutorial themselves (hireState, roomList).
function NativeUI:tutorialBlink(window, button)
  local tool = window == "UIBottomPanel" and tutorial_tools[button] or nil
  if tool ~= self.tutorial_tool then
    self.tutorial_tool = tool
    self:updateToolbar(true)
  end
  -- The tutorial moves on after the panel has opened: show it the new step.
  local screen = SDL.native.screen()
  if screen == "hire_staff" or screen == "room_catalog" then
    self:refresh()
  end
end

--! The tutorial's chapter and phase, if it's running.
function NativeUI:tutorialAt(chapter, ...)
  local t = self.app.ui and self.app.ui.tutorial
  if not t or t.chapter ~= chapter then return false end
  for _, phase in ipairs({ ... }) do
    if t.phase == phase then return true end
  end
  return false
end

--! What the adviser is saying, while the game has him saying it (his speech
-- bubble), or nil. The game keeps his queue, timing and history as ever.
function NativeUI:adviserState()
  local adviser = self.app.ui and self.app.ui.adviser
  if not adviser or not adviser.speech or (adviser.phase ~= 2 and adviser.phase ~= 3) then
    return nil
  end
  -- Trailing "/"s are the game's blank lines.
  local text = json.text(adviser.speech):gsub("/+$", "")
  return { text = text, more = #adviser.queued_messages, face = self:adviserPicture() }
end

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
    highlight = ui.tutorial and self.tutorial_tool or nil, -- (Not after it's over.)
    money = self.formatMoney(hospital.balance),
    date = _S.date_format.daymonth:format(date:dayOfMonth(), date:monthOfYear()),
    reputation = (hospital.reputation or 500) / 1000,
    faxes = faxes,
    faxes_waiting = waiting,
    adviser = self:adviserState(),
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
-- Game windows that aren't dialogs: touches on them stay trackpad touches.
local not_dialogs = {
  UIMenuBar = true, UIBottomPanel = true, UIPlaceStaff = true, Subtitles = true,
}

--! Tells the touch code where the game's own dialogs are (faxes, information
--! boxes, the opening countdown), so a finger presses their buttons directly
--! rather than through the trackpad cursor.
function NativeUI:updateDirectRegions()
  local regions, keys = {}, {}
  for _, window in ipairs(self.app.ui and self.app.ui.windows or {}) do
    if window.visible ~= false and window.width and window.height
        and window.x and window.x > editing.OFFSCREEN / 2
        and not not_dialogs[class.type(window)] then
      regions[#regions + 1] = { window.x, window.y, window.width, window.height }
      keys[#keys + 1] = table.concat(regions[#regions], ",")
    end
  end
  local key = table.concat(keys, ";")
  if key ~= self.direct_regions_key then
    self.direct_regions_key = key
    SDL.native.setDirectRegions(regions)
  end
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
  -- The Build Room and Hire Staff panels leave the game running; another
  -- tool closes them (as the player closing them would), or they'd sit on
  -- top of its controls.
  local screen = SDL.native.screen()
  if panel and (screen == "room_catalog" or screen == "hire_staff") and
      p.id ~= ({ room_catalog = "build", hire_staff = "hire" })[screen] then
    SDL.native.dismiss()
    self:screenClosed()
  end
  if p.id == "pickup" and panel then
    -- Pick Up mode (lua/pick_up.lua); the button again ends it. Not over
    -- another editor: its game window would stay open underneath.
    if self.editor and getmetatable(self.editor) == PickUp then
      self.editor:finish()
      self.editor = nil
      return
    end
    local why = PickUp.blocked(self)
    if why then
      self:message(why)
      return
    end
    if self.editor then
      self.editor:finish()
      self.editor = nil
    end
    self.editor = PickUp.start(self)
    return
  end
  if panel and tools[p.id] then
    tools[p.id](panel)
    if p.id == "edit" and ui.edit_room == true then
      -- The game is now waiting for a room to be clicked: touch picks it.
      -- (It refuses while one of its windows is open; then nothing changes.)
      if self.editor then
        self.editor:finish()
        self.editor = nil
      end
      self.editor = editing.RoomPicker.start(self)
    end
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
--! The fax the player tapped: at that place in the bottom panel's list, if
-- it's still the same kind (one expiring moves the rest along), else the
-- one of that kind (there's at most one of each).
local function tapped_fax(native, p)
  local panel = native.app.ui and native.app.ui.bottom_panel
  if not panel then return nil end
  local icon = panel.message_windows[tonumber(p.index) or 1]
  if icon and (not p.kind or icon.type == p.kind) then
    return icon
  end
  for _, other in ipairs(panel.message_windows) do
    if other.type == p.kind then
      return other
    end
  end
  return nil
end

function actions.open_message(self, p)
  local icon = tapped_fax(self, p)
  if icon then
    icon:openMessage()
    self:updateToolbar(true)
  end
end

--! The adviser's next message, or he goes away: as clicking him does.
function actions.adviser_next(self)
  local adviser = self.app.ui and self.app.ui.adviser
  if adviser and adviser.phase ~= 0 and adviser.phase ~= 4 then
    if #adviser.queued_messages > 0 then
      adviser:talk()
    else
      adviser:hide()
    end
    self:updateToolbar(true)
  end
end

--! The adviser goes away with everything he still had to say (it stays in
-- his history): as right-clicking him does.
function actions.adviser_dismiss(self)
  local adviser = self.app.ui and self.app.ui.adviser
  if adviser and adviser.phase ~= 0 and adviser.phase ~= 4 then
    adviser:hide()
    adviser:addQueuedMessagesToHistory()
    adviser.queued_messages = {}
    self:updateToolbar(true)
  end
end

--! Dismisses a fax, as right-clicking its icon does (when the game allows).
function actions.dismiss_message(self, p)
  local icon = tapped_fax(self, p)
  if icon then
    icon:dismissMessage()
    self:updateToolbar(true)
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

--! Edge scrolling (touch_gestures.h): a finger is pushing the cursor against
-- an edge, so the map scrolls that way, as the game's own edge scrolling does
-- with a mouse (screen pixels; the map's offsets are unzoomed).
function actions.scroll_map(self, p)
  local ui = self.app.ui
  if ui and ui.scrollMap and ui.zoom_factor then
    ui:scrollMap((tonumber(p.dx) or 0) / ui.zoom_factor, (tonumber(p.dy) or 0) / ui.zoom_factor)
  end
end

return { methods = NativeUI, actions = actions }

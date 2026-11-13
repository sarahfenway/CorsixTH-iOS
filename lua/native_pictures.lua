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

--! Pictures for the native screens, drawn by the game's own code from the
-- player's own data (room previews, toolbar icons, faces, furniture, the
-- adviser) and cached as PNGs on the device. Never shipped or committed.
-- Part of NativeUI (lua/native_ui.lua), which installs these methods.

local SDL = require("sdl")
local TH = require("TH")

local NativeUI = {} -- Methods, added to the real NativeUI.
local actions = {} -- Actions from the native side, by name.

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

-- The hire window's background blues: the icons below sit on them, and
-- shades show through the abacus's frame and under the computer.
local panel_blue = { { 61, 174, 202 }, { 45, 146, 186 }, { 49, 154, 190 }, { 57, 166, 198 },
  { 36, 138, 178 }, { 69, 182, 206 }, { 28, 121, 170 }, { 0, 77, 113 }, { 0, 65, 109 },
  { 0, 93, 121 }, { 32, 130, 174 } }

-- Pictures from the game's sprite sheets: {sheet folder, sheet, sprite, crop,
-- colours to make see-through, version}. The crop (x, y, w, h) is the part of
-- the sprite to keep (all of it if nil).
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

--! A picture of the adviser, as the game shows him talking (UIAdviser).
function NativeUI:adviserPicture()
  local path = self:pictureDir() .. "adviser_v1.png"
  if self.adviser_picture_failed then
    return nil
  end
  if not lfs.attributes(path, "size") then
    local anim = TH.animation()
    anim:setAnimation(self.app.world.anims, 460, DrawFlags.Nearest)
    -- A big canvas; the empty part is trimmed off.
    local ok, err = SDL.native.renderToPNG(path, 200, 200, function()
      anim:draw(self.app.video, 100, 120)
    end)
    if not ok then
      print("Native UI: couldn't make a picture of the adviser: " .. tostring(err))
      self.adviser_picture_failed = true
      return nil
    end
  end
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

return { methods = NativeUI, actions = actions }

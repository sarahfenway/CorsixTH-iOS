# Plan: make CorsixTH feel like an iPhone/iPad game

Read `CLAUDE.md` first for the layout, build commands and rules.

## Where things stand

**Verified on a real iPhone:**
- The app builds, signs, launches and renders.
- The SDL2 UIScene backport works (without it the app is refused at launch).
- Trackpad touch controls work.

**Written but never run (check these first):**
- iCloud Drive saves (`ios_platform.mm`, entitlements, `NSUbiquitousContainers`) and copying older
  local saves into iCloud.
- Saving `Resume.sav` when the app goes into the background, and resuming from it on launch.
- Console redirected to `Logs/console.txt`.
- On-screen keyboard for text boxes (save names, hospital name).
- Pinch zoom and two-finger pan on a real multi-touch screen.

**Known gaps:**
- No music: iOS has no MIDI synthesiser, and Theme Hospital's soundtrack is MIDI (XMI).
- No intro or cut-scene movies (that would need FFmpeg).
- The game draws under the notch/Dynamic Island and home indicator.
- The logical resolution is fixed at launch, so folding/unfolding and iPad multitasking aren't handled.

**Open bug from Sarah:** saving never seemed to stick. The likely causes are an unwritable save
folder (CorsixTH then silently falls back to `os.tmpname()`, which iOS forbids) or the keyboard not
appearing. The iCloud and resume work is meant to fix it. Confirm it from `console.txt`.

**Goal:** an app that feels native on iPhone and iPad, while the hospital itself keeps the original
artwork. The UI is CorsixTH's own Lua code (it only draws TH sprites), so it can be changed or
replaced freely.

---

## Phase 0: simulator workflow and test harness (do this first)

1. **Put the project under git.** It isn't a repo yet. Commit everything except the gitignored
   paths (`deps/`, `build-ios/`, `ThemeHospital/`, `Music/`).
2. **Simulator build path.** Add a `--simulator [device name]` option to `build-ios.sh` that
   generates the project if needed (without opening Xcode), builds for the simulator, installs and
   launches. The commands are in `CLAUDE.md`. If iCloud entitlements get in the way of simulator
   signing, build with `ICLOUD=OFF` for the simulator.
3. **Automation harness.** Add an in-app script runner so UI flows can be repeated and screenshotted
   without a human. Keep it in the touch build only, and only active when an environment variable
   is set. `xcrun simctl launch` forwards variables prefixed with `SIMCTL_CHILD_`.
   - `CORSIXTH_AUTOMATION=/path/to/script.txt` (the simulator can read host paths), one command per
     line:
     - `wait <ms>`
     - `tap <x> <y>`, `drag <x1> <y1> <x2> <y2> <ms>`, `twofinger_tap <x> <y>`,
       `pinch <x> <y> <scale>`, `pan <dx> <dy>`
     - `lua <code>`: run in the app's Lua state with `TheApp` available, for example to start a
       level or open a dialog directly
     - `screenshot <name>`: use CorsixTH's own screenshot (`TheApp.video:takeScreenshot`) into
       `Documents/CorsixTH/Screenshots`, or rely on `xcrun simctl io booted screenshot`
     - `log <text>`
   - Inject touches as real `SDL_FINGERDOWN/MOTION/UP` events via `SDL_PushEvent`, with the game
     window's `windowID` and a `touchId` other than `SDL_MOUSE_TOUCHID`. They then go through
     `touch_ui::handle_event` exactly like real fingers. Coordinates in screen points, normalised
     by the window size.
   - Run the script from the main loop's timer tick (`SDL_USEREVENT_TICK` in `sdl_core.cpp`) so it
     interleaves with normal frames.
   - Write a few scripts in `tests/automation/`: start a new game, open and close build and hire,
     save, load, background and relaunch.
4. **Check everything in "written but never run"** using the harness:
   - A save made from the File menu appears in `Saves/`, in iCloud when signed in.
   - Sending the app to the background (`xcrun simctl launch` another app, or the Home button)
     writes `Resume.sav`, and a relaunch continues the game.
   - The keyboard appears for the save-name box.
   - Fix whatever fails, then re-run on Sarah's phone.
5. **Optional:** get the macOS desktop build working (`cmake -S . -B build-mac -G Xcode`, run with
   `CORSIXTH_TOUCH_UI=1 CORSIXTH_TOUCH_SCREEN=874x402`) for even faster Lua UI iteration. It
   should work but has never been built.

**Done when:** one command builds, installs and runs a scripted flow in the simulator and leaves
screenshots, and every item above has been seen working.

---

## Phase 1: native "system" UI (the biggest win)

Replace the PC-style menus that sit around the game with native UIKit/SwiftUI screens shown over
the game view.

### Bridge (build this first)

- **Native side:** SwiftUI views hosted in `UIHostingController`, presented from SDL's root view
  controller (`SDL_GetWindowWMInfo` → `info.uikit.window.rootViewController`). Expose
  `@_cdecl` C functions to C++. CMake: `enable_language(Swift)`, add `.swift` sources to the
  `CorsixTH` target, set `XCODE_ATTRIBUTE_SWIFT_VERSION`. If Swift + CMake turns out to be painful,
  Objective-C++ with UIKit is an acceptable fallback; `ios_platform.mm` shows the pattern.
- **Lua → native:** a new C function, for example `SDL.native.show(screen, payload)`, where
  `payload` is a JSON string. Add a small MIT JSON library for Lua, or write one; payloads are
  small. Example screens: `game_menu`, `save`, `load`, `settings`, `main_menu`, `text_input`.
- **Native → Lua:** native code calls `native_post(action, payload)`, which pushes an
  `SDL_RegisterEvents` user event carrying a heap-allocated copy. `sdl_core.cpp` dispatches it as
  `"native"` to `App:onNativeAction(action, payload)`. Only the SDL main loop touches Lua: UIKit
  callbacks run inside `SDL_PumpEvents` on the main thread, but must not call Lua directly.
- **While a native sheet is open:** pause the game (remember and restore the speed via
  `world:setSpeed`), and stop touches from reaching the game.

### Screens, in order

1. **Game menu button + native game menu.**
   - On touch, hide the hover-to-open top menu bar. It's created in `Lua/game_ui.lua`
     (`UIMenuBar`); its menus are built in `Lua/dialogs/menu.lua`, see `makeGameMenu` and the
     speed menu around `world:setSpeed`.
   - Add a small always-visible button in a safe corner that opens a native sheet with: Resume,
     game speed (Pause / Slowest…Max), Save, Load, Settings, Restart level, Quit to main menu.
   - Map each item to the same Lua actions the menu bar uses.
   - Also put the most-used in-game windows a tap away: Staff Management, Town Map, Research,
     Graphs, Bank Manager, Status, Casebook (`Lua/dialogs/fullscreen/*.lua`).
2. **Native Save / Load.**
   - Lists `TheApp.savegame_dir` including `Autosaves/` and `Resume.sav`, with dates.
   - New save with a native text field; overwrite, rename and delete; shows iCloud status.
   - Calls `App:save` / `App:load` (`Lua/app.lua`).
   - Replaces `Lua/dialogs/resizables/file_browsers/save_game.lua` / `load_game.lua` on touch.
3. **Native text entry everywhere** (hospital name, save name, etc.). Use an alert with a text
   field instead of TH text boxes plus the SDL keyboard (`Textbox` in `Lua/window.lua`).
4. **Native Settings.**
   - Volumes and toggles, language, touch controls (trackpad/direct), cursor speed (expose
     `trackpad_recogniser::settings::speed` through a config key), edge scrolling, adviser on/off.
   - Read and write `TheApp.config` and call `App:saveConfig()`. See
     `Lua/dialogs/resizables/options.lua` and `sound_setting.lua` for what each setting does.
5. **Native main menu.**
   - Continue (latest Resume/autosave), New Game (difficulty/level, see
     `Lua/dialogs/resizables/new_game.lua`), Campaigns / custom levels, Load, Settings.
   - Shown over the TH menu background. Replaces `Lua/dialogs/resizables/main_menu.lua` on touch.

**Done when:** none of the PC-style menus, file browsers, text boxes or options windows can be
reached on touch, and everything they did can be done from native screens. Check with automation
screenshots, then on Sarah's iPhone and iPad.

---

## Phase 2: make the remaining original UI touch-friendly

1. **Safe areas.**
   - Keep important UI out of the notch/Dynamic Island, rounded corners and home-indicator areas.
   - Get insets in `ios_platform.mm` (`UIWindow.safeAreaInsets`).
   - Either inset the logical viewport (SDL2 has no safe-area API), or keep the map full-bleed
     and inset only the UI windows and bottom panel.
2. **Respond to size changes** (iPhone Duo fold/unfold, rotation, iPad multitasking).
   - Recompute the logical resolution on `SDL_WINDOWEVENT_SIZE_CHANGED` instead of only at launch
     (`touch_ui::platform_init`).
   - Call `UI:changeResolution(width, height)` (`Lua/ui.lua`), the way desktop window resizes do.
   - `UI:onWindowResize` currently ignores resizes when fullscreen.
3. **Bigger UI on phones.** At about 1044×480 logical pixels the TH interface is small.
   - Options: scale UI windows up to the screen height; a non-integer `ui_scale` for touch; or a
     touch-specific layout for the bottom panel (`Lua/dialogs/bottom_panel.lua`).
   - Pick by screenshotting the alternatives in the simulator.
   - CorsixTH can draw text with FreeType (`unicode_font`) for crisper, larger text.
4. **Hover-only features.**
   - Tooltips, cursor highlights and anything that relies on hovering need a touch equivalent,
     for example long-press for a tooltip in direct mode.
   - Audit `updateTooltip` in `Lua/ui.lua` and `onMouseMove` handlers.

---

## Phase 3: native in-game panels (one at a time; keep the TH version as a fallback)

Each panel needs read access to live game state: a Lua function that builds a plain table,
serialised to JSON for the bridge, refreshed while the panel is open. Each also needs actions
back: bridge actions that call existing Lua functions. Suggested order:

1. **Hire staff** (`hire_staff.lua`): candidate list, skills, wages, hire.
2. **Build room** (`build_room.lua`): room catalogue with costs. Placing the room stays on the map,
   using the existing blueprint tool.
3. **Hospital overview:** status, money, reputation, goals for the level (`progress_report.lua`,
   `bank_manager.lua`, `graphs.lua`, using Swift Charts).
4. **Staff management** (`staff_management.lua`), **Research** (`research_policy.lua`),
   **Casebook** (`drug_casebook.lua`).
5. **Fax/messages and adviser history** (`fax.lua`, `adviser_history.lua`): could use native
   notifications-style banners.
6. **Inspectors** for a tapped staff member or patient (`staff_dialog.lua`, `patient.lua`), as a
   native card.

---

## Phase 4: audio, movies and polish

- **Music.** CorsixTH already plays a folder of OGG/MP3 instead of MIDI. `CMakeLists.txt` bundles
  a `Music/` folder (`MUSIC_DIR`) and the touch build uses it automatically.
  - Add a build step that converts `ThemeHospital/SOUND/MIDI/*.XMI` → MIDI, using CorsixTH's
    `xmi2mid.cpp` in a tiny CLI.
  - Render with FluidSynth and a General MIDI soundfont, e.g. GeneralUser GS (Homebrew:
    `fluid-synth`), and encode to OGG.
  - When music is bundled, make sure `play_music` gets switched on: `App:init` currently forces it
    off only when there's no music, but an older config.txt may still have it off.
- **Movies (optional).** FFmpeg built for iOS, with `WITH_MOVIES` / `CORSIX_TH_USE_FFMPEG`. Keep
  `ANIMS/` and `INTRO/` in `tools/extract_gog_pkg.py`'s list if this is done.
- **Polish.** Haptics on key actions, game controller and hardware keyboard shortcuts on iPad,
  proper launch screen, iPad pointer hover effects.

---

## Ground rules

- Small, reviewable steps. After each phase, write a short note for Sarah: what changed, what was
  verified in the simulator, and what she needs to check on her phone or iPad.
- `build-ios.sh` on a clean checkout must reproduce the app. Our code stays out of `CorsixTH/`
  (see `CLAUDE.md`): new code in `src/`, only unavoidable hooks in `patches/corsixth-ios.patch`.
- Desktop CorsixTH behaviour must not change. Gate everything on touch mode.
- Never commit or redistribute Theme Hospital's data files.

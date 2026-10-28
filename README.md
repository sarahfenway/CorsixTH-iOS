# Theme Hospital for iPhone and iPad

This builds **CorsixTH**, the open-source rebuild of the Theme Hospital engine, as an iOS app.
It uses the graphics, sounds and levels from your GOG copy of the game. The original game's
program isn't used at all, so nothing gets decompiled. Your game data is bundled into the app,
so there's nothing to copy across afterwards.

## What you need

- A Mac with **Xcode** installed from the App Store. Open it once and let it install the iOS
  platform if it offers.
- Your **Apple ID** signed in to Xcode (Xcode > Settings > Accounts). A free Apple ID works.
- Your iPhone or iPad with **Developer Mode** on (Settings > Privacy & Security > Developer Mode,
  then restart the phone). The option only shows up after the phone has been plugged into a Mac
  that has Xcode open.
- The GOG installer, `theme_hospital_enUS_1_0_3_33062_1.pkg`. The script looks for it in your
  Downloads folder, or you can give it the path.

## Build it

```bash
cd CorsixTH-iOS
bash build-ios.sh ~/Downloads/theme_hospital_enUS_1_0_3_33062_1.pkg
```

The script checks Xcode, downloads CMake if you don't have it, and fetches pinned versions of
CorsixTH 0.70.1, SDL2, SDL2_mixer, Lua 5.4, LPeg, LuaFileSystem, FreeType and libpng. It applies
the iOS patch to CorsixTH and pulls the game data out of the installer (about 90 MB).

CorsixTH isn't part of this repository. The script clones it into a `CorsixTH/` folder here; if
you'd rather get it yourself, download the
[CorsixTH 0.70.1 source](https://github.com/CorsixTH/CorsixTH/releases/tag/v0.70.1) and unzip it
so that `CorsixTH/CorsixTH/CorsixTH.lua` exists before running the script.

On the first run it lists the development teams on your Mac and asks which one should sign the
app. Pick your own (the one marked **Personal Team** if you're on a free Apple ID), not a work
team. The answer is saved in `.team-id`. To change it later, run `bash build-ios.sh --team`.

Then it generates an Xcode project and opens it. In Xcode:

1. Plug in the phone and unlock it.
2. At the top of the window, choose the **CorsixTH** scheme and your phone.
3. Check the team under CorsixTH project > CorsixTH target > **Signing & Capabilities**. If
   you change it there, the change only lasts until the script runs again, so use `--team` for
   anything permanent.
4. Press **Run**. The first build takes a few minutes.
5. The first time only, on the phone: Settings > General > VPN & Device Management > trust your
   Apple ID.

After you've built once from Xcode, `bash build-ios.sh --install` can rebuild and reinstall
without opening Xcode.

**Free Apple ID limit:** apps signed with a free account stop opening after 7 days. Plug the
phone in and press Run again (or run `--install`), and your saves are kept. A paid developer
account stretches this to a year.

## Controls

By default the screen works like a laptop trackpad. The game's cursor moves by however far your
finger moves, rather than jumping to where you touch:

| Touch | Does |
|---|---|
| Slide one finger | Moves the cursor. Faster flicks move it further. |
| Tap | Left click where the cursor is |
| Tap, then touch again and move | Left-button drag, for sizing rooms, scroll bars and moving windows |
| Two-finger tap | Right click where the cursor is |
| Two-finger drag | Moves the map; the cursor stays put |
| Pinch | Zooms |

If you'd rather click wherever you touch, set `touch_controls = [[direct]]` in
`CorsixTH/config.txt`. In that mode:

| Touch | Does |
|---|---|
| Tap | Left click |
| Touch, pause briefly, then drag | Left-button drag |
| Quick swipe | Moves the pointer without clicking |
| Long press or two-finger tap | Right click |
| Two-finger drag / pinch | Moves the map / zooms |

Menus are native iOS screens. In a game, the bar at the top right builds rooms, furnishes
corridors, edits rooms and hires staff; its building button opens the hospital screens (staff,
town map, research, casebook, graphs, bank...), the play button sets the game speed and the ••• button
opens the game menu (save, load, settings, restart, quit), which pauses the game. Money, the date
and reputation are at the top left, with an envelope when a message (fax) is waiting. Text entry
uses the iOS keyboard. On an iPad, a real trackpad or mouse works too, including right click.

## Saves, settings and music

**Saves go to iCloud Drive**, so they survive reinstalling the app and are shared with your iPad.
They're in a "Theme Hospital" folder in iCloud Drive (Files app, or Finder on a Mac), under `Saves`.
If you're not signed in to iCloud, or the app was built with a free Apple ID, saves stay on the
phone in `CorsixTH/Saves` instead. Any saves already on the phone are copied into iCloud the first
time it's available.

**The game saves itself whenever you leave the app** (going home, switching apps, locking the
phone), and next time it opens it carries on from there. That save is called `Resume`. It also
shows up in the Load list. Leaving a game for the main menu clears it, so the next launch starts at
the menu. The usual monthly autosaves and your own named saves work as before.

The game's console output goes to `Logs/console.txt` in the same iCloud folder. It's handy when
something goes wrong.

The app's own Documents folder appears in the Files app under On My iPhone > Theme Hospital, and in
Finder when the phone is plugged in:

- `CorsixTH/config.txt`: settings
- `CorsixTH/Screenshots`

**Music:** iOS has no MIDI synthesiser, so Theme Hospital's original MIDI soundtrack can't play,
and the music setting starts switched off. If you put `.mp3`, `.ogg`, `.flac` or `.wav` files in a
folder called `CorsixTH/Music`, they become the soundtrack. Switch music back on in the game's
settings. Sound effects and the announcer work as normal.

## Not included yet

- The intro and cut-scene movies. They'd need FFmpeg built for iOS.
- MIDI music (see above).

## Troubleshooting

- **Wrong team:** run `bash build-ios.sh --team` and pick again.
- **Signing errors about iCloud:** Xcode normally switches iCloud on for the app ID by itself. If it
  doesn't, open Signing & Capabilities in Xcode, click **+ Capability**, add **iCloud**, tick
  **iCloud Documents** and the container `iCloud.uk.me.krn.corsixth` (press + to create it if
  needed), then build again. To skip iCloud entirely, use `ICLOUD=OFF bash build-ios.sh`.
- **"Bundle identifier is not available":** another team has already registered
  `uk.me.krn.corsixth`. This happens if Xcode tried to sign with a different team first,
  because Xcode registers the ID with whichever team it uses. Either delete it from that team at
  developer.apple.com > Certificates, Identifiers & Profiles > Identifiers, or use a new one:
  `BUNDLE_ID=uk.me.krn.themehospital bash build-ios.sh`.
- **CMake errors:** the whole log is in `build-ios.cmake.log`.
- **The game can't find its data:** check that `ThemeHospital/` in this folder has `DATA`, `LEVELS`
  and `QDATA` folders, then rebuild.
- **Start again from scratch:** delete `build-ios/` (and `deps/` and `CorsixTH/` to re-download the sources).

## How the port is put together

This project's own code is in `src/` and is compiled into the app alongside CorsixTH:

- `touch_gestures.*`: turns touches into mouse actions, in trackpad or direct mode. It has unit
  tests in `tests/test_touch_gestures.cpp`.
- `touch_ui.*`: iOS start-up. It keeps config in Documents, finds the bundled data, picks a
  resolution that fits the screen (at least 640x480 game pixels, scaled up with sharp pixels) and
  sets the SDL hints.
- `touch_storage.*`, `ios_platform.*`: iCloud Drive saves, moving older saves across, and the
  console log file. `touch_storage` has tests in `tests/test_touch_storage.cpp`.
- `touch_automation.*`: scripted test runs in the simulator (`build-ios.sh --run tests/automation`).
- `native_bridge.*` and `ios/*.swift` (SwiftUI/UIKit), with `lua/native_ui.lua`: the native main
  menu, game menu, save/load, settings, text entry and the in-game toolbar, which replace
  CorsixTH's PC-style menus, dialogs and bottom panel.

`patches/corsixth-ios.patch` makes the small changes needed in CorsixTH's own files:

- `sdl_core.cpp`: routes touch events through the above, and stops drawing while the app is in
  the background.
- `th_gfx_sdl.cpp`: creates a full-screen, high-DPI window on iOS.
- `sdl_wm.cpp`, `window.lua`, `ui.lua`: the on-screen keyboard for text boxes.
- `game_ui.lua`: pinch zoom on touch screens, also while panning.
- `app.lua`: saving when the app goes into the background, and resuming on launch.
- `app.lua`, `config_finder.lua`: iOS settings (resolution, bundled data, touch controls, no
  edge scrolling, music off without music files).
- `ui.lua`, `menu.lua`, `bottom_panel.lua`, `window.lua`, `game_ui.lua`: hooks that hand menus,
  file dialogs, text boxes and the bottom panel to the native UI.

`tools/sdl2_uiscene_edit.py` also patches SDL2, because apps built with current iOS SDKs must use
Apple's scene-based life cycle (UIScene), which SDL2 predates. The approach comes from SDL3: SDL's
app delegate doubles as the scene delegate, the game starts when the scene connects, and windows
are created inside it.

CorsixTH is MIT licensed. Theme Hospital's data belongs to EA, so use your own copy and don't
share builds that contain it.

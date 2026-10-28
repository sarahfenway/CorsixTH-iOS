# Third-party code, art and data

This repository's own code (everything not listed below) is under the MIT licence in
[`LICENSE`](LICENSE).

## CorsixTH (MIT)

- `patches/corsixth-ios.patch` changes CorsixTH's files, so it contains lines of CorsixTH's
  source as context.
- `ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png` is CorsixTH's logo.

Both are covered by CorsixTH's licence, copied in full in
[`licenses/CorsixTH-LICENSE.txt`](licenses/CorsixTH-LICENSE.txt). CorsixTH's own source isn't in
this repository: `build-ios.sh` downloads it (v0.70.1) from
<https://github.com/CorsixTH/CorsixTH>.

## SDL and the other libraries

`build-ios.sh` downloads SDL2, SDL2_mixer, Lua, LPeg, LuaFileSystem, FreeType and libpng from their
upstream projects at pinned versions; none of their source is in this repository. Each keeps its own
licence, which ships in its download. An app you build contains them, so their licences apply to it.

`tools/sdl2_uiscene_edit.py` edits SDL2's UIKit backend after download, following the approach
SDL3 takes (SDL is under the zlib licence). The edited copy is not the original SDL.

## Theme Hospital

Theme Hospital is © 1997 Electronic Arts. Its graphics, sounds, levels and text are **not** in this
repository and must not be added to it. The build extracts them from a copy of the game you own.
Apps built with that data are for your own use: don't share them.

This project isn't affiliated with or endorsed by Electronic Arts, Bullfrog, GOG or the CorsixTH
team.

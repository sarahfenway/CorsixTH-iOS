# Roadmap

What's planned, roughly in order. The README's "Known issues" says what doesn't work yet.

## Next

1. **Check folding and unfolding on a device.** The game follows the screen's new size (tested in
   the simulator by reporting the size change, as the simulator can't be folded from a script).
2. **Safe areas.** Keep the game's remaining windows clear of the notch, Dynamic Island and home
   indicator (the native controls already are), using the window's safe-area insets.

## Native versions of the remaining game windows

Each one reads the game's state from Lua and calls the game's own functions for its actions, as
the existing native panels do. The original window stays as a fallback.

- A card for a tapped member of staff or patient (`staff_dialog.lua`, `patient.lua`).
- The fax machine (`fax.lua`): messages and their choices as a native sheet.
- Hospital overview: money, reputation and the level's goals (`progress_report.lua`,
  `bank_manager.lua`, `graphs.lua` with Swift Charts).
- Staff management, research and the casebook (`staff_management.lua`, `research_policy.lua`,
  `drug_casebook.lua`).
- Long press for the game's tooltips, which on a PC appear on hover.

## Building

- Quick Build with optional extras (radiators, plants, more loos) and better furniture layouts.
- Hiring straight into the room that needs that person.

## Audio, movies and polish

- **Music:** convert the game's XMI tracks to MIDI with CorsixTH's own converter, render them with
  FluidSynth and a General MIDI soundfont at build time, and bundle the result.
- **Movies:** FFmpeg built for iOS, for the intro and cut-scenes.
- Haptics, hardware keyboard shortcuts and game controllers on iPad, a proper launch screen.

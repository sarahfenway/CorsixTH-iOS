/*
Copyright (c) 2026 CorsixTH iOS port contributors

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
SOFTWARE.
*/

#ifndef CORSIX_TH_TOUCH_UI_H_
#define CORSIX_TH_TOUCH_UI_H_

#include <SDL.h>

#include <cstdint>

//! Support for running CorsixTH on touch screens (iOS / iPadOS).
/*!
    On iOS this is always active. On other platforms it is off unless the
    environment variable CORSIXTH_TOUCH_UI=1 is set, which exists so the touch
    code paths can be exercised on a desktop.
*/
namespace touch_ui {

//! True when CorsixTH is running with the touch-screen user interface.
bool enabled();

//! Prepare the process before Lua and SDL start.
/*!
    Chooses where config.txt and saves live, finds game data bundled with the
    app, works out a logical resolution that suits the screen and sets the SDL
    hints a touch device needs. The results are passed to the Lua side through
    environment variables (CORSIXTH_TOUCH_*). Does nothing unless enabled().
*/
void platform_init();

//! Chooses where saves and logs are kept: iCloud Drive when it's available
//! (CORSIXTH_SAVE_DIR / CORSIXTH_LOG_DIR are set for the Lua side), otherwise
//! next to config.txt. Called by platform_init().
void setup_storage();

//! SDL window flags to use for the game window in touch mode.
uint32_t window_flags();

//! Size to create the game window at in touch mode.
void window_size(int* width, int* height);

//! Handles an SDL touch event, pushing synthesised mouse events onto the SDL
//! event queue. Returns true if the event was consumed. On touch screens it
//! also consumes SDL's own SDL_MULTIGESTURE events: they count every wobble of
//! two panning fingers as a pinch, so touch_ui sends its own instead, only for
//! a real pinch.
bool handle_event(const SDL_Event& e);

//! Chooses how touches work: "trackpad" (the default: the screen moves the
//! cursor like a laptop trackpad) or "direct" (click where you touch).
void set_controls(const char* name);

//! Placing things: touches act directly where the finger is, but with the
//! pointer about 40 points above it so the finger doesn't hide what's being
//! placed. Turning it off restores the player's own touch controls.
void set_placement_mode(bool on);
bool placement_mode_on();

//! The placement pointer's offset above the finger, in game pixels.
float placement_offset();

//! Sets the trackpad cursor speed multiplier (1 = the finger's distance).
void set_cursor_speed(double speed);

//! Drives time based gestures. Call on every timer tick of the main loop.
void poll();

}  // namespace touch_ui

#endif  // CORSIX_TH_TOUCH_UI_H_

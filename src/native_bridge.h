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

#ifndef CORSIX_TH_NATIVE_BRIDGE_H_
#define CORSIX_TH_NATIVE_BRIDGE_H_

#include <SDL.h>

struct lua_State;

//! Lets the Lua UI show native (SwiftUI) screens, and native screens send
//! actions back to Lua.
/*!
    Lua -> native: the SDL.native table (see luaopen) passes a screen name and
    a JSON payload to the Swift side (src/ios/NativeUI.swift).

    Native -> Lua: Swift calls cth_native_post(action, json), which queues an
    SDL user event. The main loop hands it to native_bridge::push_event_args
    and dispatches it to Lua as "native" (App:onNativeAction(action, json)).
    Lua is only ever called from the SDL main loop.
*/
namespace native_bridge {

//! Registers SDL.native: available(), show(screen, json), update(json),
//! dismiss(), setToolbar(json or nil), setQuickBuild(json or nil),
//! post(action, json) (for tests),
//! screen() (the screen showing, or nil), tap(label) (tests: activates a
//! native control by its accessibility label) and setCursorSpeed(multiplier).
int luaopen(lua_State* L);

//! True if e is an action from the native UI.
bool is_native_event(const SDL_Event& e);

//! Pushes an action event's action and JSON payload strings onto the Lua
//! stack and frees the event's copies of them. Returns the number pushed.
int push_event_args(lua_State* L, const SDL_Event& e);

}  // namespace native_bridge

extern "C" {
//! Queues an action for Lua. Safe to call from UIKit callbacks.
void cth_native_post(const char* action, const char* json);
}

#endif  // CORSIX_TH_NATIVE_BRIDGE_H_

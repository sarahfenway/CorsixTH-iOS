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

#include "native_bridge.h"

#include <cstdlib>
#include <cstring>

#include "lua.hpp"
#include "touch_ui.h"

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif
#if defined(__APPLE__) && TARGET_OS_IPHONE
#define CTH_NATIVE_UI 1
// Implemented in Swift (src/ios/NativeUI.swift).
extern "C" {
void cth_native_show(const char* screen, const char* json);
void cth_native_update(const char* json);
void cth_native_dismiss();
void cth_native_set_toolbar(const char* json);
void cth_native_set_quick_build(const char* json);
const char* cth_native_screen();
bool cth_native_tap(const char* label);
}
#else
#define CTH_NATIVE_UI 0
#endif

namespace native_bridge {

namespace {

Uint32 native_event_type() {
  // CorsixTH uses SDL_USEREVENT + 0...4 without registering them (lua_sdl.h),
  // so skip past those.
  static const Uint32 type = [] {
    Uint32 t;
    do {
      t = SDL_RegisterEvents(1);
    } while (t != static_cast<Uint32>(-1) && t <= SDL_USEREVENT + 4);
    return t;
  }();
  return type;
}

char* copy_string(const char* text) {
  if (text == nullptr) {
    text = "";
  }
  size_t size = std::strlen(text) + 1;
  char* copy = static_cast<char*>(std::malloc(size));
  std::memcpy(copy, text, size);
  return copy;
}

int l_available(lua_State* L) {
  lua_pushboolean(L, CTH_NATIVE_UI && touch_ui::enabled());
  return 1;
}

int l_show(lua_State* L) {
  const char* screen = luaL_checkstring(L, 1);
  const char* json = luaL_optstring(L, 2, "{}");
#if CTH_NATIVE_UI
  cth_native_show(screen, json);
#else
  (void)screen;
  (void)json;
#endif
  return 0;
}

int l_update(lua_State* L) {
  const char* json = luaL_checkstring(L, 1);
#if CTH_NATIVE_UI
  cth_native_update(json);
#else
  (void)json;
#endif
  return 0;
}

int l_dismiss(lua_State*) {
#if CTH_NATIVE_UI
  cth_native_dismiss();
#endif
  return 0;
}

// setToolbar(json) shows the in-game toolbar, setToolbar(nil) hides it.
int l_set_toolbar(lua_State* L) {
  const char* json = luaL_optstring(L, 1, "");
#if CTH_NATIVE_UI
  cth_native_set_toolbar(json);
#else
  (void)json;
#endif
  return 0;
}

int l_screen(lua_State* L) {
#if CTH_NATIVE_UI
  const char* screen = cth_native_screen();
  if (screen != nullptr && *screen != '\0') {
    lua_pushstring(L, screen);
    return 1;
  }
#endif
  lua_pushnil(L);
  return 1;
}

// Pretends the native UI sent an action (automation scripts use this to
// drive native screens, which they can't tap).
int l_post(lua_State* L) {
  cth_native_post(luaL_checkstring(L, 1), luaL_optstring(L, 2, "{}"));
  return 0;
}

// setQuickBuild(json) shows Quick Build's handles and bar, (nil) removes them.
int l_set_quick_build(lua_State* L) {
  const char* json = luaL_optstring(L, 1, "");
#if CTH_NATIVE_UI
  cth_native_set_quick_build(json);
#else
  (void)json;
#endif
  return 0;
}

// Activates the native control with this accessibility label (tests).
int l_tap(lua_State* L) {
  const char* label = luaL_checkstring(L, 1);
#if CTH_NATIVE_UI
  lua_pushboolean(L, cth_native_tap(label));
#else
  (void)label;
  lua_pushboolean(L, false);
#endif
  return 1;
}

int l_set_cursor_speed(lua_State* L) {
  touch_ui::set_cursor_speed(luaL_checknumber(L, 1));
  return 0;
}

constexpr luaL_Reg native_lib[] = {{"available", l_available},
                                   {"show", l_show},
                                   {"update", l_update},
                                   {"dismiss", l_dismiss},
                                   {"setToolbar", l_set_toolbar},
                                   {"setQuickBuild", l_set_quick_build},
                                   {"screen", l_screen},
                                   {"post", l_post},
                                   {"tap", l_tap},
                                   {"setCursorSpeed", l_set_cursor_speed},
                                   {nullptr, nullptr}};

}  // namespace

int luaopen(lua_State* L) {
  native_event_type();  // Register the event type on the main thread.
  luaL_newlib(L, native_lib);
  return 1;
}

bool is_native_event(const SDL_Event& e) {
  return e.type == native_event_type();
}

int push_event_args(lua_State* L, const SDL_Event& e) {
  char* action = static_cast<char*>(e.user.data1);
  char* json = static_cast<char*>(e.user.data2);
  lua_pushstring(L, action != nullptr ? action : "");
  lua_pushstring(L, json != nullptr ? json : "{}");
  std::free(action);
  std::free(json);
  return 2;
}

}  // namespace native_bridge

extern "C" void cth_native_post(const char* action, const char* json) {
  SDL_Event e{};
  e.type = native_bridge::native_event_type();
  e.user.data1 = native_bridge::copy_string(action);
  e.user.data2 = native_bridge::copy_string(json);
  if (SDL_PushEvent(&e) != 1) {
    std::free(e.user.data1);
    std::free(e.user.data2);
  }
}

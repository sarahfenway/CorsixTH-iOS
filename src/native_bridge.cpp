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

#include <png.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <vector>

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
void cth_native_set_editor(const char* json);
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

// setEditor(json) shows the room editor / furnishing controls, (nil) removes
// them (lua/room_editor.lua).
int l_set_editor(lua_State* L) {
  const char* json = luaL_optstring(L, 1, "");
#if CTH_NATIVE_UI
  cth_native_set_editor(json);
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

// renderToPNG(path, width, height, draw[, key]) points the game's renderer at
// an offscreen picture of that size, calls draw() (which draws with the game's
// own code, e.g. an animation onto TheApp.video at picture coordinates), and
// saves the drawn part (empty borders trimmed) as a PNG with transparency.
// key, a list of {r, g, b}, makes those colours see-through.
// Used to show the game's art
// in native menus. Returns true or nil, error.
int l_render_to_png(lua_State* L) {
  const char* path = luaL_checkstring(L, 1);
  int width = static_cast<int>(luaL_checkinteger(L, 2));
  int height = static_cast<int>(luaL_checkinteger(L, 3));
  luaL_checktype(L, 4, LUA_TFUNCTION);
  SDL_Window* window = SDL_GetKeyboardFocus();
  for (Uint32 id = 1; window == nullptr && id < 16; ++id) {
    window = SDL_GetWindowFromID(id);
  }
  SDL_Renderer* renderer = window != nullptr ? SDL_GetRenderer(window) : nullptr;
  if (renderer == nullptr || width <= 0 || height <= 0) {
    lua_pushnil(L);
    lua_pushliteral(L, "no renderer");
    return 2;
  }
  SDL_Texture* previous = SDL_GetRenderTarget(renderer);
  SDL_Texture* picture =
      SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ABGR8888,
                        SDL_TEXTUREACCESS_TARGET, width, height);
  if (picture == nullptr || SDL_SetRenderTarget(renderer, picture) != 0) {
    if (picture != nullptr) SDL_DestroyTexture(picture);
    lua_pushnil(L);
    lua_pushstring(L, SDL_GetError());
    return 2;
  }
  SDL_SetTextureBlendMode(picture, SDL_BLENDMODE_BLEND);
  SDL_SetRenderDrawColor(renderer, 0, 0, 0, 0);
  SDL_RenderClear(renderer);

  lua_pushvalue(L, 4);
  int status = lua_pcall(L, 0, 0, 0);

  // ABGR8888 is R, G, B, A in memory order on little-endian machines, which
  // is libpng's RGBA.
  std::vector<unsigned char> pixels(static_cast<size_t>(width) * height * 4);
  bool read = SDL_RenderReadPixels(renderer, nullptr, SDL_PIXELFORMAT_ABGR8888,
                                   pixels.data(), width * 4) == 0;
  SDL_SetRenderTarget(renderer, previous);
  SDL_DestroyTexture(picture);
  if (status != LUA_OK) {
    lua_pushnil(L);
    lua_insert(L, -2);  // nil, error message
    return 2;
  }
  if (!read) {
    lua_pushnil(L);
    lua_pushstring(L, SDL_GetError());
    return 2;
  }
  // Colours to make see-through (a sprite's own background), if given as
  // {{r, g, b}, ...}.
  if (lua_istable(L, 5)) {
    lua_Integer keys = luaL_len(L, 5);
    for (lua_Integer k = 1; k <= keys; ++k) {
      lua_rawgeti(L, 5, k);
      unsigned char rgb[3] = {0, 0, 0};
      for (int c = 0; c < 3; ++c) {
        lua_rawgeti(L, -1, c + 1);
        rgb[c] = static_cast<unsigned char>(lua_tointeger(L, -1));
        lua_pop(L, 1);
      }
      lua_pop(L, 1);
      for (size_t i = 0; i < pixels.size(); i += 4) {
        if (pixels[i] == rgb[0] && pixels[i + 1] == rgb[1] && pixels[i + 2] == rgb[2]) {
          pixels[i + 3] = 0;
        }
      }
    }
  }
  // Trim to the pixels that were drawn, keeping a one pixel margin.
  int min_x = width;
  int min_y = height;
  int max_x = -1;
  int max_y = -1;
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      if (pixels[(static_cast<size_t>(y) * width + x) * 4 + 3] != 0) {
        min_x = std::min(min_x, x);
        max_x = std::max(max_x, x);
        min_y = std::min(min_y, y);
        max_y = std::max(max_y, y);
      }
    }
  }
  if (max_x < 0) {
    min_x = min_y = max_x = max_y = 0;  // Nothing drawn: a 1x1 picture.
  } else {
    min_x = std::max(0, min_x - 1);
    min_y = std::max(0, min_y - 1);
    max_x = std::min(width - 1, max_x + 1);
    max_y = std::min(height - 1, max_y + 1);
  }
  png_image image{};
  image.version = PNG_IMAGE_VERSION;
  image.width = static_cast<png_uint_32>(max_x - min_x + 1);
  image.height = static_cast<png_uint_32>(max_y - min_y + 1);
  image.format = PNG_FORMAT_RGBA;
  const unsigned char* first =
      pixels.data() + (static_cast<size_t>(min_y) * width + min_x) * 4;
  if (!png_image_write_to_file(&image, path, 0, first, width * 4, nullptr)) {
    lua_pushnil(L);
    lua_pushstring(L, image.message);
    return 2;
  }
  lua_pushboolean(L, 1);
  return 1;
}

// setPlacementTouch(mode): the native editors' touch controls: "place"
// (placing an item), true or "pick" (direct taps), false (the player's own).
int l_set_placement_touch(lua_State* L) {
  touch_ui::placement_touch mode = touch_ui::placement_touch::off;
  if (lua_type(L, 1) == LUA_TSTRING && std::strcmp(lua_tostring(L, 1), "place") == 0) {
    mode = touch_ui::placement_touch::place;
  } else if (lua_toboolean(L, 1)) {
    mode = touch_ui::placement_touch::pick;
  }
  touch_ui::set_placement_mode(mode);
  return 0;
}

// movePointer(x, y): moves the game's pointer there (game pixels).
int l_move_pointer(lua_State* L) {
  touch_ui::move_pointer(static_cast<int>(std::lround(luaL_checknumber(L, 1))),
                         static_cast<int>(std::lround(luaL_checknumber(L, 2))));
  return 0;
}

// setDirectRegions({{x, y, w, h}, ...}): the game's dialogs on screen, in
// game pixels; with the trackpad, touches on them act where they land.
int l_set_direct_regions(lua_State* L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  std::vector<touch_ui::region> regions;
  lua_Integer n = luaL_len(L, 1);
  for (lua_Integer i = 1; i <= n; ++i) {
    lua_geti(L, 1, i);
    int v[4] = {0, 0, 0, 0};
    for (int k = 0; k < 4; ++k) {
      lua_geti(L, -1, k + 1);
      v[k] = static_cast<int>(std::lround(lua_tonumber(L, -1)));  // may be fractional
      lua_pop(L, 1);
    }
    lua_pop(L, 1);
    regions.push_back({v[0], v[1], v[2], v[3]});
  }
  touch_ui::set_direct_regions(std::move(regions));
  return 0;
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
                                   {"setEditor", l_set_editor},
                                   {"screen", l_screen},
                                   {"post", l_post},
                                   {"tap", l_tap},
                                   {"renderToPNG", l_render_to_png},
                                   {"setPlacementTouch", l_set_placement_touch},
                                   {"movePointer", l_move_pointer},
                                   {"setDirectRegions", l_set_direct_regions},
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

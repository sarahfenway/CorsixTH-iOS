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

#include "touch_ui.h"

#include "touch_automation.h"
#include "touch_gestures.h"
#include "touch_storage.h"

#include <sys/stat.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif
#if defined(__APPLE__) && TARGET_OS_IPHONE
#include "ios_platform.h"
#endif

namespace touch_ui {

static_assert(button_left == SDL_BUTTON_LEFT, "button numbers must match SDL");
static_assert(button_middle == SDL_BUTTON_MIDDLE, "button numbers must match SDL");
static_assert(button_right == SDL_BUTTON_RIGHT, "button numbers must match SDL");

namespace {

constexpr bool built_for_ios() {
#if defined(__APPLE__) && TARGET_OS_IPHONE
  return true;
#else
  return false;
#endif
}

bool is_directory(const std::string& path) {
  struct stat st {};
  return stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

void set_env(const char* name, const std::string& value, bool overwrite) {
  setenv(name, value.c_str(), overwrite ? 1 : 0);
}

int env_int(const char* name, int fallback) {
  const char* value = std::getenv(name);
  if (value == nullptr || *value == '\0') {
    return fallback;
  }
  return std::atoi(value);
}

// Size of the screen (or simulated screen) in window coordinates.
int screen_w = 0;
int screen_h = 0;

// Two ways of turning touches into mouse input; see touch_gestures.h.
gesture_recogniser direct;
trackpad_recogniser trackpad;
bool trackpad_mode = true;
std::vector<mouse_action> actions;
// The game's logical screen size, as last seen on the renderer.
int logical_w = 0;
int logical_h = 0;
int cursor_x = 0;
int cursor_y = 0;
uint32_t buttons_held = 0;

bool finger_to_logical(const SDL_TouchFingerEvent& f, int* x, int* y) {
  SDL_Window* window = SDL_GetWindowFromID(f.windowID);
  if (window == nullptr) {
    window = SDL_GetMouseFocus();
  }
  if (window == nullptr) {
    window = SDL_GetKeyboardFocus();
  }
  if (window == nullptr) {
    return false;
  }
  int ww = 0;
  int wh = 0;
  SDL_GetWindowSize(window, &ww, &wh);
  int wx = static_cast<int>(std::lround(f.x * ww));
  int wy = static_cast<int>(std::lround(f.y * wh));

  SDL_Renderer* renderer = SDL_GetRenderer(window);
  if (renderer == nullptr) {
    *x = wx;
    *y = wy;
    return true;
  }
  float lx = 0;
  float ly = 0;
  SDL_RenderWindowToLogical(renderer, wx, wy, &lx, &ly);
  int lw = 0;
  int lh = 0;
  SDL_RenderGetLogicalSize(renderer, &lw, &lh);
  if (lw > 0 && lh > 0) {
    logical_w = lw;
    logical_h = lh;
    lx = std::clamp(lx, 0.0f, static_cast<float>(lw - 1));
    ly = std::clamp(ly, 0.0f, static_cast<float>(lh - 1));
  }
  *x = static_cast<int>(lx);
  *y = static_cast<int>(ly);
  return true;
}

uint32_t button_mask(int button) {
  return SDL_BUTTON(static_cast<uint32_t>(button));
}

// Pushes synthesised mouse events onto the SDL queue. windowID is left at 0
// so SDL's renderer does not rescale the (already logical) coordinates.
void flush_actions() {
  for (const mouse_action& a : actions) {
    SDL_Event ev{};
    switch (a.type) {
      case mouse_action::kind::move:
        if (a.x == cursor_x && a.y == cursor_y) {
          continue;
        }
        ev.type = SDL_MOUSEMOTION;
        ev.motion.timestamp = SDL_GetTicks();
        ev.motion.which = 0;
        ev.motion.state = buttons_held;
        ev.motion.x = a.x;
        ev.motion.y = a.y;
        ev.motion.xrel = a.x - cursor_x;
        ev.motion.yrel = a.y - cursor_y;
        break;
      case mouse_action::kind::pan:
        // Drag the map with the middle button while the pointer stays put.
        ev.type = SDL_MOUSEMOTION;
        ev.motion.timestamp = SDL_GetTicks();
        ev.motion.which = 0;
        ev.motion.state = buttons_held;
        ev.motion.x = cursor_x;
        ev.motion.y = cursor_y;
        ev.motion.xrel = a.x;
        ev.motion.yrel = a.y;
        SDL_PushEvent(&ev);
        continue;
      case mouse_action::kind::press:
      case mouse_action::kind::release: {
        bool press = a.type == mouse_action::kind::press;
        ev.type = press ? SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
        ev.button.timestamp = SDL_GetTicks();
        ev.button.which = 0;
        ev.button.button = static_cast<Uint8>(a.button);
        ev.button.state = press ? SDL_PRESSED : SDL_RELEASED;
        ev.button.clicks = 1;
        ev.button.x = a.x;
        ev.button.y = a.y;
        if (press) {
          buttons_held |= button_mask(a.button);
        } else {
          buttons_held &= ~button_mask(a.button);
        }
        break;
      }
    }
    cursor_x = a.x;
    cursor_y = a.y;
    SDL_PushEvent(&ev);
  }
  actions.clear();
}

}  // namespace

bool enabled() {
  static const bool value = [] {
    if (built_for_ios()) {
      return true;
    }
    const char* env = std::getenv("CORSIXTH_TOUCH_UI");
    return env != nullptr && env[0] == '1';
  }();
  return value;
}

void platform_init() {
  if (!enabled()) {
    return;
  }
  set_env("CORSIXTH_TOUCH_UI", "1", true);

  if (built_for_ios()) {
    // Keep config.txt, screenshots (and saves, unless iCloud Drive is
    // available) in the app's Documents folder, which the Files app and
    // Finder can see.
    const char* home = std::getenv("HOME");
    if (home != nullptr) {
      set_env("XDG_CONFIG_HOME", std::string(home) + "/Documents", true);
    }
  }
  setup_storage();

  // Game data (and optionally pre-rendered music) bundled inside the app.
  if (char* base = SDL_GetBasePath()) {
    std::string base_path(base);
    SDL_free(base);
    if (is_directory(base_path + "ThemeHospital")) {
      set_env("CORSIXTH_BUNDLED_DATA", base_path + "ThemeHospital", false);
    }
    if (is_directory(base_path + "Music")) {
      set_env("CORSIXTH_BUNDLED_MUSIC", base_path + "Music", false);
    }
  }

  // Hints have to be in place before the video subsystem starts.
  SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
  SDL_SetHint(SDL_HINT_MOUSE_TOUCH_EVENTS, "0");
  SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
  SDL_SetHint(SDL_HINT_IOS_HIDE_HOME_INDICATOR, "2");
  SDL_SetHint(SDL_HINT_IDLE_TIMER_DISABLED, "1");
  if (built_for_ios()) {
    SDL_SetHint(SDL_HINT_RENDER_DRIVER, "metal");
  }
  // The game is drawn at a low logical resolution and scaled up a lot, so
  // sharp pixels look much better than smoothing (which also leaves seams
  // between floor tiles). CORSIXTH_TOUCH_FILTER=linear restores smoothing.
  const char* filter = std::getenv("CORSIXTH_TOUCH_FILTER");
  SDL_SetHintWithPriority(SDL_HINT_RENDER_SCALE_QUALITY,
                          filter != nullptr ? filter : "nearest",
                          SDL_HINT_OVERRIDE);

  // Work out the screen size (landscape) in window coordinates.
  const char* simulated = std::getenv("CORSIXTH_TOUCH_SCREEN");
  if (simulated != nullptr &&
      std::sscanf(simulated, "%dx%d", &screen_w, &screen_h) == 2) {
    // Desktop testing: pretend the window is a device screen of this size.
  } else if (SDL_InitSubSystem(SDL_INIT_VIDEO) == 0) {
    // Video stays initialised; Lua's SDL.init just adds to it later.
    SDL_Rect bounds{};
    if (SDL_GetDisplayBounds(0, &bounds) == 0) {
      screen_w = bounds.w;
      screen_h = bounds.h;
    }
  }
  if (screen_w < screen_h) {
    std::swap(screen_w, screen_h);
  }

  // Theme Hospital's interface needs at least 640x480 game pixels. On small
  // screens (phones) the logical resolution is stretched up to that; on big
  // screens (iPads, folded-out phones) one game pixel is one point.
  if (screen_w > 0 && screen_h > 0) {
    const int min_w = 640;
    const int min_h = env_int("CORSIXTH_TOUCH_MIN_HEIGHT", 480);
    double scale = std::max({static_cast<double>(min_w) / screen_w,
                             static_cast<double>(min_h) / screen_h, 1.0});
    int logical_w = static_cast<int>(std::lround(screen_w * scale));
    int logical_h = static_cast<int>(std::lround(screen_h * scale));
    set_env("CORSIXTH_TOUCH_WIDTH", std::to_string(logical_w), true);
    set_env("CORSIXTH_TOUCH_HEIGHT", std::to_string(logical_h), true);
    std::printf("Touch UI: screen %dx%d, game resolution %dx%d\n", screen_w,
                screen_h, logical_w, logical_h);
  }

  // Scripted test runs (CORSIXTH_AUTOMATION); see touch_automation.h.
  touch_automation::init();
}

void setup_storage() {
  const char* config_home = std::getenv("XDG_CONFIG_HOME");
  std::string local_dir =
      config_home != nullptr ? std::string(config_home) + "/CorsixTH" : "";

  // Saves and logs go to iCloud Drive when possible, so they survive
  // reinstalling and are shared with other devices (and visible on a Mac).
  // CORSIXTH_TEST_CLOUD_DIR stands in for iCloud Drive when testing.
  std::string cloud_dir;
#if defined(__APPLE__) && TARGET_OS_IPHONE
  cloud_dir = ios_platform::icloud_documents_dir();
#else
  if (const char* test_dir = std::getenv("CORSIXTH_TEST_CLOUD_DIR")) {
    cloud_dir = test_dir;
  }
#endif

  std::string log_dir = local_dir.empty() ? "" : local_dir + "/Logs";
  int moved = 0;
  if (!cloud_dir.empty()) {
    std::string saves_dir = cloud_dir + "/Saves";
    log_dir = cloud_dir + "/Logs";
    set_env("CORSIXTH_SAVE_DIR", saves_dir, true);
    set_env("CORSIXTH_LOG_DIR", log_dir, true);
    if (!local_dir.empty()) {
      // Bring along saves made before iCloud Drive was used.
      moved = touch_storage::copy_missing_files(local_dir + "/Saves",
                                                saves_dir, ".sav");
    }
#if defined(__APPLE__) && TARGET_OS_IPHONE
    ios_platform::request_downloads(saves_dir);
#endif
  }

  // On a phone nobody sees stdout, so keep it in a file that can be read
  // afterwards (in iCloud Drive it even turns up on the Mac).
  if (built_for_ios() && !log_dir.empty()) {
    touch_storage::redirect_console(log_dir);
  }
  std::printf("Touch UI: saves in %s\n",
              cloud_dir.empty() ? "the app's Documents folder (no iCloud Drive)"
                                : (cloud_dir + "/Saves").c_str());
  if (moved > 0) {
    std::printf("Touch UI: copied %d earlier save(s) to iCloud Drive\n", moved);
  }
}

uint32_t window_flags() {
  if (built_for_ios()) {
    return SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_FULLSCREEN |
           SDL_WINDOW_BORDERLESS;
  }
  return 0;
}

void window_size(int* width, int* height) {
  if (screen_w > 0 && screen_h > 0) {
    *width = screen_w;
    *height = screen_h;
  }
}

// ---------------------------------------------------------------------------
// SDL glue

bool handle_event(const SDL_Event& e) {
  if (!enabled()) {
    return false;
  }
  switch (e.type) {
    case SDL_FINGERDOWN:
    case SDL_FINGERMOTION:
    case SDL_FINGERUP: {
      const SDL_TouchFingerEvent& f = e.tfinger;
      if (f.touchId == SDL_MOUSE_TOUCHID) {
        return true;  // Touch events faked from a real mouse; ignore.
      }
      int x = 0;
      int y = 0;
      if (!finger_to_logical(f, &x, &y)) {
        return true;
      }
      uint32_t now = SDL_GetTicks();
      if (trackpad_mode) {
        trackpad.set_bounds(logical_w, logical_h);
        if (e.type == SDL_FINGERDOWN) {
          trackpad.finger_down(f.fingerId, x, y, now, actions);
        } else if (e.type == SDL_FINGERMOTION) {
          trackpad.finger_move(f.fingerId, x, y, now, actions);
        } else {
          trackpad.finger_up(f.fingerId, x, y, now, actions);
        }
      } else {
        if (e.type == SDL_FINGERDOWN) {
          direct.finger_down(f.fingerId, x, y, now, actions);
        } else if (e.type == SDL_FINGERMOTION) {
          direct.finger_move(f.fingerId, x, y, now, actions);
        } else {
          direct.finger_up(f.fingerId, x, y, now, actions);
        }
      }
      flush_actions();
      return true;
    }
    case SDL_APP_WILLENTERBACKGROUND:
      direct.cancel(actions);
      trackpad.cancel(actions);
      flush_actions();
      return false;
    default:
      return false;
  }
}

void poll() {
  if (!enabled()) {
    return;
  }
  if (!trackpad_mode) {
    direct.tick(SDL_GetTicks(), actions);  // long press
  }
  flush_actions();
}

void set_controls(const char* name) {
  bool want_trackpad = name == nullptr || std::strcmp(name, "direct") != 0;
  if (want_trackpad != trackpad_mode) {
    direct.cancel(actions);
    trackpad.cancel(actions);
    flush_actions();
    trackpad_mode = want_trackpad;
  }
}

}  // namespace touch_ui

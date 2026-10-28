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

#include "touch_automation.h"

#include <SDL.h>
#include <sys/stat.h>

#include <algorithm>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <map>
#include <sstream>

#include "lua.hpp"
#include "touch_ui.h"

namespace touch_automation {

namespace {

// Used when the platform has no touch device. Anything but SDL_MOUSE_TOUCHID
// (which touch_ui ignores) will do.
constexpr SDL_TouchID fallback_touch_id = 0x7A57;
// How long to let the game settle after a gesture before the next command.
constexpr uint32_t settle_ms = 60;
// How long the host gets to answer a request (screenshots, backgrounding).
constexpr uint32_t host_timeout_ms = 30000;

struct timed_event {
  uint32_t at;
  SDL_Event event;
};

struct point {
  float x;
  float y;
};

struct script_state {
  bool loaded = false;
  bool finished = false;
  std::vector<std::string> lines;
  size_t next = 0;
  std::string out_dir;
  FILE* log = nullptr;
  bool host = false;
  bool game_coords = true;
  uint32_t start_ms = 0;
  uint32_t resume_at = 0;
  // Set while waiting for a "wait_until" condition.
  bool polling = false;
  std::string poll_expr;
  uint32_t poll_deadline = 0;
  // Set while the host has a request to answer.
  bool awaiting_host = false;
  uint32_t host_deadline = 0;
  std::vector<timed_event> pending;
  SDL_FingerID next_finger = 1;
  // Where each finger was last put (normalised), for motion deltas.
  std::map<SDL_FingerID, point> finger_pos;
};

script_state s;

std::string trim(const std::string& text) {
  size_t begin = text.find_first_not_of(" \t\r\n");
  if (begin == std::string::npos) {
    return "";
  }
  size_t end = text.find_last_not_of(" \t\r\n");
  return text.substr(begin, end - begin + 1);
}

void make_dirs(const std::string& path) {
  for (size_t i = 1; i <= path.size(); ++i) {
    if (i == path.size() || path[i] == '/') {
      mkdir(path.substr(0, i).c_str(), 0755);
    }
  }
}

bool file_exists(const std::string& path) {
  struct stat st {};
  return stat(path.c_str(), &st) == 0;
}

void log_line(const char* format, ...) {
  char buffer[2048];
  va_list args;
  va_start(args, format);
  std::vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  double seconds = (SDL_GetTicks() - s.start_ms) / 1000.0;
  if (s.log != nullptr) {
    std::fprintf(s.log, "[%7.2f] %s\n", seconds, buffer);
    std::fflush(s.log);
  }
  std::printf("Automation: %s\n", buffer);
}

void finish(bool passed, const std::string& reason) {
  s.finished = true;
  s.pending.clear();
  if (passed) {
    log_line("RESULT: PASS");
  } else {
    log_line("RESULT: FAIL line %zu: %s", s.next, reason.c_str());
  }
}

// The screen's own touch device if there is one, so that SDL's multi-finger
// gesture detection (pinch zoom) also sees the injected fingers.
SDL_TouchID touch_device() {
  for (int i = 0; i < SDL_GetNumTouchDevices(); ++i) {
    SDL_TouchID id = SDL_GetTouchDevice(i);
    if (id != SDL_MOUSE_TOUCHID && id != 0) {
      return id;
    }
  }
  return fallback_touch_id;
}

SDL_Window* game_window() {
  SDL_Window* window = SDL_GetKeyboardFocus();
  if (window == nullptr) {
    window = SDL_GetMouseFocus();
  }
  for (Uint32 id = 1; window == nullptr && id < 16; ++id) {
    window = SDL_GetWindowFromID(id);
  }
  return window;
}

// Converts script coordinates to window coordinates (screen points).
point to_window(double x, double y) {
  SDL_Window* window = game_window();
  SDL_Renderer* renderer =
      window != nullptr ? SDL_GetRenderer(window) : nullptr;
  if (!s.game_coords || renderer == nullptr) {
    return {static_cast<float>(x), static_cast<float>(y)};
  }
  int wx = 0;
  int wy = 0;
  SDL_RenderLogicalToWindow(renderer, static_cast<float>(x),
                            static_cast<float>(y), &wx, &wy);
  return {static_cast<float>(wx), static_cast<float>(wy)};
}

void add_finger(uint32_t type, SDL_FingerID finger, point p, uint32_t at) {
  SDL_Window* window = game_window();
  int ww = 1;
  int wh = 1;
  if (window != nullptr) {
    SDL_GetWindowSize(window, &ww, &wh);
  }
  timed_event te{};
  te.at = at;
  te.event.type = type;
  te.event.tfinger.touchId = touch_device();
  te.event.tfinger.fingerId = finger;
  te.event.tfinger.x = std::clamp(p.x / static_cast<float>(ww), 0.0f, 1.0f);
  te.event.tfinger.y = std::clamp(p.y / static_cast<float>(wh), 0.0f, 1.0f);
  // SDL's pinch detection works from the deltas.
  if (type != SDL_FINGERDOWN) {
    auto last = s.finger_pos.find(finger);
    if (last != s.finger_pos.end()) {
      te.event.tfinger.dx = te.event.tfinger.x - last->second.x;
      te.event.tfinger.dy = te.event.tfinger.y - last->second.y;
    }
  }
  if (type == SDL_FINGERUP) {
    s.finger_pos.erase(finger);
  } else {
    s.finger_pos[finger] = {te.event.tfinger.x, te.event.tfinger.y};
  }
  te.event.tfinger.pressure = type == SDL_FINGERUP ? 0.0f : 1.0f;
  te.event.tfinger.windowID = window != nullptr ? SDL_GetWindowID(window) : 0;
  s.pending.push_back(te);
}

// Moves a finger in a straight line from a to b, starting at `start` and
// taking `ms`, without putting it down or lifting it.
void add_moves(SDL_FingerID finger, point a, point b, uint32_t start,
               uint32_t ms) {
  int steps = std::max(2, static_cast<int>(ms / 16));
  for (int i = 1; i <= steps; ++i) {
    float t = static_cast<float>(i) / static_cast<float>(steps);
    point p{a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t};
    add_finger(SDL_FINGERMOTION, finger, p, start + ms * i / steps);
  }
}

// Two fingers moving from (a1, a2) to (b1, b2) together.
void add_two_finger_gesture(point a1, point a2, point b1, point b2,
                            uint32_t now, uint32_t ms) {
  SDL_FingerID f1 = s.next_finger++;
  SDL_FingerID f2 = s.next_finger++;
  add_finger(SDL_FINGERDOWN, f1, a1, now);
  add_finger(SDL_FINGERDOWN, f2, a2, now + 10);
  add_moves(f1, a1, b1, now + 30, ms);
  add_moves(f2, a2, b2, now + 30, ms);
  add_finger(SDL_FINGERUP, f1, b1, now + 30 + ms + 20);
  add_finger(SDL_FINGERUP, f2, b2, now + 30 + ms + 30);
}

void schedule_pending() {
  std::stable_sort(
      s.pending.begin(), s.pending.end(),
      [](const timed_event& a, const timed_event& b) { return a.at < b.at; });
  if (!s.pending.empty()) {
    s.resume_at = s.pending.back().at + settle_ms;
  }
}

std::string request_path() { return s.out_dir + "/request"; }

void send_host_request(const std::string& request, uint32_t now) {
  std::string tmp = request_path() + ".tmp";
  {
    std::ofstream out(tmp);
    out << request << "\n";
  }
  std::rename(tmp.c_str(), request_path().c_str());
  s.awaiting_host = true;
  s.host_deadline = now + host_timeout_ms;
}

// Runs Lua code. It's tried as an expression first, so `lua 1 + 1` logs 2.
bool run_lua(lua_State* L, const std::string& code, bool* truthy,
             std::string* result) {
  int top = lua_gettop(L);
  std::string as_expression = "return " + code;
  if (luaL_loadbuffer(L, as_expression.data(), as_expression.size(),
                      "=automation") != LUA_OK) {
    lua_settop(L, top);
    if (luaL_loadbuffer(L, code.data(), code.size(), "=automation") !=
        LUA_OK) {
      *result = lua_tostring(L, -1);
      lua_settop(L, top);
      return false;
    }
  }
  if (lua_pcall(L, 0, 1, 0) != LUA_OK) {
    *result = lua_tostring(L, -1) != nullptr ? lua_tostring(L, -1) : "error";
    lua_settop(L, top);
    return false;
  }
  *truthy = lua_toboolean(L, -1) != 0;
  result->clear();
  if (!lua_isnil(L, -1)) {
    *result = luaL_tolstring(L, -1, nullptr);
  }
  lua_settop(L, top);
  return true;
}

// Runs one script command. Returns false if the script has to stop.
bool run_command(lua_State* L, const std::string& line, uint32_t now) {
  std::string command;
  std::string rest;
  split_command(line, &command, &rest);
  std::vector<double> n;
  auto bad = [&](const char* usage) {
    finish(false, std::string("usage: ") + usage);
    return false;
  };

  if (command == "wait") {
    if (!parse_numbers(rest, 1, &n)) return bad("wait <ms>");
    s.resume_at = now + static_cast<uint32_t>(n[0]);
  } else if (command == "tap") {
    if (!parse_numbers(rest, 2, &n)) return bad("tap <x> <y>");
    point p = to_window(n[0], n[1]);
    SDL_FingerID f = s.next_finger++;
    add_finger(SDL_FINGERDOWN, f, p, now);
    add_finger(SDL_FINGERUP, f, p, now + 50);
  } else if (command == "drag") {
    if (!parse_numbers(rest, 5, &n)) {
      return bad("drag <x1> <y1> <x2> <y2> <ms>");
    }
    point a = to_window(n[0], n[1]);
    point b = to_window(n[2], n[3]);
    uint32_t ms = static_cast<uint32_t>(std::max(n[4], 16.0));
    SDL_FingerID f = s.next_finger++;
    add_finger(SDL_FINGERDOWN, f, a, now);
    add_moves(f, a, b, now + 16, ms);
    add_finger(SDL_FINGERUP, f, b, now + 32 + ms);
  } else if (command == "twofinger_tap") {
    if (!parse_numbers(rest, 2, &n)) return bad("twofinger_tap <x> <y>");
    point p = to_window(n[0], n[1]);
    point a{p.x - 20, p.y};
    point b{p.x + 20, p.y};
    SDL_FingerID f1 = s.next_finger++;
    SDL_FingerID f2 = s.next_finger++;
    add_finger(SDL_FINGERDOWN, f1, a, now);
    add_finger(SDL_FINGERDOWN, f2, b, now + 10);
    add_finger(SDL_FINGERUP, f1, a, now + 70);
    add_finger(SDL_FINGERUP, f2, b, now + 80);
  } else if (command == "pinch") {
    if (!parse_numbers(rest, 3, &n) || n[2] <= 0) {
      return bad("pinch <x> <y> <scale>");
    }
    point c = to_window(n[0], n[1]);
    float half = 40.0f;
    float end = half * static_cast<float>(n[2]);
    add_two_finger_gesture({c.x - half, c.y}, {c.x + half, c.y},
                           {c.x - end, c.y}, {c.x + end, c.y}, now, 400);
  } else if (command == "pan") {
    if (!parse_numbers(rest, 2, &n)) return bad("pan <dx> <dy>");
    // Pan around the middle of the screen; only the distance matters.
    SDL_Window* window = game_window();
    int ww = 0;
    int wh = 0;
    if (window != nullptr) {
      SDL_GetWindowSize(window, &ww, &wh);
    }
    point origin = to_window(0, 0);
    point delta = to_window(n[0], n[1]);
    float dx = delta.x - origin.x;
    float dy = delta.y - origin.y;
    point c{ww / 2.0f - dx / 2, wh / 2.0f - dy / 2};
    point a1{c.x - 30, c.y};
    point a2{c.x + 30, c.y};
    add_two_finger_gesture(a1, a2, {a1.x + dx, a1.y + dy},
                           {a2.x + dx, a2.y + dy}, now, 400);
  } else if (command == "type") {
    // Text arrives in chunks that fit an SDL text event (nul-terminated).
    constexpr size_t chunk_size = SDL_TEXTINPUTEVENT_TEXT_SIZE - 1;
    for (size_t i = 0; i < rest.size(); i += chunk_size) {
      SDL_Event ev{};
      ev.type = SDL_TEXTINPUT;
      std::string chunk = rest.substr(i, chunk_size);
      std::copy(chunk.begin(), chunk.end(), ev.text.text);
      SDL_PushEvent(&ev);
    }
    s.resume_at = now + settle_ms;
  } else if (command == "key") {
    SDL_Keycode key = SDL_GetKeyFromName(rest.c_str());
    if (key == SDLK_UNKNOWN) return bad("key <SDL key name>");
    for (uint32_t type : {SDL_KEYDOWN, SDL_KEYUP}) {
      SDL_Event ev{};
      ev.type = type;
      ev.key.state = type == SDL_KEYDOWN ? SDL_PRESSED : SDL_RELEASED;
      ev.key.keysym.sym = key;
      ev.key.keysym.scancode = SDL_GetScancodeFromKey(key);
      SDL_PushEvent(&ev);
    }
    s.resume_at = now + settle_ms;
  } else if (command == "native_tap") {
    if (rest.empty()) return bad("native_tap <label>");
    bool truthy = false;
    std::string result;
    if (!run_lua(L, "require('sdl').native.tap([==[" + rest + "]==])", &truthy,
                 &result) ||
        !truthy) {
      finish(false, "no native control called \"" + rest + "\"");
      return false;
    }
    s.resume_at = now + settle_ms;
  } else if (command == "coords") {
    if (rest != "game" && rest != "points") return bad("coords game|points");
    s.game_coords = rest == "game";
  } else if (command == "controls") {
    if (rest != "trackpad" && rest != "direct") {
      return bad("controls trackpad|direct");
    }
    touch_ui::set_controls(rest.c_str());
  } else if (command == "lua") {
    bool truthy = false;
    std::string result;
    if (!run_lua(L, rest, &truthy, &result)) {
      finish(false, "Lua error: " + result);
      return false;
    }
    if (!result.empty()) {
      log_line("  = %s", result.c_str());
    }
  } else if (command == "expect") {
    bool truthy = false;
    std::string result;
    if (!run_lua(L, rest, &truthy, &result)) {
      finish(false, "Lua error: " + result);
      return false;
    }
    if (!truthy) {
      finish(false, "expected " + rest + " (got " +
                        (result.empty() ? "nil" : result) + ")");
      return false;
    }
  } else if (command == "wait_until") {
    std::istringstream in(rest);
    double ms = 0;
    if (!(in >> ms)) return bad("wait_until <ms> <lua expression>");
    std::string expr;
    std::getline(in, expr);
    s.polling = true;
    s.poll_expr = trim(expr);
    s.poll_deadline = now + static_cast<uint32_t>(ms);
  } else if (command == "screenshot") {
    if (rest.empty()) return bad("screenshot <name>");
    if (s.host) {
      send_host_request("screenshot " + rest, now);
    } else {
      std::string path = s.out_dir + "/" + rest + ".png";
      bool truthy = false;
      std::string result;
      if (!run_lua(L,
                   "TheApp.video:takeScreenshot([==[" + path + "]==])",
                   &truthy, &result) ||
          !truthy) {
        log_line("  screenshot failed: %s", result.c_str());
      }
    }
  } else if (command == "host") {
    if (rest.empty()) return bad("host <request>");
    if (!s.host) {
      log_line("  skipped: no host script is watching");
    } else {
      send_host_request(rest, now);
    }
  } else if (command == "log") {
    // Already logged with the rest of the line.
  } else {
    finish(false, "unknown command \"" + command + "\"");
    return false;
  }
  schedule_pending();
  return true;
}

}  // namespace

void split_command(const std::string& line, std::string* command,
                   std::string* rest) {
  std::string text = trim(line);
  size_t space = text.find_first_of(" \t");
  if (space == std::string::npos) {
    *command = text;
    rest->clear();
  } else {
    *command = text.substr(0, space);
    *rest = trim(text.substr(space));
  }
}

bool parse_numbers(const std::string& text, size_t count,
                   std::vector<double>* out) {
  out->clear();
  std::istringstream in(text);
  double value = 0;
  while (in >> value) {
    out->push_back(value);
  }
  return in.eof() && out->size() == count;
}

void init() {
  const char* script = std::getenv("CORSIXTH_AUTOMATION");
  if (!touch_ui::enabled() || script == nullptr || *script == '\0') {
    return;
  }
  if (const char* out = std::getenv("CORSIXTH_AUTOMATION_OUT")) {
    s.out_dir = out;
  } else if (const char* config = std::getenv("XDG_CONFIG_HOME")) {
    s.out_dir = std::string(config) + "/CorsixTH/Automation";
  } else if (const char* home = std::getenv("HOME")) {
    s.out_dir = std::string(home) + "/.config/CorsixTH/Automation";
  } else {
    s.out_dir = "Automation";
  }
  make_dirs(s.out_dir);
  std::remove(request_path().c_str());
  s.log = std::fopen((s.out_dir + "/automation.log").c_str(), "w");
  const char* host = std::getenv("CORSIXTH_AUTOMATION_HOST");
  s.host = host != nullptr && host[0] == '1';
  s.start_ms = SDL_GetTicks();

  std::ifstream in(script);
  if (!in) {
    s.loaded = true;
    finish(false, std::string("can't read ") + script);
    return;
  }
  std::string line;
  while (std::getline(in, line)) {
    s.lines.push_back(line);
  }
  s.loaded = true;
  log_line("script %s (%zu lines), output in %s", script, s.lines.size(),
           s.out_dir.c_str());
}

bool running() { return s.loaded && !s.finished; }

void poll(lua_State* L) {
  if (!running()) {
    return;
  }
  uint32_t now = SDL_GetTicks();
  // Inject the touch events that are due.
  size_t due = 0;
  while (due < s.pending.size() && s.pending[due].at <= now) {
    SDL_Event ev = s.pending[due].event;
    ev.tfinger.timestamp = now;
    SDL_PushEvent(&ev);
    ++due;
  }
  s.pending.erase(s.pending.begin(), s.pending.begin() + due);
  if (!s.pending.empty() || now < s.resume_at) {
    return;
  }
  if (s.awaiting_host) {
    if (file_exists(request_path())) {
      if (now > s.host_deadline) {
        finish(false, "the host script didn't answer");
      }
      return;
    }
    s.awaiting_host = false;
  }
  if (s.polling) {
    bool truthy = false;
    std::string result;
    if (!run_lua(L, s.poll_expr, &truthy, &result)) {
      finish(false, "Lua error: " + result);
      return;
    }
    if (!truthy) {
      if (now > s.poll_deadline) {
        finish(false, "timed out waiting for " + s.poll_expr);
      }
      return;
    }
    s.polling = false;
  }

  // Run commands until one of them has to wait.
  while (s.next < s.lines.size()) {
    std::string line = s.lines[s.next++];
    std::string command;
    std::string rest;
    split_command(line, &command, &rest);
    if (command.empty() || command[0] == '#') {
      continue;
    }
    log_line("%s", trim(line).c_str());
    if (!run_command(L, line, now)) {
      return;
    }
    if (!s.pending.empty() || s.resume_at > now || s.polling ||
        s.awaiting_host) {
      return;
    }
  }
  finish(true, "");
}

}  // namespace touch_automation

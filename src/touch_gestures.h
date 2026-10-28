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

#ifndef CORSIX_TH_TOUCH_GESTURES_H_
#define CORSIX_TH_TOUCH_GESTURES_H_

#include <cstdint>
#include <vector>

namespace touch_ui {

// Mouse button numbers, the same values SDL uses.
constexpr int button_left = 1;
constexpr int button_middle = 2;
constexpr int button_right = 3;

//! A mouse action synthesised from touch input, in logical (game) coordinates.
struct mouse_action {
  //! move: pointer to (x, y). press/release: button at (x, y).
  //! pan: drag the map by (x, y) with the middle button held, without moving
  //! the pointer.
  enum class kind { move, press, release, pan };
  kind type;
  int button;  // button_left / button_middle / button_right; unused otherwise
  int x;
  int y;
};

//! Turns touches into the mouse actions Theme Hospital expects.
/*!
    - tap                          -> left click
    - touch, pause briefly, drag   -> left button drag (e.g. sizing a room)
    - quick swipe                  -> move the pointer only (e.g. positioning
                                      an object before tapping to place it)
    - long press                   -> right click
    - two-finger tap               -> right click
    - two-finger drag              -> middle button drag (pans the map)
    - pinch                        -> left to SDL_MULTIGESTURE (zoom)

    The class is pure logic so it can be unit tested without SDL windows.
*/
class gesture_recogniser {
 public:
  struct settings {
    uint32_t drag_delay_ms = 150;
    uint32_t long_press_ms = 500;
    uint32_t two_finger_tap_ms = 350;
    int move_threshold = 12;  // logical pixels
  };

  gesture_recogniser() = default;
  explicit gesture_recogniser(const settings& s) : cfg(s) {}

  void finger_down(int64_t finger, int x, int y, uint32_t now,
                   std::vector<mouse_action>& out);
  void finger_move(int64_t finger, int x, int y, uint32_t now,
                   std::vector<mouse_action>& out);
  void finger_up(int64_t finger, int x, int y, uint32_t now,
                 std::vector<mouse_action>& out);
  //! Handles time based gestures (long press). Call regularly.
  void tick(uint32_t now, std::vector<mouse_action>& out);
  //! Forget all touches, releasing any button that is held.
  void cancel(std::vector<mouse_action>& out);

 private:
  enum class state { idle, pending, hovering, dragging, consumed, multi };
  struct finger_info {
    int64_t id;
    int start_x;
    int start_y;
    int x;
    int y;
  };

  finger_info* find(int64_t id);
  void remove(int64_t id);
  void centroid(int* x, int* y) const;
  bool moved_far(int x0, int y0, int x1, int y1) const;

  settings cfg{};
  state st{state::idle};
  std::vector<finger_info> fingers;
  int64_t primary{0};
  int origin_x{0};
  int origin_y{0};
  uint32_t down_time{0};
  bool tap_possible{false};
  bool panning{false};
  int pan_start_x{0};
  int pan_start_y{0};
  int tap_x{0};
  int tap_y{0};
};

//! Turns touches into mouse actions with the screen acting as a trackpad: the
//! game's own cursor moves by as much as the finger does, not to the finger.
/*!
    - one-finger move               -> moves the cursor
    - tap                           -> left click at the cursor
    - tap, then touch again and move -> left button drag (as on a laptop)
    - two-finger tap                -> right click at the cursor
    - two-finger drag               -> pans the map; the cursor stays put
    - pinch                         -> left to SDL_MULTIGESTURE (zoom)
*/
class trackpad_recogniser {
 public:
  struct settings {
    uint32_t tap_ms = 250;             // longest touch that counts as a tap
    uint32_t double_tap_ms = 350;      // tap-then-drag: gap allowed after the tap
    uint32_t two_finger_tap_ms = 300;  // longest two-finger tap
    int move_threshold = 8;            // logical pixels before a touch moves
    double speed = 1.0;                // cursor speed multiplier
  };

  trackpad_recogniser() = default;
  explicit trackpad_recogniser(const settings& s) : cfg(s) {}

  //! Size of the area the cursor can move in (the game's logical screen).
  void set_bounds(int width, int height);

  void finger_down(int64_t finger, int x, int y, uint32_t now,
                   std::vector<mouse_action>& out);
  void finger_move(int64_t finger, int x, int y, uint32_t now,
                   std::vector<mouse_action>& out);
  void finger_up(int64_t finger, int x, int y, uint32_t now,
                 std::vector<mouse_action>& out);
  //! Forget all touches, releasing any button that is held.
  void cancel(std::vector<mouse_action>& out);

  int cursor_x() const;
  int cursor_y() const;

 private:
  enum class state { idle, pending, tracking, dragging, multi };
  struct finger_info {
    int64_t id;
    int start_x;
    int start_y;
    int x;
    int y;
  };

  finger_info* find(int64_t id);
  void remove(int64_t id);
  void centroid(int* x, int* y) const;
  bool moved_far(int x0, int y0, int x1, int y1) const;
  void move_cursor(double dx, double dy, std::vector<mouse_action>& out);
  void click(int button, std::vector<mouse_action>& out);

  settings cfg{};
  state st{state::idle};
  std::vector<finger_info> fingers;
  int64_t primary{0};
  uint32_t down_time{0};
  uint32_t last_move_time{0};
  uint32_t last_tap_time{0};
  bool last_was_tap{false};
  bool drag_armed{false};
  bool tap_possible{false};
  bool panning{false};
  int pan_x{0};
  int pan_y{0};
  int bounds_w{0};
  int bounds_h{0};
  double cx{0};
  double cy{0};
  bool cursor_announced{false};
};

}  // namespace touch_ui

#endif  // CORSIX_TH_TOUCH_GESTURES_H_

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

#include "touch_gestures.h"

#include <algorithm>
#include <cmath>

namespace touch_ui {

namespace {

// Distance between the first two fingers.
template <typename Finger>
double finger_separation(const std::vector<Finger>& fingers) {
  if (fingers.size() < 2) {
    return 0;
  }
  double dx = fingers[1].x - fingers[0].x;
  double dy = fingers[1].y - fingers[0].y;
  return std::sqrt(dx * dx + dy * dy);
}

}  // namespace

void pinch_tracker::begin(double separation) {
  start = separation;
  last = separation;
  pinching = false;
}

int pinch_tracker::update(double separation) {
  if (!pinching) {
    if (std::abs(separation - start) <= threshold) {
      return 0;
    }
    pinching = true;  // Zoom from here on, without a jump.
    last = separation;
    return 0;
  }
  int change = static_cast<int>(std::lround(separation - last));
  last += change;
  return change;
}

double gesture_recogniser::separation() const {
  return finger_separation(fingers);
}

double trackpad_recogniser::separation() const {
  return finger_separation(fingers);
}

// ---------------------------------------------------------------------------
// gesture_recogniser

gesture_recogniser::finger_info* gesture_recogniser::find(int64_t id) {
  for (finger_info& f : fingers) {
    if (f.id == id) {
      return &f;
    }
  }
  return nullptr;
}

void gesture_recogniser::remove(int64_t id) {
  fingers.erase(std::remove_if(fingers.begin(), fingers.end(),
                               [id](const finger_info& f) { return f.id == id; }),
                fingers.end());
}

void gesture_recogniser::centroid(int* x, int* y) const {
  // Only the first two fingers count; a third finger should not jerk the map.
  size_t n = std::min<size_t>(fingers.size(), 2);
  if (n == 0) {
    return;
  }
  long sx = 0;
  long sy = 0;
  for (size_t i = 0; i < n; ++i) {
    sx += fingers[i].x;
    sy += fingers[i].y;
  }
  *x = static_cast<int>(sx / static_cast<long>(n));
  *y = static_cast<int>(sy / static_cast<long>(n));
}

bool gesture_recogniser::moved_far(int x0, int y0, int x1, int y1) const {
  long dx = x1 - x0;
  long dy = y1 - y0;
  long limit = cfg.move_threshold;
  return dx * dx + dy * dy > limit * limit;
}

void gesture_recogniser::finger_down(int64_t finger, int x, int y,
                                     uint32_t now,
                                     std::vector<mouse_action>& out) {
  if (find(finger) != nullptr) {
    return;
  }
  fingers.push_back({finger, x, y, x, y});

  if (fingers.size() == 1 && st == state::idle) {
    st = state::pending;
    primary = finger;
    origin_x = x;
    origin_y = y;
    down_time = now;
    out.push_back({mouse_action::kind::move, 0, x, y});
    return;
  }

  // An extra finger: whatever the first finger was doing turns into a
  // two-finger gesture.
  if (st == state::multi) {
    tap_possible = false;  // three or more fingers
    if (!panning) {
      centroid(&pan_start_x, &pan_start_y);
    }
    pinch.begin(separation());
    return;
  }
  if (st == state::dragging) {
    finger_info* p = find(primary);
    out.push_back({mouse_action::kind::release, button_left,
                   p ? p->x : origin_x, p ? p->y : origin_y});
  }
  tap_possible = st == state::pending &&
                 now - down_time <= cfg.two_finger_tap_ms / 2;
  st = state::multi;
  panning = false;
  centroid(&pan_start_x, &pan_start_y);
  tap_x = pan_start_x;
  tap_y = pan_start_y;
  pinch.begin(separation());
}

void gesture_recogniser::finger_move(int64_t finger, int x, int y,
                                     uint32_t now,
                                     std::vector<mouse_action>& out) {
  finger_info* f = find(finger);
  if (f == nullptr) {
    return;
  }
  f->x = x;
  f->y = y;

  if (st == state::multi) {
    if (moved_far(f->start_x, f->start_y, x, y)) {
      tap_possible = false;
    }
    if (fingers.size() < 2) {
      return;
    }
    int cx = 0;
    int cy = 0;
    centroid(&cx, &cy);
    if (!panning && moved_far(pan_start_x, pan_start_y, cx, cy)) {
      panning = true;
      out.push_back({mouse_action::kind::move, 0, pan_start_x, pan_start_y});
      out.push_back({mouse_action::kind::press, button_middle, pan_start_x,
                     pan_start_y});
    }
    if (panning) {
      out.push_back({mouse_action::kind::move, 0, cx, cy});
    }
    if (int change = pinch.update(separation())) {
      out.push_back({mouse_action::kind::zoom, 0, cx, cy, change});
    }
    return;
  }

  if (finger != primary) {
    return;
  }
  switch (st) {
    case state::pending:
      if (moved_far(origin_x, origin_y, x, y)) {
        if (now - down_time >= cfg.drag_delay_ms) {
          out.push_back(
              {mouse_action::kind::press, button_left, origin_x, origin_y});
          st = state::dragging;
        } else {
          st = state::hovering;
        }
        out.push_back({mouse_action::kind::move, 0, x, y});
      }
      break;
    case state::hovering:
    case state::dragging:
      out.push_back({mouse_action::kind::move, 0, x, y});
      break;
    default:
      break;
  }
}

void gesture_recogniser::finger_up(int64_t finger, int x, int y, uint32_t now,
                                   std::vector<mouse_action>& out) {
  finger_info* f = find(finger);
  if (f == nullptr) {
    return;
  }
  f->x = x;
  f->y = y;

  if (st == state::multi) {
    if (moved_far(f->start_x, f->start_y, x, y)) {
      tap_possible = false;
    }
    if (panning) {
      int cx = 0;
      int cy = 0;
      centroid(&cx, &cy);
      out.push_back({mouse_action::kind::release, button_middle, cx, cy});
      panning = false;
    }
    remove(finger);
    // If fingers remain, a later pan or pinch starts from where they are now.
    centroid(&pan_start_x, &pan_start_y);
    pinch.begin(separation());
    if (fingers.empty()) {
      if (tap_possible && now - down_time <= cfg.two_finger_tap_ms) {
        out.push_back({mouse_action::kind::move, 0, tap_x, tap_y});
        out.push_back(
            {mouse_action::kind::press, button_right, tap_x, tap_y});
        out.push_back(
            {mouse_action::kind::release, button_right, tap_x, tap_y});
      }
      st = state::idle;
      tap_possible = false;
    }
    return;
  }

  remove(finger);
  if (finger == primary) {
    switch (st) {
      case state::pending:
        out.push_back(
            {mouse_action::kind::press, button_left, origin_x, origin_y});
        out.push_back(
            {mouse_action::kind::release, button_left, origin_x, origin_y});
        break;
      case state::dragging:
        out.push_back({mouse_action::kind::move, 0, x, y});
        out.push_back({mouse_action::kind::release, button_left, x, y});
        break;
      case state::hovering:
        out.push_back({mouse_action::kind::move, 0, x, y});
        break;
      default:
        break;
    }
  }
  if (fingers.empty()) {
    st = state::idle;
  }
}

void gesture_recogniser::tick(uint32_t now, std::vector<mouse_action>& out) {
  if (st == state::pending && now - down_time >= cfg.long_press_ms) {
    out.push_back(
        {mouse_action::kind::press, button_right, origin_x, origin_y});
    out.push_back(
        {mouse_action::kind::release, button_right, origin_x, origin_y});
    st = state::consumed;
  }
}

void gesture_recogniser::cancel(std::vector<mouse_action>& out) {
  if (st == state::dragging) {
    const finger_info* p = find(primary);
    out.push_back({mouse_action::kind::release, button_left,
                   p ? p->x : origin_x, p ? p->y : origin_y});
  }
  if (st == state::multi && panning) {
    out.push_back({mouse_action::kind::release, button_middle, pan_start_x,
                   pan_start_y});
  }
  fingers.clear();
  st = state::idle;
  panning = false;
  tap_possible = false;
}

// ---------------------------------------------------------------------------
// trackpad_recogniser

void trackpad_recogniser::set_bounds(int width, int height) {
  if (width <= 0 || height <= 0) {
    return;
  }
  if (bounds_w == 0 || bounds_h == 0) {
    cx = width / 2.0;  // The cursor starts in the middle of the screen.
    cy = height / 2.0;
  }
  bounds_w = width;
  bounds_h = height;
  cx = std::clamp(cx, 0.0, static_cast<double>(width - 1));
  cy = std::clamp(cy, 0.0, static_cast<double>(height - 1));
}

int trackpad_recogniser::cursor_x() const {
  return static_cast<int>(std::lround(cx));
}

int trackpad_recogniser::cursor_y() const {
  return static_cast<int>(std::lround(cy));
}

void trackpad_recogniser::set_pointer_mode(bool on) {
  pointer_mode = on;
  last_was_tap = false;
  drag_armed = false;
}

void trackpad_recogniser::tick(uint32_t now, std::vector<mouse_action>& out) {
  if (!pointer_mode || st != state::pending || fingers.size() != 1 ||
      now - down_time < cfg.long_press_ms) {
    return;
  }
  // A still finger: right click under it. Moving on carries the pointer.
  const finger_info& f = fingers.front();
  warp_cursor(f.x, f.y);
  out.push_back({mouse_action::kind::move, 0, cursor_x(), cursor_y()});
  click(button_right, out);
  fingers.front().start_x = f.x;
  fingers.front().start_y = f.y;
  st = state::tracking;
  last_move_time = now;
}

void trackpad_recogniser::warp_cursor(int x, int y) {
  cx = x;
  cy = y;
  if (bounds_w > 0 && bounds_h > 0) {
    cx = std::clamp(cx, 0.0, static_cast<double>(bounds_w - 1));
    cy = std::clamp(cy, 0.0, static_cast<double>(bounds_h - 1));
  }
  cursor_announced = true;
  last_was_tap = false;
  drag_armed = false;
}

trackpad_recogniser::finger_info* trackpad_recogniser::find(int64_t id) {
  for (finger_info& f : fingers) {
    if (f.id == id) {
      return &f;
    }
  }
  return nullptr;
}

void trackpad_recogniser::remove(int64_t id) {
  fingers.erase(std::remove_if(fingers.begin(), fingers.end(),
                               [id](const finger_info& f) { return f.id == id; }),
                fingers.end());
}

void trackpad_recogniser::centroid(int* x, int* y) const {
  size_t n = std::min<size_t>(fingers.size(), 2);
  if (n == 0) {
    return;
  }
  long sx = 0;
  long sy = 0;
  for (size_t i = 0; i < n; ++i) {
    sx += fingers[i].x;
    sy += fingers[i].y;
  }
  *x = static_cast<int>(sx / static_cast<long>(n));
  *y = static_cast<int>(sy / static_cast<long>(n));
}

bool trackpad_recogniser::moved_far(int x0, int y0, int x1, int y1) const {
  long dx = x1 - x0;
  long dy = y1 - y0;
  long limit = cfg.move_threshold;
  return dx * dx + dy * dy > limit * limit;
}

void trackpad_recogniser::move_cursor(double dx, double dy,
                                      std::vector<mouse_action>& out) {
  int old_x = cursor_x();
  int old_y = cursor_y();
  cx += dx;
  cy += dy;
  if (bounds_w > 0 && bounds_h > 0) {
    cx = std::clamp(cx, 0.0, static_cast<double>(bounds_w - 1));
    cy = std::clamp(cy, 0.0, static_cast<double>(bounds_h - 1));
  }
  if (cursor_x() != old_x || cursor_y() != old_y || !cursor_announced) {
    out.push_back({mouse_action::kind::move, 0, cursor_x(), cursor_y()});
    cursor_announced = true;
  }
}

void trackpad_recogniser::click(int button, std::vector<mouse_action>& out) {
  out.push_back({mouse_action::kind::press, button, cursor_x(), cursor_y()});
  out.push_back({mouse_action::kind::release, button, cursor_x(), cursor_y()});
}

void trackpad_recogniser::finger_down(int64_t finger, int x, int y,
                                      uint32_t now,
                                      std::vector<mouse_action>& out) {
  if (find(finger) != nullptr) {
    return;
  }
  if (!cursor_announced) {
    move_cursor(0, 0, out);  // Show the cursor where it starts.
  }
  fingers.push_back({finger, x, y, x, y});

  if (fingers.size() == 1 && st == state::idle) {
    st = state::pending;
    primary = finger;
    down_time = now;
    last_move_time = now;
    // A touch that follows a tap closely turns into a drag if it moves.
    drag_armed = !pointer_mode && last_was_tap && now - last_tap_time <= cfg.double_tap_ms;
    last_was_tap = false;
    return;
  }

  // An extra finger: switch to two-finger gestures.
  if (st == state::multi) {
    tap_possible = false;  // three or more fingers
    if (!panning) {
      centroid(&pan_x, &pan_y);
    }
    pinch.begin(separation());
    return;
  }
  if (st == state::dragging) {
    out.push_back(
        {mouse_action::kind::release, button_left, cursor_x(), cursor_y()});
  }
  tap_possible = st == state::pending && now - down_time <= cfg.tap_ms;
  st = state::multi;
  panning = false;
  last_was_tap = false;
  centroid(&pan_x, &pan_y);
  pinch.begin(separation());
}

void trackpad_recogniser::finger_move(int64_t finger, int x, int y,
                                      uint32_t now,
                                      std::vector<mouse_action>& out) {
  finger_info* f = find(finger);
  if (f == nullptr) {
    return;
  }
  int prev_x = f->x;
  int prev_y = f->y;
  f->x = x;
  f->y = y;

  if (st == state::multi) {
    if (moved_far(f->start_x, f->start_y, x, y)) {
      tap_possible = false;
    }
    if (fingers.size() < 2) {
      return;
    }
    int mx = 0;
    int my = 0;
    centroid(&mx, &my);
    if (!panning && moved_far(pan_x, pan_y, mx, my)) {
      panning = true;
      out.push_back(
          {mouse_action::kind::press, button_middle, cursor_x(), cursor_y()});
    }
    if (panning && (mx != pan_x || my != pan_y)) {
      out.push_back({mouse_action::kind::pan, 0, mx - pan_x, my - pan_y});
      pan_x = mx;
      pan_y = my;
    }
    if (int change = pinch.update(separation())) {
      out.push_back({mouse_action::kind::zoom, 0, mx, my, change});
    }
    return;
  }

  if (finger != primary) {
    return;
  }
  if (st == state::pending) {
    if (!moved_far(f->start_x, f->start_y, x, y)) {
      return;  // Not moved enough yet; a tap may still be coming.
    }
    if (drag_armed) {
      out.push_back(
          {mouse_action::kind::press, button_left, cursor_x(), cursor_y()});
      st = state::dragging;
    } else {
      st = state::tracking;
    }
    // Catch up with everything since the finger went down.
    prev_x = f->start_x;
    prev_y = f->start_y;
    last_move_time = now;
    move_cursor((x - prev_x) * cfg.speed, (y - prev_y) * cfg.speed, out);
    return;
  }
  if (st == state::tracking || st == state::dragging) {
    // Gentle acceleration: slow movements are precise, flicks go further.
    double dx = x - prev_x;
    double dy = y - prev_y;
    double dt = std::max<double>(1.0, now - last_move_time);
    double velocity = std::sqrt(dx * dx + dy * dy) / dt;  // pixels per ms
    double gain = 1.0 + std::clamp((velocity - 0.25) * 0.8, 0.0, 1.5);
    last_move_time = now;
    move_cursor(dx * gain * cfg.speed, dy * gain * cfg.speed, out);
  }
}

void trackpad_recogniser::finger_up(int64_t finger, int x, int y,
                                    uint32_t now,
                                    std::vector<mouse_action>& out) {
  finger_info* f = find(finger);
  if (f == nullptr) {
    return;
  }
  f->x = x;
  f->y = y;

  if (st == state::multi) {
    if (moved_far(f->start_x, f->start_y, x, y)) {
      tap_possible = false;
    }
    if (panning) {
      out.push_back(
          {mouse_action::kind::release, button_middle, cursor_x(), cursor_y()});
      panning = false;
    }
    remove(finger);
    centroid(&pan_x, &pan_y);  // A later pan or pinch starts from here.
    pinch.begin(separation());
    if (fingers.empty()) {
      if (tap_possible && now - down_time <= cfg.two_finger_tap_ms) {
        click(button_right, out);
      }
      st = state::idle;
      tap_possible = false;
    }
    return;
  }

  remove(finger);
  if (finger == primary) {
    if (st == state::pending && pointer_mode) {
      // Pointer mode: a tap (or a still touch let go before the long press)
      // moves the pointer to the finger.
      warp_cursor(x, y);
      out.push_back({mouse_action::kind::move, 0, cursor_x(), cursor_y()});
    } else if (st == state::pending && now - down_time <= cfg.tap_ms) {
      click(button_left, out);
      last_was_tap = true;
      last_tap_time = now;
    } else if (st == state::dragging) {
      out.push_back(
          {mouse_action::kind::release, button_left, cursor_x(), cursor_y()});
    }
  }
  if (fingers.empty()) {
    st = state::idle;
  }
}

void trackpad_recogniser::cancel(std::vector<mouse_action>& out) {
  if (st == state::dragging) {
    out.push_back(
        {mouse_action::kind::release, button_left, cursor_x(), cursor_y()});
  }
  if (st == state::multi && panning) {
    out.push_back(
        {mouse_action::kind::release, button_middle, cursor_x(), cursor_y()});
  }
  fingers.clear();
  st = state::idle;
  panning = false;
  tap_possible = false;
  drag_armed = false;
  last_was_tap = false;
}

}  // namespace touch_ui

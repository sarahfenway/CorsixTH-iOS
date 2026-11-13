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

// Unit tests for touch_layout: the game's resolution for a screen size.
// Build: c++ -std=c++17 -Isrc tests/test_touch_layout.cpp src/touch_layout.cpp

#include <cstdio>

#include "touch_layout.h"

static int failures = 0;

static void expect(const char* what, int sw, int sh, int want_w, int want_h) {
  int w = 0;
  int h = 0;
  touch_ui::logical_size(sw, sh, 640, 480, &w, &h);
  bool ok = w == want_w && h == want_h;
  std::printf("%s %s: %dx%d -> %dx%d", ok ? "ok  " : "FAIL", what, sw, sh, w, h);
  if (!ok) {
    std::printf(" (wanted %dx%d)", want_w, want_h);
    ++failures;
  }
  std::printf("\n");
}

int main() {
  // A phone is stretched up to the game's 480 rows, keeping its shape.
  expect("iPhone Duo folded", 678, 466, 698, 480);
  expect("iPhone 17 Pro", 874, 402, 1044, 480);
  // Folded out, or an iPad: one game pixel per point.
  expect("iPhone Duo unfolded", 951, 669, 951, 669);
  expect("iPad Pro 11-inch", 1210, 834, 1210, 834);
  // A narrow iPad Split View pane is stretched to 640 columns.
  expect("narrow pane", 507, 834, 640, 1053);
  // Nothing known yet: nothing to pick.
  expect("no screen", 0, 0, 0, 0);
  if (failures > 0) {
    std::printf("%d test(s) failed\n", failures);
    return 1;
  }
  std::printf("All tests passed\n");
  return 0;
}

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

#include "touch_layout.h"

#include <algorithm>
#include <cmath>

namespace touch_ui {

void logical_size(int screen_w, int screen_h, int min_w, int min_h, int* width,
                  int* height) {
  if (screen_w <= 0 || screen_h <= 0) {
    *width = 0;
    *height = 0;
    return;
  }
  double scale = std::max({static_cast<double>(min_w) / screen_w,
                           static_cast<double>(min_h) / screen_h, 1.0});
  *width = static_cast<int>(std::lround(screen_w * scale));
  *height = static_cast<int>(std::lround(screen_h * scale));
}

}  // namespace touch_ui

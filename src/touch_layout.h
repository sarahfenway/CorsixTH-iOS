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

#ifndef CORSIX_TH_TOUCH_LAYOUT_H_
#define CORSIX_TH_TOUCH_LAYOUT_H_

namespace touch_ui {

//! The game's (logical) resolution for a screen or window of screen_w x
//! screen_h points. Theme Hospital's interface needs at least min_w x min_h
//! game pixels: on small screens (phones) the screen's shape is scaled up to
//! that; on big ones (iPads, folded-out phones) one game pixel is one point.
//! The game is drawn at this size and scaled to fit (touch_ui). Sizes of 0
//! give 0x0.
void logical_size(int screen_w, int screen_h, int min_w, int min_h, int* width,
                  int* height);

}  // namespace touch_ui

#endif  // CORSIX_TH_TOUCH_LAYOUT_H_

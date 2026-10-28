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

#ifndef CORSIX_TH_TOUCH_STORAGE_H_
#define CORSIX_TH_TOUCH_STORAGE_H_

#include <string>

//! File helpers for the touch (iOS) build. Pure C++17, so they can be tested
//! on any platform.
namespace touch_storage {

//! Copies files ending in extension from the folder from (and its
//! subfolders) into to, keeping the same relative paths, unless a file with
//! that path is already there. Used to move saves made on the phone into
//! iCloud Drive. Returns how many files were copied.
int copy_missing_files(const std::string& from, const std::string& to,
                       const std::string& extension);

//! Sends stdout and stderr to dir/console.txt (replacing any earlier one),
//! creating dir if needed. Returns false if that wasn't possible.
bool redirect_console(const std::string& dir);

}  // namespace touch_storage

#endif  // CORSIX_TH_TOUCH_STORAGE_H_

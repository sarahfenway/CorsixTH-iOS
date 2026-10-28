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

#include "touch_storage.h"

#include <unistd.h>

#include <cstdio>
#include <filesystem>
#include <system_error>

namespace fs = std::filesystem;

namespace touch_storage {

int copy_missing_files(const std::string& from, const std::string& to,
                       const std::string& extension) {
  std::error_code ec;
  if (!fs::is_directory(from, ec)) {
    return 0;
  }
  int copied = 0;
  fs::recursive_directory_iterator it(from, ec);
  for (; !ec && it != fs::recursive_directory_iterator(); it.increment(ec)) {
    const fs::path& source = it->path();
    std::error_code file_ec;
    if (!it->is_regular_file(file_ec) || source.extension() != extension) {
      continue;
    }
    fs::path target = fs::path(to) / fs::relative(source, from, file_ec);
    if (file_ec || fs::exists(target, file_ec)) {
      continue;
    }
    fs::create_directories(target.parent_path(), file_ec);
    if (fs::copy_file(source, target, file_ec) && !file_ec) {
      ++copied;
    }
  }
  return copied;
}

bool redirect_console(const std::string& dir) {
  std::error_code ec;
  fs::create_directories(dir, ec);
  std::string path = (fs::path(dir) / "console.txt").string();
  if (std::freopen(path.c_str(), "w", stdout) == nullptr) {
    return false;
  }
  // Line buffering, so the log is complete even if the app is killed.
  std::setvbuf(stdout, nullptr, _IOLBF, 0);
  dup2(fileno(stdout), fileno(stderr));
  return true;
}

}  // namespace touch_storage

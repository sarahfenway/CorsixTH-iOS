// Tests for the touch build's file helpers.
// Build: c++ -std=c++17 -I../deps/CorsixTH/CorsixTH/Src test_touch_storage.cpp
//            ../deps/CorsixTH/CorsixTH/Src/touch_storage.cpp -o test_touch_storage

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>

#include "touch_storage.h"

namespace fs = std::filesystem;

static int failures = 0;

static void check(bool ok, const char* what) {
  std::printf("%s %s\n", ok ? "ok  " : "FAIL", what);
  if (!ok) ++failures;
}

static void write(const fs::path& p, const std::string& text) {
  fs::create_directories(p.parent_path());
  std::ofstream(p) << text;
}

static std::string read(const fs::path& p) {
  std::ifstream f(p);
  return std::string(std::istreambuf_iterator<char>(f), {});
}

int main() {
  fs::path root = fs::temp_directory_path() / "cth_storage_test";
  fs::remove_all(root);
  fs::path local = root / "local" / "Saves";
  fs::path cloud = root / "cloud" / "Saves";

  write(local / "My hospital.sav", "local A");
  write(local / "Autosaves" / "Autosave3.sav", "local B");
  write(local / "notes.txt", "not a save");
  write(cloud / "Shared.sav", "cloud C");
  write(cloud / "My hospital.sav", "cloud newer");  // already in the cloud

  int copied = touch_storage::copy_missing_files(local.string(), cloud.string(), ".sav");
  check(copied == 1, "copies only saves missing from the cloud");
  check(read(cloud / "Autosaves" / "Autosave3.sav") == "local B", "keeps subfolders (Autosaves)");
  check(read(cloud / "My hospital.sav") == "cloud newer", "never overwrites a save already there");
  check(!fs::exists(cloud / "notes.txt"), "ignores files that aren't saves");
  check(read(cloud / "Shared.sav") == "cloud C", "leaves other cloud saves alone");
  check(touch_storage::copy_missing_files(local.string(), cloud.string(), ".sav") == 0,
        "running again copies nothing");
  check(touch_storage::copy_missing_files((root / "missing").string(), cloud.string(), ".sav") == 0,
        "a missing source folder is fine");

  std::fflush(stdout);
  fs::path logs = root / "Logs";
  bool redirected = touch_storage::redirect_console(logs.string());
  std::printf("hello log\n");
  std::fprintf(stderr, "error line\n");
  std::fflush(stdout);
  std::string log = read(logs / "console.txt");
  // stdout now goes to the file, so report through a fresh file instead.
  std::ofstream report(root / "report.txt");
  report << (redirected && log.find("hello log") != std::string::npos &&
                     log.find("error line") != std::string::npos
                 ? "ok"
                 : "FAIL");
  report.close();
  return failures;
}

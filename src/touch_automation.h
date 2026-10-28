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

#ifndef CORSIX_TH_TOUCH_AUTOMATION_H_
#define CORSIX_TH_TOUCH_AUTOMATION_H_

#include <string>
#include <vector>

struct lua_State;

//! Scripted UI runs for testing the touch build without a person.
/*!
    Only active in touch mode, and only when CORSIXTH_AUTOMATION names a script
    file (on the simulator: `SIMCTL_CHILD_CORSIXTH_AUTOMATION=/host/path`).
    One command per line; blank lines and lines starting with # are ignored:

      wait <ms>
      tap <x> <y>                       one finger, down and up
      drag <x1> <y1> <x2> <y2> <ms>     one finger
      twofinger_tap <x> <y>
      pinch <x> <y> <scale>             two fingers moving apart (scale > 1)
      pan <dx> <dy>                     two fingers moving together
      coords game|points                what tap/drag/... coordinates mean:
                                        game pixels (the default) or screen
                                        points
      controls trackpad|direct          switch touch controls
      lua <code>                        run in the game's Lua state
      expect <lua expression>           fail unless it is true
      wait_until <ms> <lua expression>  wait for it to become true, or fail
      type <text>                       text, as if typed on the keyboard
      key <name>                        press and release a key, by SDL name
                                        (e.g. Return, Escape, Backspace)
      native_tap <label>                activate a native (UIKit/SwiftUI)
                                        control by its accessibility label
      screenshot <name>
      host <request>                    ask the host script to do something
                                        (e.g. "background") and wait for it
      log <text>

    Touches are injected as real SDL finger events, so they go through the
    same gesture recognition as a real finger. Progress goes to
    automation.log in the output folder (CORSIXTH_AUTOMATION_OUT, by default
    <config folder>/Automation), ending with "RESULT: PASS" or
    "RESULT: FAIL <reason>".

    When CORSIXTH_AUTOMATION_HOST=1 a host script is watching the output
    folder: screenshots and host requests are written to a file called
    "request" there, and the script carries on once the host deletes it (the
    host takes screenshots with `simctl io screenshot`, so native UI shows up
    too). Without a host, screenshots are taken in-app.
*/
namespace touch_automation {

//! Loads the script named by CORSIXTH_AUTOMATION, if any. Call once at
//! start-up, after the config folder is known.
void init();

//! True while a script is loaded and hasn't finished.
bool running();

//! Runs any script steps that are due. Call on every timer tick of the main
//! loop, with the Lua state the game runs in.
void poll(lua_State* L);

//! Splits a script line into its command and the rest of the line (both
//! trimmed). Exposed for unit tests.
void split_command(const std::string& line, std::string* command,
                   std::string* rest);

//! Parses whitespace separated numbers. Returns false unless there are
//! exactly `count` of them. Exposed for unit tests.
bool parse_numbers(const std::string& text, size_t count,
                   std::vector<double>* out);

}  // namespace touch_automation

#endif  // CORSIX_TH_TOUCH_AUTOMATION_H_

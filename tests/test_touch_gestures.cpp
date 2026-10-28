// Unit tests for the touch gesture recogniser (no SDL needed).
// Build: c++ -std=c++17 -I../deps/CorsixTH/CorsixTH/Src test_touch_gestures.cpp
//            ../deps/CorsixTH/CorsixTH/Src/touch_gestures.cpp -o test_touch_gestures

#include <cstdio>
#include <string>
#include <vector>

#include "touch_gestures.h"

using touch_ui::button_left;
using touch_ui::button_middle;
using touch_ui::button_right;
using touch_ui::gesture_recogniser;
using touch_ui::trackpad_recogniser;
using touch_ui::mouse_action;
using kind = mouse_action::kind;

namespace {

int failures = 0;

std::string describe(const std::vector<mouse_action>& v) {
  std::string s;
  for (const auto& a : v) {
    char buf[64];
    const char* name = a.type == kind::move    ? "move"
                       : a.type == kind::press ? "press"
                       : a.type == kind::pan   ? "pan"
                       : a.type == kind::zoom  ? "zoom"
                                               : "release";
    if (a.type == kind::zoom) {
      std::snprintf(buf, sizeof(buf), "%s%+d(%d,%d) ", name, a.distance, a.x,
                    a.y);
    } else if (a.type == kind::move || a.type == kind::pan) {
      std::snprintf(buf, sizeof(buf), "%s(%d,%d) ", name, a.x, a.y);
    } else {
      std::snprintf(buf, sizeof(buf), "%s%d(%d,%d) ", name, a.button, a.x,
                    a.y);
    }
    s += buf;
  }
  return s;
}

void expect(const char* test, const std::vector<mouse_action>& got,
            const std::string& want) {
  std::string g = describe(got);
  if (g != want) {
    ++failures;
    std::printf("FAIL %s\n  want: %s\n  got:  %s\n", test, want.c_str(),
                g.c_str());
  } else {
    std::printf("ok   %s\n", test);
  }
}

}  // namespace

int main() {
  {
    gesture_recogniser g;
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.finger_move(1, 103, 102, 1040, out);  // within slop
    g.tick(1060, out);
    g.finger_up(1, 103, 102, 1080, out);
    expect("tap is a left click at the touch point", out,
           "move(100,100) press1(100,100) release1(100,100) ");
  }
  {
    gesture_recogniser g;
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.finger_move(1, 160, 100, 1050, out);  // quick swipe
    g.finger_move(1, 200, 120, 1070, out);
    g.finger_up(1, 200, 120, 1090, out);
    expect("quick swipe only moves the pointer", out,
           "move(100,100) move(160,100) move(200,120) move(200,120) ");
  }
  {
    gesture_recogniser g;
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.tick(1100, out);
    g.tick(1200, out);
    g.finger_move(1, 150, 100, 1250, out);  // after the drag delay
    g.finger_move(1, 220, 140, 1300, out);
    g.finger_up(1, 220, 140, 1350, out);
    expect("touch, pause and drag is a left drag", out,
           "move(100,100) press1(100,100) move(150,100) move(220,140) "
           "move(220,140) release1(220,140) ");
  }
  {
    gesture_recogniser g;
    std::vector<mouse_action> out;
    g.finger_down(1, 300, 200, 1000, out);
    g.tick(1400, out);
    g.tick(1520, out);  // past 500 ms
    g.tick(1600, out);  // fires once only
    g.finger_move(1, 360, 200, 1700, out);  // ignored after long press
    g.finger_up(1, 360, 200, 1800, out);
    expect("long press is a single right click", out,
           "move(300,200) press3(300,200) release3(300,200) ");
  }
  {
    gesture_recogniser g;
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.finger_down(2, 200, 100, 1040, out);
    g.finger_up(1, 100, 100, 1150, out);
    g.finger_up(2, 200, 100, 1160, out);
    g.tick(1700, out);
    expect("two-finger tap is a right click between the fingers", out,
           "move(100,100) move(150,100) press3(150,100) release3(150,100) ");
  }
  {
    gesture_recogniser g;
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.finger_down(2, 200, 100, 1030, out);
    g.finger_move(1, 130, 140, 1060, out);
    g.finger_move(2, 230, 140, 1060, out);
    g.finger_move(1, 160, 180, 1090, out);
    g.finger_move(2, 260, 180, 1090, out);
    g.finger_up(1, 160, 180, 1120, out);
    g.finger_up(2, 260, 180, 1130, out);
    expect("two-finger drag is a middle button drag (map pan)", out,
           "move(100,100) move(150,100) press2(150,100) move(165,120) "
           "move(180,140) move(195,160) move(210,180) release2(210,180) ");
  }
  {
    gesture_recogniser g;
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.finger_down(2, 200, 100, 1030, out);
    for (int i = 1; i <= 6; ++i) {  // pinch out; the centre stays put
      g.finger_move(1, 100 - 10 * i, 100, 1030 + 20 * i, out);
      g.finger_move(2, 200 + 10 * i, 100, 1040 + 20 * i, out);
    }
    g.finger_up(1, 40, 100, 1300, out);
    g.finger_up(2, 260, 100, 1310, out);
    expect("pinch zooms once the fingers' spacing has changed enough, "
           "no clicks", out,
           // (The fingers move one at a time, so the centre steps between them.)
           "move(100,100) " "zoom+10(150,100) zoom+10(145,100) zoom+10(150,100) "
           "zoom+10(145,100) zoom+10(150,100) zoom+10(145,100) "
           "zoom+10(150,100) zoom+10(145,100) zoom+10(150,100) ");
  }
  {
    gesture_recogniser g;
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.tick(1200, out);
    g.finger_move(1, 150, 100, 1250, out);  // left drag in progress
    g.finger_down(2, 300, 100, 1300, out);  // second finger arrives
    g.finger_up(2, 300, 100, 1350, out);
    g.finger_up(1, 150, 100, 1400, out);
    expect("second finger ends a left drag cleanly, no right click", out,
           "move(100,100) press1(100,100) move(150,100) release1(150,100) ");
  }
  {
    gesture_recogniser g;
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.tick(1200, out);
    g.finger_move(1, 150, 100, 1250, out);
    g.cancel(out);
    g.finger_down(3, 50, 50, 2000, out);
    g.finger_up(3, 50, 50, 2050, out);
    expect("cancel releases held buttons and resets", out,
           "move(100,100) press1(100,100) move(150,100) release1(150,100) "
           "move(50,50) press1(50,50) release1(50,50) ");
  }
  {
    // Every press must be matched by a release, whatever the fingers do.
    gesture_recogniser g;
    std::vector<mouse_action> out;
    unsigned seed = 12345;
    auto rnd = [&seed](int n) {
      seed = seed * 1103515245u + 12345u;
      return static_cast<int>((seed >> 16) % static_cast<unsigned>(n));
    };
    bool down[4] = {false, false, false, false};
    uint32_t now = 1000;
    for (int step = 0; step < 20000; ++step) {
      now += static_cast<uint32_t>(rnd(120));
      int f = rnd(4);
      int x = rnd(1000);
      int y = rnd(480);
      int op = rnd(4);
      if (!down[f] && op == 0) {
        g.finger_down(f, x, y, now, out);
        down[f] = true;
      } else if (down[f] && op == 1) {
        g.finger_up(f, x, y, now, out);
        down[f] = false;
      } else if (down[f]) {
        g.finger_move(f, x, y, now, out);
      }
      g.tick(now, out);
    }
    for (int f = 0; f < 4; ++f) {
      if (down[f]) {
        g.finger_up(f, 0, 0, now + 10, out);
      }
    }
    int held[4] = {0, 0, 0, 0};
    bool ok = true;
    for (const auto& a : out) {
      if (a.type == kind::press) {
        ok = ok && held[a.button] == 0;
        held[a.button]++;
      } else if (a.type == kind::release) {
        ok = ok && held[a.button] == 1;
        held[a.button]--;
      }
    }
    ok = ok && held[1] == 0 && held[2] == 0 && held[3] == 0;
    if (ok) {
      std::printf("ok   presses and releases always pair up (%zu actions)\n",
                  out.size());
    } else {
      ++failures;
      std::printf("FAIL presses and releases do not pair up\n");
    }
  }

  // ---- trackpad mode -------------------------------------------------------
  auto trackpad = [] {
    trackpad_recogniser t;
    t.set_bounds(1000, 480);  // cursor starts at (500, 240)
    return t;
  };
  {
    auto g = trackpad();
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.finger_up(1, 100, 100, 1100, out);
    expect("trackpad: tap clicks at the cursor, not under the finger", out,
           "move(500,240) press1(500,240) release1(500,240) ");
  }
  {
    auto g = trackpad();
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.finger_move(1, 105, 100, 1016, out);  // within slop: nothing yet
    g.finger_move(1, 120, 110, 1032, out);  // catches up with the whole move
    g.finger_move(1, 125, 110, 1048, out);  // slow: about 1:1
    g.finger_up(1, 125, 110, 1100, out);
    expect("trackpad: moving a finger moves the cursor the same way", out,
           "move(500,240) move(520,250) move(525,250) ");
  }
  {
    auto g = trackpad();
    std::vector<mouse_action> out;
    g.finger_down(1, 0, 0, 1000, out);
    g.finger_move(1, 20, 0, 1010, out);
    g.finger_move(1, 60, 0, 1020, out);  // 40 px in 10 ms: accelerated
    expect("trackpad: a fast flick moves the cursor further", out,
           "move(500,240) move(520,240) move(620,240) ");
  }
  {
    auto g = trackpad();
    std::vector<mouse_action> out;
    g.finger_down(1, 900, 240, 1000, out);
    g.finger_move(1, 100, 240, 1300, out);
    expect("trackpad: the cursor stays on screen", out,
           "move(500,240) move(0,240) ");
  }
  {
    auto g = trackpad();
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.finger_up(1, 100, 100, 1600, out);
    expect("trackpad: resting a finger without moving is not a click", out,
           "move(500,240) ");
  }
  {
    auto g = trackpad();
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.finger_up(1, 100, 100, 1080, out);
    g.finger_down(2, 300, 300, 1200, out);  // soon after the tap
    g.finger_move(2, 320, 300, 1250, out);
    g.finger_move(2, 340, 300, 1270, out);
    g.finger_up(2, 340, 300, 1300, out);
    expect("trackpad: tap then touch-and-move is a left drag", out,
           "move(500,240) press1(500,240) release1(500,240) "
           "press1(500,240) move(520,240) move(552,240) release1(552,240) ");
  }
  {
    auto g = trackpad();
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.finger_up(1, 100, 100, 1080, out);
    g.finger_down(2, 100, 100, 1200, out);
    g.finger_up(2, 100, 100, 1280, out);
    expect("trackpad: double tap is two clicks", out,
           "move(500,240) press1(500,240) release1(500,240) "
           "press1(500,240) release1(500,240) ");
  }
  {
    auto g = trackpad();
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.finger_up(1, 100, 100, 1080, out);
    g.finger_down(2, 300, 300, 2000, out);  // long after the tap
    g.finger_move(2, 320, 300, 2050, out);
    g.finger_up(2, 320, 300, 2100, out);
    expect("trackpad: a later touch just moves the cursor", out,
           "move(500,240) press1(500,240) release1(500,240) move(520,240) ");
  }
  {
    auto g = trackpad();
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.finger_down(2, 200, 100, 1030, out);
    g.finger_up(1, 100, 100, 1150, out);
    g.finger_up(2, 200, 100, 1160, out);
    expect("trackpad: two-finger tap right-clicks at the cursor", out,
           "move(500,240) press3(500,240) release3(500,240) ");
  }
  {
    auto g = trackpad();
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.finger_down(2, 200, 100, 1030, out);
    g.finger_move(1, 130, 140, 1060, out);
    g.finger_move(2, 230, 140, 1060, out);
    g.finger_up(1, 130, 140, 1100, out);
    g.finger_up(2, 230, 140, 1110, out);
    expect("trackpad: two-finger drag pans, cursor stays put", out,
           "move(500,240) press2(500,240) pan(15,20) pan(15,20) "
           "release2(500,240) ");
  }
  {
    auto g = trackpad();
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 100, 1000, out);
    g.finger_down(2, 200, 100, 1030, out);
    for (int i = 1; i <= 6; ++i) {
      g.finger_move(1, 100 - 10 * i, 100, 1030 + 20 * i, out);
      g.finger_move(2, 200 + 10 * i, 100, 1040 + 20 * i, out);
    }
    g.finger_up(1, 40, 100, 1300, out);
    g.finger_up(2, 260, 100, 1310, out);
    expect("trackpad: pinch zooms once the spacing has changed enough, "
           "no clicks or pans", out,
           "move(500,240) " "zoom+10(150,100) zoom+10(145,100) zoom+10(150,100) "
           "zoom+10(145,100) zoom+10(150,100) zoom+10(145,100) "
           "zoom+10(150,100) zoom+10(145,100) zoom+10(150,100) ");
  }
  {
    auto g = trackpad();
    std::vector<mouse_action> out;
    unsigned seed = 999;
    auto rnd = [&seed](int n) {
      seed = seed * 1103515245u + 12345u;
      return static_cast<int>((seed >> 16) % static_cast<unsigned>(n));
    };
    bool down[4] = {false, false, false, false};
    uint32_t now = 1000;
    for (int step = 0; step < 20000; ++step) {
      now += static_cast<uint32_t>(rnd(150));
      int f = rnd(4);
      int x = rnd(1000);
      int y = rnd(480);
      int op = rnd(4);
      if (!down[f] && op == 0) {
        g.finger_down(f, x, y, now, out);
        down[f] = true;
      } else if (down[f] && op == 1) {
        g.finger_up(f, x, y, now, out);
        down[f] = false;
      } else if (down[f]) {
        g.finger_move(f, x, y, now, out);
      }
    }
    for (int f = 0; f < 4; ++f) {
      if (down[f]) {
        g.finger_up(f, 0, 0, now + 10, out);
      }
    }
    int held[4] = {0, 0, 0, 0};
    bool ok = true;
    for (const auto& a : out) {
      if (a.type == kind::press) {
        ok = ok && held[a.button] == 0;
        held[a.button]++;
      } else if (a.type == kind::release) {
        ok = ok && held[a.button] == 1;
        held[a.button]--;
      } else if (a.type == kind::move) {
        ok = ok && a.x >= 0 && a.x < 1000 && a.y >= 0 && a.y < 480;
      }
    }
    ok = ok && held[1] == 0 && held[2] == 0 && held[3] == 0;
    if (ok) {
      std::printf("ok   trackpad: buttons always pair up, cursor stays on "
                  "screen (%zu actions)\n", out.size());
    } else {
      ++failures;
      std::printf("FAIL trackpad: unpaired buttons or cursor off screen\n");
    }
  }

  // Placing things (aim offset on): a tap places right where it lands; a drag
  // aims the item above the finger, so it isn't hidden, and lifting drops it
  // there; a long press is still a right click where it lands (picks an item
  // up); the aim stays on screen.
  {
    gesture_recogniser g;
    g.set_aim_offset(40);
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 200, 1000, out);
    g.finger_up(1, 102, 201, 1080, out);
    expect("placing: a tap places where it lands", out,
           "move(100,200) press1(100,200) release1(100,200) ");
  }
  {
    gesture_recogniser g;
    g.set_aim_offset(40);
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 200, 1000, out);
    g.finger_move(1, 130, 200, 1040, out);
    g.finger_move(1, 160, 210, 1300, out);  // a slow drag: still aiming
    g.finger_up(1, 160, 210, 1400, out);
    expect("placing: a drag aims above the finger and lifting drops it", out,
           "move(100,200) move(130,160) move(160,170) move(160,170) "
           "press1(160,170) release1(160,170) ");
  }
  {
    gesture_recogniser g;
    g.set_aim_offset(40);
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 200, 1000, out);
    g.tick(1600, out);
    g.finger_up(1, 100, 200, 1700, out);
    expect("placing: a long press right-clicks where it lands", out,
           "move(100,200) press3(100,200) release3(100,200) ");
  }
  {
    gesture_recogniser g;
    g.set_aim_offset(40);
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 20, 1000, out);
    g.finger_move(1, 100, 50, 1040, out);
    g.finger_up(1, 100, 50, 1100, out);
    expect("placing: the aim stays on screen near the top", out,
           "move(100,20) move(100,10) move(100,10) press1(100,10) "
           "release1(100,10) ");
  }
  {
    gesture_recogniser g;
    g.set_aim_offset(40);
    g.set_aim_offset(0);  // Placing over: back to the usual direct touches.
    std::vector<mouse_action> out;
    g.finger_down(1, 100, 200, 1000, out);
    g.finger_move(1, 130, 200, 1040, out);
    g.finger_up(1, 130, 200, 1100, out);
    expect("placing off: a quick swipe only moves the pointer again", out,
           "move(100,200) move(130,200) move(130,200) ");
  }

  // A two-finger pan where the fingers drift a little closer and further
  // apart (as real fingers do) must not zoom, and must still pan.
  {
    auto wobbly_pan = [](auto& g, std::vector<mouse_action>& out) {
      g.finger_down(1, 100, 200, 1000, out);
      g.finger_down(2, 160, 200, 1020, out);
      for (int i = 1; i <= 40; ++i) {
        int wobble = (i % 8 < 4 ? i % 4 : 4 - i % 4) * 5;  // 0..20 px
        g.finger_move(1, 100 + 5 * i, 200 + 2 * i, 1020 + 8 * i, out);
        g.finger_move(2, 160 + 5 * i + wobble, 200 + 2 * i, 1024 + 8 * i, out);
      }
      g.finger_up(1, 300, 280, 1400, out);
      g.finger_up(2, 360, 280, 1410, out);
    };
    auto count = [](const std::vector<mouse_action>& out, kind k) {
      int n = 0;
      for (const auto& a : out) n += a.type == k;
      return n;
    };
    {
      gesture_recogniser g;
      std::vector<mouse_action> out;
      wobbly_pan(g, out);
      bool ok = count(out, kind::zoom) == 0 && count(out, kind::press) == 1;
      std::printf("%s direct: a wobbly two-finger pan pans without zooming "
                  "(%d zooms)\n", ok ? "ok  " : "FAIL", count(out, kind::zoom));
      failures += ok ? 0 : 1;
    }
    {
      auto g = trackpad();
      std::vector<mouse_action> out;
      wobbly_pan(g, out);
      bool ok = count(out, kind::zoom) == 0 && count(out, kind::pan) > 0;
      std::printf("%s trackpad: a wobbly two-finger pan pans without zooming "
                  "(%d zooms)\n", ok ? "ok  " : "FAIL", count(out, kind::zoom));
      failures += ok ? 0 : 1;
    }
  }

  std::printf(failures == 0 ? "\nAll tests passed\n" : "\n%d test(s) failed\n",
              failures);
  return failures == 0 ? 0 : 1;
}

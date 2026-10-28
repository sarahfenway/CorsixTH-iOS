#!/bin/bash
# Builds CorsixTH (the open-source Theme Hospital engine) as an iPhone/iPad
# app with your Theme Hospital game data bundled inside it.
#
#   ./build-ios.sh [path/to/theme_hospital*.pkg]   prepare + open in Xcode
#   ./build-ios.sh --install                        also build and install on a
#                                                   connected iPhone/iPad
#   ./build-ios.sh --team                           choose the signing team again
#   ./build-ios.sh --simulator [device]             build, install and launch in
#                                                   the iOS Simulator (default: a
#                                                   "CorsixTH-Duo" simulator,
#                                                   created if missing)
#   ./build-ios.sh --run tests/automation           same, then run automation
#                                                   scripts (a folder runs all of
#                                                   them; --run can be repeated);
#                                                   results in build-ios/automation/
#
# The first run asks which Apple development team should sign the app and
# remembers the answer in .team-id. Environment overrides: TEAM_ID, BUNDLE_ID,
# ICLOUD=OFF (keep save games on the device instead of in iCloud Drive).
# Needs: a Mac with Xcode (and its iOS platform) installed. Everything else
# (CMake, SDL, Lua...) is downloaded into this folder. Works with macOS's
# built-in bash 3.2.

set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

BUNDLE_ID="${BUNDLE_ID:-uk.me.krn.corsixth}"
CMAKE_VERSION="4.4.4"
BUILD_DIR="$ROOT/build-ios"
INSTALL=0
CHOOSE_TEAM=0
SIMULATOR=0
SIM_DEVICE=""
RUN_SCRIPTS=""  # newline-separated (bash 3.2 and set -u don't mix with empty arrays)
PKG=""

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die() { printf '\n\033[31mProblem:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL=1 ;;
    --team) CHOOSE_TEAM=1 ;;
    --simulator)
      SIMULATOR=1
      # An optional device name or UDID follows.
      if [ $# -gt 1 ] && [ "${2#-}" = "$2" ] && [ "${2%.pkg}" = "$2" ]; then
        SIM_DEVICE="$2"; shift
      fi ;;
    --run)
      [ $# -gt 1 ] || die "--run needs a script file or folder"
      SIMULATOR=1
      if [ -d "$2" ]; then
        # Every script in the folder, in name order.
        for f in "$(cd "$2" && pwd)"/*.txt; do
          [ -f "$f" ] && RUN_SCRIPTS="$RUN_SCRIPTS$f
"
        done
      elif [ -f "$2" ]; then
        RUN_SCRIPTS="$RUN_SCRIPTS$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
"
      else
        die "No automation script at $2"
      fi
      shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) PKG="$1" ;;
  esac
  shift
done
[ "$SIMULATOR" = "0" ] || [ "$INSTALL" = "0" ] || die "Use either --install or --simulator, not both."

# ---------------------------------------------------------------------------
say "Checking Xcode"
[ "$(uname)" = "Darwin" ] || die "This has to run on a Mac."
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  die "Xcode's iOS SDK wasn't found. Install Xcode from the App Store, open it
once (let it install the iOS platform if it offers), then run:
    sudo xcode-select -s /Applications/Xcode.app"
fi
note "$(xcodebuild -version | head -1), iOS SDK $(xcrun --sdk iphoneos --show-sdk-version)"

# ---------------------------------------------------------------------------
say "Finding CMake"
CMAKE=""
if command -v cmake >/dev/null 2>&1; then
  CMAKE="$(command -v cmake)"
  # Older CMake releases don't know about recent Xcode versions.
  major_minor="$("$CMAKE" --version | head -1 | sed 's/[^0-9]*\([0-9]*\)\.\([0-9]*\).*/\1 \2/')"
  set -- $major_minor
  if [ "${1:-0}" -lt 3 ] || { [ "${1:-0}" -eq 3 ] && [ "${2:-0}" -lt 28 ]; }; then
    note "Your CMake is too old for this; using a private copy instead"
    CMAKE=""
  fi
fi
if [ -z "$CMAKE" ]; then
  CMAKE="$ROOT/tools/cmake-$CMAKE_VERSION-macos-universal/CMake.app/Contents/bin/cmake"
  if [ ! -x "$CMAKE" ]; then
    note "Not installed - downloading CMake $CMAKE_VERSION into tools/ (about 60 MB)"
    curl -fL --progress-bar -o "$ROOT/tools/cmake.tar.gz" \
      "https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/cmake-$CMAKE_VERSION-macos-universal.tar.gz"
    tar -xzf "$ROOT/tools/cmake.tar.gz" -C "$ROOT/tools"
    rm -f "$ROOT/tools/cmake.tar.gz"
  fi
fi
note "$("$CMAKE" --version | head -1)"

# ---------------------------------------------------------------------------
say "Fetching source code (pinned versions)"
mkdir -p "$ROOT/deps"
fetch() {  # fetch <folder> <github owner/repo> <tag>
  if [ -d "$ROOT/deps/$1/.git" ]; then
    note "$1 already present"
  else
    note "$1 ($3)"
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$3" \
      "https://github.com/$2.git" "$ROOT/deps/$1"
  fi
}
fetch SDL       libsdl-org/SDL              release-2.32.10
fetch SDL_mixer libsdl-org/SDL_mixer        release-2.8.1
fetch lua       lua/lua                     v5.4.7
fetch lpeg      roberto-ieru/LPeg           v1.1.0
fetch lfs       lunarmodules/luafilesystem  v1_8_0
fetch freetype  freetype/freetype           VER-2-13-3
fetch libpng    pnggroup/libpng             v1.6.50

# SDL2 predates the UIScene life cycle that recent iOS SDKs insist on.
/usr/bin/python3 "$ROOT/tools/sdl2_uiscene_edit.py" "$ROOT/deps/SDL" | sed 's/^/    /'

# CorsixTH (MIT licensed) isn't part of this repository: it lives in CorsixTH/,
# either cloned here or put there by hand (the 0.70.1 source download, unzipped
# so that CorsixTH/CorsixTH/CorsixTH.lua exists). The small changes this port
# needs in CorsixTH's own files are in patches/corsixth-ios.patch.
CTH="$ROOT/CorsixTH"
if [ -f "$CTH/CorsixTH/CorsixTH.lua" ]; then
  note "CorsixTH already present"
else
  note "CorsixTH (v0.70.1)"
  git -c advice.detachedHead=false clone -q --depth 1 --branch v0.70.1 \
    https://github.com/CorsixTH/CorsixTH.git "$CTH"
fi
PATCH="$ROOT/patches/corsixth-ios.patch"
if git apply --directory=CorsixTH --reverse --check "$PATCH" >/dev/null 2>&1; then
  note "iOS patch already applied to CorsixTH"
else
  git apply --directory=CorsixTH "$PATCH" \
    || die "Couldn't apply patches/corsixth-ios.patch to CorsixTH/. It needs an
unmodified copy of CorsixTH 0.70.1 there."
  note "Applied the iOS patch to CorsixTH"
fi

# ---------------------------------------------------------------------------
say "Theme Hospital game data"
DATA="$ROOT/ThemeHospital"
if [ -d "$DATA/DATA" ] && [ -d "$DATA/LEVELS" ] && [ -d "$DATA/QDATA" ]; then
  note "Already extracted in ThemeHospital/"
else
  if [ -z "$PKG" ]; then
    for candidate in "$ROOT"/theme_hospital*.pkg "$HOME"/Downloads/theme_hospital*.pkg; do
      if [ -f "$candidate" ]; then PKG="$candidate"; break; fi
    done
  fi
  INSTALLED="/Applications/Theme Hospital.app/Contents/Resources/game"
  if [ -n "$PKG" ] && [ -f "$PKG" ]; then
    note "Extracting from $(basename "$PKG")"
    rm -rf "$DATA.partial"
    /usr/bin/python3 "$ROOT/tools/extract_gog_pkg.py" "$PKG" "$DATA.partial"
    mv "$DATA.partial" "$DATA"
  elif [ -d "$INSTALLED/DATA" ]; then
    note "Copying from the installed GOG app"
    mkdir -p "$DATA"
    for d in DATA DATAM QDATA QDATAM LEVELS SOUND; do
      [ -d "$INSTALLED/$d" ] && cp -R "$INSTALLED/$d" "$DATA/"
    done
  else
    die "Couldn't find the GOG installer. Pass its path, e.g.
    ./build-ios.sh ~/Downloads/theme_hospital_enUS_1_0_3_33062_1.pkg"
  fi
fi
note "$(du -sh "$DATA" | cut -f1) of game data will be bundled into the app"

# ---------------------------------------------------------------------------
say "Code signing"
TEAM_FILE="$ROOT/.team-id"

# Prints "TEAMID<TAB>description" for each development team this Mac knows
# about: the teams of the Apple IDs signed in to Xcode, then any other team
# with an "Apple Development" certificate in the keychain.
list_teams() {
  {
    defaults export com.apple.dt.Xcode - 2>/dev/null \
      | /usr/bin/python3 "$ROOT/tools/list_xcode_teams.py" || true
    certs="$(mktemp -d)"
    security find-certificate -a -c "Apple Development" -p 2>/dev/null \
      | awk -v dir="$certs" '/BEGIN CERTIFICATE/ {n++} n {print > (dir "/" n ".pem")}' || true
    for pem in "$certs"/*.pem; do
      [ -f "$pem" ] || continue
      openssl x509 -in "$pem" -noout -checkend 0 >/dev/null 2>&1 || continue  # expired
      subject="$(openssl x509 -in "$pem" -noout -subject 2>/dev/null || true)"
      ou="$(printf '%s' "$subject" | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p')"
      org="$(printf '%s' "$subject" | sed -n 's/.*[/,] *O *= *\([^/,]*\).*/\1/p')"
      if [ -n "$ou" ]; then printf '%s\t%s (certificate in keychain)\n' "$ou" "$org"; fi
    done
    rm -rf "$certs"
  } | awk -F '\t' 'NF >= 2 && !seen[$1]++'
}

choose_team() {
  teams="$(list_teams)"
  if [ -n "$teams" ]; then
    echo "    Development teams on this Mac:"
    printf '%s\n' "$teams" | awk -F '\t' '{printf "      %d) %s   [%s]\n", NR, $2, $1}'
  else
    echo "    No teams found. Is your Apple ID signed in to Xcode (Settings > Accounts)?"
  fi
  if [ ! -t 0 ]; then
    die "Not running in a terminal, so can't ask which team to use. Set TEAM_ID=XXXXXXXXXX."
  fi
  echo "    Type the number of the team that should sign Theme Hospital, or a 10-character"
  echo "    team ID, or just press Return to choose it in Xcode instead."
  answer=""
  read -r -p "    Team: " answer || answer=""
  case "$answer" in
    "") TEAM="" ;;
    *[!0-9]*) TEAM="$(printf '%s' "$answer" | tr 'a-z' 'A-Z')" ;;
    *) TEAM="$(printf '%s\n' "$teams" | awk -F '\t' -v n="$answer" 'NR == n {print $1}')"
       [ -n "$TEAM" ] || die "There's no team number $answer." ;;
  esac
  if [ -n "$TEAM" ]; then
    printf '%s' "$TEAM" | grep -Eq '^[A-Z0-9]{10}$' || die "\"$TEAM\" doesn't look like a team ID."
    printf '%s\n' "$TEAM" > "$TEAM_FILE"
  else
    rm -f "$TEAM_FILE"
  fi
}

TEAM="${TEAM_ID:-}"
if [ -z "$TEAM" ]; then
  if [ "$CHOOSE_TEAM" = "0" ] && [ -f "$TEAM_FILE" ]; then
    TEAM="$(tr -d '[:space:]' < "$TEAM_FILE")"
  elif [ "$CHOOSE_TEAM" = "1" ] || [ "$SIMULATOR" = "0" ]; then
    choose_team  # (the simulator doesn't need a team)
  fi
fi
if [ -n "$TEAM" ]; then
  note "Signing with team $TEAM, bundle ID $BUNDLE_ID (change with: ./build-ios.sh --team)"
else
  note "No team set - pick it in Xcode under Signing & Capabilities."
fi
# iCloud Drive (for save games) needs a paid developer account.
ICLOUD="${ICLOUD:-ON}"
if [ -n "$TEAM" ] && list_teams | grep -q "^$TEAM	.*(Personal Team)"; then
  ICLOUD=OFF
  note "Free (personal) team: save games stay on the device, as iCloud Drive needs a paid account."
fi

# ---------------------------------------------------------------------------
say "Generating the Xcode project"
"$CMAKE" -S "$ROOT" -B "$BUILD_DIR" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCTH_BUNDLE_ID="$BUNDLE_ID" \
  -DCTH_DEVELOPMENT_TEAM="$TEAM" \
  -DCTH_ICLOUD="$ICLOUD" \
  > "$BUILD_DIR.cmake.log" 2>&1 \
  || { tail -40 "$BUILD_DIR.cmake.log"; die "CMake failed - full log in build-ios.cmake.log"; }
PROJECT="$(ls -d "$BUILD_DIR"/*.xcodeproj | head -1)"
note "Created $(basename "$PROJECT")"

if [ "$SIMULATOR" = "1" ]; then
  # -------------------------------------------------------------------------
  say "Building for the simulator"
  # Prints the UDID of the available simulator with this name (the newest iOS
  # runtime wins) or UDID.
  find_simulator() {
    xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
want = sys.argv[1]
found = ""
for runtime, devices in sorted(json.load(sys.stdin)["devices"].items()):
    if ".iOS-" not in runtime:
        continue
    for d in devices:
        if want in (d["name"], d["udid"]):
            found = d["udid"]
print(found)' "$1"
  }
  SIM_NAME="${SIM_DEVICE:-CorsixTH-Duo}"
  UDID="$(find_simulator "$SIM_NAME")"
  if [ -z "$UDID" ]; then
    [ -z "$SIM_DEVICE" ] || die "No simulator called \"$SIM_DEVICE\". See: xcrun simctl list devices available"
    RUNTIME="$(xcrun simctl list runtimes available | sed -n 's/^iOS .* - \(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*\).*/\1/p' | tail -1)"
    [ -n "$RUNTIME" ] || die "No iOS simulator runtime installed (Xcode > Settings > Components)."
    # The foldable iPhone Duo if this Xcode knows it, else a regular iPhone.
    UDID="$(xcrun simctl create CorsixTH-Duo com.apple.CoreSimulator.SimDeviceType.iPhone-Duo "$RUNTIME" 2>/dev/null \
      || xcrun simctl create CorsixTH-Duo com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$RUNTIME")"
    note "Created simulator CorsixTH-Duo ($RUNTIME)"
  fi
  note "Simulator $SIM_NAME ($UDID)"
  xcodebuild -project "$PROJECT" -scheme CorsixTH -configuration Debug \
    -destination "id=$UDID" build > "$BUILD_DIR.xcodebuild.log" 2>&1 \
    || { grep -E 'error:|BUILD FAILED' "$BUILD_DIR.xcodebuild.log" | head -30
         die "The build failed - full log in build-ios.xcodebuild.log"; }
  APP="$BUILD_DIR/Debug-iphonesimulator/CorsixTH.app"
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  [ -n "${NO_SIMULATOR_WINDOW:-}" ] || open -a Simulator --args -CurrentDeviceUDID "$UDID"
  xcrun simctl install "$UDID" "$APP"
  DATA_DIR="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
  CONSOLE="$DATA_DIR/Documents/CorsixTH/Logs/console.txt"

  if [ -z "$RUN_SCRIPTS" ]; then
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
    say "Running in the simulator"
    note "Console log (when the simulator isn't signed in to iCloud):"
    note "  $CONSOLE"
    exit 0
  fi

  # Runs one automation script in a fresh launch of the app, answering its
  # requests (see CorsixTH/CorsixTH/Src/touch_automation.h). Prints PASS/FAIL.
  run_script() {
    script="$1"
    name="$(basename "$script" .txt)"
    app_out="$DATA_DIR/Documents/CorsixTH/Automation/$name"
    results="$BUILD_DIR/automation/$name"
    rm -rf "$app_out" "$results"
    mkdir -p "$app_out" "$results"
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    console_start=0
    [ -f "$CONSOLE" ] && console_start="$(wc -l < "$CONSOLE")"
    SIMCTL_CHILD_CORSIXTH_AUTOMATION="$script" \
    SIMCTL_CHILD_CORSIXTH_AUTOMATION_OUT="$app_out" \
    SIMCTL_CHILD_CORSIXTH_AUTOMATION_HOST=1 \
      xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
    deadline=$((SECONDS + ${AUTOMATION_TIMEOUT:-300}))
    while ! grep -q 'RESULT:' "$app_out/automation.log" 2>/dev/null; do
      if [ "$SECONDS" -ge "$deadline" ]; then
        echo "RESULT: FAIL timed out (did the app crash?)" >> "$app_out/automation.log"
        break
      fi
      if [ -f "$app_out/request" ]; then
        request="$(cat "$app_out/request")"
        case "$request" in
          "screenshot "*)
            xcrun simctl io "$UDID" screenshot "$results/${request#screenshot }.png" >/dev/null 2>&1 ;;
          background)
            # Another app comes to the front; ours is told it's going into
            # the background, gets a few seconds, then comes back.
            xcrun simctl launch "$UDID" com.apple.Preferences >/dev/null
            sleep "${BACKGROUND_SECONDS:-4}"
            xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null ;;
          *) note "Unknown request from the script: $request" >&2 ;;
        esac
        rm -f "$app_out/request"
      fi
      sleep 0.2
    done
    cp "$app_out"/*.png "$results/" 2>/dev/null || true
    cp "$app_out/automation.log" "$results/"
    [ -f "$CONSOLE" ] && tail -n +"$((console_start + 1))" "$CONSOLE" > "$results/console.txt"
    sed -n 's/.*RESULT: //p' "$results/automation.log" | tail -1
  }

  say "Running automation scripts"
  FAILED=0
  OLD_IFS="$IFS"; IFS='
'
  for script in $RUN_SCRIPTS; do
    IFS="$OLD_IFS"
    result="$(run_script "$script")"
    case "$result" in
      PASS) note "PASS  $(basename "$script")" ;;
      *) note "FAIL  $(basename "$script"): ${result#FAIL }"; FAILED=1 ;;
    esac
  done
  IFS="$OLD_IFS"
  note "Logs and screenshots: build-ios/automation/"
  exit "$FAILED"
fi

if [ "$INSTALL" = "0" ]; then
  say "Ready"
  cat <<EOF
    Opening the project in Xcode. Then:
      1. Plug in your iPhone (or iPad) and unlock it.
      2. At the top of the Xcode window choose the "CorsixTH" scheme and
         your device.
      3. Click the CorsixTH project > CorsixTH target > Signing & Capabilities
         and pick your team (your Apple ID), if it isn't set already.
      4. Press Run (the play button). The first build takes a few minutes.
    Or run ./build-ios.sh --install to do it all from here.
EOF
  open "$PROJECT"
  exit 0
fi

# ---------------------------------------------------------------------------
say "Building and installing"
[ -n "$TEAM" ] || die "No signing team chosen. Run ./build-ios.sh --team first."
# Ask Xcode which real (not simulator, not placeholder) iOS devices it can see.
DEVICE="$(xcodebuild -project "$PROJECT" -scheme CorsixTH -showdestinations 2>/dev/null \
  | grep 'platform:iOS,' | grep -v 'placeholder\|dvtdevice\|Simulator' \
  | sed -n 's/.*id:\([^,}]*\).*/\1/p' | head -1 || true)"
[ -n "$DEVICE" ] || die "No iPhone or iPad found. Plug it in, unlock it, trust this Mac,
and make sure Developer Mode is on (Settings > Privacy & Security)."
note "Device $DEVICE"
xcodebuild -project "$PROJECT" -scheme CorsixTH -configuration Release \
  -destination "id=$DEVICE" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" build > "$BUILD_DIR.xcodebuild.log" 2>&1 \
  || { grep -E 'error:|BUILD FAILED' "$BUILD_DIR.xcodebuild.log" | head -30
       die "The build failed - full log in build-ios.xcodebuild.log"; }
APP="$BUILD_DIR/Release-iphoneos/CorsixTH.app"
[ -d "$APP" ] || APP="$(find "$BUILD_DIR" -name CorsixTH.app -path '*iphoneos*' | head -1)"
xcrun devicectl device install app --device "$DEVICE" "$APP"
say "Installed. Look for \"Theme Hospital\" on your home screen."
note "First time only: Settings > General > VPN & Device Management > trust your Apple ID."

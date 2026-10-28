# CorsixTH for iPhone / iPad
#
# Builds CorsixTH (an open-source re-implementation of Theme Hospital) and all
# of its libraries from source into a single iOS app, with the Theme Hospital
# game data bundled inside it. Run ./build-ios.sh rather than calling this
# directly; that script fetches the sources this file expects under deps/.
#
# The same file also builds a desktop (Linux/macOS) binary. Starting that with
# CORSIXTH_TOUCH_UI=1 (and e.g. CORSIXTH_TOUCH_SCREEN=874x402) runs the iOS
# touch code paths in a window, which is handy for testing off-device.

cmake_minimum_required(VERSION 3.21)
project(CorsixTH_iOS LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(BUILD_SHARED_LIBS OFF)
# Only the app itself gets an Xcode scheme (set on the target further down).
set(CMAKE_XCODE_GENERATE_SCHEME OFF)

set(DEPS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/deps)
# CorsixTH's own source (v0.70.1 with patches/corsixth-ios.patch applied),
# downloaded by build-ios.sh. It isn't part of this repository.
set(CTH_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/CorsixTH)
set(CTH_DIR ${CTH_ROOT}/CorsixTH)
# This project's own code: touch controls, iOS platform glue, test automation.
set(PORT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src)
set(GAME_DATA_DIR ${CMAKE_CURRENT_SOURCE_DIR}/ThemeHospital CACHE PATH
    "Theme Hospital data folder (DATA, LEVELS, QDATA, SOUND...) to bundle")
set(MUSIC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/Music CACHE PATH
    "Optional folder of .ogg/.mp3 music to bundle")
set(CTH_BUNDLE_ID "uk.me.krn.corsixth" CACHE STRING "iOS bundle identifier")
set(CTH_DEVELOPMENT_TEAM "" CACHE STRING "Apple development team ID for signing")
option(CTH_ICLOUD "Keep save games in iCloud Drive (needs a paid developer account)" ON)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  set(CTH_IOS ON)
  enable_language(OBJCXX)
else()
  set(CTH_IOS OFF)
endif()

if(NOT EXISTS ${CTH_DIR}/CorsixTH.lua)
  message(FATAL_ERROR "CorsixTH/ is missing - run ./build-ios.sh (it downloads "
    "CorsixTH 0.70.1 there and applies patches/corsixth-ios.patch)")
endif()
if(NOT EXISTS ${DEPS_DIR}/SDL/CMakeLists.txt)
  message(FATAL_ERROR "deps/ is missing - run ./build-ios.sh (it downloads the sources)")
endif()

# ---------------------------------------------------------------------------
# SDL2

set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST OFF CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL2_DISABLE_INSTALL ON CACHE BOOL "" FORCE)
set(SDL2_DISABLE_UNINSTALL ON CACHE BOOL "" FORCE)
add_subdirectory(${DEPS_DIR}/SDL ${CMAKE_BINARY_DIR}/SDL EXCLUDE_FROM_ALL)

# ---------------------------------------------------------------------------
# SDL2_mixer - only formats with built-in decoders, so no extra libraries.

set(SDL2MIXER_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_INSTALL OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_SAMPLES OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_VENDORED OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_DEPS_SHARED OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_CMD OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_FLAC ON CACHE BOOL "" FORCE)
set(SDL2MIXER_FLAC_DRFLAC ON CACHE BOOL "" FORCE)
set(SDL2MIXER_FLAC_LIBFLAC OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_GME OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_MOD OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_MP3 ON CACHE BOOL "" FORCE)
set(SDL2MIXER_MP3_MINIMP3 ON CACHE BOOL "" FORCE)
set(SDL2MIXER_MP3_MPG123 OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_MIDI ON CACHE BOOL "" FORCE)
set(SDL2MIXER_MIDI_FLUIDSYNTH OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_MIDI_NATIVE OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_MIDI_TIMIDITY ON CACHE BOOL "" FORCE)
set(SDL2MIXER_OPUS OFF CACHE BOOL "" FORCE)
set(SDL2MIXER_VORBIS STB CACHE STRING "" FORCE)
set(SDL2MIXER_WAVE ON CACHE BOOL "" FORCE)
set(SDL2MIXER_WAVPACK OFF CACHE BOOL "" FORCE)
add_subdirectory(${DEPS_DIR}/SDL_mixer ${CMAKE_BINARY_DIR}/SDL_mixer EXCLUDE_FROM_ALL)

# ---------------------------------------------------------------------------
# FreeType (only used for non-Latin languages, but CorsixTH always links it)

set(FT_DISABLE_ZLIB ON CACHE BOOL "" FORCE)
set(FT_DISABLE_BZIP2 ON CACHE BOOL "" FORCE)
set(FT_DISABLE_PNG ON CACHE BOOL "" FORCE)
set(FT_DISABLE_HARFBUZZ ON CACHE BOOL "" FORCE)
set(FT_DISABLE_BROTLI ON CACHE BOOL "" FORCE)
set(SKIP_INSTALL_ALL ON CACHE BOOL "" FORCE)
add_subdirectory(${DEPS_DIR}/freetype ${CMAKE_BINARY_DIR}/freetype EXCLUDE_FROM_ALL)

# ---------------------------------------------------------------------------
# Lua 5.4, plus the LPeg and LuaFileSystem modules linked in statically
# (iOS apps cannot load Lua C modules at runtime).

file(GLOB LUA_SOURCES ${DEPS_DIR}/lua/*.c)
list(FILTER LUA_SOURCES EXCLUDE REGEX "/(lua|luac|onelua|ltests)\\.c$")
add_library(cth_lua STATIC ${LUA_SOURCES})
target_include_directories(cth_lua PUBLIC ${DEPS_DIR}/lua)
if(CTH_IOS)
  target_compile_definitions(cth_lua PUBLIC LUA_USE_IOS)
elseif(APPLE)
  target_compile_definitions(cth_lua PUBLIC LUA_USE_MACOSX)
else()
  target_compile_definitions(cth_lua PUBLIC LUA_USE_LINUX)
  target_link_libraries(cth_lua PUBLIC m ${CMAKE_DL_LIBS})
endif()

add_library(cth_lpeg STATIC
  ${DEPS_DIR}/lpeg/lpcap.c ${DEPS_DIR}/lpeg/lpcode.c ${DEPS_DIR}/lpeg/lpcset.c
  ${DEPS_DIR}/lpeg/lpprint.c ${DEPS_DIR}/lpeg/lptree.c ${DEPS_DIR}/lpeg/lpvm.c)
target_link_libraries(cth_lpeg PUBLIC cth_lua)

add_library(cth_lfs STATIC ${DEPS_DIR}/lfs/src/lfs.c)
target_link_libraries(cth_lfs PUBLIC cth_lua)

# ---------------------------------------------------------------------------
# libpng (screenshots); zlib comes from the system / iOS SDK.

set(PNG_DIR ${DEPS_DIR}/libpng)
configure_file(${PNG_DIR}/scripts/pnglibconf.h.prebuilt
  ${CMAKE_BINARY_DIR}/png/pnglibconf.h COPYONLY)
add_library(cth_png STATIC
  ${PNG_DIR}/png.c ${PNG_DIR}/pngerror.c ${PNG_DIR}/pngget.c ${PNG_DIR}/pngmem.c
  ${PNG_DIR}/pngpread.c ${PNG_DIR}/pngread.c ${PNG_DIR}/pngrio.c
  ${PNG_DIR}/pngrtran.c ${PNG_DIR}/pngrutil.c ${PNG_DIR}/pngset.c
  ${PNG_DIR}/pngtrans.c ${PNG_DIR}/pngwio.c ${PNG_DIR}/pngwrite.c
  ${PNG_DIR}/pngwtran.c ${PNG_DIR}/pngwutil.c)
target_include_directories(cth_png PUBLIC ${PNG_DIR} ${CMAKE_BINARY_DIR}/png)
target_compile_definitions(cth_png PRIVATE
  PNG_ARM_NEON_OPT=0 PNG_INTEL_SSE_OPT=0 PNG_MIPS_MSA_OPT=0 PNG_MIPS_MMI_OPT=0
  PNG_POWERPC_VSX_OPT=0 PNG_LOONGARCH_LSX_OPT=0 PNG_RISCV_RVV_OPT=0)
target_link_libraries(cth_png PUBLIC z)

# ---------------------------------------------------------------------------
# CorsixTH

set(CORSIX_TH_SEARCH_LOCAL_DATADIRS ON)
set(CORSIX_TH_INTERPRETER_NAME CorsixTH.lua)
set(CORSIX_TH_INTERPRETER_PATH CorsixTH.lua)
set(CORSIX_TH_LINK_LUA_MODULES ON)
set(CORSIX_TH_USE_FFMPEG OFF)
set(WITH_UPDATE_CHECK OFF)
set(WITH_MIDI_DEVICE OFF)
set(WITH_TRACY OFF)
if(CTH_IOS)
  set(CORSIX_TH_OS ios)
elseif(APPLE)
  set(CORSIX_TH_OS macos)
else()
  set(CORSIX_TH_OS unix)
endif()
set(CORSIX_TH_ARCH arm64)
if(NOT CTH_IOS AND CMAKE_SYSTEM_PROCESSOR)
  set(CORSIX_TH_ARCH ${CMAKE_SYSTEM_PROCESSOR})
endif()
configure_file(${CTH_DIR}/Src/config.h.in ${CMAKE_BINARY_DIR}/cth/config.h)

set(CTH_SOURCES
  random.c bootstrap.cpp iso_fs.cpp lua_rnc.cpp midi_player.cpp persist_lua.cpp
  run_length_encoder.cpp sdl_audio.cpp sdl_core.cpp sdl_wm.cpp th.cpp
  th_gfx.cpp th_gfx_font.cpp th_gfx_sdl.cpp th_lua.cpp th_lua_anims.cpp
  th_lua_gfx.cpp th_lua_iso.cpp th_lua_lfs_ext.cpp th_lua_map.cpp
  th_lua_midi.cpp th_lua_movie.cpp th_lua_sound.cpp th_lua_strings.cpp
  th_lua_ui.cpp th_map.cpp th_map_overlays.cpp th_movie.cpp th_pathfind.cpp
  th_sound.cpp th_strings.cpp xmi2mid.cpp main.cpp)
list(TRANSFORM CTH_SOURCES PREPEND ${CTH_DIR}/Src/)
list(APPEND CTH_SOURCES
  ${PORT_DIR}/touch_automation.cpp ${PORT_DIR}/touch_gestures.cpp
  ${PORT_DIR}/touch_storage.cpp ${PORT_DIR}/touch_ui.cpp)
list(APPEND CTH_SOURCES
  ${CTH_ROOT}/libs/rnc/rnc.cpp
  ${CTH_ROOT}/libs/whereami/whereami.c)
if(CTH_IOS)
  # iCloud Drive access, written in Objective-C++.
  list(APPEND CTH_SOURCES ${PORT_DIR}/ios_platform.mm)
  set_source_files_properties(${PORT_DIR}/ios_platform.mm PROPERTIES
    COMPILE_OPTIONS "-fobjc-arc")
endif()

# The game itself is a static library and the executable only holds the entry
# point, as upstream does (both have a file called main.cpp).
add_library(cth_core STATIC ${CTH_SOURCES})
target_include_directories(cth_core PUBLIC
  ${CMAKE_BINARY_DIR}/cth ${PORT_DIR} ${CTH_DIR}/Src ${CTH_ROOT}/libs
  ${CTH_ROOT}/libs/rnc ${CTH_ROOT}/libs/whereami)
target_link_libraries(cth_core PUBLIC
  SDL2::SDL2-static SDL2_mixer::SDL2_mixer-static freetype
  cth_lpeg cth_lfs cth_lua cth_png z)

if(CTH_IOS)
  add_executable(CorsixTH MACOSX_BUNDLE ${CTH_DIR}/SrcUnshared/main.cpp)
else()
  add_executable(CorsixTH ${CTH_DIR}/SrcUnshared/main.cpp)
endif()
target_link_libraries(CorsixTH PRIVATE SDL2::SDL2main cth_core)

# Everything CorsixTH reads at runtime goes next to the executable (desktop)
# or into the root of the app bundle (iOS), where CorsixTH looks for it.
if(CTH_IOS)
  set(CTH_RUNTIME_DIR "$<TARGET_BUNDLE_CONTENT_DIR:CorsixTH>")
else()
  set(CTH_RUNTIME_DIR "$<TARGET_FILE_DIR:CorsixTH>")
endif()
set(copy_runtime_files
  COMMAND ${CMAKE_COMMAND} -E copy ${CTH_DIR}/CorsixTH.lua ${CTH_RUNTIME_DIR}/CorsixTH.lua
  COMMAND ${CMAKE_COMMAND} -E copy_directory ${CTH_DIR}/Lua ${CTH_RUNTIME_DIR}/Lua
  COMMAND ${CMAKE_COMMAND} -E copy_directory ${CTH_DIR}/Bitmap ${CTH_RUNTIME_DIR}/Bitmap
  COMMAND ${CMAKE_COMMAND} -E copy_directory ${CTH_DIR}/Levels ${CTH_RUNTIME_DIR}/Levels
  COMMAND ${CMAKE_COMMAND} -E copy_directory ${CTH_DIR}/Campaigns ${CTH_RUNTIME_DIR}/Campaigns)
if(EXISTS ${GAME_DATA_DIR}/DATA OR EXISTS ${GAME_DATA_DIR}/Data)
  list(APPEND copy_runtime_files
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${GAME_DATA_DIR} ${CTH_RUNTIME_DIR}/ThemeHospital)
  message(STATUS "Bundling Theme Hospital data from ${GAME_DATA_DIR}")
else()
  message(WARNING "No Theme Hospital data in ${GAME_DATA_DIR}; the app will "
    "look for it in its Documents folder instead.")
endif()
if(EXISTS ${MUSIC_DIR})
  list(APPEND copy_runtime_files
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${MUSIC_DIR} ${CTH_RUNTIME_DIR}/Music)
  message(STATUS "Bundling music from ${MUSIC_DIR}")
endif()
add_custom_command(TARGET CorsixTH POST_BUILD ${copy_runtime_files}
  COMMENT "Copying CorsixTH scripts and Theme Hospital data")

if(CTH_IOS)
  set(IOS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/ios)
  # The asset catalog (app icon) is compiled by Xcode as a bundle resource.
  target_sources(CorsixTH PRIVATE ${IOS_DIR}/Assets.xcassets)
  set_target_properties(CorsixTH PROPERTIES
    OUTPUT_NAME CorsixTH
    XCODE_GENERATE_SCHEME ON
    MACOSX_BUNDLE_INFO_PLIST ${IOS_DIR}/Info.plist.in
    MACOSX_BUNDLE_GUI_IDENTIFIER ${CTH_BUNDLE_ID}
    MACOSX_BUNDLE_BUNDLE_NAME "Theme Hospital"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.70.1"
    MACOSX_BUNDLE_BUNDLE_VERSION "2"
    RESOURCE ${IOS_DIR}/Assets.xcassets
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER ${CTH_BUNDLE_ID}
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET ${CMAKE_OSX_DEPLOYMENT_TARGET}
    XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME AppIcon
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic
    XCODE_ATTRIBUTE_ENABLE_BITCODE NO
    XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT "dwarf"
    XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL[variant=Debug] "s"
    XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL[variant=Release] "s")
  if(CTH_DEVELOPMENT_TEAM)
    set_target_properties(CorsixTH PROPERTIES
      XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ${CTH_DEVELOPMENT_TEAM})
  endif()
  if(CTH_ICLOUD)
    # Xcode's automatic signing enables iCloud for the app ID from this.
    configure_file(${IOS_DIR}/CorsixTH.entitlements.in
      ${CMAKE_BINARY_DIR}/CorsixTH.entitlements @ONLY)
    set_target_properties(CorsixTH PROPERTIES
      XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS ${CMAKE_BINARY_DIR}/CorsixTH.entitlements)
    message(STATUS "Save games will go to iCloud Drive (iCloud.${CTH_BUNDLE_ID})")
  endif()
  # Frameworks SDL needs on iOS (listed explicitly; duplicates are harmless).
  foreach(framework AVFoundation AudioToolbox CoreAudio CoreFoundation
      CoreGraphics CoreHaptics CoreMotion Foundation GameController Metal
      QuartzCore UIKit OpenGLES CoreBluetooth)
    target_link_libraries(CorsixTH PRIVATE "-framework ${framework}")
  endforeach()
  target_link_libraries(CorsixTH PRIVATE iconv)
endif()

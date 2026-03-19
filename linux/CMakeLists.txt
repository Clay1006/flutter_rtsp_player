cmake_minimum_required(VERSION 3.13)

set(PROJECT_NAME "flutter_rtsp_player")
project(${PROJECT_NAME} LANGUAGES CXX C)

# This native plugin is a thin helper that exposes the X11 XID of the Flutter
# top-level window to the Dart side via a method channel.  All libVLC control
# is driven from Dart using the Dart FFI (package:ffi) and libvlc.so.5 loaded
# at runtime.  No link-time dependency on libVLC is required here.

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED gtk+-3.0)
pkg_check_modules(GDK REQUIRED gdk-3.0)

set(PLUGIN_NAME "flutter_rtsp_player_plugin")

add_library(${PLUGIN_NAME} SHARED
  "flutter_rtsp_player_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_include_directories(${PLUGIN_NAME} PRIVATE
  ${GTK_INCLUDE_DIRS}
  ${GDK_INCLUDE_DIRS}
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  ${GTK_LIBRARIES}
  ${GDK_LIBRARIES}
)

# Runtime requirement: libvlc.so.5 and libvlccore.so.5 must be installed on
# the target system (e.g. via apt install vlc).  Dart FFI locates the library
# via DynamicLibrary.open('libvlc.so.5') at runtime.
set(flutter_rtsp_player_bundled_libraries
  ""
  PARENT_SCOPE
)

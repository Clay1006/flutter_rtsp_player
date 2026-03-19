cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "flutter_rtsp_player")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "flutter_rtsp_player_plugin")

# This native plugin is a thin helper that exposes the native window handle
# (HWND) to the Dart side via a method channel.  All libVLC control is driven
# from Dart using the Dart FFI (package:ffi) and libvlc.dll loaded at runtime.
# No link-time dependency on libVLC is required here.

list(APPEND PLUGIN_SOURCES
  "flutter_rtsp_player_plugin.cpp"
  "flutter_rtsp_player_plugin_c_api.cpp"
)

add_library(${PLUGIN_NAME} SHARED ${PLUGIN_SOURCES})

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
)

# Runtime requirement: the consuming app must ship libvlc.dll + libvlccore.dll
# (and the VLC plugins/ folder) alongside its executable.  Dart FFI locates
# libvlc.dll via DynamicLibrary.open('libvlc.dll') at runtime.
# See README for setup instructions.
set(flutter_rtsp_player_bundled_libraries
  ""
  PARENT_SCOPE
)

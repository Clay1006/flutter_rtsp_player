#ifndef FLUTTER_PLUGIN_FLUTTER_RTSP_PLAYER_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_RTSP_PLAYER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <memory>

namespace flutter_rtsp_player {

/// Thin native helper plugin for Windows.
///
/// Responsibility:
///   - Respond to "getWindowHandle" on the desktop_helper method channel,
///     returning the HWND of the Flutter view as a 64-bit integer.
///
/// All libVLC lifecycle management (init, play, pause, stop, options) is
/// handled from Dart via FFI (package:ffi + libvlc.dll), not from native code.
class FlutterRtspPlayerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit FlutterRtspPlayerPlugin(flutter::PluginRegistrarWindows* registrar);
  ~FlutterRtspPlayerPlugin() override;

  FlutterRtspPlayerPlugin(const FlutterRtspPlayerPlugin&) = delete;
  FlutterRtspPlayerPlugin& operator=(const FlutterRtspPlayerPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> helper_channel_;
};

}  // namespace flutter_rtsp_player

#endif  // FLUTTER_PLUGIN_FLUTTER_RTSP_PLAYER_PLUGIN_H_

#include "flutter_rtsp_player_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>
#include <windows.h>

namespace flutter_rtsp_player {

using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

// ── Registration ──────────────────────────────────────────────────────────────

void FlutterRtspPlayerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<FlutterRtspPlayerPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

// ── Constructor ───────────────────────────────────────────────────────────────

FlutterRtspPlayerPlugin::FlutterRtspPlayerPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {

  // Desktop helper channel: only provides the native window handle to Dart.
  // Dart FFI handles all libVLC operations directly.
  helper_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(),
      "flutter_rtsp_player/desktop_helper",
      &flutter::StandardMethodCodec::GetInstance());

  helper_channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });
}

FlutterRtspPlayerPlugin::~FlutterRtspPlayerPlugin() = default;

// ── Method call handler ───────────────────────────────────────────────────────

void FlutterRtspPlayerPlugin::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {

  if (call.method_name() == "getWindowHandle") {
    HWND hwnd = registrar_->GetView()->GetNativeWindow();
    if (hwnd == nullptr) {
      result->Error("NO_WINDOW", "Could not obtain native window handle.");
      return;
    }
    // Return the HWND as a 64-bit integer. Dart FFI passes this to
    // libvlc_media_player_set_hwnd() so VLC renders into the Flutter window.
    const int64_t handle = reinterpret_cast<int64_t>(hwnd);
    result->Success(EncodableValue(handle));
  } else {
    result->NotImplemented();
  }
}

}  // namespace flutter_rtsp_player

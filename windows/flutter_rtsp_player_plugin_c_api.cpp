#include "flutter_rtsp_player_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_rtsp_player_plugin.h"

void FlutterRtspPlayerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_rtsp_player::FlutterRtspPlayerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

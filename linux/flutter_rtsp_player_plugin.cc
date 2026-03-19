#include "flutter_rtsp_player_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <gdk/gdkx.h>

#include <cstring>

#define FLUTTER_RTSP_PLAYER_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_rtsp_player_plugin_get_type(), \
                               FlutterRtspPlayerPlugin))

/// Thin native helper plugin for Linux.
///
/// Responsibility:
///   - Respond to "getWindowHandle" on the desktop_helper method channel,
///     returning the X11 XID of the top-level GDK window as a 64-bit integer.
///
/// All libVLC lifecycle management (init, play, pause, stop, options) is
/// handled from Dart via FFI (package:ffi + libvlc.so), not from native code.

struct _FlutterRtspPlayerPlugin {
  GObject parent_instance;
  FlPluginRegistrar* registrar;
  FlMethodChannel* helper_channel;
};

G_DEFINE_TYPE(FlutterRtspPlayerPlugin, flutter_rtsp_player_plugin, G_TYPE_OBJECT)

// ── Forward declarations ───────────────────────────────────────────────────────

static void helper_method_call_cb(FlMethodChannel* channel,
                                   FlMethodCall* method_call,
                                   gpointer user_data);

// ── Plugin lifecycle ──────────────────────────────────────────────────────────

static void flutter_rtsp_player_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(flutter_rtsp_player_plugin_parent_class)->dispose(object);
}

static void flutter_rtsp_player_plugin_class_init(
    FlutterRtspPlayerPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = flutter_rtsp_player_plugin_dispose;
}

static void flutter_rtsp_player_plugin_init(FlutterRtspPlayerPlugin* self) {}

// ── Registration ──────────────────────────────────────────────────────────────

void flutter_rtsp_player_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  FlutterRtspPlayerPlugin* plugin = FLUTTER_RTSP_PLAYER_PLUGIN(
      g_object_new(flutter_rtsp_player_plugin_get_type(), nullptr));
  plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->helper_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "flutter_rtsp_player/desktop_helper",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->helper_channel, helper_method_call_cb,
      g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}

// ── "getWindowHandle" handler ─────────────────────────────────────────────────

static void helper_method_call_cb(FlMethodChannel* channel,
                                   FlMethodCall* method_call,
                                   gpointer user_data) {
  FlutterRtspPlayerPlugin* self = FLUTTER_RTSP_PLAYER_PLUGIN(user_data);

  if (strcmp(fl_method_call_get_name(method_call), "getWindowHandle") == 0) {
    // Obtain the X11 Window (XID) of the top-level GDK window.
    GtkWidget* view_widget = GTK_WIDGET(
        fl_plugin_registrar_get_view(self->registrar));

    if (!view_widget) {
      fl_method_call_respond_error(method_call, "NO_VIEW",
                                    "Flutter view widget is not available.",
                                    nullptr, nullptr);
      return;
    }

    GtkWidget* top = gtk_widget_get_toplevel(view_widget);
    if (!GTK_IS_WINDOW(top)) {
      fl_method_call_respond_error(method_call, "NO_WINDOW",
                                    "Could not obtain top-level GTK window.",
                                    nullptr, nullptr);
      return;
    }

    GdkWindow* gdk_win = gtk_widget_get_window(top);
    if (!gdk_win) {
      fl_method_call_respond_error(method_call, "NO_GDK_WINDOW",
                                    "GDK window is not yet realized.",
                                    nullptr, nullptr);
      return;
    }

    // Return the X11 XID as a 64-bit integer.
    // Dart FFI passes this to libvlc_media_player_set_xwindow().
    const guint32 xid = static_cast<guint32>(GDK_WINDOW_XID(gdk_win));
    g_autoptr(FlValue) result = fl_value_new_int(static_cast<int64_t>(xid));
    fl_method_call_respond_success(method_call, result, nullptr);
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

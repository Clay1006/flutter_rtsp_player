## 0.1.0

* Initial release.
* Android: ExoPlayer (`media3-exoplayer-rtsp`) backend.
* iOS: MobileVLCKit backend.
* macOS: VLCKit backend.
* Windows: libVLC via C++ plugin.
* Linux: libVLC via C++ plugin (GLib/GTK).
* Full `RtspPlayerOptions` API with transport, buffer, latency, codec, and `extraFFmpegOptions` pass-through.
* `RtspPlayerWidget` with built-in loading/error overlays and optional controls.
* Demo app with live options panel and extra FFmpeg key=value editor.

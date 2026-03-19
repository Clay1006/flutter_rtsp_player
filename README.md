# flutter_rtsp_player

[![pub.dev](https://img.shields.io/badge/pub.dev-flutter__rtsp__player-blue)](https://pub.dev/packages/flutter_rtsp_player)
[![GitHub](https://img.shields.io/badge/GitHub-Clay1006%2Fflutter__rtsp__player-black?logo=github)](https://github.com/Clay1006/flutter_rtsp_player)

A Flutter plugin for playing live **RTSP** streams (IP cameras, media servers, etc.) with full FFmpeg/VLC tuning support.

**Clone or use as a Git dependency:**

```bash
git clone https://github.com/Clay1006/flutter_rtsp_player.git
```

```yaml
# pubspec.yaml — use directly from GitHub
dependencies:
  flutter_rtsp_player:
    git:
      url: https://github.com/Clay1006/flutter_rtsp_player.git
      ref: main
```

| Platform | Backend | Notes |
|----------|---------|-------|
| Android  | ExoPlayer (`media3-exoplayer-rtsp`) | Hardware-accelerated via MediaCodec |
| iOS      | MobileVLCKit 3.x | CocoaPods, min iOS 12 |
| macOS    | VLCKit 3.x | CocoaPods, min macOS 10.14 |
| Windows  | libVLC SDK | Requires VLC SDK DLLs |
| Linux    | libvlc (`libvlc-dev`) | GTK window rendering |

---

## Platform behavior differences

| | Android | iOS | macOS | Windows / Linux |
|---|---------|-----|-------|-----------------|
| Engine | ExoPlayer (media3-rtsp) | MobileVLCKit | VLCKit | libVLC (Dart FFI) |
| Rendering | Flutter `Texture` | `UiKitView` | `AppKitView` | Native HWND / X11 Window |
| `extraFFmpegOptions` | **Partial** — known keys mapped; others logged, not applied | Full VLC pass-through | Full VLC pass-through | Full VLC pass-through |
| `setOptions()` | Re-initialises ExoPlayer with new options; same texture ID | VLC `addOption` live | VLC `addOption` live | `libvlc_media_player_set_media` swap |

### Desktop rendering constraints (Windows / Linux)

On Windows and Linux, libVLC renders video **directly into the OS window surface**
(the top-level `HWND` / X11 `Window` handle).  This is a fundamental constraint
of the libVLC windowed rendering API — there is no per-widget GPU texture path
comparable to Android's `SurfaceTexture` or iOS/macOS `AVSampleBufferDisplayLayer`.

What this means in practice:

- `RtspPlayerWidget` **reserves the screen region** via a transparent `SizedBox.expand()`.
  The libVLC video compositor fills that same region at the OS level.
- Flutter overlay widgets (loading spinner, control bar) **sit on top of the video** and
  work correctly.
- The video surface **cannot be clipped, rotated, or transformed** by Flutter's
  compositor — it is painted by the OS independently of the Flutter layer tree.
- Layout changes (widget resize, scroll, route transitions) will **not** clip the video
  surface; the video fills the entire `SizedBox` region regardless.
- If your UI requires per-widget clipping or composited transforms on the video,
  prefer Android, iOS, or macOS where the plugin uses proper Flutter texture/platform-view integration.

### Android `extraFFmpegOptions` — partial mapping

ExoPlayer does not expose generic FFmpeg option pass-through for RTSP.  Only the
following keys from `extraFFmpegOptions` are applied on Android:

| Key | Mapping |
|-----|---------|
| `stimeout` / `timeout` | `RtspMediaSource.setTimeoutMs` (µs → ms) |
| `buffer_size` | Minimum buffer floor heuristic |
| `max_delay` | Overrides `maxLatency` (µs → ms) |
| `rtsp_flags: prefer_tcp` | `RtspMediaSource.setForceUseRtpTcp(true)` |

All other keys are **logged at DEBUG level** (`adb logcat -s RtspPlayerPlugin`)
and **not applied**.  They do not cause crashes.

---

## Features

- Drop-in `RtspPlayerWidget` — just pass a URL
- Full `RtspPlayerController` for lifecycle management
- `RtspPlayerOptions` with typed tuning fields (transport, buffer, latency, codec, HW accel)
- `extraFFmpegOptions` — full VLC pass-through on iOS/macOS/Windows/Linux; mapped subset on Android
- State stream (`idle → connecting → playing / paused / error`)
- Optional built-in play/pause/stop controls overlay
- `setOptions()` to apply options without full reconnection (implementation varies by platform)

---

## Quick start

```dart
import 'package:flutter_rtsp_player/flutter_rtsp_player.dart';

// Fire-and-forget (widget manages its own controller):
RtspPlayerWidget.url(
  'rtsp://admin:password@192.168.1.10:554/stream',
  options: RtspPlayerOptions(
    transport: RtspTransport.tcp,
    bufferDuration: Duration(milliseconds: 200),
    networkCaching: 150,
  ),
)
```

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_rtsp_player: ^0.1.0
```

Then follow the platform-specific setup below.

---

## Platform setup

### Android

Add the `INTERNET` permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

The plugin pulls in ExoPlayer automatically. No extra configuration needed.

Minimum SDK: **21** (Android 5.0 Lollipop).

---

### iOS

1. Add `MobileVLCKit` to your `ios/Podfile`:

```ruby
platform :ios, '12.0'

target 'Runner' do
  use_frameworks!
  pod 'MobileVLCKit', '~> 3.6'
end
```

2. Add camera/network usage descriptions to `Info.plist` if needed.

3. Run `pod install` in the `ios/` directory.

---

### macOS

1. Add `VLCKit` to your `macos/Podfile`:

```ruby
platform :osx, '10.14'

target 'Runner' do
  use_frameworks!
  pod 'VLCKit', '~> 3.6'
end
```

2. Run `pod install` in the `macos/` directory.

3. Enable network access in `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

---

### Windows

1. Download the **VLC SDK** for Windows from [VideoLAN](https://download.videolan.org/pub/videolan/vlc/).

2. Copy or symlink the SDK's `include/` and `lib/` directories so the Dart FFI loader can find `libvlc.dll` at runtime.

3. Distribute `libvlc.dll`, `libvlccore.dll`, and the `plugins/` folder alongside your built `.exe`.

> **Note:** The plugin loads `libvlc.dll` at runtime via `DynamicLibrary.open`. The DLL must be on the system `PATH` or in the same directory as the application executable. No special CMake build-time variable is required — VLC SDK setup is done manually before running the app.

---

### Linux

Install libVLC development headers:

```bash
sudo apt-get install libvlc-dev
```

No additional configuration is required; `CMakeLists.txt` uses `pkg-config` to locate the library.

---

## Usage

### Simple — widget manages the controller

```dart
RtspPlayerWidget.url(
  'rtsp://192.168.1.10:554/live',
  options: RtspPlayerOptions(
    transport: RtspTransport.tcp,
    bufferDuration: Duration(milliseconds: 300),
    extraFFmpegOptions: {
      'stimeout': '5000000', // socket timeout: 5 s
      'rtsp_flags': 'prefer_tcp',
    },
  ),
  showControls: true,
)
```

### Advanced — controller lifecycle

```dart
class _MyState extends State<MyWidget> {
  late final RtspPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RtspPlayerController();
    _controller.stateStream.listen((state) {
      debugPrint('Player state: $state');
    });
    _controller.initialize(
      url: 'rtsp://192.168.1.10:554/live',
      options: const RtspPlayerOptions(
        transport: RtspTransport.tcp,
        bufferDuration: Duration(milliseconds: 200),
        networkCaching: 150,
        hwAcceleration: true,
        extraFFmpegOptions: {
          'stimeout': '5000000',
          'reorder_queue_size': '0',
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RtspPlayerWidget(controller: _controller);
  }
}
```

### Applying options while streaming

Some options can be applied to a running stream without reconnecting:

```dart
await _controller.setOptions(RtspPlayerOptions(
  networkCaching: 100,
  extraFFmpegOptions: {'clock-jitter': '0'},
));
```

> Note: Transport and codec changes require a full `stop()` → `initialize()` cycle.

---

## RtspPlayerOptions reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `transport` | `RtspTransport` | `.tcp` | RTSP transport protocol. TCP is reliable; UDP has lower overhead. |
| `bufferDuration` | `Duration` | `500 ms` | Target buffer fill before playback starts. Larger → less stutter, more latency. |
| `maxLatency` | `Duration` | `1000 ms` | Maximum tolerated end-to-end latency. ExoPlayer uses this for its live config. |
| `videoCodec` | `RtspVideoCodec` | `.auto` | Preferred decoder hint (`auto`, `h264`, `h265`, `mjpeg`). |
| `networkCaching` | `int` (ms) | `300` | Forwarded as VLC `:network-caching`. Controls buffering at the demuxer level. |
| `hwAcceleration` | `bool` | `true` | Use hardware decoders (MediaCodec / VideoToolbox / DXVA2). |
| `extraFFmpegOptions` | `Map<String,String>` | `{}` | Raw key-value pairs forwarded to FFmpeg/VLC. See tables below. |

### Common `extraFFmpegOptions` keys

#### FFmpeg (Android / ExoPlayer via underlying format)

| Key | Description | Example |
|-----|-------------|---------|
| `stimeout` | Socket read timeout in microseconds | `5000000` (5 s) |
| `rtsp_flags` | RTSP flags | `prefer_tcp`, `listen` |
| `buffer_size` | UDP receive buffer in bytes | `65535` |
| `reorder_queue_size` | Packet reorder buffer size (0 = disable) | `0` |
| `max_delay` | Maximum demux-decode delay in microseconds | `500000` |
| `fflags` | Format flags | `nobuffer+flush_packets` |
| `timeout` | I/O timeout in microseconds | `3000000` |

#### VLC (iOS, macOS, Windows, Linux)

| Key | Description | Example |
|-----|-------------|---------|
| `network-caching` | Network caching (ms) — same as `networkCaching` field | `150` |
| `clock-jitter` | Clock jitter tolerance (ms); 0 = low-latency | `0` |
| `clock-synchro` | A/V clock sync behaviour | `0` |
| `avcodec-hw` | Hardware acceleration module | `any`, `none`, `vdpau` |
| `sout-mux-caching` | Muxer caching (ms) | `500` |
| `live-caching` | Live stream caching (ms) | `100` |
| `file-caching` | File caching (ms) | `300` |

---

## RtspPlayerController API

| Method | Description |
|--------|-------------|
| `initialize({url, options})` | Connect and start streaming. Returns when the texture is ready. |
| `play()` | Resume playback after pause. |
| `pause()` | Pause without releasing the connection. |
| `stop()` | Stop and release the stream connection. |
| `setOptions(options)` | Apply live-tunable options without reconnecting. |
| `dispose()` | Release all resources. |
| `state` | Current `RtspPlayerState`. |
| `stateStream` | Broadcast stream of state changes. |
| `error` | Last error string when `state == RtspPlayerState.error`. |
| `textureId` | Flutter texture identifier (non-null after `initialize`). |

---

## Known limitations

- **Windows / Linux**: Video renders into the host Flutter window; overlapping Flutter widgets above the video surface may not work correctly with all GPU compositors. This is a known limitation of the libVLC windowed rendering approach on desktop.
- **iOS**: MobileVLCKit adds approximately 35 MB to the IPA. If bundle size is a concern, consider a smaller backend.
- **Transport changes**: Switching between TCP and UDP requires a full `stop()` → `initialize()` cycle.
- **Credentials**: Only URL-embedded credentials are supported (`rtsp://user:pass@host/path`). Separate auth flows are out of scope.
- **HLS / DASH**: This plugin is RTSP-only. Use `video_player` or `media_kit` for HLS/DASH.

---

## Example app

The `example/` directory contains a full demo app with:

- RTSP URL input
- Transport, buffer, latency, network-caching, codec, and HW-accel controls
- A live-apply button to push option changes to a running stream
- An "Extra FFmpeg Options" editor for arbitrary key-value pass-through
- State display (`_StateChip`: LIVE / CONNECTING / PAUSED / ERROR / IDLE) in the AppBar
- Status bar with coloured dot and descriptive text below the video
- **Full-screen mode**: tap the `⤢` button while playing to enter a full-screen landscape route; tap the video or the back button to return

Run the example:

```bash
cd example
flutter run
```

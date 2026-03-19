import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'rtsp_player_controller.dart';
import 'rtsp_player_options.dart';
import 'rtsp_player_state.dart';

const _kViewType = 'flutter_rtsp_player/video_view';

/// A widget that displays an RTSP video stream.
///
/// Provide either an [RtspPlayerController] (for full lifecycle control) or
/// a plain [url] string for a self-managed, fire-and-forget player.
///
/// ### Using a controller (recommended)
/// ```dart
/// RtspPlayerWidget(controller: myController)
/// ```
///
/// ### Auto-managed (simple)
/// ```dart
/// RtspPlayerWidget.url(
///   'rtsp://192.168.1.10:554/stream',
///   options: RtspPlayerOptions(transport: RtspTransport.tcp),
/// )
/// ```
///
/// ## Desktop rendering note
/// On Windows and Linux, libVLC renders video directly into the native host
/// window using the `HWND` / `XID` returned by the thin native helper plugin.
/// The [RtspPlayerWidget] reserves the required screen area; the video surface
/// sits at the OS level behind Flutter's overlay widgets.  You can still place
/// Flutter widgets (loading indicator, controls) on top.
class RtspPlayerWidget extends StatefulWidget {
  final RtspPlayerController? controller;
  final String? url;
  final RtspPlayerOptions options;
  final Widget? loadingBuilder;
  final Widget Function(BuildContext context, String? error)? errorBuilder;
  final Color backgroundColor;
  final bool showControls;

  const RtspPlayerWidget({
    super.key,
    required RtspPlayerController this.controller,
    this.loadingBuilder,
    this.errorBuilder,
    this.backgroundColor = Colors.black,
    this.showControls = false,
  })  : url = null,
        options = const RtspPlayerOptions();

  /// Creates a self-contained player that manages its own controller.
  const RtspPlayerWidget.url(
    String this.url, {
    super.key,
    this.options = const RtspPlayerOptions(),
    this.loadingBuilder,
    this.errorBuilder,
    this.backgroundColor = Colors.black,
    this.showControls = true,
  }) : controller = null;

  @override
  State<RtspPlayerWidget> createState() => _RtspPlayerWidgetState();
}

class _RtspPlayerWidgetState extends State<RtspPlayerWidget> {
  late RtspPlayerController _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = RtspPlayerController();
      _ownsController = true;
      _controller.initialize(url: widget.url!, options: widget.options);
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.backgroundColor,
      child: StreamBuilder<RtspPlayerState>(
        stream: _controller.stateStream,
        initialData: _controller.state,
        builder: (context, snapshot) {
          final state = snapshot.data ?? RtspPlayerState.idle;

          return Stack(
            fit: StackFit.expand,
            children: [
              // ── Video surface ──────────────────────────────────────────────
              if (state == RtspPlayerState.playing ||
                  state == RtspPlayerState.paused)
                _buildVideoSurface(state),

              // ── Loading overlay ────────────────────────────────────────────
              if (state == RtspPlayerState.connecting)
                Center(
                  child: widget.loadingBuilder ??
                      const CircularProgressIndicator(color: Colors.white),
                ),

              // ── Error overlay ──────────────────────────────────────────────
              if (state == RtspPlayerState.error)
                Center(
                  child: widget.errorBuilder != null
                      ? widget.errorBuilder!(context, _controller.error)
                      : _DefaultErrorWidget(error: _controller.error),
                ),

              // ── Controls overlay ───────────────────────────────────────────
              if (widget.showControls &&
                  state != RtspPlayerState.error &&
                  state != RtspPlayerState.disposed &&
                  state != RtspPlayerState.idle)
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: _ControlsBar(controller: _controller, state: state),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVideoSurface(RtspPlayerState state) {
    if (kIsWeb) {
      return const SizedBox.expand();
    }

    // ── Desktop: libVLC renders to the native window ─────────────────────────
    // libVLC attaches to the top-level OS window handle (HWND on Windows,
    // X11 Window ID on Linux) and paints video at the OS compositor level.
    // This means:
    //   • Video composition is NOT widget-scoped. Flutter layout, clipping,
    //     scroll, opacity, or transform effects on this widget do NOT affect
    //     the video surface — the OS always fills the full widget region.
    //   • Flutter children stacked above (e.g. control overlays) DO render
    //     correctly on top of the video.
    //   • This is a fundamental constraint of the libVLC windowed API; there
    //     is no per-widget GPU texture path on Windows/Linux.
    if (Platform.isWindows || Platform.isLinux) {
      return const SizedBox.expand();
    }

    // ── iOS: UiKitView (Hybrid Composition) ──────────────────────────────────
    if (Platform.isIOS) {
      return UiKitView(
        viewType: _kViewType,
        layoutDirection: TextDirection.ltr,
        creationParams: {'textureId': _controller.textureId},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    // ── macOS: AppKitView ─────────────────────────────────────────────────────
    if (Platform.isMacOS) {
      return AppKitView(
        viewType: _kViewType,
        layoutDirection: TextDirection.ltr,
        creationParams: {'textureId': _controller.textureId},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    // ── Android: Texture (registered via FlutterTextureRegistry) ─────────────
    final id = _controller.textureId;
    if (id != null) {
      return Texture(textureId: id);
    }

    return const SizedBox.expand();
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _DefaultErrorWidget extends StatelessWidget {
  final String? error;
  const _DefaultErrorWidget({this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 8),
          Text(
            error ?? 'Playback error',
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ControlsBar extends StatelessWidget {
  final RtspPlayerController controller;
  final RtspPlayerState state;
  const _ControlsBar({required this.controller, required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ControlButton(
          icon: state == RtspPlayerState.playing ? Icons.pause : Icons.play_arrow,
          onPressed: state == RtspPlayerState.playing
              ? controller.pause
              : controller.play,
        ),
        const SizedBox(width: 16),
        _ControlButton(icon: Icons.stop, onPressed: controller.stop),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _ControlButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}

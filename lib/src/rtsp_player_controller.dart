import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ffi/desktop_vlc_player.dart';
import 'rtsp_player_options.dart';
import 'rtsp_player_state.dart';

/// Controls an RTSP video stream.
///
/// On **Android**, **iOS**, and **macOS** the controller communicates with the
/// native plugin over a method/event channel.
///
/// On **Windows** and **Linux** the controller drives libVLC directly via Dart
/// FFI (see [DesktopVlcPlayer]); no method channel is used for playback
/// control.
///
/// Create a controller, pass it to [RtspPlayerWidget], then call [initialize]
/// to start the connection. Dispose the controller when it is no longer needed.
///
/// ### Example
/// ```dart
/// final controller = RtspPlayerController();
///
/// @override
/// void initState() {
///   super.initState();
///   controller.initialize(
///     url: 'rtsp://admin:password@192.168.1.10:554/stream',
///     options: RtspPlayerOptions(
///       transport: RtspTransport.tcp,
///       bufferDuration: Duration(milliseconds: 200),
///       extraFFmpegOptions: {'stimeout': '5000000'},
///     ),
///   );
/// }
///
/// @override
/// void dispose() {
///   controller.dispose();
///   super.dispose();
/// }
/// ```
class RtspPlayerController {
  static const _methodChannel = MethodChannel('flutter_rtsp_player/methods');
  static const _eventChannel = EventChannel('flutter_rtsp_player/events');

  final _stateController = StreamController<RtspPlayerState>.broadcast();
  StreamSubscription<dynamic>? _eventSubscription;

  /// Non-null after a successful [initialize] on mobile/macOS.
  /// On desktop (Windows/Linux) the texture is not used; VLC renders
  /// directly into the native window surface.
  int? _textureId;
  DesktopVlcPlayer? _desktopPlayer;
  StreamSubscription<RtspPlayerState>? _desktopStateSub;

  RtspPlayerState _state = RtspPlayerState.idle;
  String? _error;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// The current playback state.
  RtspPlayerState get state => _state;

  /// The last error message when [state] is [RtspPlayerState.error].
  String? get error => _error;

  /// Flutter texture ID used on Android/iOS/macOS.
  ///
  /// Non-null after [initialize] completes on those platforms.
  /// Always `null` on Windows/Linux (rendering is window-based via libVLC).
  int? get textureId => _textureId;

  /// Whether this controller is using the desktop FFI path.
  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// Broadcast stream of state changes.
  Stream<RtspPlayerState> get stateStream => _stateController.stream;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Initialises the player and begins connecting to [url].
  Future<void> initialize({
    required String url,
    RtspPlayerOptions options = const RtspPlayerOptions(),
  }) async {
    _assertNotDisposed();

    if (isDesktop) {
      await _initDesktop(url: url, options: options);
    } else {
      await _initMobile(url: url, options: options);
    }
  }

  /// Starts or resumes playback.
  Future<void> play() async {
    _assertNotDisposed();
    if (isDesktop) {
      _desktopPlayer?.play();
    } else {
      await _methodChannel.invokeMethod<void>('play');
    }
  }

  /// Pauses playback without releasing resources.
  Future<void> pause() async {
    _assertNotDisposed();
    if (isDesktop) {
      _desktopPlayer?.pause();
    } else {
      await _methodChannel.invokeMethod<void>('pause');
    }
  }

  /// Stops playback and releases the stream connection.
  Future<void> stop() async {
    _assertNotDisposed();
    if (isDesktop) {
      _desktopPlayer?.stop();
    } else {
      await _methodChannel.invokeMethod<void>('stop');
    }
  }

  /// Applies new [options] to a running stream where supported.
  ///
  /// Transport and codec changes always require a full stop → initialize cycle.
  Future<void> setOptions(RtspPlayerOptions options) async {
    _assertNotDisposed();
    if (isDesktop) {
      _desktopPlayer?.setOptions(options);
    } else {
      await _methodChannel.invokeMethod<void>('setOptions', {
        'options': options.toMap(),
      });
    }
  }

  /// Releases all resources. Must not be called more than once.
  Future<void> dispose() async {
    if (_state == RtspPlayerState.disposed) return;
    _updateState(RtspPlayerState.disposed);

    // Desktop
    await _desktopStateSub?.cancel();
    _desktopStateSub = null;
    await _desktopPlayer?.dispose();
    _desktopPlayer = null;

    // Mobile / macOS
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (!isDesktop) {
      await _methodChannel.invokeMethod<void>('dispose');
    }

    await _stateController.close();
  }

  // ── Desktop (FFI) init ─────────────────────────────────────────────────────

  Future<void> _initDesktop({
    required String url,
    required RtspPlayerOptions options,
  }) async {
    final player = DesktopVlcPlayer();
    _desktopPlayer = player;

    _desktopStateSub = player.stateStream.listen((s) {
      if (s == RtspPlayerState.error) {
        _error = 'libVLC playback error';
      } else {
        _error = null;
      }
      _updateState(s);
    });

    await player.initialize(url: url, options: options);
    _updateState(RtspPlayerState.connecting);
  }

  // ── Mobile / macOS (method channel) init ──────────────────────────────────

  Future<void> _initMobile({
    required String url,
    required RtspPlayerOptions options,
  }) async {
    final result = await _methodChannel.invokeMethod<int>('initialize', {
      'url': url,
      'options': options.toMap(),
    });
    _textureId = result;
    _listenToEvents();
    _updateState(RtspPlayerState.connecting);
  }

  void _listenToEvents() {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map) return;
        final type = event['type'] as String?;
        if (type == 'stateChanged') {
          final stateName = event['state'] as String?;
          final parsed = _parseState(stateName);
          if (parsed != null) {
            _error = parsed == RtspPlayerState.error
                ? event['error'] as String?
                : null;
            _updateState(parsed);
          }
        }
      },
      onError: (dynamic err) {
        _error = err.toString();
        _updateState(RtspPlayerState.error);
      },
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _updateState(RtspPlayerState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) _stateController.add(newState);
  }

  void _assertNotDisposed() {
    if (_state == RtspPlayerState.disposed) {
      throw StateError('RtspPlayerController has been disposed.');
    }
  }

  static RtspPlayerState? _parseState(String? name) {
    return switch (name) {
      'idle' => RtspPlayerState.idle,
      'connecting' => RtspPlayerState.connecting,
      'playing' => RtspPlayerState.playing,
      'paused' => RtspPlayerState.paused,
      'error' => RtspPlayerState.error,
      _ => null,
    };
  }
}

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import '../rtsp_player_options.dart';
import '../rtsp_player_state.dart';
import 'libvlc_ffi.dart';

/// Desktop (Windows/Linux) libVLC player driven entirely from Dart via FFI.
///
/// Lifecycle:
///  1. Call [initialize] to load libVLC, build a player, and attach it to the
///     native window surface provided by the thin native plugin helper.
///  2. Use [play], [pause], [stop] to control playback.
///  3. Call [setOptions] to apply new options live (rebuilds the media object
///     and calls `libvlc_media_player_set_media` without tearing down VLC).
///  4. Call [dispose] to release all libVLC and FFI resources.
///
/// State changes are broadcast on [stateStream].
///
/// ## extraFFmpegOptions forwarding
/// Every entry in [RtspPlayerOptions.extraFFmpegOptions] is forwarded as a
/// VLC media option string `":key=value"` via `libvlc_media_add_option`.
/// This is a full pass-through — any option accepted by `vlc --option=value`
/// can be used here.
class DesktopVlcPlayer {
  static const _helperChannel =
      MethodChannel('flutter_rtsp_player/desktop_helper');

  final _stateController = StreamController<RtspPlayerState>.broadcast();

  LibVlcBindings? _bindings;
  Pointer<LibvlcInstance>? _vlcInstance;
  Pointer<LibvlcMediaPlayer>? _player;

  String? _currentUrl;

  /// Current playback state.
  RtspPlayerState get state => _state;
  RtspPlayerState _state = RtspPlayerState.idle;

  /// Broadcast stream of state changes.
  Stream<RtspPlayerState> get stateStream => _stateController.stream;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Initialises libVLC and starts the RTSP stream.
  Future<void> initialize({
    required String url,
    required RtspPlayerOptions options,
  }) async {
    _currentUrl = url;

    // 1. Load the shared library once
    final bindings = LibVlcBindings.load();
    _bindings = bindings;

    // 2. Build libVLC instance-level args from options
    final vlcArgs = _buildVlcArgs(options);
    final (argArrayPtr, argPointers) = _allocArgs(vlcArgs);
    try {
      final vlcInstance = bindings.libvlcNew(vlcArgs.length, argArrayPtr);
      if (vlcInstance == nullptr) {
        throw StateError('libvlc_new() failed — is libvlc installed?');
      }
      _vlcInstance = vlcInstance;

      // 3. Create media player
      final player = _createPlayer(bindings, vlcInstance, url, options);
      _player = player;

      // 4. Attach to native window surface via thin native helper
      final handle = await _getNativeWindowHandle();
      _attachToWindow(bindings, player, handle);

      // 5. Start polling state
      _startStatePolling();

      // 6. Begin playback
      final rc = bindings.libvlcMediaPlayerPlay(player);
      if (rc != 0) {
        throw StateError('libvlc_media_player_play() failed (rc=$rc)');
      }
      _updateState(RtspPlayerState.connecting);
    } finally {
      _freeArgs(argPointers, argArrayPtr);
    }
  }

  /// Resumes playback.
  void play() {
    _assertAlive();
    _bindings!.libvlcMediaPlayerPlay(_player!);
  }

  /// Pauses playback without releasing resources.
  void pause() {
    _assertAlive();
    _bindings!.libvlcMediaPlayerPause(_player!);
  }

  /// Stops playback and closes the stream connection.
  void stop() {
    _assertAlive();
    _bindings!.libvlcMediaPlayerStop(_player!);
    _updateState(RtspPlayerState.idle);
  }

  /// Applies new options by rebuilding the VLC media object and swapping it
  /// into the running player via `libvlc_media_player_set_media`.
  ///
  /// The VLC instance is reused; only the media (and its option set) is
  /// replaced.  Playback is briefly interrupted while the new media loads.
  ///
  /// All [RtspPlayerOptions.extraFFmpegOptions] entries are forwarded as
  /// VLC media option strings — this is a full pass-through with no key
  /// filtering.
  void setOptions(RtspPlayerOptions options) {
    _assertAlive();
    final bindings = _bindings!;
    final player = _player!;
    final instance = _vlcInstance!;
    final url = _currentUrl;
    if (url == null) return;

    // Stop playback while we swap media
    bindings.libvlcMediaPlayerStop(player);

    // Build a new media object with the updated options
    final newMedia = _createMedia(bindings, instance, url, options);

    // Swap media into the running player
    bindings.libvlcMediaPlayerSetMedia(player, newMedia);
    bindings.libvlcMediaRelease(newMedia);

    // Resume playback with the new media
    bindings.libvlcMediaPlayerPlay(player);
    _updateState(RtspPlayerState.connecting);
  }

  /// Releases all libVLC resources.
  Future<void> dispose() async {
    _pollingTimer?.cancel();
    _pollingTimer = null;

    final bindings = _bindings;
    final player = _player;
    final instance = _vlcInstance;

    if (player != null && bindings != null) {
      bindings.libvlcMediaPlayerStop(player);
      bindings.libvlcMediaPlayerRelease(player);
    }
    if (instance != null && bindings != null) {
      bindings.libvlcRelease(instance);
    }

    _player = null;
    _vlcInstance = null;
    _bindings = null;
    _currentUrl = null;

    if (!_stateController.isClosed) await _stateController.close();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Timer? _pollingTimer;

  void _startStatePolling() {
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final player = _player;
      final bindings = _bindings;
      if (player == null || bindings == null) return;

      final vlcState = bindings.libvlcMediaPlayerGetState(player);
      final newState = _mapVlcState(vlcState);
      if (newState != null) _updateState(newState);
    });
  }

  void _updateState(RtspPlayerState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  void _assertAlive() {
    if (_player == null) {
      throw StateError(
          'DesktopVlcPlayer is not initialised or has been disposed.');
    }
  }

  Future<int> _getNativeWindowHandle() async {
    final handle =
        await _helperChannel.invokeMethod<int>('getWindowHandle');
    if (handle == null) {
      throw StateError('Native helper returned null window handle.');
    }
    return handle;
  }

  void _attachToWindow(LibVlcBindings bindings,
      Pointer<LibvlcMediaPlayer> player, int handle) {
    if (Platform.isWindows) {
      bindings.libvlcMediaPlayerSetHwnd(player, Pointer.fromAddress(handle));
    } else if (Platform.isLinux) {
      bindings.libvlcMediaPlayerSetXwindow(player, handle);
    }
  }

  // ── Factory helpers ─────────────────────────────────────────────────────────

  /// Creates a media player attached to a new media for [url]+[options].
  static Pointer<LibvlcMediaPlayer> _createPlayer(
      LibVlcBindings bindings,
      Pointer<LibvlcInstance> instance,
      String url,
      RtspPlayerOptions options) {
    final media = _createMedia(bindings, instance, url, options);
    final player = bindings.libvlcMediaPlayerNewFromMedia(media);
    bindings.libvlcMediaRelease(media);
    if (player == nullptr) {
      throw StateError('libvlc_media_player_new_from_media() failed');
    }
    return player;
  }

  /// Creates a VLC media object for [url] with all options applied.
  ///
  /// All [RtspPlayerOptions.extraFFmpegOptions] are forwarded via
  /// `libvlc_media_add_option` — no filtering, full pass-through.
  static Pointer<LibvlcMedia> _createMedia(
      LibVlcBindings bindings,
      Pointer<LibvlcInstance> instance,
      String url,
      RtspPlayerOptions options) {
    final urlPtr = url.toNativeUtf8();
    final media = bindings.libvlcMediaNewLocation(instance, urlPtr);
    calloc.free(urlPtr);
    if (media == nullptr) {
      throw StateError('libvlc_media_new_location() failed for "$url"');
    }

    void addOption(String opt) {
      final ptr = opt.toNativeUtf8();
      bindings.libvlcMediaAddOption(media, ptr);
      calloc.free(ptr);
    }

    // Typed options
    addOption(':network-caching=${options.networkCaching}');
    addOption(':clock-jitter=${options.maxLatency.inMilliseconds}');
    if (options.transport == RtspTransport.tcp) addOption(':rtsp-tcp');
    if (!options.hwAcceleration) addOption(':avcodec-hw=none');
    if (options.videoCodec != RtspVideoCodec.auto) {
      addOption(':avcodec-codec=${options.videoCodec.name}');
    }

    // Full pass-through of all extraFFmpegOptions
    for (final entry in options.extraFFmpegOptions.entries) {
      addOption(':${entry.key}=${entry.value}');
    }

    return media;
  }

  static List<String> _buildVlcArgs(RtspPlayerOptions options) {
    return [
      '--no-video-title-show',
      '--network-caching=${options.networkCaching}',
      if (options.transport == RtspTransport.tcp) '--rtsp-tcp',
      if (!options.hwAcceleration) '--avcodec-hw=none',
      if (options.videoCodec != RtspVideoCodec.auto)
        '--avcodec-codec=${options.videoCodec.name}',
    ];
  }

  /// Allocates a native C string array from [args].
  /// Returns (array pointer, list of individual pointers to free later).
  static (Pointer<Pointer<Utf8>>, List<Pointer<Utf8>>) _allocArgs(
      List<String> args) {
    final ptrs = <Pointer<Utf8>>[];
    final array = calloc<Pointer<Utf8>>(args.length);
    for (var i = 0; i < args.length; i++) {
      ptrs.add(args[i].toNativeUtf8());
      array[i] = ptrs[i];
    }
    return (array, ptrs);
  }

  static void _freeArgs(
      List<Pointer<Utf8>> ptrs, Pointer<Pointer<Utf8>> array) {
    for (final p in ptrs) calloc.free(p);
    calloc.free(array);
  }

  /// Maps a raw `libvlc_state_t` integer to [RtspPlayerState].
  ///
  /// Values match `libvlc_state_t` from `<vlc/libvlc_media.h>`:
  ///   0 = NothingSpecial, 1 = Opening, 2 = Buffering, 3 = Playing,
  ///   4 = Paused, 5 = Stopped, 6 = Ended, 7 = Error
  static RtspPlayerState? _mapVlcState(int vlcState) {
    return switch (vlcState) {
      LibvlcState.nothingSpecial => RtspPlayerState.idle,
      LibvlcState.opening || LibvlcState.buffering => RtspPlayerState.connecting,
      LibvlcState.playing => RtspPlayerState.playing,
      LibvlcState.paused => RtspPlayerState.paused,
      LibvlcState.stopped || LibvlcState.ended => RtspPlayerState.idle,
      LibvlcState.error => RtspPlayerState.error,
      _ => null,
    };
  }
}

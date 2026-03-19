import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// ── libVLC opaque handle types ─────────────────────────────────────────────

final class LibvlcInstance extends Opaque {}
final class LibvlcMediaPlayer extends Opaque {}
final class LibvlcMedia extends Opaque {}
final class LibvlcEventManager extends Opaque {}
final class LibvlcEvent extends Opaque {}

// ── Native function typedefs ───────────────────────────────────────────────

typedef _LibvlcNewNative = Pointer<LibvlcInstance> Function(
    Int32 argc, Pointer<Pointer<Utf8>> argv);
typedef LibvlcNew = Pointer<LibvlcInstance> Function(
    int argc, Pointer<Pointer<Utf8>> argv);

typedef _LibvlcReleaseNative = Void Function(Pointer<LibvlcInstance> instance);
typedef LibvlcRelease = void Function(Pointer<LibvlcInstance> instance);

typedef _LibvlcMediaNewLocationNative = Pointer<LibvlcMedia> Function(
    Pointer<LibvlcInstance> instance, Pointer<Utf8> mrl);
typedef LibvlcMediaNewLocation = Pointer<LibvlcMedia> Function(
    Pointer<LibvlcInstance> instance, Pointer<Utf8> mrl);

typedef _LibvlcMediaAddOptionNative = Void Function(
    Pointer<LibvlcMedia> media, Pointer<Utf8> option);
typedef LibvlcMediaAddOption = void Function(
    Pointer<LibvlcMedia> media, Pointer<Utf8> option);

typedef _LibvlcMediaReleaseNative = Void Function(Pointer<LibvlcMedia> media);
typedef LibvlcMediaRelease = void Function(Pointer<LibvlcMedia> media);

typedef _LibvlcMediaPlayerNewFromMediaNative = Pointer<LibvlcMediaPlayer>
    Function(Pointer<LibvlcMedia> media);
typedef LibvlcMediaPlayerNewFromMedia = Pointer<LibvlcMediaPlayer> Function(
    Pointer<LibvlcMedia> media);

typedef _LibvlcMediaPlayerReleaseNative = Void Function(
    Pointer<LibvlcMediaPlayer> player);
typedef LibvlcMediaPlayerRelease = void Function(
    Pointer<LibvlcMediaPlayer> player);

typedef _LibvlcMediaPlayerSetHwndNative = Void Function(
    Pointer<LibvlcMediaPlayer> player, Pointer<Void> drawable);
typedef LibvlcMediaPlayerSetHwnd = void Function(
    Pointer<LibvlcMediaPlayer> player, Pointer<Void> drawable);

typedef _LibvlcMediaPlayerSetXwindowNative = Void Function(
    Pointer<LibvlcMediaPlayer> player, Uint32 drawable);
typedef LibvlcMediaPlayerSetXwindow = void Function(
    Pointer<LibvlcMediaPlayer> player, int drawable);

typedef _LibvlcMediaPlayerSetNsdisplayNative = Void Function(
    Pointer<LibvlcMediaPlayer> player, Pointer<Void> drawable);
typedef LibvlcMediaPlayerSetNsdisplay = void Function(
    Pointer<LibvlcMediaPlayer> player, Pointer<Void> drawable);

typedef _LibvlcMediaPlayerPlayNative = Int32 Function(
    Pointer<LibvlcMediaPlayer> player);
typedef LibvlcMediaPlayerPlay = int Function(
    Pointer<LibvlcMediaPlayer> player);

typedef _LibvlcMediaPlayerPauseNative = Void Function(
    Pointer<LibvlcMediaPlayer> player);
typedef LibvlcMediaPlayerPause = void Function(
    Pointer<LibvlcMediaPlayer> player);

typedef _LibvlcMediaPlayerStopNative = Void Function(
    Pointer<LibvlcMediaPlayer> player);
typedef LibvlcMediaPlayerStop = void Function(
    Pointer<LibvlcMediaPlayer> player);

typedef _LibvlcMediaPlayerIsPlayingNative = Int32 Function(
    Pointer<LibvlcMediaPlayer> player);
typedef LibvlcMediaPlayerIsPlaying = int Function(
    Pointer<LibvlcMediaPlayer> player);

typedef _LibvlcMediaPlayerGetStateNative = Int32 Function(
    Pointer<LibvlcMediaPlayer> player);
typedef LibvlcMediaPlayerGetState = int Function(
    Pointer<LibvlcMediaPlayer> player);

typedef _LibvlcMediaPlayerEventManagerNative = Pointer<LibvlcEventManager>
    Function(Pointer<LibvlcMediaPlayer> player);
typedef LibvlcMediaPlayerEventManager = Pointer<LibvlcEventManager> Function(
    Pointer<LibvlcMediaPlayer> player);

// Event callback: void (*)(const libvlc_event_t *, void *)
typedef LibvlcCallbackNative = Void Function(
    Pointer<LibvlcEvent> event, Pointer<Void> userData);
typedef LibvlcCallback = void Function(
    Pointer<LibvlcEvent> event, Pointer<Void> userData);

typedef _LibvlcEventAttachNative = Int32 Function(
    Pointer<LibvlcEventManager> eventManager,
    Int32 eventType,
    Pointer<NativeFunction<LibvlcCallbackNative>> callback,
    Pointer<Void> userData);
typedef LibvlcEventAttach = int Function(
    Pointer<LibvlcEventManager> eventManager,
    int eventType,
    Pointer<NativeFunction<LibvlcCallbackNative>> callback,
    Pointer<Void> userData);

typedef _LibvlcEventDetachNative = Void Function(
    Pointer<LibvlcEventManager> eventManager,
    Int32 eventType,
    Pointer<NativeFunction<LibvlcCallbackNative>> callback,
    Pointer<Void> userData);
typedef LibvlcEventDetach = void Function(
    Pointer<LibvlcEventManager> eventManager,
    int eventType,
    Pointer<NativeFunction<LibvlcCallbackNative>> callback,
    Pointer<Void> userData);

typedef _LibvlcMediaPlayerSetMediaNative = Void Function(
    Pointer<LibvlcMediaPlayer> player, Pointer<LibvlcMedia> media);
typedef LibvlcMediaPlayerSetMedia = void Function(
    Pointer<LibvlcMediaPlayer> player, Pointer<LibvlcMedia> media);

/// libVLC media player state values.
///
/// These match the `libvlc_state_t` enum defined in `<vlc/libvlc_media.h>`:
/// ```c
/// typedef enum libvlc_state_t {
///   libvlc_NothingSpecial = 0,
///   libvlc_Opening        = 1,
///   libvlc_Buffering      = 2,
///   libvlc_Playing        = 3,
///   libvlc_Paused         = 4,
///   libvlc_Stopped        = 5,
///   libvlc_Ended          = 6,
///   libvlc_Error          = 7,
/// } libvlc_state_t;
/// ```
abstract class LibvlcState {
  static const int nothingSpecial = 0;
  static const int opening = 1;
  static const int buffering = 2;
  static const int playing = 3;
  static const int paused = 4;
  static const int stopped = 5;
  static const int ended = 6;
  static const int error = 7;
}

/// libVLC event type enum values (subset used for state tracking).
abstract class LibvlcEventType {
  static const int mediaPlayerMediaChanged = 0x100;
  static const int mediaPlayerOpening = 0x101;
  static const int mediaPlayerBuffering = 0x102;
  static const int mediaPlayerPlaying = 0x103;
  static const int mediaPlayerPaused = 0x104;
  static const int mediaPlayerStopped = 0x105;
  static const int mediaPlayerForward = 0x106;
  static const int mediaPlayerBackward = 0x107;
  static const int mediaPlayerEndReached = 0x108;
  static const int mediaPlayerEncounteredError = 0x109;
}

/// Loads the libVLC shared library and exposes bound Dart functions.
///
/// Call [LibVlcBindings.load] once and keep the instance alive for the duration
/// of the player's lifetime.
class LibVlcBindings {
  final DynamicLibrary _lib;

  LibVlcBindings._(this._lib);

  /// Loads `libvlc.so` on Linux or `libvlc.dll` on Windows.
  ///
  /// Throws [ArgumentError] on unsupported platforms and [StateError] if the
  /// library cannot be found.
  factory LibVlcBindings.load() {
    final DynamicLibrary lib;
    if (Platform.isLinux) {
      lib = DynamicLibrary.open('libvlc.so.5');
    } else if (Platform.isWindows) {
      lib = DynamicLibrary.open('libvlc.dll');
    } else {
      throw ArgumentError(
          'LibVlcBindings.load() is only supported on Linux and Windows.');
    }
    return LibVlcBindings._(lib);
  }

  // ── Lazily bound functions ─────────────────────────────────────────────────

  late final LibvlcNew libvlcNew =
      _lib.lookupFunction<_LibvlcNewNative, LibvlcNew>('libvlc_new');

  late final LibvlcRelease libvlcRelease =
      _lib.lookupFunction<_LibvlcReleaseNative, LibvlcRelease>('libvlc_release');

  late final LibvlcMediaNewLocation libvlcMediaNewLocation =
      _lib.lookupFunction<_LibvlcMediaNewLocationNative, LibvlcMediaNewLocation>(
          'libvlc_media_new_location');

  late final LibvlcMediaAddOption libvlcMediaAddOption =
      _lib.lookupFunction<_LibvlcMediaAddOptionNative, LibvlcMediaAddOption>(
          'libvlc_media_add_option');

  late final LibvlcMediaRelease libvlcMediaRelease =
      _lib.lookupFunction<_LibvlcMediaReleaseNative, LibvlcMediaRelease>(
          'libvlc_media_release');

  late final LibvlcMediaPlayerNewFromMedia libvlcMediaPlayerNewFromMedia =
      _lib.lookupFunction<_LibvlcMediaPlayerNewFromMediaNative,
          LibvlcMediaPlayerNewFromMedia>('libvlc_media_player_new_from_media');

  late final LibvlcMediaPlayerRelease libvlcMediaPlayerRelease =
      _lib.lookupFunction<_LibvlcMediaPlayerReleaseNative,
          LibvlcMediaPlayerRelease>('libvlc_media_player_release');

  late final LibvlcMediaPlayerSetHwnd libvlcMediaPlayerSetHwnd =
      _lib.lookupFunction<_LibvlcMediaPlayerSetHwndNative,
          LibvlcMediaPlayerSetHwnd>('libvlc_media_player_set_hwnd');

  late final LibvlcMediaPlayerSetXwindow libvlcMediaPlayerSetXwindow =
      _lib.lookupFunction<_LibvlcMediaPlayerSetXwindowNative,
          LibvlcMediaPlayerSetXwindow>('libvlc_media_player_set_xwindow');

  late final LibvlcMediaPlayerPlay libvlcMediaPlayerPlay =
      _lib.lookupFunction<_LibvlcMediaPlayerPlayNative, LibvlcMediaPlayerPlay>(
          'libvlc_media_player_play');

  late final LibvlcMediaPlayerPause libvlcMediaPlayerPause =
      _lib.lookupFunction<_LibvlcMediaPlayerPauseNative, LibvlcMediaPlayerPause>(
          'libvlc_media_player_pause');

  late final LibvlcMediaPlayerStop libvlcMediaPlayerStop =
      _lib.lookupFunction<_LibvlcMediaPlayerStopNative, LibvlcMediaPlayerStop>(
          'libvlc_media_player_stop');

  late final LibvlcMediaPlayerIsPlaying libvlcMediaPlayerIsPlaying =
      _lib.lookupFunction<_LibvlcMediaPlayerIsPlayingNative,
          LibvlcMediaPlayerIsPlaying>('libvlc_media_player_is_playing');

  late final LibvlcMediaPlayerGetState libvlcMediaPlayerGetState =
      _lib.lookupFunction<_LibvlcMediaPlayerGetStateNative,
          LibvlcMediaPlayerGetState>('libvlc_media_player_get_state');

  late final LibvlcMediaPlayerEventManager libvlcMediaPlayerEventManager =
      _lib.lookupFunction<_LibvlcMediaPlayerEventManagerNative,
          LibvlcMediaPlayerEventManager>(
          'libvlc_media_player_event_manager');

  late final LibvlcEventAttach libvlcEventAttach =
      _lib.lookupFunction<_LibvlcEventAttachNative, LibvlcEventAttach>(
          'libvlc_event_attach');

  late final LibvlcEventDetach libvlcEventDetach =
      _lib.lookupFunction<_LibvlcEventDetachNative, LibvlcEventDetach>(
          'libvlc_event_detach');

  late final LibvlcMediaPlayerSetMedia libvlcMediaPlayerSetMedia =
      _lib.lookupFunction<_LibvlcMediaPlayerSetMediaNative,
          LibvlcMediaPlayerSetMedia>('libvlc_media_player_set_media');
}

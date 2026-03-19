/// Represents the current playback state of an RTSP stream.
enum RtspPlayerState {
  /// No stream loaded, player is idle.
  idle,

  /// Connecting to and buffering the RTSP source.
  connecting,

  /// Stream is actively playing.
  playing,

  /// Stream is paused.
  paused,

  /// An error has occurred. Check [RtspPlayerController.error] for details.
  error,

  /// The controller has been disposed and must not be used.
  disposed,
}

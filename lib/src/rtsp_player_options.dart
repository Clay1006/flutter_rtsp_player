/// Transport protocol to use for RTSP negotiation.
enum RtspTransport {
  /// Use TCP for reliable, ordered delivery. Recommended for most cases.
  tcp,

  /// Use UDP for lower overhead. May drop packets on congested networks.
  udp,

  /// HTTP tunnelling — for use behind proxies or firewalls.
  http,
}

/// Preferred video codec hint passed to the underlying decoder.
///
/// The platform may ignore this if the hint is not supported.
enum RtspVideoCodec {
  /// Let the platform auto-detect the codec.
  auto,

  /// H.264 / AVC.
  h264,

  /// H.265 / HEVC.
  h265,

  /// MJPEG.
  mjpeg,
}

/// Configuration options for an RTSP player instance.
///
/// All fields are optional and have sensible defaults. Use [extraFFmpegOptions]
/// to pass arbitrary FFmpeg/libVLC options for advanced tuning.
///
/// ### Example
/// ```dart
/// final options = RtspPlayerOptions(
///   transport: RtspTransport.tcp,
///   bufferDuration: const Duration(milliseconds: 200),
///   networkCaching: 150,
///   extraFFmpegOptions: {
///     'rtsp_flags': 'prefer_tcp',
///     'stimeout': '5000000',
///   },
/// );
/// ```
class RtspPlayerOptions {
  /// Transport protocol for RTSP.
  ///
  /// Defaults to [RtspTransport.tcp].
  final RtspTransport transport;

  /// Target buffer duration for the player pipeline.
  ///
  /// Larger values reduce stutter on unstable networks but increase latency.
  /// Defaults to 500 ms.
  final Duration bufferDuration;

  /// Maximum acceptable end-to-end latency.
  ///
  /// Platforms that support low-latency modes will use this to tune their
  /// pipeline. Defaults to 1000 ms.
  final Duration maxLatency;

  /// Preferred video codec.
  ///
  /// Defaults to [RtspVideoCodec.auto].
  final RtspVideoCodec videoCodec;

  /// Network caching value in milliseconds, forwarded directly to VLC's
  /// `:network-caching` option and ExoPlayer's buffer configuration.
  ///
  /// Defaults to 300 ms.
  final int networkCaching;

  /// Hardware-accelerated decoding.
  ///
  /// When `true`, the platform will attempt to use hardware decoders
  /// (MediaCodec on Android, VideoToolbox on Apple, DXVA2/D3D11 on Windows).
  /// Defaults to `true`.
  final bool hwAcceleration;

  /// Arbitrary FFmpeg / libVLC option pass-through.
  ///
  /// Keys and values are passed to the underlying engine:
  ///
  /// - **iOS / macOS (VLCKit)** and **Windows / Linux (libVLC via Dart FFI)**:
  ///   Full pass-through — every entry is forwarded as a VLC media option string
  ///   `":key=value"` via `libvlc_media_add_option`. Any option accepted by
  ///   `vlc --option=value` is valid.
  ///
  /// - **Android (ExoPlayer)**: ExoPlayer does not expose a generic FFmpeg
  ///   option pass-through for RTSP.  The following keys are mapped to their
  ///   ExoPlayer equivalents:
  ///   | Key | ExoPlayer mapping |
  ///   |-----|-------------------|
  ///   | `stimeout` / `timeout` | `RtspMediaSource.setTimeoutMs` (µs→ms) |
  ///   | `buffer_size` | minimum buffer duration floor (heuristic) |
  ///   | `max_delay` | overrides `maxLatency` (µs→ms) |
  ///   | `rtsp_flags` with `prefer_tcp` | `RtspMediaSource.setForceUseRtpTcp(true)` |
  ///
  ///   All other keys are **logged at DEBUG level** and not silently dropped —
  ///   the developer can see them via `adb logcat -s RtspPlayerPlugin`.
  ///   To confirm which keys were applied, check the Android log tag
  ///   `RtspPlayerPlugin`.
  ///
  /// Refer to the [FFmpeg RTSP documentation](https://ffmpeg.org/ffmpeg-protocols.html#rtsp)
  /// and [VLC command-line options](https://wiki.videolan.org/VLC_command-line_help)
  /// for available keys.
  ///
  /// ### Common FFmpeg options
  /// | Key | Description | Example value |
  /// |-----|-------------|---------------|
  /// | `rtsp_flags` | RTSP flags | `prefer_tcp` |
  /// | `stimeout` | Socket timeout in microseconds | `5000000` |
  /// | `buffer_size` | UDP receive buffer in bytes | `65535` |
  /// | `reorder_queue_size` | Packet reorder buffer size | `0` |
  /// | `max_delay` | Max demux-decode delay in microseconds | `500000` |
  /// | `fflags` | Format flags | `nobuffer+flush_packets` |
  ///
  /// ### Common VLC options
  /// | Key | Description | Example value |
  /// |-----|-------------|---------------|
  /// | `network-caching` | Network caching (ms) | `150` |
  /// | `clock-jitter` | Clock jitter tolerance (ms) | `0` |
  /// | `clock-synchro` | A/V clock sync | `0` |
  /// | `avcodec-hw` | HW acceleration | `any` or `none` |
  final Map<String, String> extraFFmpegOptions;

  const RtspPlayerOptions({
    this.transport = RtspTransport.tcp,
    this.bufferDuration = const Duration(milliseconds: 500),
    this.maxLatency = const Duration(milliseconds: 1000),
    this.videoCodec = RtspVideoCodec.auto,
    this.networkCaching = 300,
    this.hwAcceleration = true,
    this.extraFFmpegOptions = const {},
  });

  /// Converts this options object to a plain [Map] suitable for sending over a
  /// platform method channel.
  Map<String, dynamic> toMap() {
    return {
      'transport': transport.name,
      'bufferDurationMs': bufferDuration.inMilliseconds,
      'maxLatencyMs': maxLatency.inMilliseconds,
      'videoCodec': videoCodec.name,
      'networkCaching': networkCaching,
      'hwAcceleration': hwAcceleration,
      // Explicitly typed as Map<String, String> — safe across all codecs.
      'extraFFmpegOptions': Map<String, String>.from(extraFFmpegOptions),
    };
  }

  /// Creates a copy of this instance with the given fields replaced.
  RtspPlayerOptions copyWith({
    RtspTransport? transport,
    Duration? bufferDuration,
    Duration? maxLatency,
    RtspVideoCodec? videoCodec,
    int? networkCaching,
    bool? hwAcceleration,
    Map<String, String>? extraFFmpegOptions,
  }) {
    return RtspPlayerOptions(
      transport: transport ?? this.transport,
      bufferDuration: bufferDuration ?? this.bufferDuration,
      maxLatency: maxLatency ?? this.maxLatency,
      videoCodec: videoCodec ?? this.videoCodec,
      networkCaching: networkCaching ?? this.networkCaching,
      hwAcceleration: hwAcceleration ?? this.hwAcceleration,
      extraFFmpegOptions: extraFFmpegOptions ?? this.extraFFmpegOptions,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RtspPlayerOptions) return false;
    if (other.transport != transport) return false;
    if (other.bufferDuration != bufferDuration) return false;
    if (other.maxLatency != maxLatency) return false;
    if (other.videoCodec != videoCodec) return false;
    if (other.networkCaching != networkCaching) return false;
    if (other.hwAcceleration != hwAcceleration) return false;
    if (other.extraFFmpegOptions.length != extraFFmpegOptions.length) return false;
    for (final key in extraFFmpegOptions.keys) {
      if (other.extraFFmpegOptions[key] != extraFFmpegOptions[key]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        transport,
        bufferDuration,
        maxLatency,
        videoCodec,
        networkCaching,
        hwAcceleration,
        Object.hashAll(
          extraFFmpegOptions.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  @override
  String toString() => 'RtspPlayerOptions('
      'transport: $transport, '
      'bufferDuration: $bufferDuration, '
      'maxLatency: $maxLatency, '
      'videoCodec: $videoCodec, '
      'networkCaching: $networkCaching, '
      'hwAcceleration: $hwAcceleration, '
      'extraFFmpegOptions: $extraFFmpegOptions)';
}

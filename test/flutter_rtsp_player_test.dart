import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rtsp_player/flutter_rtsp_player.dart';
import 'package:flutter_rtsp_player/src/ffi/libvlc_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('flutter_rtsp_player/methods');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return 42;
        case 'play':
        case 'pause':
        case 'stop':
        case 'setOptions':
        case 'dispose':
          return null;
        default:
          throw PlatformException(code: 'NOT_IMPLEMENTED');
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  // ── RtspPlayerOptions ──────────────────────────────────────────────────────

  group('RtspPlayerOptions', () {
    test('defaults are sensible', () {
      const opts = RtspPlayerOptions();
      expect(opts.transport, RtspTransport.tcp);
      expect(opts.bufferDuration, const Duration(milliseconds: 500));
      expect(opts.maxLatency, const Duration(milliseconds: 1000));
      expect(opts.videoCodec, RtspVideoCodec.auto);
      expect(opts.networkCaching, 300);
      expect(opts.hwAcceleration, true);
      expect(opts.extraFFmpegOptions, isEmpty);
    });

    test('toMap() serializes all fields correctly', () {
      const opts = RtspPlayerOptions(
        transport: RtspTransport.udp,
        bufferDuration: Duration(milliseconds: 200),
        maxLatency: Duration(milliseconds: 800),
        videoCodec: RtspVideoCodec.h264,
        networkCaching: 150,
        hwAcceleration: false,
        extraFFmpegOptions: {
          'stimeout': '5000000',
          'rtsp_flags': 'prefer_tcp',
        },
      );

      final map = opts.toMap();
      expect(map['transport'], 'udp');
      expect(map['bufferDurationMs'], 200);
      expect(map['maxLatencyMs'], 800);
      expect(map['videoCodec'], 'h264');
      expect(map['networkCaching'], 150);
      expect(map['hwAcceleration'], false);
      expect(map['extraFFmpegOptions'], {
        'stimeout': '5000000',
        'rtsp_flags': 'prefer_tcp',
      });
    });

    test('toMap() with all codec values', () {
      for (final codec in RtspVideoCodec.values) {
        final map = RtspPlayerOptions(videoCodec: codec).toMap();
        expect(map['videoCodec'], codec.name);
      }
    });

    test('toMap() with all transport values', () {
      for (final t in RtspTransport.values) {
        final map = RtspPlayerOptions(transport: t).toMap();
        expect(map['transport'], t.name);
      }
    });

    test('RtspVideoCodec includes h264, h265, mjpeg, auto', () {
      expect(RtspVideoCodec.values, containsAll([
        RtspVideoCodec.auto,
        RtspVideoCodec.h264,
        RtspVideoCodec.h265,
        RtspVideoCodec.mjpeg,
      ]));
    });

    test('RtspTransport includes tcp, udp, http', () {
      expect(RtspTransport.values, containsAll([
        RtspTransport.tcp,
        RtspTransport.udp,
        RtspTransport.http,
      ]));
    });

    test('toString() contains all field names', () {
      const opts = RtspPlayerOptions(
        extraFFmpegOptions: {'key': 'value'},
      );
      final s = opts.toString();
      expect(s, contains('transport'));
      expect(s, contains('bufferDuration'));
      expect(s, contains('maxLatency'));
      expect(s, contains('videoCodec'));
      expect(s, contains('networkCaching'));
      expect(s, contains('hwAcceleration'));
      expect(s, contains('extraFFmpegOptions'));
    });

    test('empty extraFFmpegOptions round-trips through toMap()', () {
      const opts = RtspPlayerOptions();
      expect(opts.toMap()['extraFFmpegOptions'], isEmpty);
    });

    test('copyWith() replaces only the specified fields', () {
      const original = RtspPlayerOptions(
        transport: RtspTransport.udp,
        networkCaching: 500,
        extraFFmpegOptions: {'key': 'val'},
      );
      final copy = original.copyWith(transport: RtspTransport.tcp);
      expect(copy.transport, RtspTransport.tcp);
      expect(copy.networkCaching, 500);
      expect(copy.extraFFmpegOptions, {'key': 'val'});
    });

    test('equality and hashCode are consistent', () {
      const a = RtspPlayerOptions(
        transport: RtspTransport.tcp,
        networkCaching: 300,
        extraFFmpegOptions: {'stimeout': '5000000'},
      );
      const b = RtspPlayerOptions(
        transport: RtspTransport.tcp,
        networkCaching: 300,
        extraFFmpegOptions: {'stimeout': '5000000'},
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when extraFFmpegOptions differ', () {
      const a = RtspPlayerOptions(extraFFmpegOptions: {'k': 'v1'});
      const b = RtspPlayerOptions(extraFFmpegOptions: {'k': 'v2'});
      expect(a, isNot(equals(b)));
    });

    test('extraFFmpegOptions is typed as Map<String, String> in toMap()', () {
      const opts = RtspPlayerOptions(
        extraFFmpegOptions: {'stimeout': '1000000', 'buffer_size': '65535'},
      );
      final map = opts.toMap();
      final extra = map['extraFFmpegOptions'];
      expect(extra, isA<Map<String, String>>());
    });

    test('large extraFFmpegOptions map is preserved in toMap()', () {
      final bigMap = {
        for (var i = 0; i < 20; i++) 'key_$i': 'value_$i',
      };
      final opts = RtspPlayerOptions(extraFFmpegOptions: bigMap);
      final result = opts.toMap()['extraFFmpegOptions'] as Map;
      expect(result.length, 20);
      for (var i = 0; i < 20; i++) {
        expect(result['key_$i'], 'value_$i');
      }
    });
  });

  // ── RtspPlayerState ────────────────────────────────────────────────────────

  group('RtspPlayerState', () {
    test('all states are distinct', () {
      final states = RtspPlayerState.values.toSet();
      expect(states.length, RtspPlayerState.values.length);
    });

    test('contains expected values', () {
      expect(RtspPlayerState.values, containsAll([
        RtspPlayerState.idle,
        RtspPlayerState.connecting,
        RtspPlayerState.playing,
        RtspPlayerState.paused,
        RtspPlayerState.error,
        RtspPlayerState.disposed,
      ]));
    });
  });

  // ── LibvlcState enum values ────────────────────────────────────────────────
  // Validates that our constants match the libvlc_state_t C enum documented in
  // <vlc/libvlc_media.h>. If these fail after a VLC version upgrade, update the
  // constants to match the new header values.

  group('LibvlcState constants match libvlc_state_t', () {
    test('NothingSpecial = 0', () => expect(LibvlcState.nothingSpecial, 0));
    test('Opening = 1',        () => expect(LibvlcState.opening,        1));
    test('Buffering = 2',      () => expect(LibvlcState.buffering,      2));
    test('Playing = 3',        () => expect(LibvlcState.playing,        3));
    test('Paused = 4',         () => expect(LibvlcState.paused,         4));
    test('Stopped = 5',        () => expect(LibvlcState.stopped,        5));
    test('Ended = 6',          () => expect(LibvlcState.ended,          6));
    test('Error = 7',          () => expect(LibvlcState.error,          7));
  });

  // ── RtspPlayerController ───────────────────────────────────────────────────

  group('RtspPlayerController', () {
    test('initial state is idle', () {
      final controller = RtspPlayerController();
      expect(controller.state, RtspPlayerState.idle);
      expect(controller.error, isNull);
      expect(controller.textureId, isNull);
    });

    test('initialize returns texture id and emits connecting state', () async {
      final controller = RtspPlayerController();
      final states = <RtspPlayerState>[];
      controller.stateStream.listen(states.add);

      await controller.initialize(
        url: 'rtsp://example.com:554/stream',
        options: const RtspPlayerOptions(),
      );

      expect(controller.textureId, 42);
      expect(states, contains(RtspPlayerState.connecting));

      await controller.dispose();
    });

    test('initialize sends extraFFmpegOptions to native channel', () async {
      final controller = RtspPlayerController();
      Map<String, dynamic>? capturedArgs;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'initialize') {
          capturedArgs = call.arguments as Map<String, dynamic>?;
          return 99;
        }
        return null;
      });

      await controller.initialize(
        url: 'rtsp://cam.example.com/live',
        options: const RtspPlayerOptions(
          extraFFmpegOptions: {
            'stimeout': '5000000',
            'rtsp_flags': 'prefer_tcp',
            'custom_key': 'custom_value',
          },
        ),
      );

      expect(capturedArgs, isNotNull);
      final extra = (capturedArgs!['options'] as Map<String, dynamic>)['extraFFmpegOptions'];
      expect(extra, isA<Map>());
      expect(extra['stimeout'], '5000000');
      expect(extra['rtsp_flags'], 'prefer_tcp');
      // Non-standard keys should be passed through to the channel
      expect(extra['custom_key'], 'custom_value');

      await controller.dispose();
    });

    test('setOptions sends updated options to native channel', () async {
      final controller = RtspPlayerController();
      Map<String, dynamic>? capturedSetOptionsArgs;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'initialize') return 42;
        if (call.method == 'setOptions') {
          capturedSetOptionsArgs = call.arguments as Map<String, dynamic>?;
          return null;
        }
        return null;
      });

      await controller.initialize(url: 'rtsp://example.com/stream');
      await controller.setOptions(const RtspPlayerOptions(
        networkCaching: 100,
        extraFFmpegOptions: {'stimeout': '1000000'},
      ));

      expect(capturedSetOptionsArgs, isNotNull);
      final opts = capturedSetOptionsArgs!['options'] as Map<String, dynamic>;
      expect(opts['networkCaching'], 100);
      expect((opts['extraFFmpegOptions'] as Map)['stimeout'], '1000000');

      await controller.dispose();
    });

    test('play / pause / stop do not throw', () async {
      final controller = RtspPlayerController();
      await controller.initialize(url: 'rtsp://example.com/stream');

      await expectLater(controller.play(), completes);
      await expectLater(controller.pause(), completes);
      await expectLater(controller.stop(), completes);

      await controller.dispose();
    });

    test('dispose transitions to disposed state', () async {
      final controller = RtspPlayerController();
      await controller.dispose();
      expect(controller.state, RtspPlayerState.disposed);
    });

    test('double dispose is a no-op', () async {
      final controller = RtspPlayerController();
      await controller.dispose();
      await expectLater(controller.dispose(), completes);
    });

    test('play() throws StateError after dispose', () async {
      final controller = RtspPlayerController();
      await controller.dispose();
      expect(controller.play, throwsStateError);
    });

    test('pause() throws StateError after dispose', () async {
      final controller = RtspPlayerController();
      await controller.dispose();
      expect(controller.pause, throwsStateError);
    });

    test('stop() throws StateError after dispose', () async {
      final controller = RtspPlayerController();
      await controller.dispose();
      expect(controller.stop, throwsStateError);
    });

    test('initialize() throws StateError after dispose', () async {
      final controller = RtspPlayerController();
      await controller.dispose();
      expect(
        () => controller.initialize(url: 'rtsp://example.com/stream'),
        throwsStateError,
      );
    });

    test('stateStream is a broadcast stream', () {
      final controller = RtspPlayerController();
      expect(controller.stateStream.isBroadcast, isTrue);
    });
  });
}

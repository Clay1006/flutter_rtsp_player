import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rtsp_player/flutter_rtsp_player.dart';

void main() {
  runApp(const RtspPlayerExampleApp());
}

class RtspPlayerExampleApp extends StatelessWidget {
  const RtspPlayerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RTSP Player Demo',
      theme: ThemeData.dark(useMaterial3: true),
      home: const PlayerScreen(),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _urlController = TextEditingController(
    text: 'rtsp://wowzaec2demo.streamlock.net/vod/mp4:BigBuckBunny_115k.mp4',
  );

  // Options state
  RtspTransport _transport = RtspTransport.tcp;
  double _bufferDuration = 500;
  double _maxLatency = 1000;
  int _networkCaching = 300;
  bool _hwAcceleration = true;
  RtspVideoCodec _videoCodec = RtspVideoCodec.auto;

  // Extra FFmpeg options (key=value pairs)
  final List<MapEntry<TextEditingController, TextEditingController>> _extraOptions = [];

  RtspPlayerController? _controller;
  StreamSubscription<RtspPlayerState>? _stateSub;
  RtspPlayerState _state = RtspPlayerState.idle;
  String? _errorMessage;

  bool get _isConnected =>
      _state == RtspPlayerState.playing || _state == RtspPlayerState.paused;

  @override
  void dispose() {
    _stateSub?.cancel();
    _controller?.dispose();
    _urlController.dispose();
    for (final e in _extraOptions) {
      e.key.dispose();
      e.value.dispose();
    }
    super.dispose();
  }

  // ── Player control ──────────────────────────────────────────────────────────

  Future<void> _connect() async {
    await _disconnect();

    final controller = RtspPlayerController();
    _stateSub = controller.stateStream.listen((s) {
      setState(() {
        _state = s;
        if (s == RtspPlayerState.error) {
          _errorMessage = controller.error;
        } else {
          _errorMessage = null;
        }
      });
    });

    setState(() => _controller = controller);

    try {
      await controller.initialize(
        url: _urlController.text.trim(),
        options: _buildOptions(),
      );
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _disconnect() async {
    await _stateSub?.cancel();
    _stateSub = null;
    await _controller?.dispose();
    setState(() {
      _controller = null;
      _state = RtspPlayerState.idle;
      _errorMessage = null;
    });
  }

  Future<void> _applyOptions() async {
    await _controller?.setOptions(_buildOptions());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Options applied')),
      );
    }
  }

  RtspPlayerOptions _buildOptions() {
    final extra = <String, String>{};
    for (final e in _extraOptions) {
      final k = e.key.text.trim();
      final v = e.value.text.trim();
      if (k.isNotEmpty) extra[k] = v;
    }
    return RtspPlayerOptions(
      transport: _transport,
      bufferDuration: Duration(milliseconds: _bufferDuration.toInt()),
      maxLatency: Duration(milliseconds: _maxLatency.toInt()),
      networkCaching: _networkCaching,
      hwAcceleration: _hwAcceleration,
      videoCodec: _videoCodec,
      extraFFmpegOptions: extra,
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RTSP Player Demo'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _StateChip(state: _state),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildVideoPanel(),
            const SizedBox(height: 8),
            _buildStatusBar(),
            const SizedBox(height: 8),
            _buildUrlBar(),
            const SizedBox(height: 16),
            _buildOptionsCard(),
            const SizedBox(height: 16),
            _buildExtraOptionsCard(),
          ],
        ),
      ),
    );
  }

  // ── Full-screen ──────────────────────────────────────────────────────────────

  Future<void> _openFullScreen() async {
    if (_controller == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullScreenPlayerRoute(controller: _controller!),
        fullscreenDialog: true,
      ),
    );
  }

  // ── Video panel ─────────────────────────────────────────────────────────────

  Widget _buildVideoPanel() {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _controller != null
                ? RtspPlayerWidget(
                    controller: _controller!,
                    showControls: true,
                    errorBuilder: (_, error) => _ErrorPanel(error: error),
                  )
                : const _IdlePanel(),
          ),
        ),
        if (_controller != null && _state == RtspPlayerState.playing)
          Positioned(
            top: 8,
            right: 8,
            child: _IconChip(
              icon: Icons.fullscreen,
              tooltip: 'Full screen',
              onTap: _openFullScreen,
            ),
          ),
      ],
    );
  }

  // ── Status bar ──────────────────────────────────────────────────────────────

  Widget _buildStatusBar() {
    final description = switch (_state) {
      RtspPlayerState.idle       => 'Not connected',
      RtspPlayerState.connecting => 'Connecting to stream…',
      RtspPlayerState.playing    => 'Live — stream playing',
      RtspPlayerState.paused     => 'Paused',
      RtspPlayerState.error      => 'Error: ${_errorMessage ?? 'unknown'}',
      RtspPlayerState.disposed   => 'Disposed',
    };
    final color = switch (_state) {
      RtspPlayerState.playing    => Colors.green.shade300,
      RtspPlayerState.connecting => Colors.amber.shade300,
      RtspPlayerState.error      => Colors.red.shade300,
      _                          => Colors.grey,
    };
    return Row(
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            description,
            style: TextStyle(color: color, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ── URL bar ─────────────────────────────────────────────────────────────────

  Widget _buildUrlBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'RTSP URL',
              hintText: 'rtsp://...',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _connect(),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _isConnected ? _disconnect : _connect,
          icon: Icon(_isConnected ? Icons.stop : Icons.play_arrow),
          label: Text(_isConnected ? 'Stop' : 'Connect'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            backgroundColor:
                _isConnected ? Colors.red.shade700 : Colors.green.shade700,
          ),
        ),
      ],
    );
  }

  // ── Stream options ──────────────────────────────────────────────────────────

  Widget _buildOptionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Stream Options',
                    style: Theme.of(context).textTheme.titleMedium),
                if (_isConnected)
                  TextButton.icon(
                    onPressed: _applyOptions,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Apply live'),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Transport
            _OptionRow(
              label: 'Transport',
              child: SegmentedButton<RtspTransport>(
                segments: const [
                  ButtonSegment(value: RtspTransport.tcp, label: Text('TCP')),
                  ButtonSegment(value: RtspTransport.udp, label: Text('UDP')),
                ],
                selected: {_transport},
                onSelectionChanged: (s) =>
                    setState(() => _transport = s.first),
              ),
            ),
            const SizedBox(height: 12),

            // Video codec
            _OptionRow(
              label: 'Codec hint',
              child: DropdownButton<RtspVideoCodec>(
                value: _videoCodec,
                isExpanded: true,
                items: RtspVideoCodec.values
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.name.toUpperCase()),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _videoCodec = v!),
              ),
            ),
            const SizedBox(height: 12),

            // Buffer duration
            _OptionRow(
              label: 'Buffer: ${_bufferDuration.toInt()} ms',
              child: Slider(
                value: _bufferDuration,
                min: 50,
                max: 5000,
                divisions: 99,
                label: '${_bufferDuration.toInt()} ms',
                onChanged: (v) => setState(() => _bufferDuration = v),
              ),
            ),

            // Max latency
            _OptionRow(
              label: 'Max latency: ${_maxLatency.toInt()} ms',
              child: Slider(
                value: _maxLatency,
                min: 100,
                max: 10000,
                divisions: 99,
                label: '${_maxLatency.toInt()} ms',
                onChanged: (v) => setState(() => _maxLatency = v),
              ),
            ),

            // Network caching
            _OptionRow(
              label: 'Network caching: $_networkCaching ms',
              child: Slider(
                value: _networkCaching.toDouble(),
                min: 50,
                max: 3000,
                divisions: 58,
                label: '$_networkCaching ms',
                onChanged: (v) =>
                    setState(() => _networkCaching = v.toInt()),
              ),
            ),

            // HW acceleration
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hardware acceleration'),
              value: _hwAcceleration,
              onChanged: (v) => setState(() => _hwAcceleration = v),
            ),
          ],
        ),
      ),
    );
  }

  // ── Extra FFmpeg options ────────────────────────────────────────────────────

  Widget _buildExtraOptionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Extra FFmpeg / VLC Options',
                    style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add option',
                  onPressed: () => setState(() => _extraOptions.add(
                      MapEntry(TextEditingController(), TextEditingController()))),
                ),
              ],
            ),
            if (_extraOptions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No extra options. Tap + to add a raw FFmpeg/VLC key=value pair.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            for (var i = 0; i < _extraOptions.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _extraOptions[i].key,
                        decoration: const InputDecoration(
                          labelText: 'Key',
                          hintText: 'stimeout',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _extraOptions[i].value,
                        decoration: const InputDecoration(
                          labelText: 'Value',
                          hintText: '5000000',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => setState(() {
                        _extraOptions[i].key.dispose();
                        _extraOptions[i].value.dispose();
                        _extraOptions.removeAt(i);
                      }),
                    ),
                  ],
                ),
              ),
            if (_extraOptions.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Common keys: stimeout, rtsp_flags, buffer_size, reorder_queue_size, '
                'max_delay, network-caching, clock-jitter, avcodec-hw',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _IdlePanel extends StatelessWidget {
  const _IdlePanel();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, size: 64, color: Colors.grey),
            SizedBox(height: 8),
            Text('Enter an RTSP URL and tap Connect',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String? error;
  const _ErrorPanel({this.error});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(
                error ?? 'Playback error',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final RtspPlayerState state;
  const _StateChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      RtspPlayerState.playing    => ('LIVE', Colors.green),
      RtspPlayerState.connecting => ('CONNECTING', Colors.amber),
      RtspPlayerState.paused     => ('PAUSED', Colors.blue),
      RtspPlayerState.error      => ('ERROR', Colors.red),
      _                          => ('IDLE', Colors.grey),
    };
    return Chip(
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      backgroundColor: color.withOpacity(0.2),
      side: BorderSide(color: color, width: 1),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _OptionRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 200,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _IconChip extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconChip({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// Full-screen player route.
///
/// Shows the [RtspPlayerWidget] filling the entire screen with system chrome
/// (status bar / navigation bar) hidden. Pressing the back button or tapping
/// the exit button restores the UI and returns to [PlayerScreen].
class _FullScreenPlayerRoute extends StatefulWidget {
  final RtspPlayerController controller;
  const _FullScreenPlayerRoute({required this.controller});

  @override
  State<_FullScreenPlayerRoute> createState() => _FullScreenPlayerRouteState();
}

class _FullScreenPlayerRouteState extends State<_FullScreenPlayerRoute> {
  bool _overlayVisible = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _toggleOverlay() => setState(() => _overlayVisible = !_overlayVisible);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleOverlay,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RtspPlayerWidget(
              controller: widget.controller,
              showControls: false,
            ),
            if (_overlayVisible) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _FullScreenTopBar(controller: widget.controller),
              ),
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: _FullScreenControlBar(controller: widget.controller),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FullScreenTopBar extends StatelessWidget {
  final RtspPlayerController controller;
  const _FullScreenTopBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
            tooltip: 'Exit full screen',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          StreamBuilder<RtspPlayerState>(
            stream: controller.stateStream,
            initialData: controller.state,
            builder: (_, snap) {
              final state = snap.data ?? RtspPlayerState.idle;
              return _StateChip(state: state);
            },
          ),
        ],
      ),
    );
  }
}

class _FullScreenControlBar extends StatelessWidget {
  final RtspPlayerController controller;
  const _FullScreenControlBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
      child: StreamBuilder<RtspPlayerState>(
        stream: controller.stateStream,
        initialData: controller.state,
        builder: (_, snap) {
          final state = snap.data ?? RtspPlayerState.idle;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  state == RtspPlayerState.playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 36,
                ),
                onPressed: state == RtspPlayerState.playing
                    ? controller.pause
                    : controller.play,
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.stop, color: Colors.white, size: 36),
                onPressed: () {
                  controller.stop();
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

package com.example.flutter_rtsp_player

import android.content.Context
import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.rtsp.RtspMediaSource
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

private const val TAG = "RtspPlayerPlugin"

/**
 * FlutterRtspPlayerPlugin — Android implementation using ExoPlayer media3-rtsp.
 *
 * extraFFmpegOptions mapping:
 *   stimeout / timeout → RtspMediaSource.Factory.setTimeoutMs (µs → ms)
 *   buffer_size        → DefaultLoadControl minimum buffer (bytes used as ms hint)
 *   reorder_queue_size → ignored (no ExoPlayer equivalent; logged)
 *   max_delay          → maxLatencyMs override (µs → ms)
 *   rtsp_flags         → "prefer_tcp" sets forceUseRtpTcp; others logged
 *   fflags             → ignored (ExoPlayer internal; logged)
 *   All other keys     → logged at DEBUG level; NOT silently dropped
 *
 * Note: ExoPlayer's RtspMediaSource does not expose a generic FFmpeg option
 * pass-through. Keys listed above are fully applied; all others are explicitly
 * logged so the developer knows they were received but are unsupported.
 */
@OptIn(UnstableApi::class)
class FlutterRtspPlayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context
    private lateinit var flutterTextures: TextureRegistry

    private val mainHandler = Handler(Looper.getMainLooper())

    private var player: ExoPlayer? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var eventSink: EventChannel.EventSink? = null

    // Stored to enable setOptions re-initialization
    private var currentUrl: String? = null
    private var currentSurfaceTexture: SurfaceTexture? = null

    // ── FlutterPlugin ──────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        flutterTextures = binding.textureRegistry

        methodChannel = MethodChannel(binding.binaryMessenger, "flutter_rtsp_player/methods")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "flutter_rtsp_player/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        releasePlayer()
    }

    // ── MethodChannel.MethodCallHandler ───────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "play"       -> { player?.playWhenReady = true; result.success(null) }
            "pause"      -> { player?.playWhenReady = false; result.success(null) }
            "stop"       -> { player?.stop(); result.success(null) }
            "setOptions" -> setOptions(call, result)
            "dispose"    -> { releasePlayer(); result.success(null) }
            else         -> result.notImplemented()
        }
    }

    // ── initialize ────────────────────────────────────────────────────────────

    @Suppress("UNCHECKED_CAST")
    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
            ?: return result.error("INVALID_ARGS", "url is required", null)
        val options = call.argument<Map<String, Any>>("options") ?: emptyMap()

        // Release the previous player but keep the texture entry alive if we
        // already have one (setOptions re-uses the same texture id).
        releasePlayerOnly()
        currentUrl = url

        val exoPlayer = buildPlayer(url, options)
        player = exoPlayer

        // Create a new texture entry only if we don't have one yet.
        val entry = textureEntry ?: flutterTextures.createSurfaceTexture().also {
            textureEntry = it
        }
        val surface = Surface(entry.surfaceTexture())
        exoPlayer.setVideoSurface(surface)
        exoPlayer.playWhenReady = true
        exoPlayer.prepare()

        result.success(entry.id().toInt())
    }

    // ── setOptions ────────────────────────────────────────────────────────────

    /**
     * Applies new options by stopping and re-initializing the player with the
     * same URL and texture, but a new ExoPlayer instance configured with the
     * updated parameters.  The Flutter texture ID is unchanged.
     */
    @Suppress("UNCHECKED_CAST")
    private fun setOptions(call: MethodCall, result: MethodChannel.Result) {
        val url = currentUrl
        if (url == null || textureEntry == null) {
            // Not yet initialized; ignore.
            result.success(null)
            return
        }
        val options = call.argument<Map<String, Any>>("options") ?: run {
            result.success(null)
            return
        }

        releasePlayerOnly()

        val exoPlayer = buildPlayer(url, options)
        player = exoPlayer

        val surface = Surface(textureEntry!!.surfaceTexture())
        exoPlayer.setVideoSurface(surface)
        exoPlayer.playWhenReady = true
        exoPlayer.prepare()

        result.success(null)
    }

    // ── buildPlayer ───────────────────────────────────────────────────────────

    @Suppress("UNCHECKED_CAST")
    private fun buildPlayer(url: String, options: Map<String, Any>): ExoPlayer {
        val extraOptions = options["extraFFmpegOptions"] as? Map<String, String> ?: emptyMap()
        val transport = options["transport"] as? String ?: "tcp"
        val bufferDurationMs = (options["bufferDurationMs"] as? Int) ?: 500
        val maxLatencyMs = (options["maxLatencyMs"] as? Int) ?: 1000
        val networkCaching = (options["networkCaching"] as? Int) ?: 300

        // ── Map extraFFmpegOptions → ExoPlayer ───────────────────────────────

        // stimeout / timeout: socket timeout in microseconds (FFmpeg convention)
        val socketTimeoutUs: Long? = extraOptions["stimeout"]?.toLongOrNull()
            ?: extraOptions["timeout"]?.toLongOrNull()
        val socketTimeoutMs: Long = socketTimeoutUs?.div(1000L) ?: 0L

        // max_delay: maximum mux-decode delay in microseconds
        val maxDelayUs: Long? = extraOptions["max_delay"]?.toLongOrNull()
        val maxDelayMs: Int = maxDelayUs?.div(1000L)?.toInt() ?: maxLatencyMs

        // rtsp_flags: "prefer_tcp" forces TCP; anything else is logged
        val rtspFlags = extraOptions["rtsp_flags"]
        val forceTcp = transport == "tcp" ||
                rtspFlags?.contains("prefer_tcp", ignoreCase = true) == true

        // buffer_size: UDP receive buffer in bytes; map to a min-buffer hint
        val bufferSizeBytes: Int? = extraOptions["buffer_size"]?.toIntOrNull()
        // Treat buffer_size as an additional minimum buffer floor in ms (heuristic)
        val bufferSizeMs: Int = bufferSizeBytes?.let {
            // Assume ~1 Mbps stream: bytes / (1_000_000/8) * 1000 = bytes * 8 / 1000
            (it.toLong() * 8L / 1000L).toInt().coerceIn(0, 5000)
        } ?: 0

        // Log known-but-unsupported keys explicitly so developers see them
        val knownKeys = setOf(
            "stimeout", "timeout", "max_delay", "rtsp_flags",
            "buffer_size", "reorder_queue_size", "fflags"
        )
        for ((key, value) in extraOptions) {
            if (key in knownKeys) continue
            Log.d(TAG, "extraFFmpegOptions key '$key'='$value' received but has no " +
                    "ExoPlayer equivalent and will not be applied. On VLC platforms " +
                    "(iOS, macOS, Windows, Linux) this key will be forwarded as-is.")
        }
        extraOptions["reorder_queue_size"]?.let {
            Log.d(TAG, "extraFFmpegOptions: reorder_queue_size=$it has no ExoPlayer " +
                    "equivalent (ExoPlayer manages reordering internally).")
        }
        extraOptions["fflags"]?.let {
            Log.d(TAG, "extraFFmpegOptions: fflags=$it has no ExoPlayer equivalent.")
        }

        // ── DefaultLoadControl ───────────────────────────────────────────────
        val effectiveMinBuffer = maxOf(networkCaching, bufferDurationMs / 2, bufferSizeMs)
        val effectiveMaxBuffer = maxOf(maxDelayMs, bufferDurationMs, effectiveMinBuffer)

        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                /* minBufferMs */                effectiveMinBuffer,
                /* maxBufferMs */                effectiveMaxBuffer,
                /* bufferForPlaybackMs */        (effectiveMinBuffer / 4).coerceAtMost(250),
                /* bufferForPlaybackAfterRebuffer */ effectiveMinBuffer / 2
            )
            .build()

        // ── RtspMediaSource.Factory ───────────────────────────────────────────
        // RtspMediaSource handles the RTSP transport directly; it does not use
        // DefaultHttpDataSource.  All supported options are configured here.
        val rtspFactory = RtspMediaSource.Factory()
            .setForceUseRtpTcp(forceTcp)
            .also { factory ->
                if (socketTimeoutMs > 0) factory.setTimeoutMs(socketTimeoutMs)
            }

        // ── ExoPlayer ────────────────────────────────────────────────────────
        val exoPlayer = ExoPlayer.Builder(context)
            .setLoadControl(loadControl)
            .build()

        exoPlayer.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                val stateName = when (playbackState) {
                    Player.STATE_BUFFERING -> "connecting"
                    Player.STATE_READY     -> if (exoPlayer.playWhenReady) "playing" else "paused"
                    Player.STATE_ENDED     -> "idle"
                    else                   -> "idle"
                }
                sendEvent("stateChanged", mapOf("state" to stateName))
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (exoPlayer.playbackState == Player.STATE_READY) {
                    sendEvent(
                        "stateChanged",
                        mapOf("state" to if (isPlaying) "playing" else "paused")
                    )
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                sendEvent(
                    "stateChanged",
                    mapOf("state" to "error", "error" to (error.message ?: "ExoPlayer error"))
                )
            }
        })

        val mediaSource = rtspFactory.createMediaSource(MediaItem.fromUri(url))
        exoPlayer.setMediaSource(mediaSource)
        return exoPlayer
    }

    // ── Resource management ───────────────────────────────────────────────────

    /** Releases only the ExoPlayer; leaves the texture entry alive. */
    private fun releasePlayerOnly() {
        player?.release()
        player = null
    }

    /** Releases ExoPlayer and the Flutter texture entry. */
    private fun releasePlayer() {
        releasePlayerOnly()
        textureEntry?.release()
        textureEntry = null
        currentUrl = null
    }

    // ── EventChannel.StreamHandler ────────────────────────────────────────────

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun sendEvent(type: String, data: Map<String, Any?> = emptyMap()) {
        mainHandler.post {
            eventSink?.success(mapOf("type" to type) + data)
        }
    }
}

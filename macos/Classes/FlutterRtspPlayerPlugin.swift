import FlutterMacOS
import Foundation
import VLCKit

// MARK: - Plugin registration

public class FlutterRtspPlayerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?
    fileprivate var activePlayer: VlcPlatformView?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FlutterRtspPlayerPlugin()

        let methodChannel = FlutterMethodChannel(
            name: "flutter_rtsp_player/methods",
            binaryMessenger: registrar.messenger
        )
        let eventChannel = FlutterEventChannel(
            name: "flutter_rtsp_player/events",
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)

        registrar.register(
            RtspPlayerViewFactory(plugin: instance),
            withId: "flutter_rtsp_player/video_view"
        )
    }

    // MARK: - FlutterPlugin

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            initialize(call: call, result: result)
        case "play":
            activePlayer?.player.play()
            result(nil)
        case "pause":
            activePlayer?.player.pause()
            result(nil)
        case "stop":
            activePlayer?.player.stop()
            result(nil)
        case "setOptions":
            applyOptions(call: call)
            result(nil)
        case "dispose":
            disposeActive()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initialize(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let url = args["url"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "url is required", details: nil))
            return
        }
        guard URL(string: url) != nil else {
            result(FlutterError(code: "INVALID_URL",
                                message: "'\(url)' is not a valid URL",
                                details: nil))
            return
        }
        let options = args["options"] as? [String: Any] ?? [:]
        disposeActive()

        let view = VlcPlatformView(url: url, options: options) { [weak self] event in
            DispatchQueue.main.async { self?.eventSink?(event) }
        }
        activePlayer = view
        result(0)
    }

    private func applyOptions(call: FlutterMethodCall) {
        guard let args = call.arguments as? [String: Any],
              let options = args["options"] as? [String: Any] else { return }
        activePlayer?.applyLiveOptions(options)
    }

    private func disposeActive() {
        activePlayer?.player.stop()
        activePlayer = nil
    }

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?,
                         eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

// MARK: - Platform view factory

class RtspPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
    private weak var plugin: FlutterRtspPlayerPlugin?

    init(plugin: FlutterRtspPlayerPlugin) {
        self.plugin = plugin
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        if let existingView = plugin?.activePlayer {
            return existingView.nsView
        }
        return NSView()
    }
}

// MARK: - VLC platform view

class VlcPlatformView: NSObject, VLCMediaPlayerDelegate {

    let player: VLCMediaPlayer
    let nsView: NSView
    private let onEvent: ([String: Any]) -> Void

    init(url: String, options: [String: Any], onEvent: @escaping ([String: Any]) -> Void) {
        self.onEvent = onEvent
        nsView = NSView()
        nsView.wantsLayer = true
        nsView.layer?.backgroundColor = NSColor.black.cgColor

        let vlcOptions = VlcPlatformView.buildVlcOptions(from: options)
        player = VLCMediaPlayer(options: vlcOptions)

        super.init()

        player.delegate = self
        player.drawable = nsView

        // URL validity is pre-checked in the plugin's initialize() handler,
        // but guard here defensively to avoid a force-unwrap crash.
        guard let mediaURL = URL(string: url) else { return }
        let media = VLCMedia(url: mediaURL)
        let extraOptions = options["extraFFmpegOptions"] as? [String: String] ?? [:]
        for (key, value) in extraOptions {
            media.addOption(":\(key)=\(value)")
        }

        player.media = media
        player.play()
    }

    static func buildVlcOptions(from options: [String: Any]) -> [String] {
        var opts: [String] = []
        let transport = options["transport"] as? String ?? "tcp"
        if transport == "tcp" { opts.append("--rtsp-tcp") }
        let networkCaching = options["networkCaching"] as? Int ?? 300
        opts.append("--network-caching=\(networkCaching)")
        let hwAccel = options["hwAcceleration"] as? Bool ?? true
        if !hwAccel { opts.append("--avcodec-hw=none") }
        let videoCodec = options["videoCodec"] as? String ?? "auto"
        if videoCodec != "auto" { opts.append("--avcodec-codec=\(videoCodec)") }
        return opts
    }

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        let stateName: String
        switch player.state {
        case .opening, .buffering: stateName = "connecting"
        case .playing:             stateName = "playing"
        case .paused:              stateName = "paused"
        case .stopped, .ended:    stateName = "idle"
        case .error:               stateName = "error"
        @unknown default:          stateName = "idle"
        }
        var event: [String: Any] = ["type": "stateChanged", "state": stateName]
        if player.state == .error { event["error"] = "VLC media error" }
        onEvent(event)
    }

    func applyLiveOptions(_ options: [String: Any]) {
        if let nc = options["networkCaching"] as? Int {
            player.media?.addOption(":network-caching=\(nc)")
        }
        let extraOptions = options["extraFFmpegOptions"] as? [String: String] ?? [:]
        for (key, value) in extraOptions {
            player.media?.addOption(":\(key)=\(value)")
        }
    }
}

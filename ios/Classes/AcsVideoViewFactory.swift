import Flutter
import UIKit

/// Debug logging helper - only prints in DEBUG builds
@inline(__always)
private func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    NSLog("%@", message())
    #endif
}

/// Owns one stable container `UIView` per participant tile.
///
/// Responsibility: hand Flutter a persistent container the moment a tile mounts (so
/// there is always something to show), and let the plugin embed the participant's
/// rendered video view (sourced from `RemoteVideoRenderManager`) into that container
/// once a stream is available. This class owns ONLY containers — it never creates or
/// disposes renderers; the render manager is the sole renderer owner.
///
/// All methods must be called on the main thread.
final class ParticipantTileContainerRegistry {
    /// participantId (rawId) -> stable container view.
    private var containers: [String: UIView] = [:]

    /// Returns the stable container for a participant, creating an empty one on first
    /// request so the platform view always has something to display.
    func container(for participantId: String) -> UIView {
        dispatchPrecondition(condition: .onQueue(.main))
        if let existing = containers[participantId] {
            return existing
        }
        let container = UIView(frame: .zero)
        container.backgroundColor = .clear
        container.clipsToBounds = true
        containers[participantId] = container
        debugLog("[ACS][TileContainers] Created container for participant=\(participantId)")
        return container
    }

    /// Returns true if a container exists for the participant (its tile is mounted).
    func hasContainer(for participantId: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return containers[participantId] != nil
    }

    /// Embeds `view` as the sole subview of the participant's container, pinned to its
    /// edges. No-ops if the same view is already embedded. Any previous video view is
    /// removed first so a stream change swaps cleanly.
    func embed(_ view: UIView, for participantId: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let container = containers[participantId] else { return }
        if view.superview === container { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        // Request layout but do NOT force a synchronous layoutIfNeeded() here. This runs on
        // the reconcile triggered by a tile mounting; a synchronous layout pass on the
        // platform thread during a hybrid-composition platform-view mount can deadlock against
        // the raster thread (the 2nd-participant-join hard-freeze). The pinned-edge constraints
        // are already active, so the view sizes correctly on the next normal layout pass.
        container.setNeedsLayout()
    }

    /// Removes the embedded video view from a participant's container (stream gone),
    /// keeping the container so the tile can re-embed when video returns.
    func clearEmbedded(for participantId: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        containers[participantId]?.subviews.forEach { $0.removeFromSuperview() }
    }

    /// Removes a participant's container entirely (tile disposed by Flutter).
    func remove(_ participantId: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let container = containers.removeValue(forKey: participantId) else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        container.removeFromSuperview()
        debugLog("[ACS][TileContainers] Removed container for participant=\(participantId)")
    }

    /// Returns the participant ids that currently have a mounted tile.
    func mountedParticipantIds() -> [String] {
        dispatchPrecondition(condition: .onQueue(.main))
        return Array(containers.keys)
    }
}

/// Factory for the `acs_video_view` platform view.
///
/// Resolves three cases from the Flutter creation params:
/// * `viewKey == "localVideoView"` -> shared local preview container.
/// * `viewKey == "remoteVideoView"` with no `participantId` -> shared remote
///   container (single-remote full-screen path).
/// * `viewKey == "remoteVideoView"` with a `participantId` -> a dedicated
///   per-participant tile container; the plugin embeds the participant's rendered
///   video (from `RemoteVideoRenderManager`) into it. On dispose, the tile is removed.
class AcsVideoViewFactory: NSObject, FlutterPlatformViewFactory {
    private let viewManager: VideoViewManager
    /// Registry of per-participant tile containers for the grid path.
    private let containerRegistry: ParticipantTileContainerRegistry
    /// Invoked after a per-participant tile is created so the plugin can embed the
    /// participant's available video immediately.
    private let onParticipantViewCreated: (String) -> Void
    /// Invoked when a per-participant tile is disposed so the plugin can tear down the
    /// participant's renderer and container.
    private let onParticipantViewDisposed: (String) -> Void

    /// Creates the factory.
    /// - Parameters:
    ///   - viewManager: Shared local/remote container manager (single-remote path).
    ///   - containerRegistry: Registry owning per-participant tile containers.
    ///   - onParticipantViewCreated: Callback fired with a participantId right after
    ///     its tile is created, letting the plugin embed any available stream.
    ///   - onParticipantViewDisposed: Callback fired with a participantId when its tile
    ///     is disposed, letting the plugin release the renderer + container.
    init(
        viewManager: VideoViewManager,
        containerRegistry: ParticipantTileContainerRegistry,
        onParticipantViewCreated: @escaping (String) -> Void,
        onParticipantViewDisposed: @escaping (String) -> Void
    ) {
        self.viewManager = viewManager
        self.containerRegistry = containerRegistry
        self.onParticipantViewCreated = onParticipantViewCreated
        self.onParticipantViewDisposed = onParticipantViewDisposed
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        let params = args as? [String: Any]
        let key = params?["viewKey"] as? String ?? ""
        // Optional participant id selects the per-participant grid tile path.
        let participantId = (params?["participantId"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        debugLog("[ACS][VideoViewFactory] Creating platform view: key=\(key), participantId=\(participantId ?? "nil"), frame=\(frame), viewId=\(viewId)")
        // [ACSFREEZE] diagnostic: brackets native platform-view creation. If Dart logs
        // "PV initState" but this ENTER never prints, the freeze is in the Flutter engine
        // PlatformView create handshake before native runs.
        NSLog("[ACSFREEZE] iOS factory.create ENTER key=%@ participant=%@ main=%@",
              key, participantId ?? "nil", Thread.isMainThread ? "Y" : "N")
        defer { NSLog("[ACSFREEZE] iOS factory.create EXIT key=%@ participant=%@", key, participantId ?? "nil") }

        // Per-participant grid tile: return a dedicated container and let the plugin
        // embed the participant's rendered video if it is already available.
        if key == "remoteVideoView", let participantId = participantId {
            let container = containerRegistry.container(for: participantId)
            if frame != .zero {
                container.frame = frame
            }
            onParticipantViewCreated(participantId)
            return AcsPlatformView(
                view: container,
                viewKey: key,
                participantId: participantId,
                onDispose: onParticipantViewDisposed
            )
        }

        let view: UIView
        switch key {
        case "localVideoView":
            view = viewManager.localContainer
            debugLog("[ACS][VideoViewFactory] Returning localContainer: frame=\(view.frame), bounds=\(view.bounds)")
        case "remoteVideoView":
            view = viewManager.remoteContainer
            debugLog("[ACS][VideoViewFactory] Returning remoteContainer: frame=\(view.frame), bounds=\(view.bounds)")
        default:
            view = UIView(frame: frame)
            view.backgroundColor = .clear
            debugLog("[ACS][VideoViewFactory] Returning default view")
        }

        // CRITICAL: Set the initial frame from Flutter if provided
        // This ensures the view has proper size when first rendered
        if frame != .zero {
            view.frame = frame
            debugLog("[ACS][VideoViewFactory] Set view frame to: \(frame)")
        }

        return AcsPlatformView(view: view, viewKey: key)
    }
}

/// Custom platform view that handles frame updates and ensures proper rendering
private class AcsPlatformView: NSObject, FlutterPlatformView {
    private let embeddedView: UIView
    private let viewKey: String
    /// Set only for per-participant tiles; used to notify the plugin on `dispose()`.
    private let participantId: String?
    /// Callback fired on dispose for per-participant tiles (renderer + container teardown).
    private let onDispose: ((String) -> Void)?

    /// Creates a platform view wrapper.
    /// - Parameters:
    ///   - view: The embedded native view (shared container or participant tile).
    ///   - viewKey: The Flutter view key.
    ///   - participantId: Non-nil for a per-participant tile.
    ///   - onDispose: Fired with the participant id on teardown (per-participant tiles).
    init(
        view: UIView,
        viewKey: String,
        participantId: String? = nil,
        onDispose: ((String) -> Void)? = nil
    ) {
        embeddedView = view
        self.viewKey = viewKey
        self.participantId = participantId
        self.onDispose = onDispose
        super.init()

        // Ensure the view uses frame-based layout since Flutter will manage the frame
        // This is important for UiKitView integration
        embeddedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        debugLog("[ACS][AcsPlatformView] Created for key=\(viewKey), view.frame=\(view.frame)")
    }

    func view() -> UIView {
        // [ACSFREEZE] diagnostic: view() runs on the platform thread during the UiKitView
        // mount handshake — the #94524 latch point. A missing EXIT here = engine deadlock.
        NSLog("[ACSFREEZE] iOS AcsPlatformView.view() ENTER key=%@ main=%@",
              viewKey, Thread.isMainThread ? "Y" : "N")
        defer { NSLog("[ACSFREEZE] iOS AcsPlatformView.view() EXIT key=%@", viewKey) }
        // Request a layout pass but do NOT force a synchronous layoutIfNeeded() here.
        // Flutter calls view() on the platform thread while mounting this UiKitView; a
        // synchronous layout during a hybrid-composition mount can deadlock against the
        // raster thread and hard-freeze the app when a 2nd participant tile mounts. The
        // container is empty at this point anyway, so the forced layout bought nothing.
        embeddedView.setNeedsLayout()

        debugLog("[ACS][AcsPlatformView] view() called for key=\(viewKey), frame=\(embeddedView.frame), bounds=\(embeddedView.bounds)")
        return embeddedView
    }

    func dispose() {
        // [ACSFREEZE] diagnostic: platform-view teardown on DROP. The dispose handshake
        // (and the onDispose → renderer teardown) is a prime grid→single freeze suspect.
        NSLog("[ACSFREEZE] iOS AcsPlatformView.dispose ENTER key=%@ participant=%@ main=%@",
              viewKey, participantId ?? "nil", Thread.isMainThread ? "Y" : "N")
        defer { NSLog("[ACSFREEZE] iOS AcsPlatformView.dispose EXIT key=%@", viewKey) }
        debugLog("[ACS][AcsPlatformView] dispose() called for key=\(viewKey), participantId=\(participantId ?? "nil")")
        // Tear down the per-participant renderer + container when the tile is removed.
        if let participantId = participantId, let onDispose = onDispose {
            if Thread.isMainThread {
                onDispose(participantId)
            } else {
                DispatchQueue.main.async { onDispose(participantId) }
            }
        }
    }
}

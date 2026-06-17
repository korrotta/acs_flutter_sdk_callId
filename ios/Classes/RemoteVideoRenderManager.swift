import AzureCommunicationCalling
import UIKit

/// Debug logging helper - only prints in DEBUG builds.
@inline(__always)
private func renderManagerDebugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    NSLog("%@", message())
    #endif
}

/// Identity a remote video stream must expose for the render manager to key its
/// cache. Abstracted (rather than depending on the concrete ACS `RemoteVideoStream`)
/// so the cache/dispose logic is unit-testable without the ACS framework.
protocol RenderableVideoStream {
    /// Stable per-stream identifier used in the `participantId:streamId` cache key.
    var renderStreamId: Int { get }
}

extension RemoteVideoStream: RenderableVideoStream {
    var renderStreamId: Int { Int(id) }
}

/// A created renderer's displayable view plus its teardown. Abstracted so a fake
/// can stand in for the real ACS `VideoStreamRenderer` in tests.
protocol ManagedRendererHandle: AnyObject {
    /// The view that displays the decoded video frames.
    var view: UIView { get }
    /// Releases the underlying decoder session and detaches any delegate.
    func dispose()
}

/// Owns one renderer per `participantId:streamId` and reuses it.
///
/// Responsibility: this is the single source of truth for remote video rendering on
/// iOS. It serves BOTH the single-remote full-screen view and the multi-participant
/// grid tiles (single-remote is just a one-cell grid). For any given remote video
/// stream a renderer is created exactly once and cached; subsequent requests return
/// the existing view. This guarantees the ACS one-renderer-per-stream limit is never
/// violated, which removes the decoder-session contention that froze the call and the
/// renderer-takeover race that left late joiners spinning forever.
///
/// Lifecycle / invariants:
/// * `rendererView(participantId:stream:)` is a cache-hit-or-create accessor: a hit
///   returns the embedded `UIView`; a miss builds a renderer + view exactly once.
/// * `updateDisplayed([keys])` diffs the displayed set and disposes ONLY renderers no
///   longer shown, so off-screen tiles free their decoder session immediately.
/// * `disposeAll()` tears everything down on call cleanup (no leaks).
/// * On first painted frame the manager fires `onFirstFrame(participantId)` so the
///   owning tile can clear its connecting spinner.
///
/// Threading: every renderer create / dispose / view mutation runs on the main thread
/// (callers must already be on main; methods assert this). The first-frame callback is
/// hopped to main before invocation by the production renderer handle.
///
/// Testability: renderer creation is injected via `makeRenderer`. The production
/// convenience initializer wires the real ACS `VideoStreamRenderer`; tests inject a
/// fake factory so the cache and dispose logic can be exercised without ACS or a GPU.
final class RemoteVideoRenderManager {

    /// One cached renderer handle plus the originating identity.
    private struct RenderEntry {
        let handle: ManagedRendererHandle
        let streamId: Int
        /// Raw participant id this renderer belongs to.
        let participantId: String
    }

    /// Cache keyed by `"participantId:streamId"` (see `cacheKey`).
    private var entries: [String: RenderEntry] = [:]

    /// Fired (on the main thread) with the owning participant's raw id the first time
    /// that participant's renderer paints a frame. The plugin forwards this to Dart as
    /// the `participantVideoRendering` event so the tile can drop its spinner.
    private let onFirstFrame: (String) -> Void

    /// Builds a renderer handle for a stream, wiring `fire` to be invoked on the
    /// renderer's first painted frame. Returns nil on failure (caller may retry).
    private let makeRenderer:
        (_ stream: RenderableVideoStream, _ fire: @escaping () -> Void) -> ManagedRendererHandle?

    /// Designated initializer.
    /// - Parameters:
    ///   - onFirstFrame: invoked with a participant raw id when that participant's
    ///     renderer paints its first frame. Always called on main.
    ///   - makeRenderer: renderer factory (injected for testing).
    init(
        onFirstFrame: @escaping (String) -> Void,
        makeRenderer: @escaping (RenderableVideoStream, @escaping () -> Void) -> ManagedRendererHandle?
    ) {
        self.onFirstFrame = onFirstFrame
        self.makeRenderer = makeRenderer
    }

    /// Builds the `"participantId:streamId"` cache key.
    private func cacheKey(participantId: String, streamId: Int) -> String {
        return "\(participantId):\(streamId)"
    }

    /// Returns the rendered video view for a participant's stream, creating the
    /// renderer exactly once on a cache miss.
    ///
    /// - Returns: the embedded `UIView`, or nil if renderer creation failed (the
    ///   caller may retry on a later stream event or via a bounded reconcile retry).
    /// - Side effects: on a miss, creates and caches a renderer whose first-frame
    ///   callback forwards to `onFirstFrame`. Main-thread only.
    func rendererView(participantId: String, stream: RenderableVideoStream) -> UIView? {
        dispatchPrecondition(condition: .onQueue(.main))

        let streamId = stream.renderStreamId
        let key = cacheKey(participantId: participantId, streamId: streamId)

        // [ACSFREEZE] diagnostic: bracket the renderer accessor so a freeze inside the
        // create path is localizable. Unconditional NSLog so it shows regardless of
        // build config. Remove by grepping the [ACSFREEZE] tag.
        NSLog("[ACSFREEZE] iOS rendererView ENTER key=%@ cached=%@ main=%@",
              key, entries[key] != nil ? "Y" : "N", Thread.isMainThread ? "Y" : "N")

        // Cache hit: never build a second renderer for the same stream.
        if let entry = entries[key] {
            NSLog("[ACSFREEZE] iOS rendererView EXIT (cache hit) key=%@", key)
            return entry.handle.view
        }

        guard let handle = makeRenderer(stream, { [weak self] in
            self?.onFirstFrame(participantId)
        }) else {
            // Release-visible: a create failure (e.g. transient decoder-pool
            // exhaustion during a multi-participant join) leaves the tile blank, so
            // the caller must schedule a retry. Logged unconditionally so the failure
            // is diagnosable from production logs.
            NSLog("[ACS][RenderManager] Failed to create renderer for key=%@", key)
            return nil
        }

        entries[key] = RenderEntry(
            handle: handle,
            streamId: streamId,
            participantId: participantId
        )
        renderManagerDebugLog("[ACS][RenderManager] Created renderer for key=\(key)")
        NSLog("[ACSFREEZE] iOS rendererView EXIT (created) key=%@", key)
        return handle.view
    }

    /// Returns true if a renderer is currently cached for the participant/stream pair.
    func isRendering(participantId: String, streamId: Int) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return entries[cacheKey(participantId: participantId, streamId: streamId)] != nil
    }

    /// Disposes every renderer whose key is NOT in `displayedKeys`.
    ///
    /// Drives lazy render scoping: only on-screen tiles keep a decoder session. Each
    /// key is `"participantId:streamId"`. Main-thread only.
    func updateDisplayed(_ displayedKeys: [String]) {
        dispatchPrecondition(condition: .onQueue(.main))
        let keep = Set(displayedKeys)
        // Snapshot the keys to dispose BEFORE mutating: `disposeEntry` removes from
        // `entries`, and mutating a dictionary while iterating its `keys` view is a
        // runtime crash ("mutation during enumeration").
        let dead = entries.keys.filter { !keep.contains($0) }
        for key in dead {
            disposeEntry(forKey: key)
        }
    }

    /// Disposes the renderer for one participant/stream pair (e.g. a single stream
    /// went unavailable). Main-thread only.
    func disposeStream(participantId: String, streamId: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        disposeEntry(forKey: cacheKey(participantId: participantId, streamId: streamId))
    }

    /// Disposes the renderer for a single participant (all of its cached streams),
    /// e.g. when the participant leaves or their tile unmounts. Main-thread only.
    func disposeParticipant(_ participantId: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        let prefix = "\(participantId):"
        // Snapshot before mutating (disposeEntry removes from `entries`).
        let dead = entries.keys.filter { $0.hasPrefix(prefix) }
        for key in dead {
            disposeEntry(forKey: key)
        }
    }

    /// Tears down all cached renderers (call cleanup). Main-thread only.
    func disposeAll() {
        dispatchPrecondition(condition: .onQueue(.main))
        // Snapshot before mutating (disposeEntry removes from `entries`).
        for key in Array(entries.keys) {
            disposeEntry(forKey: key)
        }
    }

    /// Removes one cached entry and disposes its renderer so no decoder session leaks.
    private func disposeEntry(forKey key: String) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        entry.handle.dispose()
        renderManagerDebugLog("[ACS][RenderManager] Disposed renderer for key=\(key)")
    }
}

// MARK: - Production ACS wiring

extension RemoteVideoRenderManager {
    /// Real ACS renderer handle: owns a `VideoStreamRenderer` and a first-frame
    /// delegate that forwards exactly once to `fire`. Kept private to the production
    /// factory; tests inject their own `ManagedRendererHandle`.
    private final class AcsRendererHandle: NSObject, ManagedRendererHandle, RendererDelegate {
        let view: UIView
        private let renderer: VideoStreamRenderer
        private let fire: () -> Void
        private var didFire = false

        init(renderer: VideoStreamRenderer, view: UIView, fire: @escaping () -> Void) {
            self.renderer = renderer
            self.view = view
            self.fire = fire
            super.init()
            renderer.delegate = self
        }

        func dispose() {
            // [ACSFREEZE] diagnostic: bracket the decoder-session teardown — a freeze on
            // DROP (grid→single) most likely parks here in renderer.dispose() on main.
            NSLog("[ACSFREEZE] iOS RenderManager.handle.dispose ENTER main=%@",
                  Thread.isMainThread ? "Y" : "N")
            // Detach the rendered view from whatever container embedded it (tile or
            // shared full-screen), then release the decoder session. Matches the
            // pre-refactor teardown which removed the view before disposing.
            view.removeFromSuperview()
            renderer.delegate = nil
            renderer.dispose()
            NSLog("[ACSFREEZE] iOS RenderManager.handle.dispose EXIT")
        }

        func videoStreamRenderer(didRenderFirstFrame renderer: VideoStreamRenderer) {
            guard !didFire else { return }
            didFire = true
            if Thread.isMainThread {
                fire()
            } else {
                let fire = self.fire
                DispatchQueue.main.async { fire() }
            }
        }

        func videoStreamRenderer(didFailToStart renderer: VideoStreamRenderer) {
            renderManagerDebugLog("[ACS][RenderManager] Renderer failed to start")
        }
    }

    /// Production initializer: wires the real ACS `VideoStreamRenderer`. This is the
    /// ONLY place the manager touches the ACS renderer API.
    /// - Parameters:
    ///   - onFirstFrame: forwarded to clear the Dart connecting spinner on first paint.
    convenience init(onFirstFrame: @escaping (String) -> Void) {
        self.init(onFirstFrame: onFirstFrame, makeRenderer: { stream, fire in
            guard let stream = stream as? RemoteVideoStream else { return nil }
            do {
                // Both camera and screen-share render CONTENT-FIT (letterbox, never crop):
                // the whole frame is always visible, matching the prior shipped behaviour.
                // The SDK scalingMode AND the UIView contentMode must agree, or they fight;
                // `clipsToBounds` keeps the video inside the tile bounds.
                let options = CreateViewOptions(scalingMode: .fit)
                // [ACSFREEZE] diagnostic: the ACS renderer create + createView() run
                // synchronously on main and acquire a VideoToolbox decoder session — the
                // #1 freeze suspect. If ENTER prints with no EXIT, THIS is the deadlock.
                NSLog("[ACSFREEZE] iOS VideoStreamRenderer.createView ENTER stream=%d main=%@",
                      stream.renderStreamId, Thread.isMainThread ? "Y" : "N")
                let renderer = try VideoStreamRenderer(remoteVideoStream: stream)
                let view = try renderer.createView(withOptions: options)
                NSLog("[ACSFREEZE] iOS VideoStreamRenderer.createView EXIT stream=%d",
                      stream.renderStreamId)
                view.translatesAutoresizingMaskIntoConstraints = false
                view.contentMode = .scaleAspectFit
                view.clipsToBounds = true
                view.backgroundColor = .clear
                return AcsRendererHandle(renderer: renderer, view: view, fire: fire)
            } catch {
                NSLog("[ACS][RenderManager] Failed to create renderer: %@", error.localizedDescription)
                return nil
            }
        })
    }
}

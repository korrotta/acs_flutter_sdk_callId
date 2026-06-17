import AzureCommunicationCalling
import UIKit

/// Debug logging helper - only prints in DEBUG builds
@inline(__always)
private func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    NSLog("%@", message())
    #endif
}

/// Custom container view that properly propagates layout changes to its subviews
/// This is critical for Flutter platform view integration where frame updates come from Flutter
private class VideoContainerView: UIView {
    private let containerName: String

    init(name: String) {
        self.containerName = name
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        self.containerName = "unknown"
        super.init(coder: coder)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        debugLog("[ACS][VideoContainerView][\(containerName)] layoutSubviews called, frame=\(frame), bounds=\(bounds)")
        // Mark subviews as needing layout when our frame changes, but do NOT force a
        // synchronous `layoutIfNeeded()` here. This view is a Flutter-mounted platform view;
        // a synchronous layout pass on the platform thread during a hybrid-composition mount
        // can deadlock against the raster thread (the 2nd-participant-join hard-freeze). The
        // marked subviews resolve on the next normal layout pass.
        for subview in subviews {
            debugLog("[ACS][VideoContainerView][\(containerName)] Subview frame=\(subview.frame), bounds=\(subview.bounds)")
            subview.setNeedsLayout()
        }
    }

    override var frame: CGRect {
        didSet {
            if frame != oldValue {
                debugLog("[ACS][VideoContainerView][\(containerName)] frame changed from \(oldValue) to \(frame)")
                setNeedsLayout()
            }
        }
    }

    override var bounds: CGRect {
        didSet {
            if bounds != oldValue {
                debugLog("[ACS][VideoContainerView][\(containerName)] bounds changed from \(oldValue) to \(bounds)")
                setNeedsLayout()
            }
        }
    }
}

/// Manages local and remote video views for ACS calls on iOS.
/// All public methods must be called from the main thread.
class VideoViewManager {
    let localContainer: UIView = VideoContainerView(name: "local")
    let remoteContainer: UIView = VideoContainerView(name: "remote")

    private var previewRenderer: VideoStreamRenderer?
    private var previewView: UIView?

    init() {
        localContainer.backgroundColor = .clear
        localContainer.clipsToBounds = true

        remoteContainer.backgroundColor = .clear
        remoteContainer.clipsToBounds = true
    }

    func showLocalPreview(stream: LocalVideoStream) throws {
        dispatchPrecondition(condition: .onQueue(.main))

        debugLog("[ACS][VideoViewManager] showLocalPreview called")

        if previewRenderer != nil {
            debugLog("[ACS][VideoViewManager] showLocalPreview - previewRenderer already exists, returning")
            return
        }

        let renderer = try VideoStreamRenderer(localVideoStream: stream)
        let view = try renderer.createView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true

        localContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: localContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: localContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: localContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: localContainer.bottomAnchor),
        ])

        previewRenderer = renderer
        previewView = view

        // Request layout only; never force a synchronous pass on the platform thread (see
        // VideoContainerView.layoutSubviews — avoids the hybrid-composition mount deadlock).
        localContainer.setNeedsLayout()

        debugLog("[ACS][VideoViewManager] showLocalPreview - view added, frame=\(view.frame)")
    }

    func clearLocalPreview() {
        dispatchPrecondition(condition: .onQueue(.main))

        previewView?.removeFromSuperview()
        previewView = nil
        previewRenderer?.dispose()
        previewRenderer = nil
    }

    func addRemote(view: UIView, streamId: Int) {
        dispatchPrecondition(condition: .onQueue(.main))

        // [ACSFREEZE] diagnostic: shared single-feed attach (single-remote / takeover path).
        NSLog("[ACSFREEZE] iOS VideoViewManager.addRemote ENTER streamId=%d main=%@",
              streamId, Thread.isMainThread ? "Y" : "N")
        defer { NSLog("[ACSFREEZE] iOS VideoViewManager.addRemote EXIT streamId=%d", streamId) }
        debugLog("[ACS][VideoViewManager] addRemote called for streamId=\(streamId)")
        debugLog("[ACS][VideoViewManager] addRemote - remoteContainer.frame=\(remoteContainer.frame)")

        // Remove any existing instance for this stream ID before re-adding
        removeRemote(streamId: streamId)

        // Detach from any previous parent to avoid stale layout state when reusing the same view
        view.removeFromSuperview()

        view.translatesAutoresizingMaskIntoConstraints = false
        view.tag = streamId
        view.clipsToBounds = true
        view.backgroundColor = .clear
        view.isHidden = false
        view.alpha = 1.0
        view.isOpaque = true

        // Embed the renderer view DIRECTLY into remoteContainer, pinned edge-to-edge —
        // identical to showLocalPreview (which paints reliably). remoteContainer IS the
        // Flutter-mounted platform view, so the renderer view is in a real, on-screen,
        // sized window the moment Flutter lays the platform view out. The previous design
        // nested an intermediate UIStackView that resolved to a ZERO frame at attach time,
        // so the VideoStreamRenderer started its decode surface against a zero-sized view
        // and never painted (the "remote tile black until the sender toggles camera" bug).
        // Single-remote only ever shows one stream, so no multi-arranged-subview stack is
        // needed.
        remoteContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: remoteContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: remoteContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: remoteContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: remoteContainer.bottomAnchor),
        ])

        // Request layout only; never force a synchronous pass on the platform thread (see
        // VideoContainerView.layoutSubviews — avoids the hybrid-composition mount deadlock).
        remoteContainer.setNeedsLayout()
        debugLog("[ACS][VideoViewManager] addRemote - layout requested: view.frame=\(view.frame)")
    }

    func removeRemote(streamId: Int) {
        dispatchPrecondition(condition: .onQueue(.main))

        // [ACSFREEZE] diagnostic: shared single-feed detach (DROP / takeover path).
        NSLog("[ACSFREEZE] iOS VideoViewManager.removeRemote ENTER streamId=%d main=%@",
              streamId, Thread.isMainThread ? "Y" : "N")
        defer { NSLog("[ACSFREEZE] iOS VideoViewManager.removeRemote EXIT streamId=%d", streamId) }
        for subview in remoteContainer.subviews where subview.tag == streamId {
            subview.removeFromSuperview()
        }
    }

    func removeAllRemote() {
        dispatchPrecondition(condition: .onQueue(.main))

        for subview in remoteContainer.subviews {
            subview.removeFromSuperview()
        }
    }

    /// Forces a layout update on all video views.
    func forceLayoutUpdate() {
        dispatchPrecondition(condition: .onQueue(.main))

        debugLog("[ACS][VideoViewManager] forceLayoutUpdate called")
        debugLog("[ACS][VideoViewManager] forceLayoutUpdate - remoteContainer.frame=\(remoteContainer.frame)")
        debugLog("[ACS][VideoViewManager] forceLayoutUpdate - subviews.count=\(remoteContainer.subviews.count)")

        // Request layout/redisplay only. NO synchronous `layoutIfNeeded()` anywhere here:
        // these containers are Flutter-mounted platform views, and a forced layout pass on
        // the platform thread can deadlock against the raster thread during a tile mount
        // (the 2nd-participant-join hard-freeze). Marked views resolve on the next pass.
        remoteContainer.setNeedsLayout()
        localContainer.setNeedsLayout()

        for (index, subview) in remoteContainer.subviews.enumerated() {
            debugLog("[ACS][VideoViewManager] forceLayoutUpdate - subview[\(index)] frame=\(subview.frame), isHidden=\(subview.isHidden)")
            subview.setNeedsLayout()
            subview.setNeedsDisplay()
            subview.isHidden = false
            subview.alpha = 1.0

            if let sublayers = subview.layer.sublayers {
                for sublayer in sublayers {
                    sublayer.setNeedsLayout()
                    sublayer.setNeedsDisplay()
                }
            }
        }

        for subview in localContainer.subviews {
            subview.setNeedsLayout()
            subview.setNeedsDisplay()
        }

        debugLog("[ACS][VideoViewManager] forceLayoutUpdate completed")
    }
}

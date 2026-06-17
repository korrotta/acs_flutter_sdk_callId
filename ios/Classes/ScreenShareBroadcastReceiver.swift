import CoreVideo
import Darwin
import Foundation

/// SDK-side receiver for device-screen frames produced by an in-app **ReplayKit
/// Broadcast Upload Extension**.
///
/// This file OWNS the App Group IPC contract between the broadcast extension and
/// the host app's SDK. It does NOT own the extension itself — the extension
/// (`SampleHandler` / `RPBroadcastSampleHandler`) lives in the application and is
/// scaffolded separately. Both sides MUST agree on:
///
/// * **App Group id** — `ScreenShareIPC.appGroupId` (overridable, see below).
/// * **Transport** — a single memory-mapped file in the App Group container plus a
///   Darwin notification fired on every new frame.
/// * **Pixel format** — `kCVPixelFormatType_32BGRA` (BGRA), matching the ACS
///   `ScreenShareOutgoingVideoStream` format (`.bgrx`) the frame is fed into.
///
/// ## IPC frame contract (extension MUST follow exactly)
/// The shared file layout is: a fixed 32-byte header followed by tightly packed
/// BGRA pixels (no per-row padding; `bytesPerRow == width * 4`).
///
/// ```
/// offset  size  field
/// 0       4     magic   = 0x41435346 ("ACSF"), big-endian
/// 4       4     width   (UInt32, little-endian)
/// 8       4     height  (UInt32, little-endian)
/// 12      4     pixelFormat (UInt32, little-endian) = 'BGRA' fourCC
/// 16      8     frameSequence (UInt64, little-endian, monotonically increasing)
/// 24      8     reserved (0)
/// 32      ...   width*height*4 bytes of BGRA pixel data
/// ```
///
/// The extension writes a frame (header + pixels), then posts the Darwin
/// notification `ScreenShareIPC.frameNotificationName`. The receiver reads the
/// most recent frame on notification (latest-wins; intermediate frames may be
/// dropped, which is acceptable for screen share). Target rate: <= 15 fps; the
/// extension should throttle to avoid overrunning the single-slot buffer.
enum ScreenShareIPC {
    /// fourCC magic identifying a valid frame header ("ACSF").
    static let magic: UInt32 = 0x41435346

    /// Header size in bytes preceding the BGRA pixel payload.
    static let headerSize = 32

    /// Default App Group identifier shared by the host app and the broadcast
    /// extension. Apps SHOULD override this via the host app `Info.plist` key
    /// `ACSScreenShareAppGroup` so it matches their provisioning profile / app id;
    /// a hardcoded group that is not in the app's entitlements fails silently.
    static let defaultAppGroupId = "group.com.burhanrabbani.acs.screenshare"

    /// Info.plist key the host app can set to override `defaultAppGroupId`.
    static let appGroupInfoPlistKey = "ACSScreenShareAppGroup"

    /// Filename of the shared memory-mapped frame buffer inside the App Group container.
    static let frameFileName = "acs_screenshare_frame.bin"

    /// Darwin notification name posted by the extension after each frame write.
    static let frameNotificationName = "com.burhanrabbani.acs.screenshare.frame"

    /// Resolves the effective App Group id: the `Info.plist` override if present
    /// and non-empty, otherwise `defaultAppGroupId`.
    /// - Returns: The App Group identifier to use for the shared container.
    static func resolveAppGroupId() -> String {
        if let override = Bundle.main.object(forInfoDictionaryKey: appGroupInfoPlistKey) as? String,
           !override.isEmpty {
            return override
        }
        return defaultAppGroupId
    }

    /// Computes the URL of the shared frame file inside the App Group container.
    /// - Returns: The file URL, or `nil` if the App Group is not configured/entitled.
    static func frameFileURL() -> URL? {
        let group = resolveAppGroupId()
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group) else {
            return nil
        }
        return container.appendingPathComponent(frameFileName)
    }
}

/// Reads device-screen frames written by the broadcast extension and forwards each
/// decoded BGRA frame to a sink (the plugin's `sendScreenFrame(_:)`).
///
/// Lifecycle: create, call `start(onFrame:)` to begin listening for the Darwin
/// frame notification, and `stop()` to tear down. All frame decoding happens on a
/// private serial queue; the sink is invoked on that queue.
final class ScreenShareBroadcastReceiver {
    /// Serial queue on which the shared file is read and frames decoded.
    private let queue = DispatchQueue(label: "acs_flutter_sdk.screen_share.broadcast")

    /// Sink invoked with each decoded frame's pixel buffer. Set in `start`.
    private var onFrame: ((CVPixelBuffer) -> Void)?

    /// True between `start()` and `stop()`.
    private var isListening = false

    /// Last frame sequence number consumed, used to skip re-reading the same frame.
    private var lastSequence: UInt64 = 0

    /// Begins listening for broadcast-extension frames.
    ///
    /// Registers a Darwin notification observer; on each notification the latest
    /// frame is read from the shared file and forwarded to `onFrame`.
    /// - Parameter onFrame: Callback receiving each decoded BGRA `CVPixelBuffer`.
    func start(onFrame: @escaping (CVPixelBuffer) -> Void) {
        queue.async { [weak self] in
            guard let self = self, !self.isListening else { return }
            self.onFrame = onFrame
            self.isListening = true
            self.lastSequence = 0

            // Register for the cross-process Darwin notification. We pass `self`
            // unretained as the observer token; `stop()` removes the observer.
            let observer = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                observer,
                { _, observer, _, _, _ in
                    guard let observer = observer else { return }
                    let receiver = Unmanaged<ScreenShareBroadcastReceiver>
                        .fromOpaque(observer).takeUnretainedValue()
                    receiver.handleFrameNotification()
                },
                ScreenShareIPC.frameNotificationName as CFString,
                nil,
                .deliverImmediately
            )
        }
    }

    /// Stops listening and releases resources. Safe to call multiple times.
    func stop() {
        queue.async { [weak self] in
            guard let self = self, self.isListening else { return }
            self.isListening = false
            self.onFrame = nil
            let observer = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                observer,
                CFNotificationName(ScreenShareIPC.frameNotificationName as CFString),
                nil
            )
        }
    }

    /// Darwin-notification entry point. Hops to the private queue to read+decode.
    private func handleFrameNotification() {
        queue.async { [weak self] in
            self?.readLatestFrame()
        }
    }

    /// Reads the most recent frame from the shared file, validates the header,
    /// builds a BGRA `CVPixelBuffer`, and forwards it to the sink.
    ///
    /// Latest-wins: if the on-disk sequence equals the last consumed sequence the
    /// read is skipped. Any malformed header or unreadable file is ignored (the
    /// next notification will retry); this is intentional best-effort behaviour for
    /// a lossy screen-share transport.
    private func readLatestFrame() {
        guard isListening, let onFrame = onFrame else { return }
        guard let url = ScreenShareIPC.frameFileURL() else { return }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        guard data.count >= ScreenShareIPC.headerSize else { return }

        // Parse header. Multi-byte numeric fields are little-endian per the contract.
        let magic = data.readUInt32BE(at: 0)
        guard magic == ScreenShareIPC.magic else { return }
        let width = Int(data.readUInt32LE(at: 4))
        let height = Int(data.readUInt32LE(at: 8))
        let sequence = data.readUInt64LE(at: 16)

        guard width > 0, height > 0 else { return }
        guard sequence != lastSequence else { return }

        let expectedPixelBytes = width * height * 4
        guard data.count >= ScreenShareIPC.headerSize + expectedPixelBytes else { return }
        lastSequence = sequence

        // Build a BGRA pixel buffer from the tightly-packed pixel payload.
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let destBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let srcBytesPerRow = width * 4

        // Copy row-by-row to honour the destination buffer's stride, which may be
        // padded by CoreVideo even though the source is tightly packed.
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let srcBase = raw.baseAddress else { return }
            let pixelStart = srcBase.advanced(by: ScreenShareIPC.headerSize)
            for row in 0..<height {
                memcpy(
                    base.advanced(by: row * destBytesPerRow),
                    pixelStart.advanced(by: row * srcBytesPerRow),
                    srcBytesPerRow)
            }
        }

        onFrame(buffer)
    }
}

/// Little/big-endian fixed-width readers over `Data` for parsing the IPC header.
private extension Data {
    /// Reads a big-endian `UInt32` at the given byte offset.
    func readUInt32BE(at offset: Int) -> UInt32 {
        let b = self
        return (UInt32(b[startIndex + offset]) << 24)
            | (UInt32(b[startIndex + offset + 1]) << 16)
            | (UInt32(b[startIndex + offset + 2]) << 8)
            | UInt32(b[startIndex + offset + 3])
    }

    /// Reads a little-endian `UInt32` at the given byte offset.
    func readUInt32LE(at offset: Int) -> UInt32 {
        let b = self
        return UInt32(b[startIndex + offset])
            | (UInt32(b[startIndex + offset + 1]) << 8)
            | (UInt32(b[startIndex + offset + 2]) << 16)
            | (UInt32(b[startIndex + offset + 3]) << 24)
    }

    /// Reads a little-endian `UInt64` at the given byte offset.
    func readUInt64LE(at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(self[startIndex + offset + i]) << (8 * i)
        }
        return value
    }
}

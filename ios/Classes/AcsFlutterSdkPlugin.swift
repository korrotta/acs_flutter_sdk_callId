import AVFoundation
import Flutter
import UIKit
import ReplayKit
import AzureCommunicationCommon
import AzureCommunicationCalling
// OPTIMIZATION: Chat removed - import AzureCommunicationChat

public class AcsFlutterSdkPlugin: NSObject, FlutterPlugin, CallDelegate, RemoteParticipantDelegate, CallAgentDelegate, CapabilitiesCallFeatureDelegate {
    private var channel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    /// Participant raw ids whose first video frame painted while the Dart event
    /// channel was not yet subscribed (`eventSink == nil`). `participantVideoRendering`
    /// is a one-shot signal, so on a cold connect the renderer can paint before Dart
    /// has called `onListen`; without this buffer the event is lost and the tile spins
    /// for the full fallback window. Drained (re-emitted) the moment a sink attaches.
    /// Main-thread only — mutated solely from the event emit / onListen paths.
    private var pendingFirstFrameIds: Set<String> = []

    /// Coalescing latch for `reconcileAllParticipantTiles`. ACS fires a burst of
    /// participant/stream delegate callbacks during a multi-party join; each previously
    /// scheduled a full all-tiles reconcile (N tiles × O(participants×streams) each),
    /// and the resulting per-event fan-out enqueued main-queue work faster than it
    /// drained — a livelock that froze the UI at 3+ participants. With this latch a
    /// burst collapses into a SINGLE trailing reconcile pass. Touched on main only.
    private var reconcileAllScheduled = false
    /// Per-participant coalescing latch. The create path (onParticipantViewCreated →
    /// reconcileParticipantTile) and the per-stream delegate paths all call
    /// reconcileParticipantTile DIRECTLY, bypassing `reconcileAllScheduled`. Without this,
    /// a 2-participant join burst fans out into N synchronous `VideoStreamRenderer.createView`
    /// calls on the platform thread — the 2nd-join hard-freeze. Ids in-flight here collapse a
    /// burst into ONE trailing reconcile per participant. Touched on main only.
    private var reconcilingTiles: Set<String> = []
    /// Trailing window over which duplicate per-tile reconcile requests are coalesced.
    private static let tileReconcileCoalesceWindow: TimeInterval = 0.12
    private var capabilitiesEventSink: FlutterEventSink?
    private var incomingCallEventSink: FlutterEventSink?
    private var callFeaturesEventSink: FlutterEventSink?
    private var captionsEventSink: FlutterEventSink?
    private var realTimeTextEventSink: FlutterEventSink?
    private var dataChannelEventSink: FlutterEventSink?
    private var mediaStatisticsEventSink: FlutterEventSink?
    private var diagnosticsEventSink: FlutterEventSink?

    private let callClient = CallClient()
    private let viewManager = VideoViewManager()
    /// Single owner of every remote `VideoStreamRenderer` (one per participant:stream,
    /// cached and reused). Serves both the single-remote full-screen view and the grid
    /// tiles. Lazily built so the first-frame callback can forward to `eventSink`.
    private lazy var renderManager: RemoteVideoRenderManager = {
        RemoteVideoRenderManager(onFirstFrame: { [weak self] participantId in
            self?.emitParticipantVideoRendering(participantId: participantId)
        })
    }()
    /// Registry of per-participant grid tile containers (containers only; the render
    /// manager owns all renderers).
    private let tileContainers = ParticipantTileContainerRegistry()

    private var tokenCredential: CommunicationTokenCredential?
    private var callAgent: CallAgent?
    private var deviceManager: DeviceManager?
    private var call: Call?
    private var localVideoStream: LocalVideoStream?
    private var currentCamera: VideoDeviceInfo?
    private var activeVideoEffect: VideoEffect?
    private var screenShareStream: ScreenShareOutgoingVideoStream?
    private var screenShareFormat: VideoStreamFormat?
    private var screenShareActive = false
    private let screenShareQueue = DispatchQueue(label: "acs_flutter_sdk.screen_share")
    private var lastScreenShareFrameTime: CFTimeInterval = 0
    /// Receiver for device-screen frames from the Broadcast Upload Extension.
    /// Non-nil only while the default (broadcast) screen-share path is active.
    private var screenShareBroadcastReceiver: ScreenShareBroadcastReceiver?
    /// True when the active screen share uses the in-app `RPScreenRecorder`
    /// fallback (captures only the app's own UI) rather than the broadcast path.
    private var screenShareUsingInAppFallback = false
    private var incomingCall: IncomingCall?
    private var callCaptions: CallCaptions?
    private var capabilitiesFeature: CapabilitiesCallFeature?
    private var recordingFeature: RecordingCallFeature?
    private var transcriptionFeature: TranscriptionCallFeature?
    private var dominantSpeakersFeature: DominantSpeakersCallFeature?
    private var raiseHandFeature: RaiseHandCallFeature?
    private var spotlightFeature: SpotlightCallFeature?
    private var realTimeTextFeature: RealTimeTextCallFeature?
    private var mediaStatisticsFeature: MediaStatisticsCallFeature?
    private var dataChannelFeature: DataChannelCallFeature?
    private var localUserDiagnosticsFeature: LocalUserDiagnosticsCallFeature?
    private var dataChannelSenders: [Int: DataChannelSender] = [:]
    private var dataChannelReceivers: [Int: DataChannelReceiver] = [:]
    private var pendingSurveys: [String: CallSurvey] = [:]

    // OPTIMIZATION: Chat removed - private var chatClient: ChatClient?
    // OPTIMIZATION: Chat removed - private var chatThreadClient: ChatThreadClient?

    private func logError(_ context: String, _ error: Error) {
        #if DEBUG
        debugLog("[ACS][Error][\(context)] \(error.localizedDescription)")
        #endif
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        NSLog("%@", message)
        #endif
    }

    private func safeHandle(_ context: String, result: FlutterResult? = nil, _ block: () throws -> Void) {
        do {
            try block()
        } catch {
            logError(context, error)
            result?(FlutterError(code: "UNEXPECTED_ERROR", message: "Error in \(context): \(error.localizedDescription)", details: nil))
        }
    }

    deinit {
        cleanupCallResources()
        callAgent?.delegate = nil
        callAgent = nil
        deviceManager = nil
        tokenCredential = nil
        eventSink = nil
        capabilitiesEventSink = nil
        incomingCallEventSink = nil
        callFeaturesEventSink = nil
        captionsEventSink = nil
        realTimeTextEventSink = nil
        dataChannelEventSink = nil
        mediaStatisticsEventSink = nil
        diagnosticsEventSink = nil
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "acs_flutter_sdk", binaryMessenger: registrar.messenger())
        let instance = AcsFlutterSdkPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.register(
            AcsVideoViewFactory(
                viewManager: instance.viewManager,
                containerRegistry: instance.tileContainers,
                // When a per-participant tile mounts, reconcile that participant's
                // current stream so an already-available stream renders immediately.
                onParticipantViewCreated: { [weak instance] participantId in
                    instance?.reconcileParticipantTile(participantId: participantId)
                },
                // When a tile unmounts, release that participant's renderer + container.
                onParticipantViewDisposed: { [weak instance] participantId in
                    instance?.disposeParticipantTile(participantId: participantId)
                }
            ),
            withId: "acs_video_view"
        )
        let eventChannel = FlutterEventChannel(name: "acs_flutter_sdk/events", binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
        let capabilitiesChannel = FlutterEventChannel(name: "acs_flutter_sdk/capabilities", binaryMessenger: registrar.messenger())
        capabilitiesChannel.setStreamHandler(EventSinkHandler { sink in
            instance.capabilitiesEventSink = sink
        })
        let incomingCallChannel = FlutterEventChannel(name: "acs_flutter_sdk/incoming_calls", binaryMessenger: registrar.messenger())
        incomingCallChannel.setStreamHandler(EventSinkHandler { sink in
            instance.incomingCallEventSink = sink
        })
        let callFeaturesChannel = FlutterEventChannel(name: "acs_flutter_sdk/call_features", binaryMessenger: registrar.messenger())
        callFeaturesChannel.setStreamHandler(EventSinkHandler { sink in
            instance.callFeaturesEventSink = sink
        })
        let captionsChannel = FlutterEventChannel(name: "acs_flutter_sdk/captions", binaryMessenger: registrar.messenger())
        captionsChannel.setStreamHandler(EventSinkHandler { sink in
            instance.captionsEventSink = sink
        })
        let realTimeTextChannel = FlutterEventChannel(name: "acs_flutter_sdk/real_time_text", binaryMessenger: registrar.messenger())
        realTimeTextChannel.setStreamHandler(EventSinkHandler { sink in
            instance.realTimeTextEventSink = sink
        })
        let dataChannel = FlutterEventChannel(name: "acs_flutter_sdk/data_channel", binaryMessenger: registrar.messenger())
        dataChannel.setStreamHandler(EventSinkHandler { sink in
            instance.dataChannelEventSink = sink
        })
        let mediaStatisticsChannel = FlutterEventChannel(name: "acs_flutter_sdk/media_statistics", binaryMessenger: registrar.messenger())
        mediaStatisticsChannel.setStreamHandler(EventSinkHandler { sink in
            instance.mediaStatisticsEventSink = sink
        })
        let diagnosticsChannel = FlutterEventChannel(name: "acs_flutter_sdk/diagnostics", binaryMessenger: registrar.messenger())
        diagnosticsChannel.setStreamHandler(EventSinkHandler { sink in
            instance.diagnosticsEventSink = sink
        })
        AcsUiLibraryPlugin.register(with: registrar)
        instance.channel = channel
        instance.eventChannel = eventChannel
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        safeHandle("handle:\(call.method)", result: result) {
            switch call.method {
            case "getPlatformVersion":
                result("iOS \(UIDevice.current.systemVersion)")

            case "initializeIdentity":
                initializeIdentity(args: args, result: result)

            case "initializeCalling":
                initializeCalling(args: args, result: result)
            case "requestPermissions":
                requestPermissions(result: result)
            case "startCall":
                startCall(args: args, result: result)
            case "joinCall":
                joinCall(args: args, result: result)
            case "endCall":
                endCall(result: result)
            case "muteAudio":
                muteAudio(result: result)
            case "unmuteAudio":
                unmuteAudio(result: result)
            case "startVideo":
                startVideo(result: result)
            case "stopVideo":
                stopVideo(result: result)
            case "switchCamera":
                switchCamera(result: result)
            case "joinTeamsMeeting":
                joinTeamsMeeting(args: args, result: result)
            case "addParticipants":
                addParticipants(args: args, result: result)
            case "removeParticipants":
                removeParticipants(args: args, result: result)
            case "startCaptions":
                startCaptions(args: args, result: result)
            case "stopCaptions":
                stopCaptions(result: result)
            case "setSpokenLanguage":
                setSpokenLanguage(args: args, result: result)
            case "setCaptionLanguage":
                setCaptionLanguage(args: args, result: result)
            case "getCapabilities":
                getCapabilities(result: result)
            case "acceptIncomingCall":
                acceptIncomingCall(args: args, result: result)
            case "rejectIncomingCall":
                rejectIncomingCall(result: result)
            case "registerPushNotifications":
                registerPushNotifications(args: args, result: result)
            case "unregisterPushNotifications":
                unregisterPushNotifications(result: result)
            case "handlePushNotification":
                handlePushNotification(args: args, result: result)
            case "isRecordingActive":
                isRecordingActive(result: result)
            case "isTranscriptionActive":
                isTranscriptionActive(result: result)
            case "getDominantSpeakers":
                getDominantSpeakers(result: result)
            case "raiseHand":
                raiseHand(result: result)
            case "lowerHand":
                lowerHand(result: result)
            case "lowerAllHands":
                lowerAllHands(result: result)
            case "lowerHands":
                lowerHands(args: args, result: result)
            case "getRaisedHands":
                getRaisedHands(result: result)
            case "getSpotlightedParticipants":
                getSpotlightedParticipants(result: result)
            case "getMaxSpotlightedParticipants":
                getMaxSpotlightedParticipants(result: result)
            case "spotlightParticipants":
                spotlightParticipants(args: args, result: result)
            case "cancelSpotlights":
                cancelSpotlights(args: args, result: result)
            case "cancelAllSpotlights":
                cancelAllSpotlights(result: result)
            case "sendRealTimeText":
                sendRealTimeText(args: args, result: result)
            case "getCaptionsState":
                getCaptionsState(result: result)
            case "setMediaStatisticsReportInterval":
                setMediaStatisticsReportInterval(args: args, result: result)
            case "getMediaStatisticsReportInterval":
                getMediaStatisticsReportInterval(result: result)
            case "getLatestDiagnostics":
                getLatestDiagnostics(result: result)
            case "createDataChannelSender":
                createDataChannelSender(args: args, result: result)
            case "sendDataChannelMessage":
                sendDataChannelMessage(args: args, result: result)
            case "closeDataChannelSender":
                closeDataChannelSender(args: args, result: result)
            case "setDataChannelParticipants":
                setDataChannelParticipants(args: args, result: result)
            case "startSurvey":
                startSurvey(result: result)
            case "submitSurvey":
                submitSurvey(args: args, result: result)
            case "discardSurvey":
                discardSurvey(args: args, result: result)
            case "enableBackgroundBlur":
                enableBackgroundBlur(result: result)
            case "enableBackgroundReplacement":
                enableBackgroundReplacement(args: args, result: result)
            case "disableVideoEffects":
                disableVideoEffects(result: result)
            case "muteIncomingAudio":
                muteIncomingAudio(result: result)
            case "unmuteIncomingAudio":
                unmuteIncomingAudio(result: result)
            case "muteAllRemoteParticipants":
                muteAllRemoteParticipants(result: result)
            case "admitLobbyParticipants":
                admitLobbyParticipants(args: args, result: result)
            case "admitAllFromLobby":
                admitAllFromLobby(result: result)
            case "rejectLobbyParticipant":
                rejectLobbyParticipant(args: args, result: result)
            case "getLobbyParticipants":
                getLobbyParticipants(result: result)
            case "getRemoteParticipants":
                getRemoteParticipants(result: result)
            case "getRemoteParticipantStates":
                getRemoteParticipantStates(result: result)
            case "holdCall":
                holdCall(result: result)
            case "resumeCall":
                resumeCall(result: result)
            case "transferCall":
                transferCall(args: args, result: result)
            case "startScreenShare":
                startScreenShare(result: result)
            case "stopScreenShare":
                stopScreenShare(result: result)
            case "listCameras":
                listCameras(result: result)
            case "setCamera":
                setCamera(args: args, result: result)
            case "hasRemoteVideo":
                hasRemoteVideo(result: result)
            case "isInLobby":
                isInLobby(result: result)

            case "createUser", "getToken", "revokeToken":
                result(FlutterError(
                    code: "NOT_IMPLEMENTED",
                    message: "Identity management should be implemented on your backend.",
                    details: nil
                ))

            // OPTIMIZATION: Chat feature removed - only calling is supported
            case "initializeChat", "createChatThread", "joinChatThread", "sendMessage", "getMessages", "sendTypingNotification":
                result(FlutterError(
                    code: "NOT_SUPPORTED",
                    message: "Chat feature has been removed. This SDK only supports calling.",
                    details: nil
                ))

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func getRemoteParticipantStates(result: FlutterResult) {
        guard let participants = call?.remoteParticipants else {
            result([])
            return
        }

        let list: [[String: Any]] = participants.map { serialize(participant: $0) }
        result(list)
    }

    private func getCapabilities(result: FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.capabilities)
        let list: [[String: Any]] = feature.capabilities.map { cap in
            [
                "type": String(describing: cap.type),
                "isAllowed": cap.isAllowed,
                "reason": String(describing: cap.reason)
            ]
        }
        result(list)
    }

    private func acceptIncomingCall(args: [String: Any], result: @escaping FlutterResult) {
        guard let incoming = incomingCall else {
            result(FlutterError(code: "NO_INCOMING_CALL", message: "No incoming call to accept", details: nil))
            return
        }

        let withVideo = args["withVideo"] as? Bool ?? false
        let accept: (LocalVideoStream?) -> Void = { stream in
            let options = AcceptCallOptions()
            if let stream = stream {
                options.videoOptions = VideoOptions(localVideoStreams: [stream])
            }

            incoming.accept(options: options, completionHandler: { [weak self] call, error in
                DispatchQueue.main.async {
                    if let error = error {
                        result(FlutterError(code: "ACCEPT_FAILED", message: error.localizedDescription, details: nil))
                        return
                    }
                    if let call = call {
                        self?.attachCall(call)
                    }
                    self?.incomingCall = nil
                    result(nil)
                }
            })
        }

        if withVideo {
            ensureLocalVideoStream { stream, error in
                if let error = error {
                    result(FlutterError(code: "VIDEO_UNAVAILABLE", message: error.localizedDescription, details: nil))
                    return
                }
                guard let stream = stream else {
                    result(FlutterError(code: "VIDEO_UNAVAILABLE", message: "Unable to access camera", details: nil))
                    return
                }
                DispatchQueue.main.async {
                    try? self.viewManager.showLocalPreview(stream: stream)
                    accept(stream)
                }
            }
        } else {
            accept(nil)
        }
    }

    private func rejectIncomingCall(result: @escaping FlutterResult) {
        guard let incoming = incomingCall else {
            result(FlutterError(code: "NO_INCOMING_CALL", message: "No incoming call to reject", details: nil))
            return
        }
        incoming.reject { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "REJECT_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    self?.incomingCall = nil
                    result(nil)
                }
            }
        }
    }

    private func registerPushNotifications(args: [String: Any], result: @escaping FlutterResult) {
        guard let agent = callAgent else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Call agent not initialized", details: nil))
            return
        }

        if let tokenData = args["token"] as? FlutterStandardTypedData {
            agent.registerPushNotifications(deviceToken: tokenData.data) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        result(FlutterError(code: "PUSH_REGISTER_FAILED", message: error.localizedDescription, details: nil))
                    } else {
                        result(nil)
                    }
                }
            }
            return
        }

        guard let tokenString = args["token"] as? String, !tokenString.isEmpty,
              let tokenData = dataFromHexString(tokenString) else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Valid push token is required", details: nil))
            return
        }

        agent.registerPushNotifications(deviceToken: tokenData) { error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "PUSH_REGISTER_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    result(nil)
                }
            }
        }
    }

    private func unregisterPushNotifications(result: @escaping FlutterResult) {
        guard let agent = callAgent else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Call agent not initialized", details: nil))
            return
        }
        agent.unregisterPushNotification { error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "PUSH_UNREGISTER_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    result(nil)
                }
            }
        }
    }

    private func handlePushNotification(args: [String: Any], result: @escaping FlutterResult) {
        guard let agent = callAgent else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Call agent not initialized", details: nil))
            return
        }
        guard let payload = args["payload"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "payload is required", details: nil))
            return
        }
        let info = PushNotificationInfo.fromDictionary(payload)
        agent.handlePush(notification: info) { error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "PUSH_HANDLE_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    result(nil)
                }
            }
        }
    }

    private func holdCall(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        activeCall.hold { error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "HOLD_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    result(nil)
                }
            }
        }
    }

    private func resumeCall(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        activeCall.resume { error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "RESUME_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    result(nil)
                }
            }
        }
    }

    private func transferCall(args: [String: Any], result: @escaping FlutterResult) {
        result(FlutterError(code: "NOT_IMPLEMENTED", message: "Call transfer not supported in current iOS SDK build", details: nil))
    }

    /// Starts outgoing screen sharing for the active call.
    ///
    /// **Default path — device screen via Broadcast Upload Extension.** Captures the
    /// entire device screen (not just this app's UI). The SDK creates the ACS
    /// `ScreenShareOutgoingVideoStream` and a `ScreenShareBroadcastReceiver` that
    /// listens for frames the app's broadcast extension writes into the shared App
    /// Group container (see `ScreenShareBroadcastReceiver` for the IPC contract).
    /// The app is responsible for presenting `RPSystemBroadcastPickerView` so the
    /// user can start the system broadcast; until they do, no frames flow but the
    /// stream is ready. This path requires an App Group entitlement shared by app
    /// and extension; if the App Group container cannot be resolved the SDK falls
    /// back to the in-app recorder path below.
    ///
    /// **Fallback path — in-app `RPScreenRecorder`.** Captures ONLY this app's own
    /// UI. Used automatically when no App Group container is available (i.e. the
    /// host app has not added the broadcast extension / entitlement). Documented and
    /// retained for back-compat, but it is not device-screen capture.
    /// - Parameter result: Flutter result; `nil` on success, `FlutterError` on failure.
    private func startScreenShare(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        if screenShareActive {
            result(nil)
            return
        }

        // Build the ACS raw outgoing stream format. BGRA payload (`.bgrx`) — the
        // broadcast extension MUST emit BGRA to match (see IPC contract).
        let dimensions = screenShareDimensions()
        let format = VideoStreamFormat()
        format.width = numericCast(dimensions.width)
        format.height = numericCast(dimensions.height)
        format.pixelFormat = .bgrx
        format.framesPerSecond = 15
        format.stride1 = numericCast(dimensions.width * 4)

        let options = RawOutgoingVideoStreamOptions()
        options.formats = [format]

        let stream = ScreenShareOutgoingVideoStream(videoStreamOptions: options)
        screenShareStream = stream
        screenShareFormat = format
        screenShareActive = true
        lastScreenShareFrameTime = 0

        // Prefer the device-screen broadcast path when an App Group container is
        // reachable; otherwise fall back to the in-app recorder.
        let canUseBroadcast = ScreenShareIPC.frameFileURL() != nil
        screenShareUsingInAppFallback = !canUseBroadcast

        activeCall.startVideo(stream: stream) { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    self.screenShareActive = false
                    self.screenShareStream = nil
                    self.screenShareFormat = nil
                    self.screenShareUsingInAppFallback = false
                    result(FlutterError(code: "SCREEN_SHARE_START_FAILED", message: error.localizedDescription, details: nil))
                    return
                }

                if canUseBroadcast {
                    self.startBroadcastReceiver(result: result)
                } else {
                    NSLog("[ACS][Plugin] Screen share App Group unavailable; using in-app RPScreenRecorder fallback (captures app UI only)")
                    self.startInAppRecorderFallback(result: result)
                }
            }
        }
    }

    /// Starts the default broadcast-extension receiver and reports success.
    ///
    /// Frames are decoded off-thread by `ScreenShareBroadcastReceiver` and forwarded
    /// to `sendScreenFrame`. Success is reported immediately because the stream is
    /// live; actual frames begin once the user starts the system broadcast via the
    /// app's `RPSystemBroadcastPickerView`.
    /// - Parameter result: Flutter result to fulfil with `nil` on success.
    private func startBroadcastReceiver(result: @escaping FlutterResult) {
        let receiver = ScreenShareBroadcastReceiver()
        screenShareBroadcastReceiver = receiver
        receiver.start { [weak self] pixelBuffer in
            self?.sendScreenFrame(pixelBuffer)
        }
        result(nil)
    }

    /// Starts the in-app `RPScreenRecorder` fallback capture (app UI only).
    ///
    /// Used when the broadcast App Group is unavailable. Each captured video sample
    /// is throttled and forwarded through the shared `sendScreenFrame` sink.
    /// - Parameter result: Flutter result; `nil` on success, error on capture failure.
    private func startInAppRecorderFallback(result: @escaping FlutterResult) {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            self.screenShareActive = false
            self.stopScreenShareInternal { _ in }
            result(FlutterError(code: "SCREEN_SHARE_NOT_SUPPORTED", message: "Screen sharing is not available", details: nil))
            return
        }

        recorder.isMicrophoneEnabled = false
        recorder.startCapture(handler: { [weak self] sampleBuffer, sampleBufferType, captureError in
            guard let self = self else { return }
            if let captureError = captureError {
                NSLog("[ACS][Plugin] Screen share capture error: %@", captureError.localizedDescription)
                return
            }
            guard sampleBufferType == .video else { return }
            self.handleScreenShareSample(sampleBuffer)
        }, completionHandler: { [weak self] captureError in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let captureError = captureError {
                    self.screenShareActive = false
                    self.stopScreenShareInternal { _ in }
                    result(FlutterError(code: "SCREEN_SHARE_START_FAILED", message: captureError.localizedDescription, details: nil))
                } else {
                    result(nil)
                }
            }
        })
    }

    private func stopScreenShare(result: @escaping FlutterResult) {
        guard call != nil else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        guard screenShareStream != nil else {
            result(nil)
            return
        }
        stopScreenShareInternal { error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "SCREEN_SHARE_STOP_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    result(nil)
                }
            }
        }
    }

    /// Tears down whichever screen-share path is active and stops the ACS stream.
    ///
    /// Stops the broadcast receiver (default path) and/or the in-app recorder
    /// (fallback path) as applicable, then stops the outgoing video stream on the
    /// call. Safe to call when nothing is active.
    /// - Parameter completion: Invoked with any `stopVideo` error (or `nil`).
    private func stopScreenShareInternal(completion: ((Error?) -> Void)? = nil) {
        let stream = screenShareStream
        let activeCall = call
        let usedInAppFallback = screenShareUsingInAppFallback
        screenShareActive = false
        screenShareStream = nil
        screenShareFormat = nil
        screenShareUsingInAppFallback = false
        lastScreenShareFrameTime = 0

        // Stop the broadcast receiver if it was running (default device-screen path).
        screenShareBroadcastReceiver?.stop()
        screenShareBroadcastReceiver = nil

        let stopVideo = {
            guard let activeCall = activeCall, let stream = stream else {
                completion?(nil)
                return
            }
            activeCall.stopVideo(stream: stream) { error in
                completion?(error)
            }
        }

        // Only the in-app fallback owns RPScreenRecorder; do not touch it for the
        // broadcast path (the system broadcast is controlled by the extension/OS).
        let recorder = RPScreenRecorder.shared()
        if usedInAppFallback && recorder.isRecording {
            recorder.stopCapture { _ in
                stopVideo()
            }
        } else {
            stopVideo()
        }
    }

    /// Handles a screen-capture sample produced by the legacy in-app
    /// `RPScreenRecorder` fallback path.
    ///
    /// Applies frame-rate throttling and then forwards the underlying pixel buffer
    /// to the shared screen-frame sink. Kept for back-compat; the default screen
    /// share path is now the broadcast-extension receiver (see
    /// `ScreenShareBroadcastReceiver`), which calls `sendScreenFrame` directly.
    /// - Parameter sampleBuffer: A `.video` `CMSampleBuffer` from ReplayKit.
    private func handleScreenShareSample(_ sampleBuffer: CMSampleBuffer) {
        guard screenShareActive, screenShareStream != nil else { return }
        let now = CACurrentMediaTime()
        if now - lastScreenShareFrameTime < (1.0 / 15.0) {
            return
        }
        lastScreenShareFrameTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        sendScreenFrame(pixelBuffer)
    }

    /// Shared sink that injects a single screen-share frame into the active ACS
    /// `ScreenShareOutgoingVideoStream`.
    ///
    /// This is the single point through which BOTH screen-share sources feed ACS:
    /// the in-app `RPScreenRecorder` fallback (`handleScreenShareSample`) and the
    /// default Broadcast Upload Extension receiver (`ScreenShareBroadcastReceiver`).
    /// Frame injection follows the raw-media API actually used by this SDK
    /// (`RawVideoFrameBuffer` + `stream.send(frame:)`), not the `VideoFrame`
    /// pseudocode in the implementation guide.
    ///
    /// Send work is dispatched onto `screenShareQueue` to keep it off the source's
    /// callback thread. Any send error is surfaced (release-visible `NSLog` plus a
    /// Flutter `call_features` event) instead of being silently dropped, so the app
    /// can react to a degraded share. The frame buffer is always disposed.
    /// - Parameter pixelBuffer: The captured frame. Expected pixel format BGRA
    ///   (matches `screenShareFormat.pixelFormat == .bgrx`); a mismatched format
    ///   from the extension will render incorrectly, see the IPC contract in the guide.
    private func sendScreenFrame(_ pixelBuffer: CVPixelBuffer) {
        screenShareQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.screenShareActive, let stream = self.screenShareStream else { return }

            let frame = RawVideoFrameBuffer()
            frame.buffer = pixelBuffer
            if let format = self.screenShareFormat {
                frame.streamFormat = format
            } else {
                frame.streamFormat = stream.format
            }
            frame.timestampInTicks = stream.timestampInTicks

            stream.send(frame: frame) { [weak self] error in
                if let error = error {
                    // Unswallowed: was previously a DEBUG-only log (silent in release).
                    // Surface to native logs and to Flutter so the failure is observable.
                    NSLog("[ACS][Plugin] Screen share frame send error: %@", error.localizedDescription)
                    self?.emitCallFeatureEvent(type: "screenShareError", payload: [
                        "message": error.localizedDescription
                    ])
                }
                frame.dispose()
            }
        }
    }

    private func screenShareDimensions() -> (width: Int, height: Int) {
        let bounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        var width = Int(bounds.width * scale)
        var height = Int(bounds.height * scale)

        let maxWidth = 1920
        let maxHeight = 1080
        let aspect = Double(width) / Double(height)

        if height > maxHeight {
            height = maxHeight
            width = Int(Double(height) * aspect)
        }
        if width > maxWidth {
            width = maxWidth
            height = Int(Double(width) / aspect)
        }

        width = max(240, width - (width % 2))
        height = max(180, height - (height % 2))
        return (width, height)
    }

    private func listCameras(result: @escaping FlutterResult) {
        ensureDeviceManager { manager in
            guard let dm = manager else {
                result(FlutterError(code: "DEVICE_MANAGER_UNAVAILABLE", message: "Device manager not available", details: nil))
                return
            }
            let list: [[String: Any]] = dm.cameras.map { camera in
                [
                    "id": camera.id,
                    "name": camera.name,
                    "type": "camera",
                    "facing": camera.cameraFacing == .front ? "front" : "back"
                ]
            }
            result(list)
        }
    }

    private func setCamera(args: [String: Any], result: @escaping FlutterResult) {
        guard let cameraId = args["id"] as? String, !cameraId.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "id is required", details: nil))
            return
        }
        ensureDeviceManager { manager in
            guard let dm = manager,
                  let stream = self.localVideoStream,
                  let target = dm.cameras.first(where: { $0.id == cameraId }) else {
                result(FlutterError(code: "VIDEO_UNAVAILABLE", message: "Camera not found", details: nil))
                return
            }
            stream.switchSource(camera: target) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        result(FlutterError(code: "SWITCH_CAMERA_FAILED", message: error.localizedDescription, details: nil))
                    } else {
                        self.currentCamera = target
                        result(nil)
                    }
                }
            }
        }
    }

    // MARK: - Identity

    private func initializeIdentity(args: [String: Any], result: FlutterResult) {
        guard let connection = args["connectionString"] as? String, !connection.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Connection string is required", details: nil))
            return
        }
        result(["status": "initialized"])
    }

    // MARK: - Calling

    private func initializeCalling(args: [String: Any], result: @escaping FlutterResult) {
        guard let accessToken = args["accessToken"] as? String, !accessToken.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Access token is required", details: nil))
            return
        }
        let displayName = args["displayName"] as? String
        let disableInternalPush = args["disableInternalPushForIncomingCall"] as? Bool ?? false

        do {
            tokenCredential = try CommunicationTokenCredential(token: accessToken)
        } catch {
            result(FlutterError(code: "INITIALIZATION_ERROR", message: error.localizedDescription, details: nil))
            return
        }

        let options = CallAgentOptions()
        if let displayName = displayName, !displayName.isEmpty {
            options.displayName = displayName
        }
        options.disableInternalPushForIncomingCall = disableInternalPush

        callClient.createCallAgent(userCredential: tokenCredential!, options: options, completionHandler: { [weak self] agent, error in
            guard let self = self else { return }
            if let error = error {
                result(FlutterError(code: "INITIALIZATION_ERROR", message: error.localizedDescription, details: nil))
                return
            }

            self.callAgent = agent
            self.callAgent?.delegate = self
            self.callClient.getDeviceManager(completionHandler: { manager, _ in
                if let manager = manager {
                    self.deviceManager = manager
                }
                result(["status": "initialized"])
            })
        })
    }

    private func requestPermissions(result: @escaping FlutterResult) {
        let group = DispatchGroup()
        var cameraGranted = false
        var audioGranted = false

        group.enter()
        AVCaptureDevice.requestAccess(for: .video) { granted in
            cameraGranted = granted
            group.leave()
        }

        group.enter()
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            audioGranted = granted
            group.leave()
        }

        group.notify(queue: .main) {
            result(cameraGranted && audioGranted)
        }
    }

    private func startCall(args: [String: Any], result: @escaping FlutterResult) {
        debugLog("[ACS][Plugin] startCall called with args: \(args)")

        guard let participants = args["participants"] as? [String], !participants.isEmpty else {
            debugLog("[ACS][Plugin] startCall ERROR: participants list is empty or missing")
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Participants list is required", details: nil))
            return
        }
        guard let agent = callAgent else {
            debugLog("[ACS][Plugin] startCall ERROR: callAgent is nil")
            result(FlutterError(code: "NOT_INITIALIZED", message: "Call agent not initialized", details: nil))
            return
        }

        let withVideo = args["withVideo"] as? Bool ?? false
        debugLog("[ACS][Plugin] startCall - participants=\(participants), withVideo=\(withVideo)")

        let callees = participants.map { CommunicationUserIdentifier($0) }

        let beginCall: (LocalVideoStream?) -> Void = { [weak self] stream in
            self?.debugLog("[ACS][Plugin] startCall - beginCall closure executing, stream=\(String(describing: stream))")

            let options = StartCallOptions()
            if let stream = stream {
                options.videoOptions = VideoOptions(localVideoStreams: [stream])
            }

            self?.debugLog("[ACS][Plugin] startCall - Calling agent.startCall...")
            agent.startCall(participants: callees, options: options, completionHandler: { call, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.debugLog("[ACS][Plugin] startCall ERROR: \(error.localizedDescription)")
                        result(FlutterError(code: "CALL_START_FAILED", message: error.localizedDescription, details: nil))
                        return
                    }
                    guard let call = call else {
                        self?.debugLog("[ACS][Plugin] startCall ERROR: call object is nil")
                        result(FlutterError(code: "CALL_START_FAILED", message: "Failed to start call", details: nil))
                        return
                    }
                    self?.debugLog("[ACS][Plugin] startCall SUCCESS - callId=\(call.id), state=\(call.state)")
                    self?.debugLog("[ACS][Plugin] startCall - About to call attachCall...")
                    self?.attachCall(call)
                    self?.debugLog("[ACS][Plugin] startCall - attachCall completed")
                    result([
                        "id": call.id,
                        "state": self?.lobbyStateDescription(for: call) ?? self?.callStateToString(call.state) ?? "unknown"
                    ])
                }
            })
        }

        if withVideo {
            ensureLocalVideoStream { stream, error in
                if let error = error {
                    result(FlutterError(code: "VIDEO_UNAVAILABLE", message: error.localizedDescription, details: nil))
                    return
                }
                guard let stream = stream else {
                    result(FlutterError(code: "VIDEO_UNAVAILABLE", message: "Unable to access camera", details: nil))
                    return
                }
                DispatchQueue.main.async {
                    do {
                        try self.viewManager.showLocalPreview(stream: stream)
                    } catch {
                        result(FlutterError(code: "VIDEO_START_FAILED", message: error.localizedDescription, details: nil))
                        return
                    }
                    beginCall(stream)
                }
            }
        } else {
            beginCall(nil)
        }
    }

    private func joinCall(args: [String: Any], result: @escaping FlutterResult) {
        debugLog("[ACS][Plugin] joinCall (group) called with args: \(args)")

        guard let groupIdString = args["groupCallId"] as? String,
              let uuid = UUID(uuidString: groupIdString) else {
            debugLog("[ACS][Plugin] joinCall ERROR: Invalid groupCallId")
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Valid group call ID is required", details: nil))
            return
        }
        guard let agent = callAgent else {
            debugLog("[ACS][Plugin] joinCall ERROR: callAgent is nil")
            result(FlutterError(code: "NOT_INITIALIZED", message: "Call agent not initialized", details: nil))
            return
        }

        let withVideo = args["withVideo"] as? Bool ?? false
        debugLog("[ACS][Plugin] joinCall - groupId=\(groupIdString), withVideo=\(withVideo)")

        let locator = GroupCallLocator(groupId: uuid)

        let beginJoin: (LocalVideoStream?) -> Void = { [weak self] stream in
            self?.debugLog("[ACS][Plugin] joinCall - beginJoin closure executing, stream=\(String(describing: stream))")

            let options = JoinCallOptions()
            if let stream = stream {
                options.videoOptions = VideoOptions(localVideoStreams: [stream])
            }

            self?.debugLog("[ACS][Plugin] joinCall - Calling agent.join...")
            agent.join(with: locator, joinCallOptions: options, completionHandler: { call, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.debugLog("[ACS][Plugin] joinCall ERROR: \(error.localizedDescription)")
                        result(FlutterError(code: "CALL_JOIN_FAILED", message: error.localizedDescription, details: nil))
                        return
                    }
                    guard let call = call else {
                        self?.debugLog("[ACS][Plugin] joinCall ERROR: call object is nil")
                        result(FlutterError(code: "CALL_JOIN_FAILED", message: "Failed to join call", details: nil))
                        return
                    }
                    self?.debugLog("[ACS][Plugin] joinCall SUCCESS - callId=\(call.id), state=\(call.state)")
                    self?.debugLog("[ACS][Plugin] joinCall - About to call attachCall...")
                    self?.attachCall(call)
                    self?.debugLog("[ACS][Plugin] joinCall - attachCall completed")
                    result([
                        "id": call.id,
                        "state": self?.lobbyStateDescription(for: call) ?? self?.callStateToString(call.state) ?? "unknown"
                    ])
                }
            })
        }

        if withVideo {
            ensureLocalVideoStream { stream, error in
                if let error = error {
                    result(FlutterError(code: "VIDEO_UNAVAILABLE", message: error.localizedDescription, details: nil))
                    return
                }
                guard let stream = stream else {
                    result(FlutterError(code: "VIDEO_UNAVAILABLE", message: "Unable to access camera", details: nil))
                    return
                }
                DispatchQueue.main.async {
                    do {
                        try self.viewManager.showLocalPreview(stream: stream)
                    } catch {
                        result(FlutterError(code: "VIDEO_START_FAILED", message: error.localizedDescription, details: nil))
                        return
                    }
                    beginJoin(stream)
                }
            }
        } else {
            beginJoin(nil)
        }
    }

    /// Builds `OutgoingAudioOptions` carrying noise-suppression + echo-cancellation
    /// filters for the requested mode (`off|auto|low|high`, case-insensitive).
    ///
    /// Returns nil when `mode` is nil/empty or unrecognised so callers keep the
    /// ACS SDK's default audio pipeline — an unknown mode string must degrade the
    /// audio-quality nicety, never fail the join.
    private func buildOutgoingAudioOptions(mode: String?) -> OutgoingAudioOptions? {
        guard let mode = mode, !mode.isEmpty else { return nil }
        let suppression: NoiseSuppressionMode
        switch mode.lowercased() {
        case "off": suppression = .off
        case "auto": suppression = .auto
        case "low": suppression = .low
        case "high": suppression = .high
        default:
            debugLog("[ACS][Plugin] Unknown noiseSuppressionMode '\(mode)' — keeping SDK defaults")
            return nil
        }
        let filters = OutgoingAudioFilters()
        filters.noiseSuppressionMode = suppression
        // Echo cancellation accompanies any explicit suppression request so a
        // single Dart-side option yields the full quality bundle.
        filters.acousticEchoCancellationEnabled = true
        // SDK property is `filters` (verified against the vendored
        // AzureCommunicationCalling framework headers), not `audioFilters`.
        let audioOptions = OutgoingAudioOptions()
        audioOptions.filters = filters
        return audioOptions
    }

    private func joinTeamsMeeting(args: [String: Any], result: @escaping FlutterResult) {
        debugLog("[ACS][Plugin] joinTeamsMeeting called with args: \(args)")

        guard let meetingLink = args["meetingLink"] as? String, !meetingLink.isEmpty else {
            debugLog("[ACS][Plugin] joinTeamsMeeting ERROR: Invalid meetingLink")
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Valid Teams meeting link is required", details: nil))
            return
        }
        guard let agent = callAgent else {
            debugLog("[ACS][Plugin] joinTeamsMeeting ERROR: callAgent is nil")
            result(FlutterError(code: "NOT_INITIALIZED", message: "Call agent not initialized", details: nil))
            return
        }

        let withVideo = args["withVideo"] as? Bool ?? false
        let noiseSuppressionMode = args["noiseSuppressionMode"] as? String
        debugLog("[ACS][Plugin] joinTeamsMeeting - meetingLink=\(meetingLink), withVideo=\(withVideo), noiseSuppression=\(noiseSuppressionMode ?? "default")")

        let locator = TeamsMeetingLinkLocator(meetingLink: meetingLink)

        let beginJoin: (LocalVideoStream?) -> Void = { [weak self] stream in
            self?.debugLog("[ACS][Plugin] joinTeamsMeeting - beginJoin closure executing, stream=\(String(describing: stream))")

            let options = JoinCallOptions()
            if let stream = stream {
                options.videoOptions = VideoOptions(localVideoStreams: [stream])
            }
            // Outgoing audio filters (noise suppression + echo cancellation):
            // applied only when the Dart side explicitly requests a mode so
            // existing callers keep the ACS SDK defaults.
            if let audioOptions = self?.buildOutgoingAudioOptions(mode: noiseSuppressionMode) {
                options.outgoingAudioOptions = audioOptions
            }

            self?.debugLog("[ACS][Plugin] joinTeamsMeeting - Calling agent.join...")
            agent.join(with: locator, joinCallOptions: options, completionHandler: { call, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.debugLog("[ACS][Plugin] joinTeamsMeeting ERROR: \(error.localizedDescription)")
                        result(FlutterError(code: "CALL_JOIN_FAILED", message: error.localizedDescription, details: nil))
                        return
                    }
                    guard let call = call else {
                        self?.debugLog("[ACS][Plugin] joinTeamsMeeting ERROR: call object is nil")
                        result(FlutterError(code: "CALL_JOIN_FAILED", message: "Failed to join call", details: nil))
                        return
                    }
                    self?.debugLog("[ACS][Plugin] joinTeamsMeeting SUCCESS - callId=\(call.id), state=\(call.state)")
                    self?.debugLog("[ACS][Plugin] joinTeamsMeeting - About to call attachCall...")
                    self?.attachCall(call)
                    self?.debugLog("[ACS][Plugin] joinTeamsMeeting - attachCall completed")
                    result([
                        "id": call.id,
                        "state": self?.lobbyStateDescription(for: call) ?? self?.callStateToString(call.state) ?? "unknown"
                    ])
                }
            })
        }

        if withVideo {
            ensureLocalVideoStream { stream, error in
                if let error = error {
                    result(FlutterError(code: "VIDEO_UNAVAILABLE", message: error.localizedDescription, details: nil))
                    return
                }
                guard let stream = stream else {
                    result(FlutterError(code: "VIDEO_UNAVAILABLE", message: "Unable to access camera", details: nil))
                    return
                }
                DispatchQueue.main.async {
                    do {
                        try self.viewManager.showLocalPreview(stream: stream)
                    } catch {
                        result(FlutterError(code: "VIDEO_START_FAILED", message: error.localizedDescription, details: nil))
                        return
                    }
                    beginJoin(stream)
                }
            }
        } else {
            beginJoin(nil)
        }
    }

    private func endCall(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call to end", details: nil))
            return
        }

        activeCall.hangUp(options: HangUpOptions(), completionHandler: { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "HANGUP_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    self?.cleanupCallResources()
                    result(nil)
                }
            }
        })
    }

    private func muteAudio(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }

        activeCall.muteOutgoingAudio(completionHandler: { error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "MUTE_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    result(nil)
                }
            }
        })
    }

    private func unmuteAudio(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }

        activeCall.unmuteOutgoingAudio(completionHandler: { error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "UNMUTE_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    result(nil)
                }
            }
        })
    }

    private func startVideo(result: @escaping FlutterResult) {
        ensureLocalVideoStream { stream, error in
            if let error = error {
                result(FlutterError(code: "VIDEO_START_FAILED", message: error.localizedDescription, details: nil))
                return
            }
            guard let stream = stream else {
                result(FlutterError(code: "VIDEO_UNAVAILABLE", message: "Camera not available", details: nil))
                return
            }

            DispatchQueue.main.async {
                do {
                    try self.viewManager.showLocalPreview(stream: stream)
                } catch {
                    result(FlutterError(code: "VIDEO_START_FAILED", message: error.localizedDescription, details: nil))
                    return
                }

                guard let activeCall = self.call else {
                    result(nil)
                    return
                }

                activeCall.startVideo(stream: stream, completionHandler: { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            result(FlutterError(code: "VIDEO_START_FAILED", message: error.localizedDescription, details: nil))
                        } else {
                            result(nil)
                        }
                    }
                })
            }
        }
    }

    private func stopVideo(result: @escaping FlutterResult) {
        guard let stream = localVideoStream else {
            DispatchQueue.main.async {
                self.viewManager.clearLocalPreview()
                result(nil)
            }
            return
        }

        guard let activeCall = call else {
            DispatchQueue.main.async {
                self.viewManager.clearLocalPreview()
                result(nil)
            }
            return
        }

        activeCall.stopVideo(stream: stream, completionHandler: { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "VIDEO_STOP_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    self?.viewManager.clearLocalPreview()
                    result(nil)
                }
            }
        })
    }

    private func switchCamera(result: @escaping FlutterResult) {
        ensureDeviceManager { manager in
            guard let manager = manager, let stream = self.localVideoStream else {
                result(FlutterError(code: "VIDEO_UNAVAILABLE", message: "No active camera stream", details: nil))
                return
            }

            let cameras = manager.cameras
            guard !cameras.isEmpty else {
                result(FlutterError(code: "VIDEO_UNAVAILABLE", message: "No cameras detected", details: nil))
                return
            }

            let current = self.currentCamera ?? cameras.first!
            let currentIndex = cameras.firstIndex { $0.id == current.id } ?? 0
            let nextCamera = cameras[(currentIndex + 1) % cameras.count]
            stream.switchSource(camera: nextCamera, completionHandler: { error in
                DispatchQueue.main.async {
                    if let error = error {
                        result(FlutterError(code: "SWITCH_CAMERA_FAILED", message: error.localizedDescription, details: nil))
                    } else {
                        self.currentCamera = nextCamera
                        result(nil)
                    }
                }
            })
        }
    }

    private func addParticipants(args: [String: Any], result: @escaping FlutterResult) {
        guard let participantIds = args["participants"] as? [String], !participantIds.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Participants list is required", details: nil))
            return
        }
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }

        do {
            for rawId in participantIds {
                let identifier = createCommunicationIdentifier(fromRawId: rawId)
                _ = try activeCall.add(participant: identifier)
            }
            result(["added": participantIds.count])
        } catch {
            result(FlutterError(code: "ADD_PARTICIPANT_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func removeParticipants(args: [String: Any], result: @escaping FlutterResult) {
        guard let participantIds = args["participants"] as? [String], !participantIds.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Participants list is required", details: nil))
            return
        }
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }

        var participantsToRemove: [(String, RemoteParticipant)] = []
        var missing: [String] = []

        for rawId in participantIds {
            if let participant = activeCall.remoteParticipants.first(where: { $0.identifier.rawId == rawId }) {
                participantsToRemove.append((rawId, participant))
            } else {
                missing.append(rawId)
            }
        }

        guard !participantsToRemove.isEmpty else {
            result(["removed": 0, "missing": missing])
            return
        }

        let group = DispatchGroup()
        var removalError: FlutterError?

        for (_, participant) in participantsToRemove {
            group.enter()
            activeCall.remove(participant: participant) { error in
                if let error = error, removalError == nil {
                    removalError = FlutterError(code: "REMOVE_PARTICIPANT_FAILED", message: error.localizedDescription, details: participant.identifier.rawId)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let error = removalError {
                result(error)
            } else {
                result([
                    "removed": participantsToRemove.count,
                    "missing": missing,
                ])
            }
        }
    }

    private var participantMonitorTimer: Timer?

    private func attachCall(_ newCall: Call) {
        debugLog("[ACS][Plugin] ========================================")
        debugLog("[ACS][Plugin] attachCall - Starting attach for callId=\(newCall.id)")
        debugLog("[ACS][Plugin] attachCall - Call state=\(callStateToString(newCall.state))")
        debugLog("[ACS][Plugin] attachCall - remoteParticipants.count=\(newCall.remoteParticipants.count)")
        debugLog("[ACS][Plugin] ========================================")

        cleanupCallResources()
        call = newCall
        newCall.delegate = self
        debugLog("[ACS][Plugin] attachCall - Set call delegate to self")

        let capabilities = newCall.feature(Features.capabilities)
        capabilities.delegate = self
        capabilitiesFeature = capabilities
        debugLog("[ACS][Plugin] attachCall - Set capabilities delegate")

        setupCallFeatureHandlers(for: newCall)

        // Log lobby participants
        let lobby = newCall.callLobby
        debugLog("[ACS][Plugin] attachCall - Lobby participants count: \(lobby.participants.count)")
        for (index, participant) in lobby.participants.enumerated() {
            debugLog("[ACS][Plugin] attachCall - Lobby participant[\(index)]: id=\(participant.identifier.rawId)")
        }

        handleAddedParticipants(newCall.remoteParticipants)
        debugLog("[ACS][Plugin] attachCall - handleAddedParticipants completed")

        // Start periodic monitor
        startParticipantMonitor()
    }

    private func setupCallFeatureHandlers(for activeCall: Call) {
        let recording = activeCall.feature(Features.recording)
        recordingFeature = recording
        recording.events.onIsRecordingActiveChanged = { [weak self] _ in
            self?.emitRecordingState(recording)
        }
        emitRecordingState(recording)

        let transcription = activeCall.feature(Features.transcription)
        transcriptionFeature = transcription
        transcription.events.onIsTranscriptionActiveChanged = { [weak self] _ in
            self?.emitTranscriptionState(transcription)
        }
        emitTranscriptionState(transcription)

        let dominant = activeCall.feature(Features.dominantSpeakers)
        dominantSpeakersFeature = dominant
        dominant.events.onDominantSpeakersChanged = { [weak self] _ in
            self?.emitDominantSpeakers(dominant)
        }
        emitDominantSpeakers(dominant)

        let raisedHands = activeCall.feature(Features.raisedHands)
        raiseHandFeature = raisedHands
        raisedHands.events.onHandRaised = { [weak self] args in
            self?.emitCallFeatureEvent(type: "raisedHandRaised", payload: [
                "identifier": args.identifier.rawId
            ])
            self?.emitRaisedHandsSnapshot(raisedHands)
        }
        raisedHands.events.onHandLowered = { [weak self] args in
            self?.emitCallFeatureEvent(type: "raisedHandLowered", payload: [
                "identifier": args.identifier.rawId
            ])
            self?.emitRaisedHandsSnapshot(raisedHands)
        }
        emitRaisedHandsSnapshot(raisedHands)

        let spotlight = activeCall.feature(Features.spotlight)
        spotlightFeature = spotlight
        spotlight.events.onSpotlightChanged = { [weak self] args in
            self?.emitSpotlightChanged(args: args, feature: spotlight)
        }
        emitSpotlightSnapshot(spotlight)

        let realTimeText = activeCall.feature(Features.realTimeText)
        realTimeTextFeature = realTimeText
        realTimeText.events.onInfoReceived = { [weak self] args in
            self?.emitRealTimeTextEvent(info: args.info)
        }

        let captions = activeCall.feature(Features.captions)
        captions.events.onActiveCaptionsTypeChanged = { [weak self] _ in
            self?.refreshCaptions(activeCall)
        }
        refreshCaptions(activeCall)

        let mediaStats = activeCall.feature(Features.mediaStatistics)
        mediaStatisticsFeature = mediaStats
        mediaStats.events.onReportReceived = { [weak self] args in
            self?.emitMediaStatisticsReport(args.report)
        }

        let dataChannel = activeCall.feature(Features.dataChannel)
        dataChannelFeature = dataChannel
        dataChannel.events.onReceiverCreated = { [weak self] args in
            self?.attachDataChannelReceiver(args.receiver)
        }

        let diagnostics = activeCall.feature(Features.localUserDiagnostics)
        localUserDiagnosticsFeature = diagnostics
        attachDiagnosticsHandlers(diagnostics)
        emitDiagnosticsSnapshot(diagnostics)
    }

    private func startParticipantMonitor() {
        participantMonitorTimer?.invalidate()
        var monitorCount = 0
        let maxMonitorCount = 12 // Monitor for 60 seconds (12 x 5s)

        participantMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
            self?.safeHandle("participantMonitorTimer") {
                guard let self = self else {
                    timer.invalidate()
                    return
                }

                monitorCount += 1
                if monitorCount > maxMonitorCount {
                    self.debugLog("[ACS][Plugin] [MONITOR] Stopping after \(maxMonitorCount) iterations")
                    timer.invalidate()
                    self.participantMonitorTimer = nil
                    return
                }

                guard let activeCall = self.call else {
                    self.debugLog("[ACS][Plugin] [MONITOR \(monitorCount)] No active call")
                    return
                }

                self.debugLog("[ACS][Plugin] [MONITOR \(monitorCount)] ========================================")
                self.debugLog("[ACS][Plugin] [MONITOR \(monitorCount)] Call state: \(self.callStateToString(activeCall.state))")
                self.debugLog("[ACS][Plugin] [MONITOR \(monitorCount)] Remote participants: \(activeCall.remoteParticipants.count)")

                for (pIndex, participant) in activeCall.remoteParticipants.enumerated() {
                    let streams = participant.incomingVideoStreams.compactMap { $0 as? RemoteVideoStream }
                    self.debugLog("[ACS][Plugin] [MONITOR \(monitorCount)] Participant[\(pIndex)]: id=\(participant.identifier.rawId), streams=\(streams.count)")

                    // Check if delegate is set
                    if participant.delegate == nil {
                        self.debugLog("[ACS][Plugin] [MONITOR \(monitorCount)] WARNING: Participant[\(pIndex)] delegate is nil! Setting it now...")
                        participant.delegate = self
                    }

                    for (sIndex, stream) in streams.enumerated() {
                        // Pure liveness log: renderer ownership is the render manager's
                        // responsibility (cached, diff-disposed); the monitor no longer
                        // rescues renderers, it only reports stream availability.
                        self.debugLog("[ACS][Plugin] [MONITOR \(monitorCount)]   Stream[\(sIndex)]: id=\(stream.id), isAvailable=\(stream.isAvailable), state=\(stream.state)")
                    }
                }
                self.debugLog("[ACS][Plugin] [MONITOR \(monitorCount)] ========================================")
            }
        }
    }

    private func cleanupCallResources() {
        participantMonitorTimer?.invalidate()
        participantMonitorTimer = nil

        if screenShareActive || screenShareStream != nil {
            stopScreenShareInternal { _ in }
        }

        call?.delegate = nil
        call = nil
        incomingCall = nil
        capabilitiesFeature?.delegate = nil
        capabilitiesFeature = nil
        recordingFeature?.events.removeAll()
        recordingFeature = nil
        transcriptionFeature?.events.removeAll()
        transcriptionFeature = nil
        dominantSpeakersFeature?.events.removeAll()
        dominantSpeakersFeature = nil
        raiseHandFeature?.events.removeAll()
        raiseHandFeature = nil
        spotlightFeature?.events.removeAll()
        spotlightFeature = nil
        realTimeTextFeature?.events.removeAll()
        realTimeTextFeature = nil
        mediaStatisticsFeature?.events.removeAll()
        mediaStatisticsFeature = nil
        dataChannelFeature?.events.removeAll()
        dataChannelFeature = nil
        localUserDiagnosticsFeature = nil
        dataChannelSenders.removeAll()
        dataChannelReceivers.values.forEach { receiver in
            receiver.events.removeAll()
            receiver.delegate = nil
        }
        dataChannelReceivers.removeAll()
        pendingSurveys.removeAll()
        // Clear any buffered first-frame ids so a signal that fired while Dart was
        // unsubscribed cannot re-emit a stale participantVideoRendering for a
        // participant from the previous call on the next onListen.
        pendingFirstFrameIds.removeAll()

        // Tear down renderers SYNCHRONOUSLY when already on main. `cleanupCallResources`
        // runs on the main thread immediately before a new call is attached; deferring
        // disposal to a later runloop turn lets it run AFTER the new call's tile
        // reconcile has created fresh renderers — disposeAll would then destroy them,
        // leaving blank tiles on a fast end→rejoin. Running inline closes that window.
        let teardownRenderers = { [weak self] in
            guard let self = self else { return }
            self.renderManager.disposeAll()
            self.viewManager.clearLocalPreview()
            self.viewManager.removeAllRemote()
        }
        if Thread.isMainThread {
            teardownRenderers()
        } else {
            DispatchQueue.main.async(execute: teardownRenderers)
        }

        localVideoStream = nil
        currentCamera = nil
        activeVideoEffect = nil
        if let teams = callCaptions as? TeamsCaptions {
            teams.events.removeAll()
        }
        if let comm = callCaptions as? CommunicationCaptions {
            comm.events.removeAll()
        }
        callCaptions = nil
    }

    private func emitRecordingState(_ feature: RecordingCallFeature) {
        emitCallFeatureEvent(type: "recordingStateChanged", payload: [
            "isActive": feature.isRecordingActive
        ])
    }

    private func emitTranscriptionState(_ feature: TranscriptionCallFeature) {
        emitCallFeatureEvent(type: "transcriptionStateChanged", payload: [
            "isActive": feature.isTranscriptionActive
        ])
    }

    private func emitDominantSpeakers(_ feature: DominantSpeakersCallFeature) {
        let speakers = feature.dominantSpeakersInfo.speakers.map { $0.rawId }
        emitCallFeatureEvent(type: "dominantSpeakersChanged", payload: [
            "speakers": speakers,
            "lastUpdated": feature.dominantSpeakersInfo.lastUpdated.iso8601String()
        ])
    }

    private func emitRaisedHandsSnapshot(_ feature: RaiseHandCallFeature) {
        let list = feature.raisedHands.map { serialize(raisedHand: $0) }
        emitCallFeatureEvent(type: "raisedHandsUpdated", payload: [
            "raisedHands": list
        ])
    }

    private func emitSpotlightSnapshot(_ feature: SpotlightCallFeature) {
        let current = feature.spotlightedParticipants.map { $0.identifier.rawId }
        emitCallFeatureEvent(type: "spotlightChanged", payload: [
            "added": [],
            "removed": [],
            "spotlighted": current,
            "max": Int(feature.maxSpotlightedParticipants)
        ])
    }

    private func emitSpotlightChanged(args: SpotlightChangedEventArgs, feature: SpotlightCallFeature) {
        let added = args.added.map { $0.identifier.rawId }
        let removed = args.removed.map { $0.identifier.rawId }
        let current = feature.spotlightedParticipants.map { $0.identifier.rawId }
        emitCallFeatureEvent(type: "spotlightChanged", payload: [
            "added": added,
            "removed": removed,
            "spotlighted": current,
            "max": Int(feature.maxSpotlightedParticipants)
        ])
    }

    private func refreshCaptions(_ activeCall: Call) {
        let feature = activeCall.feature(Features.captions)
        feature.getCaptions { [weak self] captions, error in
            guard let self = self else { return }
            if let captions = captions {
                self.callCaptions = captions
                self.attachCaptionsHandlers(captions)
                self.emitCaptionsStateChanged(captions)
            } else if let error = error {
                self.emitCaptionsEvent(type: "captionsError", payload: [
                    "message": error.localizedDescription
                ])
            }
        }
    }

    private func attachCaptionsHandlers(_ captions: CallCaptions) {
        if let teams = captions as? TeamsCaptions {
            teams.events.onCaptionsReceived = { [weak self] args in
                self?.emitCaptionsEvent(type: "captionsReceived", payload: self?.serialize(teamsCaptions: args) ?? [:])
            }
            teams.events.onCaptionsEnabledChanged = { [weak self] _ in
                self?.emitCaptionsStateChanged(teams)
            }
            teams.events.onActiveSpokenLanguageChanged = { [weak self] _ in
                self?.emitCaptionsStateChanged(teams)
            }
            teams.events.onActiveCaptionLanguageChanged = { [weak self] _ in
                self?.emitCaptionsStateChanged(teams)
            }
        } else if let comm = captions as? CommunicationCaptions {
            comm.events.onCaptionsReceived = { [weak self] args in
                self?.emitCaptionsEvent(type: "captionsReceived", payload: self?.serialize(communicationCaptions: args) ?? [:])
            }
            comm.events.onCaptionsEnabledChanged = { [weak self] _ in
                self?.emitCaptionsStateChanged(comm)
            }
            comm.events.onActiveSpokenLanguageChanged = { [weak self] _ in
                self?.emitCaptionsStateChanged(comm)
            }
        }
    }

    private func emitCaptionsStateChanged(_ captions: CallCaptions) {
        emitCaptionsEvent(type: "captionsStateChanged", payload: serialize(captions: captions))
    }

    private func emitMediaStatisticsReport(_ report: MediaStatisticsReport) {
        guard let sink = mediaStatisticsEventSink else { return }
        let payload: [String: Any] = [
            "type": "mediaStatisticsReport",
            "report": serialize(mediaStatisticsReport: report)
        ]
        DispatchQueue.main.async {
            sink(payload)
        }
    }

    private func attachDataChannelReceiver(_ receiver: DataChannelReceiver) {
        dataChannelReceivers[Int(receiver.channelId)] = receiver
        receiver.events.onMessageReceived = { [weak self] _ in
            self?.emitDataChannelMessage(receiver)
        }
        receiver.events.onClosed = { [weak self] _ in
            self?.dataChannelReceivers.removeValue(forKey: Int(receiver.channelId))
            self?.emitDataChannelEvent(type: "dataChannelReceiverClosed", payload: [
                "channelId": Int(receiver.channelId)
            ])
        }
        emitDataChannelEvent(type: "dataChannelReceiverCreated", payload: [
            "channelId": Int(receiver.channelId),
            "senderIdentifier": receiver.senderIdentifier.rawId
        ])
    }

    private func emitDataChannelMessage(_ receiver: DataChannelReceiver) {
        guard let message = receiver.receiveMessage() else { return }
        emitDataChannelEvent(type: "dataChannelMessageReceived", payload: [
            "channelId": Int(receiver.channelId),
            "senderIdentifier": receiver.senderIdentifier.rawId,
            "sequenceNumber": message.sequenceNumber,
            "data": FlutterStandardTypedData(bytes: message.data)
        ])
    }

    private func attachDiagnosticsHandlers(_ diagnostics: LocalUserDiagnosticsCallFeature) {
        let network = diagnostics.networkDiagnostics
        network.events.onIsNetworkUnavailableChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "networkDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        network.events.onIsNetworkRelaysUnreachableChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "networkDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        network.events.onNetworkReconnectionQualityChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "networkDiagnosticChanged", payload: [
                "name": args.name,
                "value": String(describing: args.value)
            ])
        }
        network.events.onNetworkReceiveQualityChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "networkDiagnosticChanged", payload: [
                "name": args.name,
                "value": String(describing: args.value)
            ])
        }
        network.events.onNetworkSendQualityChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "networkDiagnosticChanged", payload: [
                "name": args.name,
                "value": String(describing: args.value)
            ])
        }

        let media = diagnostics.mediaDiagnostics
        media.events.onIsSpeakerNotFunctioningChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "mediaDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        media.events.onIsSpeakerBusyChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "mediaDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        media.events.onIsSpeakerMutedChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "mediaDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        media.events.onIsSpeakerVolumeZeroChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "mediaDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        media.events.onIsNoSpeakerDevicesAvailableChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "mediaDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        media.events.onIsSpeakingWhileMicrophoneIsMutedChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "mediaDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        media.events.onIsNoMicrophoneDevicesAvailableChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "mediaDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        media.events.onIsMicrophoneBusyChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "mediaDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        media.events.onIsCameraFrozenChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "mediaDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        media.events.onIsCameraStartFailedChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "mediaDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        media.events.onIsCameraStartTimedOutChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "mediaDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        media.events.onIsMicrophoneNotFunctioningChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "mediaDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        media.events.onIsMicrophoneMutedUnexpectedlyChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "mediaDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
        media.events.onIsCameraPermissionDeniedChanged = { [weak self] args in
            self?.emitDiagnosticsEvent(type: "mediaDiagnosticChanged", payload: [
                "name": args.name,
                "value": args.value
            ])
        }
    }

    private func emitDiagnosticsSnapshot(_ diagnostics: LocalUserDiagnosticsCallFeature) {
        emitDiagnosticsEvent(type: "diagnosticsSnapshot", payload: serializeDiagnostics(diagnostics))
    }

    private func handleAddedParticipants(_ participants: [RemoteParticipant]) {
        safeHandle("handleAddedParticipants") {
            debugLog("[ACS][Plugin] handleAddedParticipants called with \(participants.count) participants")

            participants.forEach { participant in
                debugLog("[ACS][Plugin] handleAddedParticipants - Processing participant: \(participant.identifier.rawId)")
                debugLog("[ACS][Plugin] handleAddedParticipants - participant.state=\(participant.state)")
                debugLog("[ACS][Plugin] handleAddedParticipants - participant.isMuted=\(participant.isMuted)")
                debugLog("[ACS][Plugin] handleAddedParticipants - participant.isSpeaking=\(participant.isSpeaking)")

                participant.delegate = self
                debugLog("[ACS][Plugin] handleAddedParticipants - Set participant delegate to self")

                let remoteStreams = participant.incomingVideoStreams.compactMap { $0 as? RemoteVideoStream }
                debugLog("[ACS][Plugin] handleAddedParticipants - Found \(remoteStreams.count) video streams")

                for (index, stream) in remoteStreams.enumerated() {
                    debugLog("[ACS][Plugin] handleAddedParticipants - Stream[\(index)]: id=\(stream.id), isAvailable=\(stream.isAvailable), state=\(stream.state)")
                    reconcileRemoteStream(stream)
                }

                emitParticipantEvent(type: "participantAdded", participant: participant)

                // Attach to a per-participant grid tile if one is already mounted for
                // this participant (handles tile-mounted-before-participant ordering).
                reconcileParticipantTile(participantId: participant.identifier.rawId)
            }
            // Re-reconcile EVERY mounted tile after a roster addition: a mid-call
            // joiner causes the grid to re-lay-out, and existing tiles may be rebuilt;
            // this re-attaches any survivor renderer that was dropped during that
            // rebuild. Idempotent per tile (guarded by hasContainer/isRendering).
            reconcileAllParticipantTiles()
            debugLog("[ACS][Plugin] handleAddedParticipants completed")
        }
    }

    private func handleRemovedParticipants(_ participants: [RemoteParticipant]) {
        safeHandle("handleRemovedParticipants") {
            debugLog("[ACS][Plugin] handleRemovedParticipants called with \(participants.count) participants")
            participants.forEach { participant in
                debugLog("[ACS][Plugin] handleRemovedParticipants - Removing participant: \(participant.identifier.rawId)")
                participant.incomingVideoStreams
                    .compactMap { $0 as? RemoteVideoStream }
                    .forEach { stream in
                        removeRemoteStream(streamId: Int(stream.id))
                    }
                participant.delegate = nil
                emitParticipantEvent(type: "participantRemoved", participant: participant)
            }
            // Re-reconcile EVERY surviving tile after a roster removal. The grid
            // re-lays-out when a participant leaves; without this, a survivor whose
            // tile is rebuilt is left without a renderer (one-drops-all-stop). Each
            // tile's reconcile is idempotent (guarded by hasContainer/isRendering),
            // so this only re-attaches tiles that actually lost their renderer.
            reconcileAllParticipantTiles()
        }
    }

    /// Maximum number of retry attempts for subscribing to a remote stream
    private static let maxStreamRetries = 5
    /// Delay between retry attempts in seconds (increased to give iOS more time)
    private static let streamRetryDelay: TimeInterval = 1.0
    /// Max self-heal retries when a grid tile's renderer fails to create (transient
    /// decoder pressure during multi-join). Bounded so a genuinely un-renderable stream
    /// does not retry forever.
    private static let maxTileReconcileRetries = 3
    /// Delay between tile-reconcile retries.
    private static let tileReconcileRetryDelay: TimeInterval = 0.6
    /// Additional delay for isAvailable checks
    private static let availabilityCheckDelay: TimeInterval = 0.5

    /// Determines if a remote video stream should be rendered.
    /// Uses the `isAvailable` property as recommended by Microsoft's official documentation.
    /// The `isAvailable` property indicates if the remote participant endpoint is actively sending a stream.
    private func shouldRenderRemoteStream(_ stream: RemoteVideoStream) -> Bool {
        // Per Microsoft documentation: use isAvailable property to determine if remote participant is sending video
        // https://learn.microsoft.com/en-us/azure/communication-services/how-tos/calling-sdk/manage-video
        let isAvailable = stream.isAvailable
        let state = stream.state
        debugLog("[ACS][Plugin] shouldRenderRemoteStream: id=\(stream.id), isAvailable=\(isAvailable), state=\(state)")
        return isAvailable
    }

    private func reconcileRemoteStream(_ stream: RemoteVideoStream) {
        let streamId = Int(stream.id)
        let state = stream.state
        let isAvailable = stream.isAvailable

        debugLog("[ACS][Plugin] Reconciling remote stream id=\(streamId), isAvailable=\(isAvailable), state=\(state)")

        // Always dispatch to main thread for consistency
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Re-check isAvailable on main thread to avoid race conditions
            // Using isAvailable as per Microsoft documentation
            if self.shouldRenderRemoteStream(stream) {
                self.subscribeRemoteStreamOnMainThread(stream, retryCount: 0)
            } else {
                self.removeRemoteStreamOnMainThread(streamId: streamId)
            }
        }
    }

    private func subscribeRemoteStreamOnMainThread(_ stream: RemoteVideoStream, retryCount: Int) {
        dispatchPrecondition(condition: .onQueue(.main))

        let streamId = Int(stream.id)

        // The single-remote full-screen view shares the same renderer cache as the grid
        // tiles. If a per-participant tile is mounted for this stream's owner, that tile
        // already drives the render manager and embeds the view directly; the shared
        // full-screen container is not used in the grid case, so there is nothing to do.
        guard let ownerId = participantIdOwning(streamId: streamId) else {
            debugLog("[ACS][Plugin] Stream id=\(streamId) has no current owner; skipping")
            return
        }
        // The unified call stage renders EVERY remote participant through a per-participant grid
        // tile (a lone remote is just a 1-cell grid). The legacy shared single-feed path used to
        // create the renderer right here — `renderManager.rendererView(...)` →
        // `VideoStreamRenderer.createView()` ON THE MAIN THREAD — the instant a stream became
        // available, which is BEFORE that participant's tile platform view has mounted. On
        // Flutter's merged platform/UI thread (default since 3.32) that synchronous create raced
        // the new tile's UiKitView mount and HARD-FROZE the app on the 2nd-participant join
        // (single→grid). The per-tile reconcile is the single source of truth: it creates the
        // (cached) renderer once the tile container exists, keyed `participantId:streamId` so there
        // is still exactly one renderer per stream. Defer to it and NEVER create on the shared path.
        //
        // If the tile is already mounted, this reconcile renders the stream now (e.g. a camera
        // turned on after join). If it is not mounted yet, the tile's own
        // `onParticipantViewCreated → reconcileParticipantTile` will render it on mount. Either
        // way the renderer is created after — never racing — the platform-view mount.
        debugLog("[ACS][Plugin] Stream id=\(streamId) owner=\(ownerId): deferring to per-tile reconcile (shared single-feed createView retired to avoid the merged-thread mount race)")
        reconcileParticipantTile(participantId: ownerId)
    }

    /// Legacy method kept for backward compatibility - now just wraps reconcileRemoteStream
    private func subscribeRemoteStream(_ stream: RemoteVideoStream) {
        reconcileRemoteStream(stream)
    }

    private func removeRemoteStreamOnMainThread(streamId: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        // Detach from the shared container; dispose the cached renderer via the manager.
        viewManager.removeRemote(streamId: streamId)
        if let ownerId = participantIdOwning(streamId: streamId) {
            renderManager.disposeStream(participantId: ownerId, streamId: streamId)
        }
    }

    private func removeRemoteStream(streamId: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.removeRemoteStreamOnMainThread(streamId: streamId)
        }
    }

    // MARK: - Per-participant grid tiles

    /// Reconciles a single per-participant tile against the active call.
    ///
    /// Looks up the participant by raw id, finds their first available remote video
    /// stream, and attaches it to the participant's tile (or detaches if none is
    /// available). Called when a tile mounts and whenever a participant's streams
    /// change, so each grid tile renders exactly its owner's video. The shared
    /// `remoteVideoView` path is unaffected.
    /// - Parameter participantId: ACS raw identifier of the participant tile.
    private func reconcileParticipantTile(participantId: String, retryCount: Int = 0) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // A retry is the scheduled continuation of an already-coalesced reconcile —
            // run it directly so the bounded self-heal is not swallowed by the latch.
            if retryCount > 0 {
                self.performReconcileParticipantTile(participantId: participantId, retryCount: retryCount)
                return
            }
            // Coalesce a burst of reconcile requests for the SAME participant (the create
            // path + the per-stream delegate paths all call this directly, bypassing the
            // all-tiles latch) into ONE trailing pass. Without this a 2-remote join burst
            // fans out into N synchronous createView calls on the platform thread → freeze.
            if self.reconcilingTiles.contains(participantId) { return }
            self.reconcilingTiles.insert(participantId)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.tileReconcileCoalesceWindow) { [weak self] in
                guard let self = self else { return }
                self.reconcilingTiles.remove(participantId)
                self.performReconcileParticipantTile(participantId: participantId, retryCount: 0)
            }
        }
    }

    /// Runs the actual tile reconcile (cache-hit-or-create renderer + embed). Always invoked
    /// on the main thread, AFTER the per-participant coalescing window, so a join burst does
    /// at most one synchronous renderer create per participant.
    private func performReconcileParticipantTile(participantId: String, retryCount: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        // [ACSFREEZE] diagnostic: brackets the per-tile reconcile (the create/embed path
        // triggered on join AND the take-over path). A missing EXIT localizes the freeze.
        NSLog("[ACSFREEZE] iOS performReconcileTile ENTER participant=%@ retry=%d main=%@",
              participantId, retryCount, Thread.isMainThread ? "Y" : "N")
        defer { NSLog("[ACSFREEZE] iOS performReconcileTile EXIT participant=%@", participantId) }
        guard self.tileContainers.hasContainer(for: participantId) else { return }

        guard let participant = self.call?.remoteParticipants.first(where: {
            $0.identifier.rawId == participantId
        }) else {
                self.tileContainers.clearEmbedded(for: participantId)
                self.renderManager.disposeParticipant(participantId)
                return
            }

            let available = participant.incomingVideoStreams
                .compactMap { $0 as? RemoteVideoStream }
                .first(where: { $0.isAvailable })

            if let stream = available {
                // Single renderer cache: a hit returns the existing view, a miss creates
                // exactly one renderer for this participant:stream. No second renderer is
                // ever made for the same stream, so there is no takeover race to resolve.
                if let view = self.renderManager.rendererView(participantId: participantId, stream: stream) {
                    // Diagnostic: confirms the renderer is embedded into a container that is
                    // already in a window and sized (the single-remote black-frame bug was a
                    // renderer attached to a zero-sized/unwindowed container). If `window=nil`
                    // or `bounds=zero` here, the platform view has not been laid out yet.
                    let container = self.tileContainers.container(for: participantId)
                    self.debugLog("[ACS][Plugin] embed tile participant=\(participantId) streamId=\(Int(stream.id)) container.window=\(container.window != nil) container.bounds=\(container.bounds)")
                    self.tileContainers.embed(view, for: participantId)
                } else if retryCount < Self.maxTileReconcileRetries {
                    // Renderer creation failed (transient — e.g. decoder-pool pressure
                    // during a multi-join). The stream is still available but no stream
                    // event may fire again, so self-heal with a bounded retry instead of
                    // leaving the tile permanently blank.
                    let next = retryCount + 1
                    self.debugLog("[ACS][Plugin] Renderer create failed for participant=\(participantId); retry \(next)/\(Self.maxTileReconcileRetries)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.tileReconcileRetryDelay) { [weak self] in
                        self?.reconcileParticipantTile(participantId: participantId, retryCount: next)
                    }
                }
            } else {
                self.tileContainers.clearEmbedded(for: participantId)
                self.renderManager.disposeParticipant(participantId)
            }
            // Drive lazy render scoping: only mounted tiles keep a decoder session.
            self.updateDisplayedRenderers()
    }

    /// Tears down a participant's tile when its platform view is disposed by Flutter:
    /// disposes the renderer (frees the decoder session) and removes the container.
    /// - Parameter participantId: ACS raw identifier of the disposed tile.
    private func disposeParticipantTile(participantId: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        // [ACSFREEZE] diagnostic: brackets tile teardown on DROP (grid→single). If this
        // ENTER prints with no EXIT, the freeze is in renderer/container disposal.
        NSLog("[ACSFREEZE] iOS disposeParticipantTile ENTER participant=%@ main=%@",
              participantId, Thread.isMainThread ? "Y" : "N")
        renderManager.disposeParticipant(participantId)
        tileContainers.remove(participantId)
        updateDisplayedRenderers()
        NSLog("[ACSFREEZE] iOS disposeParticipantTile EXIT participant=%@", participantId)
    }

    /// Recomputes the displayed renderer key set from the currently mounted tiles and
    /// asks the render manager to dispose any renderer that is no longer displayed, so
    /// only on-screen participants hold a scarce hardware decoder session.
    private func updateDisplayedRenderers() {
        dispatchPrecondition(condition: .onQueue(.main))
        var keys: [String] = []
        for participantId in tileContainers.mountedParticipantIds() {
            guard let participant = call?.remoteParticipants.first(where: {
                $0.identifier.rawId == participantId
            }) else { continue }
            for stream in participant.incomingVideoStreams.compactMap({ $0 as? RemoteVideoStream })
            where stream.isAvailable {
                keys.append("\(participantId):\(Int(stream.id))")
            }
        }
        renderManager.updateDisplayed(keys)
    }

    /// Emits the per-participant first-frame signal to Dart so the tile clears its
    /// connecting spinner. Fired by the render manager when a renderer paints.
    /// - Parameter participantId: ACS raw identifier whose video began rendering.
    private func emitParticipantVideoRendering(participantId: String) {
        // Reached only after the render manager hops the first-frame callback to main.
        // Assert it so the pendingFirstFrameIds mutation below is provably race-free.
        dispatchPrecondition(condition: .onQueue(.main))
        // Buffer when Dart hasn't subscribed yet: this one-shot signal would otherwise
        // be lost on a cold connect, stranding the tile spinner until the fallback fires.
        guard let sink = eventSink else {
            pendingFirstFrameIds.insert(participantId)
            return
        }
        let payload: [String: Any] = ["type": "participantVideoRendering", "id": participantId]
        DispatchQueue.main.async {
            sink(payload)
        }
    }

    /// Re-emits any first-frame signals that fired before the Dart event channel was
    /// subscribed. Called from `onListen` once a sink attaches so cold-connect tiles
    /// clear their spinner immediately instead of waiting for the fallback timeout.
    private func drainPendingFirstFrameEvents() {
        // Called from onListen on the platform (main) thread; assert it so the
        // pendingFirstFrameIds read/clear is provably race-free.
        dispatchPrecondition(condition: .onQueue(.main))
        guard let sink = eventSink, !pendingFirstFrameIds.isEmpty else { return }
        let ids = pendingFirstFrameIds
        pendingFirstFrameIds.removeAll()
        DispatchQueue.main.async {
            for id in ids {
                sink(["type": "participantVideoRendering", "id": id])
            }
        }
    }

    /// Returns the raw id of the remote participant that owns the given video
    /// [streamId], or nil if no current participant publishes it.
    ///
    /// Used to enforce the single-renderer-per-stream invariant: the shared
    /// single-feed path skips a stream once a per-participant grid tile owns it.
    /// Must be called on the main thread (reads the live `call` roster).
    private func participantIdOwning(streamId: Int) -> String? {
        return call?.remoteParticipants.first(where: { participant in
            participant.incomingVideoStreams.contains(where: { Int($0.id) == streamId })
        })?.identifier.rawId
    }

    /// Reconciles every mounted per-participant tile. Invoked after participant or
    /// stream changes so grid tiles stay in sync without coupling to the shared path.
    private func reconcileAllParticipantTiles() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Coalesce a burst of delegate callbacks into ONE trailing reconcile pass.
            // Without this latch, every participant/stream event scheduled a full
            // all-tiles fan-out, enqueuing main work faster than it drained (the 3+
            // participant freeze). The 120ms trailing window absorbs the join burst.
            guard !self.reconcileAllScheduled else { return }
            self.reconcileAllScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.reconcileAllScheduled = false
                for participantId in self.tileContainers.mountedParticipantIds() {
                    self.reconcileParticipantTile(participantId: participantId)
                }
            }
        }
    }

    private func ensureDeviceManager(completion: @escaping (DeviceManager?) -> Void) {
        if let manager = deviceManager {
            completion(manager)
            return
        }
        callClient.getDeviceManager(completionHandler: { [weak self] manager, _ in
            if let manager = manager {
                self?.deviceManager = manager
            }
            completion(manager)
        })
    }

    private func ensureLocalVideoStream(completion: @escaping (LocalVideoStream?, Error?) -> Void) {
        if let stream = localVideoStream {
            completion(stream, nil)
            return
        }

        // Check camera authorization status BEFORE attempting to create stream
        // This prevents crashes when camera permission is denied
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus == .denied || authStatus == .restricted {
            completion(nil, NSError(domain: "acs_flutter_sdk", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Camera permission denied"]))
            return
        }

        ensureDeviceManager { manager in
            guard let manager = manager, let camera = manager.cameras.first else {
                completion(nil, NSError(domain: "acs_flutter_sdk", code: -1, userInfo: [NSLocalizedDescriptionKey: "No camera available"]))
                return
            }
            // Use ObjC exception catcher: ACSLocalVideoStream init: can throw
            // an NSException (ObjC) which Swift's do-catch cannot catch.
            // Without this wrapper, the exception causes SIGABRT.
            var createdStream: LocalVideoStream?
            var swiftError: Error?
            let objcError = ObjCExceptionCatcher.catchException(in: {
                do {
                    createdStream = try LocalVideoStream(camera: camera)
                } catch {
                    swiftError = error
                }
            })

            if let stream = createdStream, objcError == nil, swiftError == nil {
                self.localVideoStream = stream
                self.currentCamera = camera
                completion(stream, nil)
            } else {
                let finalError = objcError ?? (swiftError as NSError?) ?? NSError(
                    domain: "acs_flutter_sdk",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create LocalVideoStream: unknown error"])
                completion(nil, finalError)
            }
        }
    }

    private func callStateToString(_ state: CallState) -> String {
        switch state {
        case .none: return "none"
        case .connecting: return "connecting"
        case .ringing: return "ringing"
        case .connected: return "connected"
        case .localHold: return "onHold"
        case .disconnecting: return "disconnecting"
        case .disconnected: return "disconnected"
        case .earlyMedia: return "earlyMedia"
        case .remoteHold: return "remoteHold"
        @unknown default: return "unknown"
        }
    }

    private func lobbyStateDescription(for call: Call?) -> String? {
        guard let lobby = call?.callLobby else { return nil }
        return lobby.participants.isEmpty ? nil : "inLobby"
    }

    private func identifierString(from identifier: CommunicationIdentifier?) -> String {
        guard let identifier = identifier else { return "" }
        return identifier.rawId
    }

    private func dataFromHexString(_ hex: String) -> Data? {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard cleaned.count % 2 == 0 else { return nil }

        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index..<next]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    // MARK: - CallDelegate

    public func call(_ call: Call, didUpdateState args: PropertyChangedEventArgs) {
        safeHandle("call.didUpdateState") {
            let stateString = callStateToString(call.state)
            debugLog("[ACS][Plugin] ========== CALL STATE CHANGED ==========")
            debugLog("[ACS][Plugin] CallDelegate didUpdateState: state=\(stateString), callId=\(call.id)")
            debugLog("[ACS][Plugin] CallDelegate didUpdateState: remoteParticipants.count=\(call.remoteParticipants.count)")

            // Log lobby status on every state change
            let lobby = call.callLobby
            debugLog("[ACS][Plugin] CallDelegate didUpdateState: lobby.participants.count=\(lobby.participants.count)")
            for (index, lobbyP) in lobby.participants.enumerated() {
                debugLog("[ACS][Plugin] CallDelegate lobby[\(index)]: id=\(lobbyP.identifier.rawId)")
            }
            debugLog("[ACS][Plugin] ==========================================")

            if call.state == .disconnected {
                debugLog("[ACS][Plugin] Call disconnected, cleaning up resources")
                participantMonitorTimer?.invalidate()
                participantMonitorTimer = nil
                cleanupCallResources()
            }

            // When call connects, log all participants and their video streams
            if call.state == .connected {
                debugLog("[ACS][Plugin] Call CONNECTED - Checking remote participants:")
                for (index, participant) in call.remoteParticipants.enumerated() {
                    debugLog("[ACS][Plugin] Connected participant[\(index)]: id=\(participant.identifier.rawId), state=\(participant.state)")
                    debugLog("[ACS][Plugin] Connected participant[\(index)]: incomingVideoStreams.count=\(participant.incomingVideoStreams.count)")
                    for stream in participant.incomingVideoStreams {
                        if let remoteStream = stream as? RemoteVideoStream {
                            debugLog("[ACS][Plugin] Connected participant[\(index)] stream: id=\(remoteStream.id), isAvailable=\(remoteStream.isAvailable), state=\(remoteStream.state)")
                        }
                    }
                }

                // IMPORTANT: Re-process existing participants when connected
                // They may have been added before delegate was set
                if !call.remoteParticipants.isEmpty {
                    debugLog("[ACS][Plugin] Re-processing \(call.remoteParticipants.count) existing participants on connect")
                    handleAddedParticipants(call.remoteParticipants)
                }
            }

            // Log for inLobby state
            if call.state == .inLobby {
                debugLog("[ACS][Plugin] User is IN LOBBY - waiting to be admitted")
            }

            channel?.invokeMethod("callStateChanged", arguments: [
                "state": lobbyStateDescription(for: call) ?? stateString
            ])
        }
    }

    public func call(_ call: Call, didUpdateRemoteParticipants args: ParticipantsUpdatedEventArgs) {
        safeHandle("call.didUpdateRemoteParticipants") {
            debugLog("[ACS][Plugin] ========== PARTICIPANTS CHANGED ==========")
            debugLog("[ACS][Plugin] CallDelegate didUpdateRemoteParticipants: added=\(args.addedParticipants.count), removed=\(args.removedParticipants.count)")

            // Log details of added participants
            for (index, participant) in args.addedParticipants.enumerated() {
                debugLog("[ACS][Plugin] ADDED participant[\(index)]: id=\(participant.identifier.rawId), state=\(participant.state)")
                debugLog("[ACS][Plugin] ADDED participant[\(index)]: streams=\(participant.incomingVideoStreams.count), isMuted=\(participant.isMuted)")
            }

            // Log details of removed participants
            for (index, participant) in args.removedParticipants.enumerated() {
                debugLog("[ACS][Plugin] REMOVED participant[\(index)]: id=\(participant.identifier.rawId)")
            }

            debugLog("[ACS][Plugin] Current total remoteParticipants: \(call.remoteParticipants.count)")
            debugLog("[ACS][Plugin] ===========================================")

            handleAddedParticipants(args.addedParticipants)
            handleRemovedParticipants(args.removedParticipants)
        }
    }

    // MARK: - RemoteParticipantDelegate

    public func remoteParticipant(_ remoteParticipant: RemoteParticipant, didUpdateVideoStreams args: RemoteVideoStreamsEventArgs) {
        safeHandle("remoteParticipant.didUpdateVideoStreams") {
            debugLog("[ACS][Plugin] didUpdateVideoStreams: added=\(args.addedRemoteVideoStreams.count), removed=\(args.removedRemoteVideoStreams.count)")
            args.addedRemoteVideoStreams.forEach { stream in
                debugLog("[ACS][Plugin] New remote stream added: id=\(stream.id), isAvailable=\(stream.isAvailable), state=\(stream.state)")
                reconcileRemoteStream(stream)
            }
            args.removedRemoteVideoStreams.forEach { stream in
                debugLog("[ACS][Plugin] Remote stream removed: id=\(stream.id)")
                removeRemoteStream(streamId: Int(stream.id))
            }
            // Keep this participant's grid tile (if mounted) in sync with its streams.
            reconcileParticipantTile(participantId: remoteParticipant.identifier.rawId)
            emitParticipantEvent(type: "participantUpdated", participant: remoteParticipant)
        }
    }

    public func remoteParticipant(_ remoteParticipant: RemoteParticipant, didChangeVideoStreamState args: VideoStreamStateChangedEventArgs) {
        safeHandle("remoteParticipant.didChangeVideoStreamState") {
            if let stream = args.stream as? RemoteVideoStream {
                debugLog("[ACS][Plugin] didChangeVideoStreamState: id=\(stream.id), isAvailable=\(stream.isAvailable), newState=\(stream.state)")
                reconcileRemoteStream(stream)
            }
            // Availability flips drive per-participant tile attach/detach.
            reconcileParticipantTile(participantId: remoteParticipant.identifier.rawId)
            emitParticipantEvent(type: "participantUpdated", participant: remoteParticipant)
        }
    }

    // MARK: - CapabilitiesCallFeatureDelegate
    public func capabilitiesCallFeature(_ capabilitiesCallFeature: CapabilitiesCallFeature, didChangeCapabilities args: CapabilitiesChangedEventArgs) {
        safeHandle("capabilities.didChange") {
            guard let sink = capabilitiesEventSink else { return }
            let changed = args.changedCapabilities.map { serialize(capability: $0) }
            let payload: [String: Any] = [
                "reason": String(describing: args.reason),
                "changedCapabilities": changed
            ]
            DispatchQueue.main.async {
                sink(payload)
            }
        }
    }


    // MARK: - CallAgentDelegate

    public func callAgent(_ callAgent: CallAgent, didReceiveIncomingCall incomingCall: IncomingCall) {
        self.incomingCall = incomingCall
        emitIncomingCallEvent(type: "incoming", incomingCall: incomingCall)
    }
}

extension AcsFlutterSdkPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        // Replay any first-frame signals that fired before this subscription so a
        // cold-connect tile clears its spinner immediately.
        drainPendingFirstFrameEvents()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

private final class EventSinkHandler: NSObject, FlutterStreamHandler {
    private let onListen: (FlutterEventSink?) -> Void

    init(onListen: @escaping (FlutterEventSink?) -> Void) {
        self.onListen = onListen
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListen(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onListen(nil)
        return nil
    }
}

// MARK: - Serialization helpers
extension AcsFlutterSdkPlugin {
    private func emitParticipantEvent(type: String, participant: RemoteParticipant) {
        guard let sink = eventSink else { return }
        var payload: [String: Any] = ["type": type, "id": participant.identifier.rawId]
        if type == "participantUpdated" || type == "participantAdded" {
            payload["participant"] = serialize(participant: participant)
        }
        DispatchQueue.main.async {
            sink(payload)
        }
    }

    private func emitIncomingCallEvent(type: String, incomingCall: IncomingCall?) {
        guard let sink = incomingCallEventSink else { return }
        var payload: [String: Any] = ["type": type]
        if let incomingCall = incomingCall {
            payload["call"] = serialize(incomingCall: incomingCall)
        }
        DispatchQueue.main.async {
            sink(payload)
        }
    }

    private func emitCallFeatureEvent(type: String, payload: [String: Any]) {
        guard let sink = callFeaturesEventSink else { return }
        var data = payload
        data["type"] = type
        DispatchQueue.main.async {
            sink(data)
        }
    }

    private func emitCaptionsEvent(type: String, payload: [String: Any]) {
        guard let sink = captionsEventSink else { return }
        var data = payload
        data["type"] = type
        DispatchQueue.main.async {
            sink(data)
        }
    }

    private func emitRealTimeTextEvent(info: RealTimeTextInfo) {
        guard let sink = realTimeTextEventSink else { return }
        let payload: [String: Any] = [
            "type": "realTimeTextReceived",
            "info": serialize(realTimeTextInfo: info)
        ]
        DispatchQueue.main.async {
            sink(payload)
        }
    }

    private func emitDataChannelEvent(type: String, payload: [String: Any]) {
        guard let sink = dataChannelEventSink else { return }
        var data = payload
        data["type"] = type
        DispatchQueue.main.async {
            sink(data)
        }
    }

    private func emitDiagnosticsEvent(type: String, payload: [String: Any]) {
        guard let sink = diagnosticsEventSink else { return }
        var data = payload
        data["type"] = type
        DispatchQueue.main.async {
            sink(data)
        }
    }

    private func serialize(capability: ParticipantCapability) -> [String: Any] {
        return [
            "type": String(describing: capability.type),
            "isAllowed": capability.isAllowed,
            "reason": String(describing: capability.reason)
        ]
    }

    private func serialize(raisedHand: RaisedHand) -> [String: Any] {
        return [
            "identifier": raisedHand.identifier.rawId,
            "order": raisedHand.order
        ]
    }

    private func serialize(captions: CallCaptions) -> [String: Any] {
        var payload: [String: Any] = [
            "available": true,
            "isEnabled": captions.isEnabled,
            "type": String(describing: captions.type),
            "activeSpokenLanguage": captions.activeSpokenLanguage,
            "supportedSpokenLanguages": captions.supportedSpokenLanguages
        ]
        if let teams = captions as? TeamsCaptions {
            payload["activeCaptionLanguage"] = teams.activeCaptionLanguage
            payload["supportedCaptionLanguages"] = teams.supportedCaptionLanguages
        }
        return payload
    }

    private func serialize(teamsCaptions args: TeamsCaptionsReceivedEventArgs) -> [String: Any] {
        return [
            "captionsType": "teams",
            "speaker": args.speaker.identifier.rawId,
            "spokenText": args.spokenText,
            "spokenLanguage": args.spokenLanguage,
            "captionText": args.captionText,
            "captionLanguage": args.captionLanguage,
            "resultType": String(describing: args.resultType),
            "timestamp": args.timestamp.iso8601String()
        ]
    }

    private func serialize(communicationCaptions args: CommunicationCaptionsReceivedEventArgs) -> [String: Any] {
        return [
            "captionsType": "communication",
            "speaker": args.speaker.identifier.rawId,
            "spokenText": args.spokenText,
            "spokenLanguage": args.spokenLanguage,
            "resultType": String(describing: args.resultType),
            "timestamp": args.timestamp.iso8601String()
        ]
    }

    private func serialize(realTimeTextInfo info: RealTimeTextInfo) -> [String: Any] {
        return [
            "sender": info.sender.identifier.rawId,
            "sequenceId": info.sequenceId,
            "text": info.text,
            "resultType": String(describing: info.resultType),
            "receivedTime": info.receivedTime.iso8601String(),
            "updatedTime": info.updatedTime.iso8601String(),
            "isLocal": info.isLocal
        ]
    }

    private func serialize(mediaStatisticsReport report: MediaStatisticsReport) -> [String: Any] {
        return [
            "lastUpdated": report.lastUpdated.iso8601String(),
            "outgoing": serialize(outgoingStatistics: report.outgoingStatistics),
            "incoming": serialize(incomingStatistics: report.incomingStatistics)
        ]
    }

    private func serialize(outgoingStatistics stats: OutgoingMediaStatistics?) -> [String: Any] {
        guard let stats = stats else {
            return [
                "audio": [],
                "video": [],
                "screenShare": [],
                "dataChannel": []
            ]
        }
        return [
            "audio": stats.audio.map { serialize(outgoingAudio: $0) },
            "video": stats.video.map { serialize(outgoingVideo: $0) },
            "screenShare": stats.screenShare.map { serialize(outgoingScreenShare: $0) },
            "dataChannel": stats.dataChannel.map { serialize(outgoingDataChannel: $0) }
        ]
    }

    private func serialize(incomingStatistics stats: IncomingMediaStatistics?) -> [String: Any] {
        guard let stats = stats else {
            return [
                "audio": [],
                "video": [],
                "screenShare": [],
                "dataChannel": []
            ]
        }
        return [
            "audio": stats.audio.map { serialize(incomingAudio: $0) },
            "video": stats.video.map { serialize(incomingVideo: $0) },
            "screenShare": stats.screenShare.map { serialize(incomingScreenShare: $0) },
            "dataChannel": stats.dataChannel.map { serialize(incomingDataChannel: $0) }
        ]
    }

    private func serialize(outgoingAudio stat: OutgoingAudioStatistics) -> [String: Any] {
        return [
            "codecName": stat.codecName,
            "bitrateInBps": stat.bitrateInBps as Any,
            "jitterInMs": stat.jitterInMs as Any,
            "packetCount": stat.packetCount as Any,
            "streamId": stat.streamId as Any
        ]
    }

    private func serialize(outgoingVideo stat: OutgoingVideoStatistics) -> [String: Any] {
        return [
            "codecName": stat.codecName,
            "bitrateInBps": stat.bitrateInBps as Any,
            "packetCount": stat.packetCount as Any,
            "streamId": stat.streamId as Any,
            "frameRate": stat.frameRate as Any,
            "frameWidth": stat.frameWidth as Any,
            "frameHeight": stat.frameHeight as Any
        ]
    }

    private func serialize(outgoingScreenShare stat: OutgoingScreenShareStatistics) -> [String: Any] {
        return [
            "codecName": stat.codecName,
            "bitrateInBps": stat.bitrateInBps as Any,
            "packetCount": stat.packetCount as Any,
            "streamId": stat.streamId as Any,
            "frameRate": stat.frameRate as Any,
            "frameWidth": stat.frameWidth as Any,
            "frameHeight": stat.frameHeight as Any
        ]
    }

    private func serialize(outgoingDataChannel stat: OutgoingDataChannelStatistics) -> [String: Any] {
        return [
            "packetCount": stat.packetCount as Any
        ]
    }

    private func serialize(incomingAudio stat: IncomingAudioStatistics) -> [String: Any] {
        return [
            "codecName": stat.codecName,
            "jitterInMs": stat.jitterInMs as Any,
            "packetCount": stat.packetCount as Any,
            "packetsLostPerSecond": stat.packetsLostPerSecond as Any,
            "streamId": stat.streamId as Any
        ]
    }

    private func serialize(incomingVideo stat: IncomingVideoStatistics) -> [String: Any] {
        return [
            "codecName": stat.codecName,
            "bitrateInBps": stat.bitrateInBps as Any,
            "jitterInMs": stat.jitterInMs as Any,
            "packetCount": stat.packetCount as Any,
            "packetsLostPerSecond": stat.packetsLostPerSecond as Any,
            "streamId": stat.streamId as Any,
            "frameRate": stat.frameRate as Any,
            "frameWidth": stat.frameWidth as Any,
            "frameHeight": stat.frameHeight as Any,
            "totalFreezeDurationInMs": stat.totalFreezeDurationInMs as Any,
            "participantIdentifier": stat.participantIdentifier.rawId
        ]
    }

    private func serialize(incomingScreenShare stat: IncomingScreenShareStatistics) -> [String: Any] {
        return [
            "bitrateInBps": stat.bitrateInBps as Any,
            "jitterInMs": stat.jitterInMs as Any,
            "packetCount": stat.packetCount as Any,
            "packetsLostPerSecond": stat.packetsLostPerSecond as Any,
            "streamId": stat.streamId as Any,
            "frameRate": stat.frameRate as Any,
            "frameWidth": stat.frameWidth as Any,
            "frameHeight": stat.frameHeight as Any,
            "totalFreezeDurationInMs": stat.totalFreezeDurationInMs as Any,
            "participantIdentifier": stat.participantIdentifier.rawId
        ]
    }

    private func serialize(incomingDataChannel stat: IncomingDataChannelStatistics) -> [String: Any] {
        return [
            "jitterInMs": stat.jitterInMs as Any,
            "packetCount": stat.packetCount as Any
        ]
    }

    /// Converts ACSDiagnosticQuality enum to a human-readable string.
    /// rawValue mapping: 0=unknown, 1=good, 2=poor, 3=bad
    private func diagnosticQualityToString(_ quality: DiagnosticQuality) -> String {
        switch quality {
        case .unknown: return "unknown"
        case .good: return "good"
        case .poor: return "poor"
        case .bad: return "bad"
        @unknown default: return "unknown"
        }
    }

    private func serializeDiagnostics(_ diagnostics: LocalUserDiagnosticsCallFeature) -> [String: Any] {
        let network = diagnostics.networkDiagnostics.latest
        let media = diagnostics.mediaDiagnostics.latest
        return [
            "network": [
                "lastUpdated": network.lastUpdated.iso8601String(),
                "isNetworkUnavailable": network.isNetworkUnavailable as Any,
                "isNetworkRelaysUnreachable": network.isNetworkRelaysUnreachable as Any,
                "networkReconnectionQuality": diagnosticQualityToString(network.networkReconnectionQuality),
                "networkSendQuality": diagnosticQualityToString(network.networkSendQuality),
                "networkReceiveQuality": diagnosticQualityToString(network.networkReceiveQuality)
            ],
            "media": [
                "lastUpdated": media.lastUpdated.iso8601String(),
                "isSpeakerNotFunctioning": media.isSpeakerNotFunctioning as Any,
                "isSpeakerBusy": media.isSpeakerBusy as Any,
                "isSpeakerMuted": media.isSpeakerMuted as Any,
                "isSpeakerVolumeZero": media.isSpeakerVolumeZero as Any,
                "isNoSpeakerDevicesAvailable": media.isNoSpeakerDevicesAvailable as Any,
                "isSpeakingWhileMicrophoneIsMuted": media.isSpeakingWhileMicrophoneIsMuted as Any,
                "isNoMicrophoneDevicesAvailable": media.isNoMicrophoneDevicesAvailable as Any,
                "isMicrophoneBusy": media.isMicrophoneBusy as Any,
                "isCameraFreeze": media.isCameraFreeze as Any,
                "isCameraStartFailed": media.isCameraStartFailed as Any,
                "isCameraStartTimedOut": media.isCameraStartTimedOut as Any,
                "isMicrophoneNotFunctioning": media.isMicrophoneNotFunctioning as Any,
                "isMicrophoneMutedUnexpectedly": media.isMicrophoneMutedUnexpectedly as Any,
                "isCameraPermissionDenied": media.isCameraPermissionDenied as Any
            ]
        ]
    }

    private func serialize(participant: RemoteParticipant) -> [String: Any] {
        let videos: [[String: Any]] = participant.incomingVideoStreams.compactMap { stream in
            guard let remote = stream as? RemoteVideoStream else { return nil }
            // Use the native isAvailable property as recommended by Microsoft documentation
            // https://learn.microsoft.com/en-us/azure/communication-services/how-tos/calling-sdk/manage-video
            let isAvailable = remote.isAvailable
            let state = remote.state
            return [
                "id": Int(remote.id),
                "type": stream.mediaStreamType.toString(),
                "isAvailable": isAvailable,
                "state": String(describing: state)
            ]
        }

        return [
            "id": participant.identifier.rawId,
            "displayName": participant.displayName ?? "",
            "state": participantStateToString(participant.state),
            "isMuted": participant.isMuted,
            "isSpeaking": participant.isSpeaking,
            "videoStreams": videos
        ]
    }

    private func serialize(incomingCall: IncomingCall) -> [String: Any] {
        let callerInfo = incomingCall.callerInfo
        return [
            "id": incomingCall.id,
            "callerId": callerInfo.identifier.rawId,
            "displayName": callerInfo.displayName ?? "",
            "hasVideo": false
        ]
    }

    private func participantStateToString(_ state: ParticipantState) -> String {
        switch state {
        case .earlyMedia: return "earlyMedia"
        case .idle: return "none"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .hold: return "onHold"
        case .disconnected: return "disconnected"
        case .ringing: return "ringing"
        @unknown default: return "unknown"
        }
    }
}

private extension MediaStreamType {
    func toString() -> String {
        switch self {
        case .screenSharing: return "screenshare"
        case .video: return "video"
        @unknown default: return "unknown"
        }
    }
}

private let isoDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

// MARK: - Extended Calling Features
extension AcsFlutterSdkPlugin {
    private func startCaptions(args: [String: Any], result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }

        let spokenLanguage = args["spokenLanguage"] as? String
        let captionsFeature = activeCall.feature(Features.captions)
        captionsFeature.getCaptions { [weak self] captions, error in
            guard let self = self else { return }
            if let error = error {
                result(FlutterError(code: "CAPTIONS_ERROR", message: error.localizedDescription, details: nil))
                return
            }
            guard let captions = captions else {
                result(FlutterError(code: "CAPTIONS_ERROR", message: "Captions unavailable", details: nil))
                return
            }
            self.callCaptions = captions
            self.attachCaptionsHandlers(captions)
            let options = StartCaptionsOptions()
            if let spokenLanguage = spokenLanguage {
                options.spokenLanguage = spokenLanguage
            }
            captions.startCaptions(options: options) { error in
                if let error = error {
                    result(FlutterError(code: "CAPTIONS_ERROR", message: error.localizedDescription, details: nil))
                } else {
                    self.emitCaptionsStateChanged(captions)
                    result(true)
                }
            }
        }
    }

    private func stopCaptions(result: @escaping FlutterResult) {
        guard let captions = callCaptions else {
            result(nil)
            return
        }
        captions.stopCaptions { error in
            if let error = error {
                result(FlutterError(code: "CAPTIONS_ERROR", message: error.localizedDescription, details: nil))
            } else {
                self.emitCaptionsStateChanged(captions)
                result(nil)
            }
        }
    }

    private func setSpokenLanguage(args: [String: Any], result: @escaping FlutterResult) {
        guard let language = args["language"] as? String, !language.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Language is required", details: nil))
            return
        }
        guard let captions = callCaptions else {
            result(FlutterError(code: "NO_CAPTIONS", message: "Captions not started", details: nil))
            return
        }
        captions.set(spokenLanguage: language) { error in
            if let error = error {
                result(FlutterError(code: "CAPTIONS_ERROR", message: error.localizedDescription, details: nil))
            } else {
                self.emitCaptionsStateChanged(captions)
                result(nil)
            }
        }
    }

    private func setCaptionLanguage(args: [String: Any], result: @escaping FlutterResult) {
        guard let language = args["language"] as? String, !language.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Language is required", details: nil))
            return
        }
        guard let teamsCaptions = callCaptions as? TeamsCaptions else {
            result(FlutterError(code: "NO_CAPTIONS", message: "Teams captions not available", details: nil))
            return
        }
        teamsCaptions.set(captionLanguage: language) { error in
            if let error = error {
                result(FlutterError(code: "CAPTIONS_ERROR", message: error.localizedDescription, details: nil))
            } else {
                self.emitCaptionsStateChanged(teamsCaptions)
                result(nil)
            }
        }
    }

    private func isRecordingActive(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.recording)
        result(feature.isRecordingActive)
    }

    private func isTranscriptionActive(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.transcription)
        result(feature.isTranscriptionActive)
    }

    private func getDominantSpeakers(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.dominantSpeakers)
        let speakers = feature.dominantSpeakersInfo.speakers
        let ids = speakers.compactMap { $0.rawId }
        result(ids)
    }

    private func raiseHand(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.raisedHands)
        feature.raiseHand { error in
            if let error = error {
                result(FlutterError(code: "RAISE_HAND_FAILED", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func lowerHand(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.raisedHands)
        feature.lowerHand { error in
            if let error = error {
                result(FlutterError(code: "LOWER_HAND_FAILED", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func lowerAllHands(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.raisedHands)
        feature.lowerAllHands { error in
            if let error = error {
                result(FlutterError(code: "LOWER_ALL_HANDS_FAILED", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func lowerHands(args: [String: Any], result: @escaping FlutterResult) {
        guard let ids = args["identifiers"] as? [String], !ids.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "identifiers is required", details: nil))
            return
        }
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.raisedHands)
        let identifiers = ids.map { createCommunicationIdentifier(fromRawId: $0) }
        feature.lowerHands(participants: identifiers) { error in
            if let error = error {
                result(FlutterError(code: "LOWER_HANDS_FAILED", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func getRaisedHands(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.raisedHands)
        let payload = feature.raisedHands.map { serialize(raisedHand: $0) }
        result(payload)
    }

    private func getSpotlightedParticipants(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.spotlight)
        let ids = feature.spotlightedParticipants.map { $0.identifier.rawId }
        result(ids)
    }

    private func getMaxSpotlightedParticipants(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.spotlight)
        result(Int(feature.maxSpotlightedParticipants))
    }

    private func spotlightParticipants(args: [String: Any], result: @escaping FlutterResult) {
        guard let ids = args["identifiers"] as? [String], !ids.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "identifiers is required", details: nil))
            return
        }
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.spotlight)
        let identifiers = ids.map { createCommunicationIdentifier(fromRawId: $0) }
        feature.spotlight(identifiers: identifiers) { error in
            if let error = error {
                result(FlutterError(code: "SPOTLIGHT_FAILED", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func cancelSpotlights(args: [String: Any], result: @escaping FlutterResult) {
        guard let ids = args["identifiers"] as? [String], !ids.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "identifiers is required", details: nil))
            return
        }
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.spotlight)
        let identifiers = ids.map { createCommunicationIdentifier(fromRawId: $0) }
        feature.cancelSpotlights(identifiers: identifiers) { error in
            if let error = error {
                result(FlutterError(code: "CANCEL_SPOTLIGHT_FAILED", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func cancelAllSpotlights(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.spotlight)
        feature.cancelAllSpotlights { error in
            if let error = error {
                result(FlutterError(code: "CANCEL_SPOTLIGHT_FAILED", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func sendRealTimeText(args: [String: Any], result: @escaping FlutterResult) {
        guard let text = args["text"] as? String, !text.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "text is required", details: nil))
            return
        }
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let finalized = args["finalized"] as? Bool ?? true
        let feature = realTimeTextFeature ?? activeCall.feature(Features.realTimeText)
        do {
            if finalized {
                try feature.send(text: text)
            } else {
                try feature.send(text: text, finalized: false)
            }
            result(nil)
        } catch {
            result(FlutterError(code: "RTT_SEND_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func getCaptionsState(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.captions)
        feature.getCaptions { [weak self] captions, error in
            guard let self = self else { return }
            if let error = error {
                result(FlutterError(code: "CAPTIONS_ERROR", message: error.localizedDescription, details: nil))
                return
            }
            guard let captions = captions else {
                result(["available": false])
                return
            }
            self.callCaptions = captions
            self.attachCaptionsHandlers(captions)
            result(self.serialize(captions: captions))
        }
    }

    private func setMediaStatisticsReportInterval(args: [String: Any], result: @escaping FlutterResult) {
        guard let seconds = args["reportIntervalInSeconds"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "reportIntervalInSeconds is required", details: nil))
            return
        }
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = mediaStatisticsFeature ?? activeCall.feature(Features.mediaStatistics)
        do {
            try feature.updateReportInterval(inSeconds: Int32(seconds))
            result(nil)
        } catch {
            result(FlutterError(code: "MEDIA_STATISTICS_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func getMediaStatisticsReportInterval(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = mediaStatisticsFeature ?? activeCall.feature(Features.mediaStatistics)
        result(Int(feature.reportIntervalInSeconds))
    }

    private func getLatestDiagnostics(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = localUserDiagnosticsFeature ?? activeCall.feature(Features.localUserDiagnostics)
        result(serializeDiagnostics(feature))
    }

    private func createDataChannelSender(args: [String: Any], result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = dataChannelFeature ?? activeCall.feature(Features.dataChannel)
        let options = DataChannelSenderOptions()
        if let channelId = args["channelId"] as? Int {
            options.channelId = Int32(channelId)
        }
        if let bitrate = args["bitrateInKbps"] as? Int {
            options.bitrateInKbps = Int32(bitrate)
        }
        if let priority = args["priority"] as? String {
            options.priority = priority == "high" ? .high : .normal
        }
        if let reliability = args["reliability"] as? String {
            options.reliability = reliability == "durable" ? .durable : .lossy
        }
        let sender = feature.getDataChannelSender(options: options)
        if let participants = args["participants"] as? [String], !participants.isEmpty {
            let identifiers = participants.map { createCommunicationIdentifier(fromRawId: $0) }
            sender.setParticipants(participants: identifiers)
        }
        let senderId = Int(sender.channelId)
        dataChannelSenders[senderId] = sender
        result([
            "channelId": senderId,
            "maxMessageSizeInBytes": Int(sender.maxMessageSizeInBytes)
        ])
    }

    private func sendDataChannelMessage(args: [String: Any], result: @escaping FlutterResult) {
        guard let channelId = args["channelId"] as? Int,
              let data = args["data"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "channelId and data are required", details: nil))
            return
        }
        guard let sender = dataChannelSenders[channelId] else {
            result(FlutterError(code: "SENDER_NOT_FOUND", message: "No sender for channelId", details: nil))
            return
        }
        sender.sendMessage(data: data.data)
        result(nil)
    }

    private func closeDataChannelSender(args: [String: Any], result: @escaping FlutterResult) {
        guard let channelId = args["channelId"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "channelId is required", details: nil))
            return
        }
        if let sender = dataChannelSenders[channelId] {
            sender.close()
            dataChannelSenders.removeValue(forKey: channelId)
        }
        result(nil)
    }

    private func setDataChannelParticipants(args: [String: Any], result: @escaping FlutterResult) {
        guard let channelId = args["channelId"] as? Int,
              let participants = args["participants"] as? [String] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "channelId and participants are required", details: nil))
            return
        }
        guard let sender = dataChannelSenders[channelId] else {
            result(FlutterError(code: "SENDER_NOT_FOUND", message: "No sender for channelId", details: nil))
            return
        }
        let identifiers = participants.map { createCommunicationIdentifier(fromRawId: $0) }
        sender.setParticipants(participants: identifiers)
        result(nil)
    }

    private func startSurvey(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.survey)
        feature.startSurvey { [weak self] survey, error in
            guard let self = self else { return }
            if let error = error {
                result(FlutterError(code: "SURVEY_FAILED", message: error.localizedDescription, details: nil))
                return
            }
            guard let survey = survey else {
                result(FlutterError(code: "SURVEY_FAILED", message: "Survey not available", details: nil))
                return
            }
            let handle = UUID().uuidString
            self.pendingSurveys[handle] = survey
            result(["handle": handle])
        }
    }

    private func submitSurvey(args: [String: Any], result: @escaping FlutterResult) {
        guard let handle = args["handle"] as? String, !handle.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle is required", details: nil))
            return
        }
        guard let survey = pendingSurveys[handle] else {
            result(FlutterError(code: "SURVEY_NOT_FOUND", message: "No survey for handle", details: nil))
            return
        }
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        let feature = activeCall.feature(Features.survey)
        applySurveyInputs(args: args, survey: survey)
        feature.submit(survey: survey) { [weak self] resultSurvey, error in
            guard let self = self else { return }
            if let error = error {
                result(FlutterError(code: "SURVEY_FAILED", message: error.localizedDescription, details: nil))
                return
            }
            self.pendingSurveys.removeValue(forKey: handle)
            guard let resultSurvey = resultSurvey else {
                result(FlutterError(code: "SURVEY_FAILED", message: "Survey submission failed", details: nil))
                return
            }
            result([
                "surveyId": resultSurvey.surveyId,
                "callId": resultSurvey.callId,
                "anonymizedParticipantId": resultSurvey.anonymizedParticipantId
            ])
        }
    }

    private func discardSurvey(args: [String: Any], result: @escaping FlutterResult) {
        guard let handle = args["handle"] as? String, !handle.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle is required", details: nil))
            return
        }
        pendingSurveys.removeValue(forKey: handle)
        result(nil)
    }

    private func applySurveyInputs(args: [String: Any], survey: CallSurvey) {
        if let overall = args["overallScore"] as? [String: Any] {
            applySurveyScore(overall, target: survey.overallScore)
        }
        if let audio = args["audioScore"] as? [String: Any] {
            applySurveyScore(audio, target: survey.audioScore)
        }
        if let video = args["videoScore"] as? [String: Any] {
            applySurveyScore(video, target: survey.videoScore)
        }
        if let screen = args["screenShareScore"] as? [String: Any] {
            applySurveyScore(screen, target: survey.screenShareScore)
        }
        if let overallIssues = args["overallIssues"] as? Int {
            survey.overallIssues = CallIssues(rawValue: overallIssues)
        }
        if let audioIssues = args["audioIssues"] as? Int {
            survey.audioIssues = AudioIssues(rawValue: audioIssues)
        }
        if let videoIssues = args["videoIssues"] as? Int {
            survey.videoIssues = VideoIssues(rawValue: videoIssues)
        }
        if let screenIssues = args["screenShareIssues"] as? Int {
            survey.screenShareIssues = ScreenShareIssues(rawValue: screenIssues)
        }
    }

    private func applySurveyScore(_ input: [String: Any], target: CallSurveyScore) {
        if let score = input["score"] as? Int {
            target.score = Int32(score)
        }
        if let scaleInput = input["scale"] as? [String: Any] {
            let scale = CallSurveyRatingScale()
            if let lower = scaleInput["lowerBound"] as? Int {
                scale.lowerBound = Int32(lower)
            }
            if let upper = scaleInput["upperBound"] as? Int {
                scale.upperBound = Int32(upper)
            }
            if let threshold = scaleInput["lowScoreThreshold"] as? Int {
                scale.lowScoreThreshold = Int32(threshold)
            }
            target.scale = scale
        }
    }

    private func enableBackgroundBlur(result: @escaping FlutterResult) {
        ensureLocalVideoEffectsFeature { [weak self] feature, error in
            guard let self = self else { return }
            if let error = error {
                result(FlutterError(code: "VIDEO_EFFECT_ERROR", message: error.localizedDescription, details: nil))
                return
            }
            guard let feature = feature else {
                result(FlutterError(code: "VIDEO_EFFECT_ERROR", message: "Video effects unavailable", details: nil))
                return
            }
            let effect = BackgroundBlurEffect()
            feature.enable(effect: effect)
            self.activeVideoEffect = effect
            result(nil)
        }
    }

    private func enableBackgroundReplacement(args: [String: Any], result: @escaping FlutterResult) {
        guard let data = args["buffer"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "buffer is required", details: nil))
            return
        }
        ensureLocalVideoEffectsFeature { [weak self] feature, error in
            guard let self = self else { return }
            if let error = error {
                result(FlutterError(code: "VIDEO_EFFECT_ERROR", message: error.localizedDescription, details: nil))
                return
            }
            guard let feature = feature else {
                result(FlutterError(code: "VIDEO_EFFECT_ERROR", message: "Video effects unavailable", details: nil))
                return
            }
            let effect = BackgroundReplacementEffect()
            effect.buffer = data.data
            feature.enable(effect: effect)
            self.activeVideoEffect = effect
            result(nil)
        }
    }

    private func disableVideoEffects(result: @escaping FlutterResult) {
        guard let feature = try? localVideoStream?.feature(Features.localVideoEffects),
              let activeEffect = activeVideoEffect else {
            result(nil)
            return
        }
        feature.disable(effect: activeEffect)
        activeVideoEffect = nil
        result(nil)
    }

    private func muteIncomingAudio(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        activeCall.muteIncomingAudio { error in
            if let error = error {
                result(FlutterError(code: "MUTE_FAILED", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func unmuteIncomingAudio(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        activeCall.unmuteIncomingAudio { error in
            if let error = error {
                result(FlutterError(code: "UNMUTE_FAILED", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func muteAllRemoteParticipants(result: @escaping FlutterResult) {
        guard let activeCall = call else {
            result(FlutterError(code: "NO_ACTIVE_CALL", message: "No active call", details: nil))
            return
        }
        activeCall.muteAllRemoteParticipants { error in
            if let error = error {
                result(FlutterError(code: "MUTE_FAILED", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func admitLobbyParticipants(args: [String: Any], result: @escaping FlutterResult) {
        guard let ids = args["identifiers"] as? [String], !ids.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "identifiers is required", details: nil))
            return
        }
        guard let lobby = call?.callLobby else {
            result(FlutterError(code: "LOBBY_UNAVAILABLE", message: "Lobby not available", details: nil))
            return
        }
        let identifiers = ids.map { createCommunicationIdentifier(fromRawId: $0) }
        lobby.admit(identifiers: identifiers) { _, error in
            if let error = error {
                result(FlutterError(code: "LOBBY_FAILED", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func admitAllFromLobby(result: @escaping FlutterResult) {
        guard let lobby = call?.callLobby else {
            result(FlutterError(code: "LOBBY_UNAVAILABLE", message: "Lobby not available", details: nil))
            return
        }
        lobby.admitAll { _, error in
            if let error = error {
                result(FlutterError(code: "LOBBY_FAILED", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func rejectLobbyParticipant(args: [String: Any], result: @escaping FlutterResult) {
        guard let id = args["identifier"] as? String, !id.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "identifier is required", details: nil))
            return
        }
        guard let lobby = call?.callLobby else {
            result(FlutterError(code: "LOBBY_UNAVAILABLE", message: "Lobby not available", details: nil))
            return
        }
        let identifier = createCommunicationIdentifier(fromRawId: id)
        lobby.reject(identifier: identifier) { error in
            if let error = error {
                result(FlutterError(code: "LOBBY_FAILED", message: error.localizedDescription, details: nil))
            } else {
                result(nil)
            }
        }
    }

    private func getLobbyParticipants(result: @escaping FlutterResult) {
        guard let lobby = call?.callLobby else {
            result(FlutterError(code: "LOBBY_UNAVAILABLE", message: "Lobby not available", details: nil))
            return
        }
        let ids = lobby.participants.map { $0.identifier.rawId }
        result(ids)
    }

    private func getRemoteParticipants(result: @escaping FlutterResult) {
        guard let participants = call?.remoteParticipants else {
            result([])
            return
        }
        let ids = participants.map { $0.identifier.rawId }
        result(ids)
    }

    private func hasRemoteVideo(result: FlutterResult) {
        guard let participants = call?.remoteParticipants else {
            result(false)
            return
        }
        let hasVideo = participants.contains { participant in
            participant.incomingVideoStreams.contains { $0 is RemoteVideoStream }
        }
        result(hasVideo)
    }

    private func isInLobby(result: FlutterResult) {
        guard let lobby = call?.callLobby else {
            result(false)
            return
        }
        result(!lobby.participants.isEmpty)
    }

    private func ensureLocalVideoEffectsFeature(completion: @escaping (LocalVideoEffectsFeature?, Error?) -> Void) {
        ensureLocalVideoStream { stream, error in
            if let error = error {
                completion(nil, error)
                return
            }
            guard let stream = stream else {
                completion(nil, NSError(domain: "acs_flutter_sdk", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active video stream"]))
                return
            }
            let feature = stream.feature(Features.localVideoEffects)
            completion(feature, nil)
        }
    }
}

private extension Date {
    func iso8601String() -> String {
        isoDateFormatter.string(from: self)
    }
}

private func createCommunicationIdentifier(fromRawId rawId: String) -> CommunicationIdentifier {
    if rawId.hasPrefix("+") {
        return PhoneNumberIdentifier(phoneNumber: rawId)
    }
    return CommunicationUserIdentifier(rawId)
}

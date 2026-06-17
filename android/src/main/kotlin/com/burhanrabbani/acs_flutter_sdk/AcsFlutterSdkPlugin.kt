package com.burhanrabbani.acs_flutter_sdk

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.azure.android.communication.calling.*
import com.azure.android.communication.calling.TeamsMeetingLinkLocator
import com.azure.android.communication.common.CommunicationIdentifier
import com.azure.android.communication.common.CommunicationTokenCredential
import com.azure.android.communication.common.CommunicationUserIdentifier
import com.azure.android.communication.common.PhoneNumberIdentifier
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.nio.ByteBuffer

/**
 * Azure Communication Services Flutter plugin implementation.
 */
class AcsFlutterSdkPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, ActivityResultListener {

    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var capabilitiesEventChannel: EventChannel? = null
    private var capabilitiesEventSink: EventChannel.EventSink? = null
    private var incomingCallEventChannel: EventChannel? = null
    private var incomingCallEventSink: EventChannel.EventSink? = null
    private var callFeaturesEventChannel: EventChannel? = null
    private var callFeaturesEventSink: EventChannel.EventSink? = null
    private var captionsEventChannel: EventChannel? = null
    private var captionsEventSink: EventChannel.EventSink? = null
    private var realTimeTextEventChannel: EventChannel? = null
    private var realTimeTextEventSink: EventChannel.EventSink? = null
    private var dataChannelEventChannel: EventChannel? = null
    private var dataChannelEventSink: EventChannel.EventSink? = null
    private var mediaStatisticsEventChannel: EventChannel? = null
    private var mediaStatisticsEventSink: EventChannel.EventSink? = null
    private var diagnosticsEventChannel: EventChannel? = null
    private var diagnosticsEventSink: EventChannel.EventSink? = null

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var viewManager: VideoViewManager? = null
    private var videoRegistry: VideoStreamRegistry? = null
    // Registry of per-participant grid tiles (additive to the shared remote path).
    private var participantRegistry: ParticipantVideoRegistry<RemoteVideoStream>? = null

    // Azure Communication Services instances
    private var tokenCredential: CommunicationTokenCredential? = null
    private var callClient: CallClient? = null
    private var deviceManager: DeviceManager? = null
    private var callAgent: CallAgent? = null
    private var call: Call? = null
    private var localVideoStream: LocalVideoStream? = null
    private var currentCamera: VideoDeviceInfo? = null
    private var activeVideoEffect: VideoEffect? = null
    // Thread-safe screen share state management
    private val screenShareLock = Any()
    @Volatile private var screenShareStream: ScreenShareOutgoingVideoStream? = null
    @Volatile private var screenShareFormat: VideoStreamFormat? = null
    @Volatile private var screenShareActive: Boolean = false
    private var mediaProjectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var screenShareVirtualDisplay: VirtualDisplay? = null
    private var screenShareImageReader: ImageReader? = null
    private var screenShareHandlerThread: HandlerThread? = null
    private var screenShareHandler: Handler? = null
    // Android 14 (API 34) requires a MediaProjection.Callback registered BEFORE
    // createVirtualDisplay(); otherwise the call throws IllegalStateException.
    private var mediaProjectionCallback: MediaProjection.Callback? = null
    private var pendingScreenShareResult: Result? = null
    private var lastScreenShareFrameTimeNs: Long = 0L
    // Reusable buffer for screen share frames to reduce GC pressure
    private var screenShareBuffer: ByteBuffer? = null
    private var screenShareBufferSize: Int = 0
    private var callCaptions: CallCaptions? = null
    private var communicationCaptionsListener: CommunicationCaptionsListener? = null
    private var teamsCaptionsListener: TeamsCaptionsListener? = null
    private var captionsEnabledListener: PropertyChangedListener? = null
    private var spokenLanguageListener: PropertyChangedListener? = null
    private var captionLanguageListener: PropertyChangedListener? = null
    private var localUserDiagnosticsFeature: LocalUserDiagnosticsCallFeature? = null
    // Diagnostics listener references (for proper cleanup to prevent memory leaks)
    private var networkUnavailableListener: DiagnosticFlagChangedListener? = null
    private var networkRelaysUnreachableListener: DiagnosticFlagChangedListener? = null
    private var networkReconnectionQualityListener: DiagnosticQualityChangedListener? = null
    private var networkReceiveQualityListener: DiagnosticQualityChangedListener? = null
    private var networkSendQualityListener: DiagnosticQualityChangedListener? = null
    private var speakerNotFunctioningListener: DiagnosticFlagChangedListener? = null
    private var speakerBusyListener: DiagnosticFlagChangedListener? = null
    private var speakerMutedListener: DiagnosticFlagChangedListener? = null
    private var speakerVolumeZeroListener: DiagnosticFlagChangedListener? = null
    private var noSpeakerDevicesListener: DiagnosticFlagChangedListener? = null
    private var speakingWhileMutedListener: DiagnosticFlagChangedListener? = null
    private var noMicrophoneDevicesListener: DiagnosticFlagChangedListener? = null
    private var microphoneBusyListener: DiagnosticFlagChangedListener? = null
    private var cameraFrozenListener: DiagnosticFlagChangedListener? = null
    private var cameraStartFailedListener: DiagnosticFlagChangedListener? = null
    private var cameraStartTimedOutListener: DiagnosticFlagChangedListener? = null
    private var microphoneNotFunctioningListener: DiagnosticFlagChangedListener? = null
    private var microphoneMutedUnexpectedlyListener: DiagnosticFlagChangedListener? = null
    private var cameraPermissionDeniedListener: DiagnosticFlagChangedListener? = null
    // Media Statistics feature and listener
    private var mediaStatisticsFeature: MediaStatisticsCallFeature? = null
    private var mediaStatisticsReportListener: MediaStatisticsReportReceivedListener? = null
    private var incomingCall: IncomingCall? = null
    // Track participant listeners for proper cleanup to prevent memory leaks
    private data class ParticipantListeners(
        val videoStreamsListener: RemoteVideoStreamsUpdatedListener,
        val mutedListener: PropertyChangedListener,
        val speakingListener: PropertyChangedListener,
        val stateListener: PropertyChangedListener,
        // Per-stream availability listeners (streamId -> stream + listener), so a
        // remote camera turned on AFTER join is reflected. Tracked here for leak-free
        // removal in removeParticipantListeners / on stream-removed.
        val streamStateListeners: MutableMap<Int, Pair<RemoteVideoStream, VideoStreamStateChangedListener>> =
            mutableMapOf()
    )
    private val participantListenersMap = mutableMapOf<String, ParticipantListeners>()
    private var remoteParticipantListener: ParticipantsUpdatedListener? = null
    private var callStateListener: PropertyChangedListener? = null
    private var capabilitiesListener: CapabilitiesChangedListener? = null
    private var uiLibraryPlugin: Any? = null

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "acs_flutter_sdk")
        channel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "acs_flutter_sdk/events")
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        capabilitiesEventChannel = EventChannel(binding.binaryMessenger, "acs_flutter_sdk/capabilities")
        capabilitiesEventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                capabilitiesEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                capabilitiesEventSink = null
            }
        })

        incomingCallEventChannel = EventChannel(binding.binaryMessenger, "acs_flutter_sdk/incoming_calls")
        incomingCallEventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                incomingCallEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                incomingCallEventSink = null
            }
        })

        callFeaturesEventChannel = EventChannel(binding.binaryMessenger, "acs_flutter_sdk/call_features")
        callFeaturesEventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                callFeaturesEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                callFeaturesEventSink = null
            }
        })

        captionsEventChannel = EventChannel(binding.binaryMessenger, "acs_flutter_sdk/captions")
        captionsEventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                captionsEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                captionsEventSink = null
            }
        })

        realTimeTextEventChannel = EventChannel(binding.binaryMessenger, "acs_flutter_sdk/real_time_text")
        realTimeTextEventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                realTimeTextEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                realTimeTextEventSink = null
            }
        })

        dataChannelEventChannel = EventChannel(binding.binaryMessenger, "acs_flutter_sdk/data_channel")
        dataChannelEventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                dataChannelEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                dataChannelEventSink = null
            }
        })

        mediaStatisticsEventChannel = EventChannel(binding.binaryMessenger, "acs_flutter_sdk/media_statistics")
        mediaStatisticsEventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                mediaStatisticsEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                mediaStatisticsEventSink = null
            }
        })

        diagnosticsEventChannel = EventChannel(binding.binaryMessenger, "acs_flutter_sdk/diagnostics")
        diagnosticsEventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                diagnosticsEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                diagnosticsEventSink = null
            }
        })

        viewManager = VideoViewManager(context)
        videoRegistry = VideoStreamRegistry(context)
        participantRegistry = ParticipantVideoRegistry(context, AcsRendererFactory())
        binding.platformViewRegistry.registerViewFactory(
            PLATFORM_VIEW_TYPE,
            VideoPlatformViewFactory(
                viewManager!!,
                participantRegistry,
                // Reconcile a participant's stream into its tile as soon as it mounts.
                onParticipantViewCreated = { participantId ->
                    reconcileParticipantTile(participantId)
                }
            )
        )

        attachUiLibrary(binding)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
        capabilitiesEventChannel?.setStreamHandler(null)
        capabilitiesEventChannel = null
        capabilitiesEventSink = null
        incomingCallEventChannel?.setStreamHandler(null)
        incomingCallEventChannel = null
        incomingCallEventSink = null
        callFeaturesEventChannel?.setStreamHandler(null)
        callFeaturesEventChannel = null
        callFeaturesEventSink = null
        captionsEventChannel?.setStreamHandler(null)
        captionsEventChannel = null
        captionsEventSink = null
        realTimeTextEventChannel?.setStreamHandler(null)
        realTimeTextEventChannel = null
        realTimeTextEventSink = null
        dataChannelEventChannel?.setStreamHandler(null)
        dataChannelEventChannel = null
        dataChannelEventSink = null
        mediaStatisticsEventChannel?.setStreamHandler(null)
        mediaStatisticsEventChannel = null
        mediaStatisticsEventSink = null
        diagnosticsEventChannel?.setStreamHandler(null)
        diagnosticsEventChannel = null
        diagnosticsEventSink = null
        cleanupCallResources()
        executor.shutdown()
        viewManager = null
        videoRegistry = null
        participantRegistry?.clear()
        participantRegistry = null
        callClient = null
        callAgent = null
        tokenCredential = null
        detachUiLibrary(binding)
    }

    // region ActivityAware
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
        invokeUiLibrary("onAttachedToActivity", binding)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
        invokeUiLibrary("onReattachedToActivityForConfigChanges", binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        invokeUiLibrary("onDetachedFromActivityForConfigChanges")
    }

    override fun onDetachedFromActivity() {
        activity = null
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        invokeUiLibrary("onDetachedFromActivity")
    }
    // endregion

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SCREEN_SHARE_REQUEST_CODE) {
            return false
        }
        safeCall("onActivityResult:SCREEN_SHARE", pendingScreenShareResult) {
            val pendingResult = pendingScreenShareResult
            pendingScreenShareResult = null
            if (resultCode != Activity.RESULT_OK || data == null) {
                stopScreenShareForegroundService()
                pendingResult?.error("SCREEN_SHARE_PERMISSION_DENIED", "Screen share permission denied", null)
                return@safeCall
            }
            val mgr = mediaProjectionManager
                ?: (activity?.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager)
            mediaProjectionManager = mgr
            val projection = mgr?.getMediaProjection(resultCode, data)
            if (projection == null) {
                stopScreenShareForegroundService()
                pendingResult?.error("SCREEN_SHARE_NOT_SUPPORTED", "Screen share not supported", null)
                return@safeCall
            }
            startScreenShareInternal(projection, pendingResult)
        }
        return true
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        safeCall("onMethodCall:${call.method}", result) {
            when (call.method) {
                // Platform info
                "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")

                // Identity methods
                "initializeIdentity" -> initializeIdentity(call, result)
                "createUser" -> result.error(
                    "NOT_IMPLEMENTED",
                    "User creation should be done server-side for security. Use your backend API.",
                    null
                )
                "getToken" -> result.error(
                    "NOT_IMPLEMENTED",
                    "Token generation should be done server-side for security. Use your backend API.",
                    null
                )
                "revokeToken" -> result.error(
                    "NOT_IMPLEMENTED",
                    "Token revocation should be done server-side. Use your backend API.",
                    null
                )

                // Calling methods
                "initializeCalling" -> initializeCalling(call, result)
                "requestPermissions" -> requestPermissions(result)
                "startCall" -> startCall(call, result)
                "joinCall" -> joinCall(call, result)
                "joinTeamsMeeting" -> joinTeamsMeeting(call, result)
                "endCall" -> endCall(result)
                "muteAudio" -> muteAudio(result)
                "unmuteAudio" -> unmuteAudio(result)
                "startVideo" -> startVideo(result)
                "stopVideo" -> stopVideo(result)
                "switchCamera" -> switchCamera(result)
                "addParticipants" -> addParticipants(call, result)
                "removeParticipants" -> removeParticipants(call, result)
                "startCaptions" -> startCaptions(call, result)
                "stopCaptions" -> stopCaptions(result)
                "setSpokenLanguage" -> setSpokenLanguage(call, result)
                "setCaptionLanguage" -> setCaptionLanguage(call, result)
                "getCapabilities" -> getCapabilities(result)
                "acceptIncomingCall" -> acceptIncomingCall(call, result)
                "rejectIncomingCall" -> rejectIncomingCall(result)
                "registerPushNotifications" -> registerPushNotifications(call, result)
                "unregisterPushNotifications" -> unregisterPushNotifications(result)
                "handlePushNotification" -> handlePushNotification(call, result)
                "isRecordingActive" -> isRecordingActive(result)
                "isTranscriptionActive" -> isTranscriptionActive(result)
                "getDominantSpeakers" -> getDominantSpeakers(result)
                "enableBackgroundBlur" -> enableBackgroundBlur(result)
                "enableBackgroundReplacement" -> enableBackgroundReplacement(call, result)
                "disableVideoEffects" -> disableVideoEffects(result)
                "muteIncomingAudio" -> muteIncomingAudio(result)
                "unmuteIncomingAudio" -> unmuteIncomingAudio(result)
                "muteAllRemoteParticipants" -> muteAllRemoteParticipants(result)
                "admitLobbyParticipants" -> admitLobbyParticipants(call, result)
                "admitAllFromLobby" -> admitAllFromLobby(result)
                "rejectLobbyParticipant" -> rejectLobbyParticipant(call, result)
                "getLobbyParticipants" -> getLobbyParticipants(result)
                "getRemoteParticipants" -> getRemoteParticipants(result)
                "getRemoteParticipantStates" -> getRemoteParticipantStates(result)
                "holdCall" -> holdCall(result)
                "resumeCall" -> resumeCall(result)
                "transferCall" -> transferCall(call, result)
                "startScreenShare" -> startScreenShare(result)
                "stopScreenShare" -> stopScreenShare(result)
                "listCameras" -> listCameras(result)
                "setCamera" -> setCamera(call, result)
                "isInLobby" -> isInLobby(result)
                "hasRemoteVideo" -> hasRemoteVideo(result)
                "getCaptionsState" -> getCaptionsState(result)
                "getLatestDiagnostics" -> getLatestDiagnostics(result)

                // Raise Hand methods
                "raiseHand" -> raiseHand(result)
                "lowerHand" -> lowerHand(result)
                "lowerAllHands" -> lowerAllHands(result)
                "lowerHands" -> lowerHands(call, result)
                "getRaisedHands" -> getRaisedHands(result)

                // Spotlight methods
                "getSpotlightedParticipants" -> getSpotlightedParticipants(result)
                "getMaxSpotlightedParticipants" -> getMaxSpotlightedParticipants(result)
                "spotlightParticipants" -> spotlightParticipants(call, result)
                "cancelSpotlights" -> cancelSpotlights(call, result)
                "cancelAllSpotlights" -> cancelAllSpotlights(result)

                // Media Statistics methods
                "setMediaStatisticsReportInterval" -> setMediaStatisticsReportInterval(call, result)
                "getMediaStatisticsReportInterval" -> getMediaStatisticsReportInterval(result)

                // Real-Time Text methods
                "sendRealTimeText" -> sendRealTimeText(call, result)

                // Data Channel methods
                "createDataChannelSender" -> createDataChannelSender(call, result)
                "sendDataChannelMessage" -> sendDataChannelMessage(call, result)
                "closeDataChannelSender" -> closeDataChannelSender(call, result)
                "setDataChannelParticipants" -> setDataChannelParticipants(call, result)

                // Survey methods
                "startSurvey" -> startSurvey(result)
                "submitSurvey" -> submitSurvey(call, result)
                "discardSurvey" -> discardSurvey(result)

                // Chat methods - OPTIMIZATION: Chat feature removed
                "initializeChat" -> result.error("NOT_SUPPORTED", "Chat feature has been removed. This SDK only supports calling.", null)
                "createChatThread" -> result.error("NOT_SUPPORTED", "Chat feature has been removed. This SDK only supports calling.", null)
                "joinChatThread" -> result.error("NOT_SUPPORTED", "Chat feature has been removed. This SDK only supports calling.", null)
                "sendMessage" -> result.error("NOT_SUPPORTED", "Chat feature has been removed. This SDK only supports calling.", null)
                "getMessages" -> result.error("NOT_SUPPORTED", "Chat feature has been removed. This SDK only supports calling.", null)
                "sendTypingNotification" -> result.error("NOT_SUPPORTED", "Chat feature has been removed. This SDK only supports calling.", null)

                else -> result.notImplemented()
            }
        }
    }

    // region Identity
    private fun initializeIdentity(call: MethodCall, result: Result) {
        val connectionString = call.argument<String>("connectionString")
        if (connectionString.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Connection string is required", null)
            return
        }
        result.success(mapOf("status" to "initialized"))
    }
    // endregion

    // region Calling
    private fun initializeCalling(call: MethodCall, result: Result) {
        val accessToken = call.argument<String>("accessToken")
        if (accessToken.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Access token is required", null)
            return
        }
        val displayName = call.argument<String>("displayName")
        val disableInternalPush = call.argument<Boolean>("disableInternalPushForIncomingCall") ?: false

        executor.execute {
            try {
                tokenCredential = CommunicationTokenCredential(accessToken)
                callClient = callClient ?: CallClient()
                val options = CallAgentOptions()
                if (!displayName.isNullOrBlank()) {
                    options.displayName = displayName
                }
                options.setDisableInternalPushForIncomingCall(disableInternalPush)
                val agentFuture = callClient!!.createCallAgent(context, tokenCredential!!, options)
                agentFuture.whenComplete { agent, error ->
                    if (error != null) {
                        runOnMainThread {
                            result.error("INITIALIZATION_ERROR", error.message, null)
                        }
                        return@whenComplete
                    }
                    callAgent = agent
                    try {
                        deviceManager = callClient!!.getDeviceManager(context).get()
                    } catch (e: Exception) {
                        // Device manager acquisition failure is non-fatal for audio-only scenarios.
                    }
                    callAgent?.addOnIncomingCallListener { incoming ->
                        incomingCall = incoming
                        emitIncomingCallEvent("incoming", incoming)
                        incoming.addOnCallEndedListener {
                            if (incomingCall == incoming) {
                                incomingCall = null
                            }
                            emitIncomingCallEvent("ended", incoming)
                        }
                    }
                    runOnMainThread { result.success(mapOf("status" to "initialized")) }
                }
            } catch (e: Exception) {
                runOnMainThread {
                    result.error("INITIALIZATION_ERROR", e.message, null)
                }
            }
        }
    }

    private fun requestPermissions(result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Permission requests require an attached activity", null)
            return
        }
        val required = arrayOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO
        )
        val missing = required.filter {
            ContextCompat.checkSelfPermission(currentActivity, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        ActivityCompat.requestPermissions(
            currentActivity,
            missing.toTypedArray(),
            PERMISSIONS_REQUEST_CODE
        )
        result.success(true)
    }

    private fun startCall(call: MethodCall, result: Result) {
        val participants = call.argument<List<String>>("participants")
        if (participants.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "Participants list is required", null)
            return
        }
        if (callAgent == null) {
            result.error("NOT_INITIALIZED", "Call agent not initialized. Call initializeCalling first.", null)
            return
        }

        val withVideo = call.argument<Boolean>("withVideo") ?: false
        executor.execute {
            try {
                val options = StartCallOptions()
                if (withVideo) {
                    ensureLocalVideoStream()?.let { stream ->
                        options.videoOptions = VideoOptions(arrayOf(stream))
                        viewManager?.showLocalPreview(context, stream)
                    }
                }
                val callees = participants.map { CommunicationUserIdentifier(it) }
                val newCall = callAgent!!.startCall(context, callees, options)
                attachCall(newCall)
                runOnMainThread {
                    result.success(
                        mapOf(
                            "id" to newCall.id,
                            "state" to (lobbyStateString(newCall) ?: callStateToString(newCall.state))
                        )
                    )
                }
            } catch (e: Exception) {
                runOnMainThread { result.error("CALL_START_FAILED", e.message, null) }
            }
        }
    }

    private fun joinCall(call: MethodCall, result: Result) {
        val groupCallId = call.argument<String>("groupCallId")
        if (groupCallId.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Group call ID is required", null)
            return
        }
        if (callAgent == null) {
            result.error("NOT_INITIALIZED", "Call agent not initialized. Call initializeCalling first.", null)
            return
        }
        val withVideo = call.argument<Boolean>("withVideo") ?: false

        executor.execute {
            try {
                val options = JoinCallOptions()
                if (withVideo) {
                    ensureLocalVideoStream()?.let { stream ->
                        options.videoOptions = VideoOptions(arrayOf(stream))
                        viewManager?.showLocalPreview(context, stream)
                    }
                }
                val locator = GroupCallLocator(UUID.fromString(groupCallId))
                val joinedCall = callAgent!!.join(context, locator, options)
                attachCall(joinedCall)
                runOnMainThread {
                    result.success(
                        mapOf(
                            "id" to joinedCall.id,
                            "state" to (lobbyStateString(joinedCall) ?: callStateToString(joinedCall.state))
                        )
                    )
                }
            } catch (e: Exception) {
                runOnMainThread { result.error("CALL_JOIN_FAILED", e.message, null) }
            }
        }
    }

    private fun endCall(result: Result) {
        val activeCall = call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call to end", null)
            return
        }
        executor.execute {
            try {
                activeCall.hangUp(HangUpOptions()).whenComplete { _, error ->
                    if (error != null) {
                        runOnMainThread { result.error("HANGUP_FAILED", error.message, null) }
                    } else {
                        cleanupCallResources()
                        runOnMainThread { result.success(null) }
                    }
                }
            } catch (e: Exception) {
                runOnMainThread { result.error("HANGUP_FAILED", e.message, null) }
            }
        }
    }

    private fun muteAudio(result: Result) {
        val activeCall = call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                activeCall.muteOutgoingAudio(context).whenComplete { _, error ->
                    if (error != null) {
                        runOnMainThread { result.error("MUTE_FAILED", error.message, null) }
                    } else {
                        runOnMainThread { result.success(null) }
                    }
                }
            } catch (e: Exception) {
                runOnMainThread { result.error("MUTE_FAILED", e.message, null) }
            }
        }
    }

    private fun unmuteAudio(result: Result) {
        val activeCall = call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                activeCall.unmuteOutgoingAudio(context).whenComplete { _, error ->
                    if (error != null) {
                        runOnMainThread { result.error("UNMUTE_FAILED", error.message, null) }
                    } else {
                        runOnMainThread { result.success(null) }
                    }
                }
            } catch (e: Exception) {
                runOnMainThread { result.error("UNMUTE_FAILED", e.message, null) }
            }
        }
    }

    private fun startVideo(result: Result) {
        executor.execute {
            try {
                val stream = ensureLocalVideoStream()
                if (stream == null) {
                    runOnMainThread {
                        result.error("VIDEO_UNAVAILABLE", "Unable to access camera", null)
                    }
                    return@execute
                }
                viewManager?.showLocalPreview(context, stream)
                val activeCall = call
                if (activeCall != null) {
                    activeCall.startVideo(context, stream).whenComplete { _, error ->
                        if (error != null) {
                            runOnMainThread { result.error("VIDEO_START_FAILED", error.message, null) }
                        } else {
                            runOnMainThread { result.success(null) }
                        }
                    }
                } else {
                    runOnMainThread { result.success(null) }
                }
            } catch (e: Exception) {
                runOnMainThread { result.error("VIDEO_START_FAILED", e.message, null) }
            }
        }
    }

    private fun stopVideo(result: Result) {
        executor.execute {
            try {
                val stream = localVideoStream
                val activeCall = call
                if (stream != null && activeCall != null) {
                    activeCall.stopVideo(context, stream).whenComplete { _, error ->
                        if (error != null) {
                            runOnMainThread { result.error("VIDEO_STOP_FAILED", error.message, null) }
                        } else {
                            viewManager?.clearLocalPreview()
                            runOnMainThread { result.success(null) }
                        }
                    }
                } else {
                    viewManager?.clearLocalPreview()
                    runOnMainThread { result.success(null) }
                }
            } catch (e: Exception) {
                runOnMainThread { result.error("VIDEO_STOP_FAILED", e.message, null) }
            }
        }
    }

    private fun switchCamera(result: Result) {
        executor.execute {
            try {
                val dm = ensureDeviceManager()
                val stream = ensureLocalVideoStream()
                if (dm == null || stream == null) {
                    runOnMainThread { result.error("VIDEO_UNAVAILABLE", "No cameras detected", null) }
                    return@execute
                }
                val cameras = dm.cameras
                if (cameras.isNullOrEmpty()) {
                    runOnMainThread { result.error("VIDEO_UNAVAILABLE", "No cameras detected", null) }
                    return@execute
                }
                val current = currentCamera
                val currentIndex = cameras.indexOfFirst { it.id == current?.id }.coerceAtLeast(0)
                val nextIndex = (currentIndex + 1) % cameras.size
                val nextCamera = cameras[nextIndex]
                stream.switchSource(nextCamera).get()
                currentCamera = nextCamera
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("SWITCH_CAMERA_FAILED", e.message, null) }
            }
        }
    }

    private fun joinTeamsMeeting(call: MethodCall, result: Result) {
        val meetingLink = call.argument<String>("meetingLink")
        if (meetingLink.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Teams meeting link is required", null)
            return
        }
        if (callAgent == null) {
            result.error("NOT_INITIALIZED", "Call agent not initialized. Call initializeCalling first.", null)
            return
        }

        val withVideo = call.argument<Boolean>("withVideo") ?: false
        val noiseSuppressionMode = call.argument<String>("noiseSuppressionMode")

        executor.execute {
            try {
                val options = JoinCallOptions()
                if (withVideo) {
                    ensureLocalVideoStream()?.let { stream ->
                        options.videoOptions = VideoOptions(arrayOf(stream))
                        viewManager?.showLocalPreview(context, stream)
                    }
                }
                // Outgoing audio filters (noise suppression + echo cancellation):
                // applied only when the Dart side explicitly requests a mode so
                // existing callers keep the ACS SDK defaults.
                buildOutgoingAudioOptions(noiseSuppressionMode)?.let {
                    // Explicit setter for the same compiled-Java-SDK reason as in
                    // buildOutgoingAudioOptions.
                    options.setOutgoingAudioOptions(it)
                }
                val locator = TeamsMeetingLinkLocator(meetingLink)
                val joinedCall = callAgent!!.join(context, locator, options)
                attachCall(joinedCall)
                runOnMainThread {
                    result.success(
                        mapOf(
                            "id" to joinedCall.id,
                            "state" to (lobbyStateString(joinedCall) ?: callStateToString(joinedCall.state))
                        )
                    )
                }
            } catch (e: Exception) {
                runOnMainThread { result.error("CALL_JOIN_FAILED", e.message, null) }
            }
        }
    }

    /// Builds [OutgoingAudioOptions] carrying noise-suppression + echo-cancellation
    /// filters for the requested [mode] (`off|auto|low|high`, case-insensitive).
    ///
    /// Returns null when [mode] is null/blank or unrecognised so callers keep the
    /// ACS SDK's default audio pipeline — an unknown mode string must degrade the
    /// audio-quality nicety, never fail the join.
    private fun buildOutgoingAudioOptions(mode: String?): OutgoingAudioOptions? {
        if (mode.isNullOrBlank()) return null
        val suppression = when (mode.lowercase()) {
            "off" -> NoiseSuppressionMode.OFF
            "auto" -> NoiseSuppressionMode.AUTO
            "low" -> NoiseSuppressionMode.LOW
            "high" -> NoiseSuppressionMode.HIGH
            else -> {
                Log.w(TAG, "Unknown noiseSuppressionMode '$mode' — keeping SDK defaults")
                return null
            }
        }
        // Explicit Java-bean setter calls (not Kotlin property syntax): the ACS
        // Android SDK is a compiled Java artifact and synthetic properties only
        // exist for matched getter/setter pairs — setters always compile.
        val filters = OutgoingAudioFilters()
        filters.setNoiseSuppressionMode(suppression)
        // Echo cancellation accompanies any explicit suppression request so a
        // single Dart-side option yields the full quality bundle.
        filters.setAcousticEchoCancellationEnabled(true)
        val audioOptions = OutgoingAudioOptions()
        // ACS Android exposes the filters bundle as `filters` (setFilters), mirroring
        // the iOS `OutgoingAudioOptions.filters` property.
        audioOptions.setFilters(filters)
        return audioOptions
    }

    private fun addParticipants(call: MethodCall, result: Result) {
        val participantIds = call.argument<List<String>>("participants")
        if (participantIds.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "Participants list is required", null)
            return
        }
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }

        executor.execute {
            try {
                participantIds.forEach { rawId ->
                    val identifier = buildIdentifier(rawId)
                    activeCall.addParticipant(identifier)
                }
                runOnMainThread { result.success(mapOf("added" to participantIds.size)) }
            } catch (e: Exception) {
                runOnMainThread { result.error("ADD_PARTICIPANT_FAILED", e.message, null) }
            }
        }
    }

    private fun removeParticipants(call: MethodCall, result: Result) {
        val participantIds = call.argument<List<String>>("participants")
        if (participantIds.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "Participants list is required", null)
            return
        }
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }

        executor.execute {
            try {
                val remoteParticipants = activeCall.remoteParticipants
                val participantsToRemove = mutableListOf<Pair<String, RemoteParticipant>>()
                val missing = mutableListOf<String>()

                participantIds.forEach { rawId ->
                    val participant = remoteParticipants.firstOrNull { it.identifier?.rawId == rawId }
                    if (participant != null) {
                        participantsToRemove.add(rawId to participant)
                    } else {
                        missing.add(rawId)
                    }
                }

                if (participantsToRemove.isEmpty()) {
                    runOnMainThread { result.success(mapOf("removed" to 0, "missing" to missing)) }
                    return@execute
                }

                // Remove participants sequentially
                var removedCount = 0
                var lastError: Throwable? = null

                for ((_, participant) in participantsToRemove) {
                    try {
                        activeCall.removeParticipant(participant).get()
                        removedCount++
                    } catch (e: Exception) {
                        lastError = e
                    }
                }

                if (lastError != null && removedCount == 0) {
                    runOnMainThread { result.error("REMOVE_PARTICIPANT_FAILED", lastError.message, null) }
                } else {
                    runOnMainThread {
                        result.success(
                            mapOf(
                                "removed" to removedCount,
                                "missing" to missing
                            )
                        )
                    }
                }
            } catch (e: Exception) {
                runOnMainThread { result.error("REMOVE_PARTICIPANT_FAILED", e.message, null) }
            }
        }
    }

    private fun startCaptions(call: MethodCall, result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        val spokenLanguage = call.argument<String>("spokenLanguage")
        executor.execute {
            try {
                val captionsFeature = activeCall.feature(Features.CAPTIONS)
                val captions = captionsFeature.captions.get()
                callCaptions = captions
                attachCaptionsListeners(captions)
                val options = StartCaptionsOptions()
                if (!spokenLanguage.isNullOrBlank()) {
                    options.setSpokenLanguage(spokenLanguage)
                }
                captions.startCaptions(options).get()
                emitCaptionsStateChanged(captions)
                runOnMainThread { result.success(true) }
            } catch (e: Exception) {
                runOnMainThread { result.error("CAPTIONS_ERROR", e.message, null) }
            }
        }
    }

    private fun attachCaptionsListeners(captions: CallCaptions) {
        removeCaptionsListeners()
        captionsEnabledListener = PropertyChangedListener {
            safeCall("captionsEnabledChanged") { emitCaptionsStateChanged(captions) }
        }
        spokenLanguageListener = PropertyChangedListener {
            safeCall("spokenLanguageChanged") { emitCaptionsStateChanged(captions) }
        }
        when (captions) {
            is TeamsCaptions -> {
                teamsCaptionsListener = TeamsCaptionsListener { event ->
                    safeCall("teamsCaptionsReceived") {
                        emitCaptionsEvent("captionsReceived", serializeTeamsCaptionsEvent(event))
                    }
                }
                captions.addOnCaptionsReceivedListener(teamsCaptionsListener)
                captions.addOnCaptionsEnabledChangedListener(captionsEnabledListener)
                captions.addOnActiveSpokenLanguageChangedListener(spokenLanguageListener)
                captionLanguageListener = PropertyChangedListener {
                    safeCall("captionLanguageChanged") { emitCaptionsStateChanged(captions) }
                }
                captions.addOnActiveCaptionLanguageChangedListener(captionLanguageListener)
            }
            is CommunicationCaptions -> {
                communicationCaptionsListener = CommunicationCaptionsListener { event ->
                    safeCall("communicationCaptionsReceived") {
                        emitCaptionsEvent("captionsReceived", serializeCommunicationCaptionsEvent(event))
                    }
                }
                captions.addOnCaptionsReceivedListener(communicationCaptionsListener)
                captions.addOnCaptionsEnabledChangedListener(captionsEnabledListener)
                captions.addOnActiveSpokenLanguageChangedListener(spokenLanguageListener)
            }
        }
    }

    private fun removeCaptionsListeners() {
        val captions = callCaptions ?: return
        when (captions) {
            is TeamsCaptions -> {
                teamsCaptionsListener?.let { captions.removeOnCaptionsReceivedListener(it) }
                captionsEnabledListener?.let { captions.removeOnCaptionsEnabledChangedListener(it) }
                spokenLanguageListener?.let { captions.removeOnActiveSpokenLanguageChangedListener(it) }
                captionLanguageListener?.let { captions.removeOnActiveCaptionLanguageChangedListener(it) }
            }
            is CommunicationCaptions -> {
                communicationCaptionsListener?.let { captions.removeOnCaptionsReceivedListener(it) }
                captionsEnabledListener?.let { captions.removeOnCaptionsEnabledChangedListener(it) }
                spokenLanguageListener?.let { captions.removeOnActiveSpokenLanguageChangedListener(it) }
            }
        }
        communicationCaptionsListener = null
        teamsCaptionsListener = null
        captionsEnabledListener = null
        spokenLanguageListener = null
        captionLanguageListener = null
    }

    private fun serializeTeamsCaptionsEvent(event: TeamsCaptionsReceivedEvent): Map<String, Any?> {
        val speakerId = event.speaker?.identifier?.rawId
        return mapOf(
            "captionsType" to "teams",
            "speaker" to speakerId,
            "spokenText" to event.spokenText,
            "spokenLanguage" to event.spokenLanguage,
            "captionText" to event.captionText,
            "captionLanguage" to event.captionLanguage,
            "resultType" to event.resultType.toString(),
            "timestamp" to event.timestamp?.time
        )
    }

    private fun serializeCommunicationCaptionsEvent(event: CommunicationCaptionsReceivedEvent): Map<String, Any?> {
        val speakerId = event.speaker?.identifier?.rawId
        return mapOf(
            "captionsType" to "communication",
            "speaker" to speakerId,
            "spokenText" to event.spokenText,
            "spokenLanguage" to event.spokenLanguage,
            "resultType" to event.resultType.toString(),
            "timestamp" to event.timestamp?.time
        )
    }

    private fun emitCaptionsEvent(type: String, payload: Map<String, Any?>) {
        val data = payload.toMutableMap()
        data["type"] = type
        runOnMainThread { captionsEventSink?.success(data) }
    }

    private fun emitCaptionsStateChanged(captions: CallCaptions) {
        emitCaptionsEvent("captionsStateChanged", serializeCaptionsState(captions))
    }

    private fun serializeCaptionsState(captions: CallCaptions): Map<String, Any?> {
        val base = mutableMapOf<String, Any?>(
            "available" to true,
            "isEnabled" to captions.isEnabled,
            "type" to captions.captionsType.toString(),
            "activeSpokenLanguage" to captions.activeSpokenLanguage,
            "supportedSpokenLanguages" to captions.supportedSpokenLanguages.toList()
        )
        if (captions is TeamsCaptions) {
            base["activeCaptionLanguage"] = captions.activeCaptionLanguage
            base["supportedCaptionLanguages"] = captions.supportedCaptionLanguages.toList()
        }
        return base
    }

    private fun getCaptionsState(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.success(mapOf("available" to false))
            return
        }
        executor.execute {
            try {
                val captionsFeature = activeCall.feature(Features.CAPTIONS)
                val captions = captionsFeature.captions.get()
                callCaptions = captions
                attachCaptionsListeners(captions)
                runOnMainThread { result.success(serializeCaptionsState(captions)) }
            } catch (e: Exception) {
                runOnMainThread { result.success(mapOf("available" to false)) }
            }
        }
    }

    private fun stopCaptions(result: Result) {
        val captions = callCaptions
        executor.execute {
            try {
                captions?.stopCaptions()?.get()
                captions?.let { emitCaptionsStateChanged(it) }
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("CAPTIONS_ERROR", e.message, null) }
            }
        }
    }

    private fun setSpokenLanguage(call: MethodCall, result: Result) {
        val language = call.argument<String>("language")
        if (language.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Language is required", null)
            return
        }
        val captions = callCaptions
        executor.execute {
            try {
                captions?.setSpokenLanguage(language)?.get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("CAPTIONS_ERROR", e.message, null) }
            }
        }
    }

    private fun setCaptionLanguage(call: MethodCall, result: Result) {
        val language = call.argument<String>("language")
        if (language.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Language is required", null)
            return
        }
        val captions = callCaptions
        executor.execute {
            try {
                if (captions is TeamsCaptions) {
                    captions.setCaptionLanguage(language).get()
                    runOnMainThread { result.success(null) }
                } else {
                    runOnMainThread { result.error("NO_CAPTIONS", "Teams captions not available", null) }
                }
            } catch (e: Exception) {
                runOnMainThread { result.error("CAPTIONS_ERROR", e.message, null) }
            }
        }
    }

    // region Raise Hand
    private fun raiseHand(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.RAISED_HANDS)
                feature.raiseHand().get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("RAISE_HAND_FAILED", e.message, null) }
            }
        }
    }

    private fun lowerHand(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.RAISED_HANDS)
                feature.lowerHand().get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("LOWER_HAND_FAILED", e.message, null) }
            }
        }
    }

    private fun lowerAllHands(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.RAISED_HANDS)
                feature.lowerAllHands().get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("LOWER_ALL_HANDS_FAILED", e.message, null) }
            }
        }
    }

    private fun lowerHands(call: MethodCall, result: Result) {
        val ids = call.argument<List<String>>("identifiers")
        if (ids.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "identifiers is required", null)
            return
        }
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.RAISED_HANDS)
                val identifiers = ids.map { buildIdentifier(it) }
                feature.lowerHands(identifiers).get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("LOWER_HANDS_FAILED", e.message, null) }
            }
        }
    }

    private fun getRaisedHands(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.RAISED_HANDS)
                val payload = feature.raisedHands.map { serializeRaisedHand(it) }
                runOnMainThread { result.success(payload) }
            } catch (e: Exception) {
                runOnMainThread { result.error("GET_RAISED_HANDS_FAILED", e.message, null) }
            }
        }
    }

    private fun serializeRaisedHand(raisedHand: RaisedHand): Map<String, Any?> {
        return mapOf(
            "identifier" to raisedHand.identifier.rawId,
            "order" to raisedHand.order
        )
    }
    // endregion

    // region Spotlight
    private fun getSpotlightedParticipants(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.SPOTLIGHT)
                val ids = feature.spotlightedParticipants.map { it.identifier.rawId }
                runOnMainThread { result.success(ids) }
            } catch (e: Exception) {
                runOnMainThread { result.error("SPOTLIGHT_FAILED", e.message, null) }
            }
        }
    }

    private fun getMaxSpotlightedParticipants(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.SPOTLIGHT)
                val max = feature.maxSpotlightedParticipants
                runOnMainThread { result.success(max) }
            } catch (e: Exception) {
                runOnMainThread { result.error("SPOTLIGHT_FAILED", e.message, null) }
            }
        }
    }

    private fun spotlightParticipants(call: MethodCall, result: Result) {
        val ids = call.argument<List<String>>("identifiers")
        if (ids.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "identifiers is required", null)
            return
        }
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.SPOTLIGHT)
                val identifiers = ids.map { buildIdentifier(it) }
                feature.spotlight(identifiers).get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("SPOTLIGHT_FAILED", e.message, null) }
            }
        }
    }

    private fun cancelSpotlights(call: MethodCall, result: Result) {
        val ids = call.argument<List<String>>("identifiers")
        if (ids.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "identifiers is required", null)
            return
        }
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.SPOTLIGHT)
                val identifiers = ids.map { buildIdentifier(it) }
                feature.cancelSpotlights(identifiers).get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("CANCEL_SPOTLIGHT_FAILED", e.message, null) }
            }
        }
    }

    private fun cancelAllSpotlights(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.SPOTLIGHT)
                feature.cancelAllSpotlights().get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("CANCEL_SPOTLIGHT_FAILED", e.message, null) }
            }
        }
    }
    // endregion

    // region Media Statistics
    private fun setMediaStatisticsReportInterval(call: MethodCall, result: Result) {
        val seconds = call.argument<Int>("reportIntervalInSeconds")
        if (seconds == null) {
            result.error("INVALID_ARGUMENT", "reportIntervalInSeconds is required", null)
            return
        }
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.MEDIA_STATISTICS)
                feature.updateReportIntervalInSeconds(seconds)
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("MEDIA_STATISTICS_FAILED", e.message, null) }
            }
        }
    }

    private fun getMediaStatisticsReportInterval(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.MEDIA_STATISTICS)
                val interval = feature.reportIntervalInSeconds
                runOnMainThread { result.success(interval) }
            } catch (e: Exception) {
                runOnMainThread { result.error("MEDIA_STATISTICS_FAILED", e.message, null) }
            }
        }
    }

    private fun attachMediaStatisticsListeners(activeCall: Call) {
        try {
            // Remove any existing listeners first to prevent duplicates
            removeMediaStatisticsListeners()

            val mediaStats = activeCall.feature(Features.MEDIA_STATISTICS)
            mediaStatisticsFeature = mediaStats

            mediaStatisticsReportListener = MediaStatisticsReportReceivedListener { args ->
                emitMediaStatisticsReport(args.report)
            }
            mediaStats.addOnReportReceivedListener(mediaStatisticsReportListener)
        } catch (e: Exception) {
            Log.e("AcsFlutterSdkPlugin", "Failed to attach media statistics listeners: ${e.message}")
        }
    }

    private fun removeMediaStatisticsListeners() {
        try {
            mediaStatisticsReportListener?.let { listener ->
                mediaStatisticsFeature?.removeOnReportReceivedListener(listener)
            }
        } catch (e: Exception) {
            Log.e("AcsFlutterSdkPlugin", "Failed to remove media statistics listeners: ${e.message}")
        }
        mediaStatisticsReportListener = null
        mediaStatisticsFeature = null
    }

    private fun emitMediaStatisticsReport(report: MediaStatisticsReport) {
        val payload = mapOf(
            "type" to "mediaStatisticsReport",
            "report" to serializeMediaStatisticsReport(report)
        )
        runOnMainThread { mediaStatisticsEventSink?.success(payload) }
    }

    private fun serializeMediaStatisticsReport(report: MediaStatisticsReport): Map<String, Any?> {
        return mapOf(
            "lastUpdated" to report.lastUpdatedAt?.time,
            "outgoing" to serializeOutgoingStatistics(report.outgoingStatistics),
            "incoming" to serializeIncomingStatistics(report.incomingStatistics)
        )
    }

    private fun serializeOutgoingStatistics(stats: OutgoingMediaStatistics?): Map<String, Any?> {
        if (stats == null) {
            return mapOf(
                "audio" to emptyList<Map<String, Any?>>(),
                "video" to emptyList<Map<String, Any?>>(),
                "screenShare" to emptyList<Map<String, Any?>>(),
                "dataChannel" to emptyList<Map<String, Any?>>()
            )
        }
        return mapOf(
            "audio" to stats.audioStatistics.map { serializeOutgoingAudio(it) },
            "video" to stats.videoStatistics.map { serializeOutgoingVideo(it) },
            "screenShare" to stats.screenShareStatistics.map { serializeOutgoingScreenShare(it) },
            "dataChannel" to stats.dataChannelStatistics.map { serializeOutgoingDataChannel(it) }
        )
    }

    private fun serializeIncomingStatistics(stats: IncomingMediaStatistics?): Map<String, Any?> {
        if (stats == null) {
            return mapOf(
                "audio" to emptyList<Map<String, Any?>>(),
                "video" to emptyList<Map<String, Any?>>(),
                "screenShare" to emptyList<Map<String, Any?>>(),
                "dataChannel" to emptyList<Map<String, Any?>>()
            )
        }
        return mapOf(
            "audio" to stats.audioStatistics.map { serializeIncomingAudio(it) },
            "video" to stats.videoStatistics.map { serializeIncomingVideo(it) },
            "screenShare" to stats.screenShareStatistics.map { serializeIncomingScreenShare(it) },
            "dataChannel" to stats.dataChannelStatistics.map { serializeIncomingDataChannel(it) }
        )
    }

    private fun serializeOutgoingAudio(stat: OutgoingAudioStatistics): Map<String, Any?> {
        return mapOf(
            "codecName" to stat.codecName,
            "bitrateInBps" to stat.bitrateInBps,
            "jitterInMs" to stat.jitterInMs,
            "packetCount" to stat.packetCount,
            "streamId" to stat.streamId
        )
    }

    private fun serializeOutgoingVideo(stat: OutgoingVideoStatistics): Map<String, Any?> {
        return mapOf(
            "codecName" to stat.codecName,
            "bitrateInBps" to stat.bitrateInBps,
            "packetCount" to stat.packetCount,
            "streamId" to stat.streamId,
            "frameRate" to stat.frameRate,
            "frameWidth" to stat.frameWidth,
            "frameHeight" to stat.frameHeight
        )
    }

    private fun serializeOutgoingScreenShare(stat: OutgoingScreenShareStatistics): Map<String, Any?> {
        return mapOf(
            "codecName" to stat.codecName,
            "bitrateInBps" to stat.bitrateInBps,
            "packetCount" to stat.packetCount,
            "streamId" to stat.streamId,
            "frameRate" to stat.frameRate,
            "frameWidth" to stat.frameWidth,
            "frameHeight" to stat.frameHeight
        )
    }

    private fun serializeOutgoingDataChannel(stat: OutgoingDataChannelStatistics): Map<String, Any?> {
        return mapOf(
            "packetCount" to stat.packetCount
        )
    }

    private fun serializeIncomingAudio(stat: IncomingAudioStatistics): Map<String, Any?> {
        return mapOf(
            "codecName" to stat.codecName,
            "jitterInMs" to stat.jitterInMs,
            "packetCount" to stat.packetCount,
            "packetsLostPerSecond" to stat.packetsLostPerSecond,
            "streamId" to stat.streamId
        )
    }

    private fun serializeIncomingVideo(stat: IncomingVideoStatistics): Map<String, Any?> {
        return mapOf(
            "codecName" to stat.codecName,
            "bitrateInBps" to stat.bitrateInBps,
            "jitterInMs" to stat.jitterInMs,
            "packetCount" to stat.packetCount,
            "packetsLostPerSecond" to stat.packetsLostPerSecond,
            "streamId" to stat.streamId,
            "frameRate" to stat.frameRate,
            "frameWidth" to stat.frameWidth,
            "frameHeight" to stat.frameHeight,
            "totalFreezeDurationInMs" to stat.totalFreezeDurationInMs,
            "participantIdentifier" to stat.participantIdentifier?.rawId
        )
    }

    private fun serializeIncomingScreenShare(stat: IncomingScreenShareStatistics): Map<String, Any?> {
        return mapOf(
            "bitrateInBps" to stat.bitrateInBps,
            "jitterInMs" to stat.jitterInMs,
            "packetCount" to stat.packetCount,
            "packetsLostPerSecond" to stat.packetsLostPerSecond,
            "streamId" to stat.streamId,
            "frameRate" to stat.frameRate,
            "frameWidth" to stat.frameWidth,
            "frameHeight" to stat.frameHeight,
            "totalFreezeDurationInMs" to stat.totalFreezeDurationInMs,
            "participantIdentifier" to stat.participantIdentifier?.rawId
        )
    }

    private fun serializeIncomingDataChannel(stat: IncomingDataChannelStatistics): Map<String, Any?> {
        return mapOf(
            "jitterInMs" to stat.jitterInMs,
            "packetCount" to stat.packetCount
        )
    }
    // endregion

    // region Real-Time Text
    private fun sendRealTimeText(call: MethodCall, result: Result) {
        val text = call.argument<String>("text")
        val finalize = call.argument<Boolean>("finalize") ?: false
        if (text == null) {
            result.error("INVALID_ARGUMENT", "text is required", null)
            return
        }
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.REAL_TIME_TEXT)
                feature.send(text, finalize)
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("RTT_FAILED", e.message, null) }
            }
        }
    }
    // endregion

    // region Data Channel
    private var dataChannelSenders = mutableMapOf<Int, DataChannelSender>()
    private var dataChannelSenderIdCounter = 0

    private fun createDataChannelSender(call: MethodCall, result: Result) {
        val channelId = call.argument<Int>("channelId") ?: 0
        val priority = call.argument<String>("priority") ?: "normal"
        val reliability = call.argument<String>("reliability") ?: "lossy"
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.DATA_CHANNEL)
                val options = DataChannelSenderOptions()
                options.channelId = channelId
                options.priority = when (priority) {
                    "high" -> DataChannelPriority.HIGH
                    else -> DataChannelPriority.NORMAL
                }
                options.reliability = when (reliability) {
                    "durable" -> DataChannelReliability.DURABLE
                    else -> DataChannelReliability.LOSSY
                }
                val sender = feature.getDataChannelSender(options)
                val senderId = dataChannelSenderIdCounter++
                dataChannelSenders[senderId] = sender
                runOnMainThread { result.success(senderId) }
            } catch (e: Exception) {
                runOnMainThread { result.error("DATA_CHANNEL_FAILED", e.message, null) }
            }
        }
    }

    private fun sendDataChannelMessage(call: MethodCall, result: Result) {
        val senderId = call.argument<Int>("senderId")
        val data = call.argument<ByteArray>("data")
        if (senderId == null || data == null) {
            result.error("INVALID_ARGUMENT", "senderId and data are required", null)
            return
        }
        val sender = dataChannelSenders[senderId]
        if (sender == null) {
            result.error("INVALID_SENDER", "Sender not found", null)
            return
        }
        executor.execute {
            try {
                sender.sendMessage(data)
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("DATA_CHANNEL_FAILED", e.message, null) }
            }
        }
    }

    private fun closeDataChannelSender(call: MethodCall, result: Result) {
        val senderId = call.argument<Int>("senderId")
        if (senderId == null) {
            result.error("INVALID_ARGUMENT", "senderId is required", null)
            return
        }
        val sender = dataChannelSenders.remove(senderId)
        if (sender == null) {
            result.error("INVALID_SENDER", "Sender not found", null)
            return
        }
        executor.execute {
            try {
                sender.closeSender()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("DATA_CHANNEL_FAILED", e.message, null) }
            }
        }
    }

    private fun setDataChannelParticipants(call: MethodCall, result: Result) {
        val senderId = call.argument<Int>("senderId")
        val ids = call.argument<List<String>>("identifiers")
        if (senderId == null || ids == null) {
            result.error("INVALID_ARGUMENT", "senderId and identifiers are required", null)
            return
        }
        val sender = dataChannelSenders[senderId]
        if (sender == null) {
            result.error("INVALID_SENDER", "Sender not found", null)
            return
        }
        executor.execute {
            try {
                val identifiers = ids.map { buildIdentifier(it) }
                sender.setParticipants(identifiers)
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("DATA_CHANNEL_FAILED", e.message, null) }
            }
        }
    }
    // endregion

    // region Survey
    private var pendingSurveys = mutableMapOf<String, CallSurvey>()

    private fun startSurvey(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.SURVEY)
                val survey = feature.startSurvey().get()
                val handle = java.util.UUID.randomUUID().toString()
                pendingSurveys[handle] = survey
                runOnMainThread { result.success(mapOf("handle" to handle)) }
            } catch (e: Exception) {
                runOnMainThread { result.error("SURVEY_FAILED", e.message, null) }
            }
        }
    }

    private fun submitSurvey(call: MethodCall, result: Result) {
        val handle = call.argument<String>("handle")
        if (handle.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "handle is required", null)
            return
        }
        val survey = pendingSurveys[handle]
        if (survey == null) {
            result.error("SURVEY_NOT_FOUND", "No survey for handle", null)
            return
        }
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        applySurveyInputs(call, survey)
        executor.execute {
            try {
                val feature = activeCall.feature(Features.SURVEY)
                val surveyResult = feature.submitSurvey(survey).get()
                pendingSurveys.remove(handle)
                runOnMainThread {
                    result.success(mapOf(
                        "surveyId" to surveyResult.surveyId,
                        "callId" to surveyResult.callId,
                        "anonymizedParticipantId" to surveyResult.anonymizedParticipantId
                    ))
                }
            } catch (e: Exception) {
                runOnMainThread { result.error("SURVEY_FAILED", e.message, null) }
            }
        }
    }

    private fun discardSurvey(result: Result) {
        result.success(null)
    }

    private fun applySurveyInputs(call: MethodCall, survey: CallSurvey) {
        val overallScore = call.argument<Map<String, Any>>("overallScore")
        val audioScore = call.argument<Map<String, Any>>("audioScore")
        val videoScore = call.argument<Map<String, Any>>("videoScore")
        val screenShareScore = call.argument<Map<String, Any>>("screenShareScore")

        overallScore?.let { score ->
            val value = (score["score"] as? Number)?.toInt() ?: return@let
            val issues = (score["issues"] as? List<*>)?.mapNotNull { it as? String }
            val surveyScore = CallSurveyScore()
            surveyScore.score = value
            val scale = CallSurveyRatingScale()
            scale.lowerBound = (score["lowerBound"] as? Number)?.toInt() ?: 1
            scale.upperBound = (score["upperBound"] as? Number)?.toInt() ?: 5
            scale.lowScoreThreshold = (score["lowScoreThreshold"] as? Number)?.toInt() ?: 2
            surveyScore.scale = scale
            survey.setOverallScore(surveyScore)
            issues?.let { issueList ->
                val callIssues = issueList.mapNotNull { issue ->
                    try { CallIssue.valueOf(issue.uppercase()) } catch (_: Exception) { null }
                }
                if (callIssues.isNotEmpty()) {
                    survey.setOverallIssues(*callIssues.toTypedArray())
                }
            }
        }

        audioScore?.let { score ->
            val value = (score["score"] as? Number)?.toInt() ?: return@let
            val issues = (score["issues"] as? List<*>)?.mapNotNull { it as? String }
            val surveyScore = CallSurveyScore()
            surveyScore.score = value
            val scale = CallSurveyRatingScale()
            scale.lowerBound = (score["lowerBound"] as? Number)?.toInt() ?: 1
            scale.upperBound = (score["upperBound"] as? Number)?.toInt() ?: 5
            scale.lowScoreThreshold = (score["lowScoreThreshold"] as? Number)?.toInt() ?: 2
            surveyScore.scale = scale
            survey.setAudioScore(surveyScore)
            issues?.let { issueList ->
                val audioIssues = issueList.mapNotNull { issue ->
                    try { AudioIssue.valueOf(issue.uppercase()) } catch (_: Exception) { null }
                }
                if (audioIssues.isNotEmpty()) {
                    survey.setAudioIssues(*audioIssues.toTypedArray())
                }
            }
        }

        videoScore?.let { score ->
            val value = (score["score"] as? Number)?.toInt() ?: return@let
            val issues = (score["issues"] as? List<*>)?.mapNotNull { it as? String }
            val surveyScore = CallSurveyScore()
            surveyScore.score = value
            val scale = CallSurveyRatingScale()
            scale.lowerBound = (score["lowerBound"] as? Number)?.toInt() ?: 1
            scale.upperBound = (score["upperBound"] as? Number)?.toInt() ?: 5
            scale.lowScoreThreshold = (score["lowScoreThreshold"] as? Number)?.toInt() ?: 2
            surveyScore.scale = scale
            survey.setVideoScore(surveyScore)
            issues?.let { issueList ->
                val videoIssues = issueList.mapNotNull { issue ->
                    try { VideoIssue.valueOf(issue.uppercase()) } catch (_: Exception) { null }
                }
                if (videoIssues.isNotEmpty()) {
                    survey.setVideoIssues(*videoIssues.toTypedArray())
                }
            }
        }

        screenShareScore?.let { score ->
            val value = (score["score"] as? Number)?.toInt() ?: return@let
            val issues = (score["issues"] as? List<*>)?.mapNotNull { it as? String }
            val surveyScore = CallSurveyScore()
            surveyScore.score = value
            val scale = CallSurveyRatingScale()
            scale.lowerBound = (score["lowerBound"] as? Number)?.toInt() ?: 1
            scale.upperBound = (score["upperBound"] as? Number)?.toInt() ?: 5
            scale.lowScoreThreshold = (score["lowScoreThreshold"] as? Number)?.toInt() ?: 2
            surveyScore.scale = scale
            survey.setScreenShareScore(surveyScore)
            issues?.let { issueList ->
                val screenShareIssues = issueList.mapNotNull { issue ->
                    try { ScreenShareIssue.valueOf(issue.uppercase()) } catch (_: Exception) { null }
                }
                if (screenShareIssues.isNotEmpty()) {
                    survey.setScreenShareIssues(*screenShareIssues.toTypedArray())
                }
            }
        }
    }
    // endregion

    // region Diagnostics
    private fun attachDiagnosticsListeners(activeCall: Call) {
        try {
            // Remove any existing listeners first to prevent duplicates
            removeDiagnosticsListeners()

            val diagnostics = activeCall.feature(Features.LOCAL_USER_DIAGNOSTICS)
            localUserDiagnosticsFeature = diagnostics

            val network = diagnostics.networkDiagnostics

            // Network diagnostics listeners - store references for cleanup
            networkUnavailableListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("networkDiagnosticChanged", mapOf("name" to "isNetworkUnavailable", "value" to args.value))
            }
            network.addOnIsNetworkUnavailableChangedListener(networkUnavailableListener)

            networkRelaysUnreachableListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("networkDiagnosticChanged", mapOf("name" to "isNetworkRelaysUnreachable", "value" to args.value))
            }
            network.addOnIsNetworkRelaysUnreachableChangedListener(networkRelaysUnreachableListener)

            networkReconnectionQualityListener = DiagnosticQualityChangedListener { args ->
                emitDiagnosticsEvent("networkDiagnosticChanged", mapOf("name" to "networkReconnectionQuality", "value" to args.value.toString()))
            }
            network.addOnNetworkReconnectionQualityChangedListener(networkReconnectionQualityListener)

            networkReceiveQualityListener = DiagnosticQualityChangedListener { args ->
                emitDiagnosticsEvent("networkDiagnosticChanged", mapOf("name" to "networkReceiveQuality", "value" to args.value.toString()))
            }
            network.addOnNetworkReceiveQualityChangedListener(networkReceiveQualityListener)

            networkSendQualityListener = DiagnosticQualityChangedListener { args ->
                emitDiagnosticsEvent("networkDiagnosticChanged", mapOf("name" to "networkSendQuality", "value" to args.value.toString()))
            }
            network.addOnNetworkSendQualityChangedListener(networkSendQualityListener)

            val media = diagnostics.mediaDiagnostics

            // Media diagnostics listeners - store references for cleanup
            speakerNotFunctioningListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("mediaDiagnosticChanged", mapOf("name" to "isSpeakerNotFunctioning", "value" to args.value))
            }
            media.addOnIsSpeakerNotFunctioningChangedListener(speakerNotFunctioningListener)

            speakerBusyListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("mediaDiagnosticChanged", mapOf("name" to "isSpeakerBusy", "value" to args.value))
            }
            media.addOnIsSpeakerBusyChangedListener(speakerBusyListener)

            speakerMutedListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("mediaDiagnosticChanged", mapOf("name" to "isSpeakerMuted", "value" to args.value))
            }
            media.addOnIsSpeakerMutedChangedListener(speakerMutedListener)

            speakerVolumeZeroListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("mediaDiagnosticChanged", mapOf("name" to "isSpeakerVolumeZero", "value" to args.value))
            }
            media.addOnIsSpeakerVolumeZeroChangedListener(speakerVolumeZeroListener)

            noSpeakerDevicesListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("mediaDiagnosticChanged", mapOf("name" to "isNoSpeakerDevicesAvailable", "value" to args.value))
            }
            media.addOnIsNoSpeakerDevicesAvailableChangedListener(noSpeakerDevicesListener)

            speakingWhileMutedListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("mediaDiagnosticChanged", mapOf("name" to "isSpeakingWhileMicrophoneIsMuted", "value" to args.value))
            }
            media.addOnIsSpeakingWhileMicrophoneIsMutedChangedListener(speakingWhileMutedListener)

            noMicrophoneDevicesListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("mediaDiagnosticChanged", mapOf("name" to "isNoMicrophoneDevicesAvailable", "value" to args.value))
            }
            media.addOnIsNoMicrophoneDevicesAvailableChangedListener(noMicrophoneDevicesListener)

            microphoneBusyListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("mediaDiagnosticChanged", mapOf("name" to "isMicrophoneBusy", "value" to args.value))
            }
            media.addOnIsMicrophoneBusyChangedListener(microphoneBusyListener)

            cameraFrozenListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("mediaDiagnosticChanged", mapOf("name" to "isCameraFrozen", "value" to args.value))
            }
            media.addOnIsCameraFrozenChangedListener(cameraFrozenListener)

            cameraStartFailedListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("mediaDiagnosticChanged", mapOf("name" to "isCameraStartFailed", "value" to args.value))
            }
            media.addOnIsCameraStartFailedChangedListener(cameraStartFailedListener)

            cameraStartTimedOutListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("mediaDiagnosticChanged", mapOf("name" to "isCameraStartTimedOut", "value" to args.value))
            }
            media.addOnIsCameraStartTimedOutChangedListener(cameraStartTimedOutListener)

            microphoneNotFunctioningListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("mediaDiagnosticChanged", mapOf("name" to "isMicrophoneNotFunctioning", "value" to args.value))
            }
            media.addOnIsMicrophoneNotFunctioningChangedListener(microphoneNotFunctioningListener)

            microphoneMutedUnexpectedlyListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("mediaDiagnosticChanged", mapOf("name" to "isMicrophoneMutedUnexpectedly", "value" to args.value))
            }
            media.addOnIsMicrophoneMutedUnexpectedlyChangedListener(microphoneMutedUnexpectedlyListener)

            cameraPermissionDeniedListener = DiagnosticFlagChangedListener { args ->
                emitDiagnosticsEvent("mediaDiagnosticChanged", mapOf("name" to "isCameraPermissionDenied", "value" to args.value))
            }
            media.addOnIsCameraPermissionDeniedChangedListener(cameraPermissionDeniedListener)

            emitDiagnosticsSnapshot(diagnostics)
        } catch (e: Exception) {
            Log.e("AcsFlutterSdkPlugin", "Failed to attach diagnostics listeners: ${e.message}")
        }
    }

    private fun removeDiagnosticsListeners() {
        val diagnostics = localUserDiagnosticsFeature ?: return

        try {
            val network = diagnostics.networkDiagnostics
            networkUnavailableListener?.let { network.removeOnIsNetworkUnavailableChangedListener(it) }
            networkRelaysUnreachableListener?.let { network.removeOnIsNetworkRelaysUnreachableChangedListener(it) }
            networkReconnectionQualityListener?.let { network.removeOnNetworkReconnectionQualityChangedListener(it) }
            networkReceiveQualityListener?.let { network.removeOnNetworkReceiveQualityChangedListener(it) }
            networkSendQualityListener?.let { network.removeOnNetworkSendQualityChangedListener(it) }

            val media = diagnostics.mediaDiagnostics
            speakerNotFunctioningListener?.let { media.removeOnIsSpeakerNotFunctioningChangedListener(it) }
            speakerBusyListener?.let { media.removeOnIsSpeakerBusyChangedListener(it) }
            speakerMutedListener?.let { media.removeOnIsSpeakerMutedChangedListener(it) }
            speakerVolumeZeroListener?.let { media.removeOnIsSpeakerVolumeZeroChangedListener(it) }
            noSpeakerDevicesListener?.let { media.removeOnIsNoSpeakerDevicesAvailableChangedListener(it) }
            speakingWhileMutedListener?.let { media.removeOnIsSpeakingWhileMicrophoneIsMutedChangedListener(it) }
            noMicrophoneDevicesListener?.let { media.removeOnIsNoMicrophoneDevicesAvailableChangedListener(it) }
            microphoneBusyListener?.let { media.removeOnIsMicrophoneBusyChangedListener(it) }
            cameraFrozenListener?.let { media.removeOnIsCameraFrozenChangedListener(it) }
            cameraStartFailedListener?.let { media.removeOnIsCameraStartFailedChangedListener(it) }
            cameraStartTimedOutListener?.let { media.removeOnIsCameraStartTimedOutChangedListener(it) }
            microphoneNotFunctioningListener?.let { media.removeOnIsMicrophoneNotFunctioningChangedListener(it) }
            microphoneMutedUnexpectedlyListener?.let { media.removeOnIsMicrophoneMutedUnexpectedlyChangedListener(it) }
            cameraPermissionDeniedListener?.let { media.removeOnIsCameraPermissionDeniedChangedListener(it) }
        } catch (e: Exception) {
            Log.e("AcsFlutterSdkPlugin", "Failed to remove diagnostics listeners: ${e.message}")
        }

        // Clear listener references
        networkUnavailableListener = null
        networkRelaysUnreachableListener = null
        networkReconnectionQualityListener = null
        networkReceiveQualityListener = null
        networkSendQualityListener = null
        speakerNotFunctioningListener = null
        speakerBusyListener = null
        speakerMutedListener = null
        speakerVolumeZeroListener = null
        noSpeakerDevicesListener = null
        speakingWhileMutedListener = null
        noMicrophoneDevicesListener = null
        microphoneBusyListener = null
        cameraFrozenListener = null
        cameraStartFailedListener = null
        cameraStartTimedOutListener = null
        microphoneNotFunctioningListener = null
        microphoneMutedUnexpectedlyListener = null
        cameraPermissionDeniedListener = null
    }

    private fun emitDiagnosticsEvent(type: String, payload: Map<String, Any?>) {
        val data = payload.toMutableMap()
        data["type"] = type
        runOnMainThread { diagnosticsEventSink?.success(data) }
    }

    private fun emitDiagnosticsSnapshot(diagnostics: LocalUserDiagnosticsCallFeature) {
        emitDiagnosticsEvent("diagnosticsSnapshot", serializeDiagnostics(diagnostics))
    }

    private fun serializeDiagnostics(diagnostics: LocalUserDiagnosticsCallFeature): Map<String, Any?> {
        val network = diagnostics.networkDiagnostics.latestDiagnostics
        val media = diagnostics.mediaDiagnostics.latestDiagnostics
        return mapOf(
            "network" to mapOf(
                "isNetworkUnavailable" to network.isNetworkUnavailable,
                "isNetworkRelaysUnreachable" to network.isNetworkRelaysUnreachable,
                "networkReconnectionQuality" to network.networkReconnectionQuality?.toString(),
                "networkSendQuality" to network.networkSendQuality?.toString(),
                "networkReceiveQuality" to network.networkReceiveQuality?.toString()
            ),
            "media" to mapOf(
                "isSpeakerNotFunctioning" to media.isSpeakerNotFunctioning,
                "isSpeakerBusy" to media.isSpeakerBusy,
                "isSpeakerMuted" to media.isSpeakerMuted,
                "isSpeakerVolumeZero" to media.isSpeakerVolumeZero,
                "isNoSpeakerDevicesAvailable" to media.isNoSpeakerDevicesAvailable,
                "isSpeakingWhileMicrophoneIsMuted" to media.isSpeakingWhileMicrophoneIsMuted,
                "isNoMicrophoneDevicesAvailable" to media.isNoMicrophoneDevicesAvailable,
                "isMicrophoneBusy" to media.isMicrophoneBusy,
                "isCameraFrozen" to media.isCameraFrozen,
                "isCameraStartFailed" to media.isCameraStartFailed,
                "isCameraStartTimedOut" to media.isCameraStartTimedOut,
                "isMicrophoneNotFunctioning" to media.isMicrophoneNotFunctioning,
                "isMicrophoneMutedUnexpectedly" to media.isMicrophoneMutedUnexpectedly,
                "isCameraPermissionDenied" to media.isCameraPermissionDenied
            )
        )
    }

    private fun getLatestDiagnostics(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val diagnostics = localUserDiagnosticsFeature ?: activeCall.feature(Features.LOCAL_USER_DIAGNOSTICS)
                runOnMainThread { result.success(serializeDiagnostics(diagnostics)) }
            } catch (e: Exception) {
                runOnMainThread { result.error("DIAGNOSTICS_ERROR", e.message, null) }
            }
        }
    }
    // endregion

    private fun isRecordingActive(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.RECORDING)
                runOnMainThread { result.success(feature.isRecordingActive) }
            } catch (e: Exception) {
                runOnMainThread { result.error("FEATURE_ERROR", e.message, null) }
            }
        }
    }

    private fun isTranscriptionActive(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.TRANSCRIPTION)
                runOnMainThread { result.success(feature.isTranscriptionActive) }
            } catch (e: Exception) {
                runOnMainThread { result.error("FEATURE_ERROR", e.message, null) }
            }
        }
    }

    private fun getDominantSpeakers(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.DOMINANT_SPEAKERS)
                val speakers = feature.dominantSpeakersInfo?.speakers?.mapNotNull { it.rawId } ?: emptyList()
                runOnMainThread { result.success(speakers) }
            } catch (e: Exception) {
                runOnMainThread { result.error("FEATURE_ERROR", e.message, null) }
            }
        }
    }

    private fun enableBackgroundBlur(result: Result) {
        executor.execute {
            try {
                val feature = ensureLocalVideoEffectsFeature()
                if (feature == null) {
                    runOnMainThread { result.error("VIDEO_EFFECT_ERROR", "Video effects unavailable", null) }
                    return@execute
                }
                val effect = BackgroundBlurEffect()
                feature.enableEffect(effect)
                activeVideoEffect = effect
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("VIDEO_EFFECT_ERROR", e.message, null) }
            }
        }
    }

    private fun enableBackgroundReplacement(call: MethodCall, result: Result) {
        val buffer = call.argument<ByteArray>("buffer")
        if (buffer == null) {
            result.error("INVALID_ARGUMENT", "buffer is required", null)
            return
        }
        executor.execute {
            try {
                val feature = ensureLocalVideoEffectsFeature()
                if (feature == null) {
                    runOnMainThread { result.error("VIDEO_EFFECT_ERROR", "Video effects unavailable", null) }
                    return@execute
                }
                val effect = BackgroundReplacementEffect()
                effect.setBuffer(ByteBuffer.wrap(buffer))
                feature.enableEffect(effect)
                activeVideoEffect = effect
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("VIDEO_EFFECT_ERROR", e.message, null) }
            }
        }
    }

    private fun disableVideoEffects(result: Result) {
        executor.execute {
            try {
                val feature = localVideoStream?.feature(Features.LOCAL_VIDEO_EFFECTS)
                val effect = activeVideoEffect
                if (feature != null && effect != null) {
                    feature.disableEffect(effect)
                }
                activeVideoEffect = null
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("VIDEO_EFFECT_ERROR", e.message, null) }
            }
        }
    }

    private fun muteIncomingAudio(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                activeCall.muteIncomingAudio(context).get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("MUTE_FAILED", e.message, null) }
            }
        }
    }

    private fun unmuteIncomingAudio(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                activeCall.unmuteIncomingAudio(context).get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("UNMUTE_FAILED", e.message, null) }
            }
        }
    }

    private fun muteAllRemoteParticipants(result: Result) {
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                activeCall.muteAllRemoteParticipants().get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("MUTE_FAILED", e.message, null) }
            }
        }
    }

    private fun admitLobbyParticipants(call: MethodCall, result: Result) {
        val ids = call.argument<List<String>>("identifiers")
        if (ids.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "identifiers is required", null)
            return
        }
        val lobby = this.call?.callLobby
        if (lobby == null) {
            result.error("LOBBY_UNAVAILABLE", "Lobby not available", null)
            return
        }
        executor.execute {
            try {
                val identifiers = ids.map { buildIdentifier(it) }
                lobby.admit(identifiers).get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("LOBBY_FAILED", e.message, null) }
            }
        }
    }

    private fun admitAllFromLobby(result: Result) {
        val lobby = this.call?.callLobby
        if (lobby == null) {
            result.error("LOBBY_UNAVAILABLE", "Lobby not available", null)
            return
        }
        executor.execute {
            try {
                lobby.admitAll().get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("LOBBY_FAILED", e.message, null) }
            }
        }
    }

    private fun rejectLobbyParticipant(call: MethodCall, result: Result) {
        val id = call.argument<String>("identifier")
        if (id.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "identifier is required", null)
            return
        }
        val lobby = this.call?.callLobby
        if (lobby == null) {
            result.error("LOBBY_UNAVAILABLE", "Lobby not available", null)
            return
        }
        executor.execute {
            try {
                lobby.reject(buildIdentifier(id)).get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("LOBBY_FAILED", e.message, null) }
            }
        }
    }

    private fun getLobbyParticipants(result: Result) {
        val lobby = this.call?.callLobby
        if (lobby == null) {
            result.error("LOBBY_UNAVAILABLE", "Lobby not available", null)
            return
        }
        executor.execute {
            try {
                val ids = lobby.participants.mapNotNull { it.identifier?.rawId }
                runOnMainThread { result.success(ids) }
            } catch (e: Exception) {
                runOnMainThread { result.error("LOBBY_FAILED", e.message, null) }
            }
        }
    }

    private fun getRemoteParticipants(result: Result) {
        val participants = this.call?.remoteParticipants
        if (participants == null) {
            result.success(emptyList<String>())
            return
        }
        executor.execute {
            try {
                val ids = participants.mapNotNull { it.identifier?.rawId }
                runOnMainThread { result.success(ids) }
            } catch (e: Exception) {
                runOnMainThread { result.error("REMOTE_PARTICIPANTS_FAILED", e.message, null) }
            }
        }
    }

    private fun getRemoteParticipantStates(result: Result) {
        val participants = this.call?.remoteParticipants
        if (participants == null) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        executor.execute {
            try {
                val list = participants.map { p -> serializeParticipant(p) }
                runOnMainThread { result.success(list) }
            } catch (e: Exception) {
                runOnMainThread { result.error("REMOTE_PARTICIPANTS_FAILED", e.message, null) }
            }
        }
    }

    private fun getCapabilities(result: Result) {
        val activeCall = call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                val feature = activeCall.feature(Features.CAPABILITIES)
                val list = feature.capabilities.map { cap ->
                    mapOf(
                        "type" to (cap.type?.toString() ?: "unknown"),
                        "isAllowed" to (cap.isAllowed == true),
                        "reason" to (cap.reason?.toString() ?: "")
                    )
                }
                runOnMainThread { result.success(list) }
            } catch (e: Exception) {
                runOnMainThread { result.error("CAPABILITIES_FAILED", e.message, null) }
            }
        }
    }

    private fun acceptIncomingCall(call: MethodCall, result: Result) {
        val incoming = incomingCall
        if (incoming == null) {
            result.error("NO_INCOMING_CALL", "No incoming call to accept", null)
            return
        }
        val withVideo = call.argument<Boolean>("withVideo") ?: false
        executor.execute {
            try {
                val options = AcceptCallOptions()
                if (withVideo) {
                    ensureLocalVideoStream()?.let { stream ->
                        options.videoOptions = VideoOptions(arrayOf(stream))
                        viewManager?.showLocalPreview(context, stream)
                    }
                }
                val acceptedCall = incoming.accept(context, options).get()
                attachCall(acceptedCall)
                incomingCall = null
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("ACCEPT_FAILED", e.message, null) }
            }
        }
    }

    private fun rejectIncomingCall(result: Result) {
        val incoming = incomingCall
        if (incoming == null) {
            result.error("NO_INCOMING_CALL", "No incoming call to reject", null)
            return
        }
        executor.execute {
            try {
                incoming.reject().get()
                incomingCall = null
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("REJECT_FAILED", e.message, null) }
            }
        }
    }

    private fun registerPushNotifications(call: MethodCall, result: Result) {
        val token = call.argument<String>("token")
        if (token.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "token is required", null)
            return
        }
        val agent = callAgent
        if (agent == null) {
            result.error("NOT_INITIALIZED", "Call agent not initialized", null)
            return
        }
        executor.execute {
            try {
                agent.registerPushNotification(token).get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("PUSH_REGISTER_FAILED", e.message, null) }
            }
        }
    }

    private fun unregisterPushNotifications(result: Result) {
        val agent = callAgent
        if (agent == null) {
            result.error("NOT_INITIALIZED", "Call agent not initialized", null)
            return
        }
        executor.execute {
            try {
                agent.unregisterPushNotification().get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("PUSH_UNREGISTER_FAILED", e.message, null) }
            }
        }
    }

    private fun handlePushNotification(call: MethodCall, result: Result) {
        val agent = callAgent
        if (agent == null) {
            result.error("NOT_INITIALIZED", "Call agent not initialized", null)
            return
        }
        val payload = call.argument<Map<String, Any?>>("payload")
        if (payload.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "payload is required", null)
            return
        }
        executor.execute {
            try {
                val map = payload.mapValues { it.value?.toString() ?: "" }
                val info = PushNotificationInfo.fromMap(map)
                agent.handlePushNotification(info).get()
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("PUSH_HANDLE_FAILED", e.message, null) }
            }
        }
    }

    private fun holdCall(result: Result) {
        val activeCall = call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                activeCall.hold().whenComplete { _, error ->
                    if (error != null) {
                        runOnMainThread { result.error("HOLD_FAILED", error.message, null) }
                    } else {
                        runOnMainThread { result.success(null) }
                    }
                }
            } catch (e: Exception) {
                runOnMainThread { result.error("HOLD_FAILED", e.message, null) }
            }
        }
    }

    private fun resumeCall(result: Result) {
        val activeCall = call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        executor.execute {
            try {
                activeCall.resume().whenComplete { _, error ->
                    if (error != null) {
                        runOnMainThread { result.error("RESUME_FAILED", error.message, null) }
                    } else {
                        runOnMainThread { result.success(null) }
                    }
                }
            } catch (e: Exception) {
                runOnMainThread { result.error("RESUME_FAILED", e.message, null) }
            }
        }
    }

    private fun transferCall(call: MethodCall, result: Result) {
        val target = call.argument<String>("target")
        if (target.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "target is required", null)
            return
        }
        val activeCall = this.call
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        // Transfer is not available in this SDK version; return explicit error to avoid build breakage.
        result.error("NOT_IMPLEMENTED", "Call transfer not supported in current Android SDK", null)
    }

    private fun startScreenShare(result: Result) {
        val activeCall = call
        val currentActivity = activity
        if (activeCall == null) {
            result.error("NO_ACTIVE_CALL", "No active call", null)
            return
        }
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "Screen share requires an attached activity", null)
            return
        }

        // Synchronized check to prevent race conditions
        synchronized(screenShareLock) {
            if (screenShareActive) {
                result.success(null)
                return
            }
            if (pendingScreenShareResult != null) {
                result.error("SCREEN_SHARE_IN_PROGRESS", "Screen share permission request in progress", null)
                return
            }
            pendingScreenShareResult = result
        }

        startScreenShareForegroundService()
        mediaProjectionManager =
            currentActivity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
        val intent = mediaProjectionManager?.createScreenCaptureIntent()
        if (intent == null) {
            synchronized(screenShareLock) { pendingScreenShareResult = null }
            stopScreenShareForegroundService()
            result.error("SCREEN_SHARE_NOT_SUPPORTED", "Screen share not supported", null)
            return
        }
        currentActivity.startActivityForResult(intent, SCREEN_SHARE_REQUEST_CODE)
    }

    private fun stopScreenShare(result: Result) {
        // Synchronized check for screen share state
        synchronized(screenShareLock) {
            if (!screenShareActive && screenShareStream == null) {
                result.success(null)
                return
            }
        }
        stopScreenShareInternal { error ->
            runOnMainThread {
                if (error != null) {
                    result.error("SCREEN_SHARE_STOP_FAILED", error.message, null)
                } else {
                    result.success(null)
                }
            }
        }
    }

    private fun startScreenShareInternal(projection: MediaProjection, result: Result?) {
        val activeCall = call
        if (activeCall == null) {
            result?.error("NO_ACTIVE_CALL", "No active call", null)
            projection.stop()
            stopScreenShareForegroundService()
            return
        }

        val metrics = context.resources.displayMetrics
        val dimensions = screenShareDimensions(metrics.widthPixels, metrics.heightPixels)
        val width = dimensions.first
        val height = dimensions.second

        val format = VideoStreamFormat()
            .setWidth(width)
            .setHeight(height)
            .setPixelFormat(VideoStreamPixelFormat.RGBA)
            .setFramesPerSecond(SCREEN_SHARE_TARGET_FPS.toFloat())
            .setStride1(width * 4)
        screenShareFormat = format

        val options = RawOutgoingVideoStreamOptions()
        options.formats = listOf(format)

        val stream = ScreenShareOutgoingVideoStream(options)
        screenShareStream = stream

        activeCall.startVideo(context, stream).whenComplete { _, error ->
            if (error != null) {
                synchronized(screenShareLock) {
                    screenShareStream = null
                    screenShareFormat = null
                }
                projection.stop()
                stopScreenShareForegroundService()
                runOnMainThread { result?.error("SCREEN_SHARE_START_FAILED", error.message, null) }
                return@whenComplete
            }

            stopScreenShareCapture()
            mediaProjection = projection
            val started = startScreenShareCapture(projection, width, height, metrics.densityDpi)
            if (!started) {
                activeCall.stopVideo(context, stream).whenComplete { _, _ -> }
                synchronized(screenShareLock) {
                    screenShareStream = null
                    screenShareFormat = null
                }
                stopScreenShareCapture()
                stopScreenShareForegroundService()
                runOnMainThread {
                    result?.error("SCREEN_SHARE_START_FAILED", "Failed to start screen capture", null)
                }
                return@whenComplete
            }

            synchronized(screenShareLock) {
                screenShareActive = true
                lastScreenShareFrameTimeNs = 0L
            }
            runOnMainThread { result?.success(null) }
        }
    }

    /// Starts the MediaProjection capture pipeline (handler thread, ImageReader,
    /// virtual display).
    ///
    /// Android 14 (API 34+) mandates that a [MediaProjection.Callback] be registered
    /// before [MediaProjection.createVirtualDisplay]; without it the platform throws
    /// `IllegalStateException`. The callback is registered on the capture handler and
    /// stops the share if the projection is revoked (e.g. user taps "Stop sharing"
    /// from the system UI).
    /// - Returns: true if the virtual display was created, false otherwise.
    private fun startScreenShareCapture(
        projection: MediaProjection,
        width: Int,
        height: Int,
        densityDpi: Int
    ): Boolean {
        screenShareHandlerThread = HandlerThread("AcsScreenShare")
        screenShareHandlerThread?.start()
        screenShareHandler = Handler(screenShareHandlerThread!!.looper)

        // REQUIRED on Android 14+: register a callback before createVirtualDisplay.
        // Also handles user-initiated stop from the system status bar.
        val callback = object : MediaProjection.Callback() {
            override fun onStop() {
                stopScreenShareInternal { }
            }
        }
        mediaProjectionCallback = callback
        projection.registerCallback(callback, screenShareHandler)

        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        screenShareImageReader = reader
        reader.setOnImageAvailableListener({ imageReader ->
            processScreenShareImage(imageReader)
        }, screenShareHandler)

        val display = projection.createVirtualDisplay(
            "AcsScreenShare",
            width,
            height,
            densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface,
            null,
            screenShareHandler
        )
        screenShareVirtualDisplay = display
        return display != null
    }

    private fun processScreenShareImage(reader: ImageReader) {
        val image = reader.acquireLatestImage() ?: return
        try {
            if (!screenShareActive) return
            val stream = screenShareStream ?: return

            val now = System.nanoTime()
            val minInterval = 1_000_000_000L / SCREEN_SHARE_TARGET_FPS
            if (now - lastScreenShareFrameTimeNs < minInterval) return
            lastScreenShareFrameTimeNs = now

            val planes = image.planes
            if (planes.isEmpty()) return
            val plane = planes[0]
            val buffer = plane.buffer
            buffer.rewind()

            val rowStride = plane.rowStride
            val height = image.height
            val requiredSize = rowStride * height

            // Reuse buffer if it's the right size, otherwise allocate new one
            val data: ByteBuffer
            if (screenShareBuffer != null && screenShareBufferSize >= requiredSize) {
                data = screenShareBuffer!!
                data.clear()
            } else {
                data = ByteBuffer.allocateDirect(requiredSize)
                screenShareBuffer = data
                screenShareBufferSize = requiredSize
            }
            data.put(buffer)
            data.flip()

            val format = screenShareFormat
            if (format != null && format.stride1 != rowStride) {
                format.setStride1(rowStride)
            }

            val frame = RawVideoFrameBuffer()
                .setStreamFormat(format ?: VideoStreamFormat()
                    .setWidth(image.width)
                    .setHeight(image.height)
                    .setPixelFormat(VideoStreamPixelFormat.RGBA)
                    .setFramesPerSecond(SCREEN_SHARE_TARGET_FPS.toFloat())
                    .setStride1(rowStride))
                .setTimestampInTicks(now / 100)
                .setBuffers(listOf(data))

            // Unswallowed: previously `whenComplete { _, _ -> }` dropped send errors
            // silently. Surface them to logcat and to Flutter so a degraded share is
            // observable, then always close the frame.
            stream.sendRawVideoFrame(frame).whenComplete { _, error ->
                if (error != null) {
                    Log.e(TAG, "[ScreenShare] sendRawVideoFrame failed: ${error.message}", error)
                    runOnMainThread {
                        safeCall("emitScreenShareError") {
                            eventSink?.success(
                                mapOf(
                                    "type" to "screenShareError",
                                    "message" to (error.message ?: "Screen share frame send failed")
                                )
                            )
                        }
                    }
                }
                frame.close()
            }
        } finally {
            image.close()
        }
    }

    private fun stopScreenShareInternal(completion: (Throwable?) -> Unit) {
        val activeCall = call
        val stream: ScreenShareOutgoingVideoStream?

        // Synchronized state update to prevent race conditions
        synchronized(screenShareLock) {
            stream = screenShareStream
            screenShareActive = false
            screenShareStream = null
            screenShareFormat = null
            pendingScreenShareResult = null
            lastScreenShareFrameTimeNs = 0L
        }

        stopScreenShareCapture()
        stopScreenShareForegroundService()

        if (activeCall == null || stream == null) {
            completion(null)
            return
        }
        activeCall.stopVideo(context, stream).whenComplete { _, error ->
            completion(error)
        }
    }

    private fun stopScreenShareCapture() {
        screenShareVirtualDisplay?.release()
        screenShareVirtualDisplay = null
        screenShareImageReader?.setOnImageAvailableListener(null, null)
        screenShareImageReader?.close()
        screenShareImageReader = null
        // Unregister the Android 14 projection callback before stopping the projection.
        mediaProjectionCallback?.let { cb -> mediaProjection?.unregisterCallback(cb) }
        mediaProjectionCallback = null
        mediaProjection?.stop()
        mediaProjection = null
        screenShareHandlerThread?.quitSafely()
        screenShareHandlerThread = null
        // Release reusable buffer to free memory
        screenShareBuffer = null
        screenShareBufferSize = 0
        screenShareHandler = null
    }

    private fun startScreenShareForegroundService() {
        try {
            AcsScreenShareService.start(context)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to start screen share foreground service", e)
        }
    }

    private fun stopScreenShareForegroundService() {
        try {
            AcsScreenShareService.stop(context)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to stop screen share foreground service", e)
        }
    }

    private fun screenShareDimensions(width: Int, height: Int): Pair<Int, Int> {
        var w = width
        var h = height
        val maxWidth = 1920
        val maxHeight = 1080

        val aspect = w.toDouble() / h.toDouble()
        if (h > maxHeight) {
            h = maxHeight
            w = (h * aspect).toInt()
        }
        if (w > maxWidth) {
            w = maxWidth
            h = (w / aspect).toInt()
        }

        w = maxOf(240, w - (w % 2))
        h = maxOf(180, h - (h % 2))
        return w to h
    }

    private fun listCameras(result: Result) {
        val dm = ensureDeviceManager()
        if (dm == null) {
            result.error("DEVICE_MANAGER_UNAVAILABLE", "DeviceManager not available", null)
            return
        }
        executor.execute {
            try {
                val cameras = dm.cameras?.map {
                    mapOf(
                        "id" to (it.id ?: ""),
                        "name" to (it.name ?: ""),
                        "type" to "camera",
                        "facing" to (it.cameraFacing?.toString()?.lowercase() ?: "")
                    )
                } ?: emptyList()
                runOnMainThread { result.success(cameras) }
            } catch (e: Exception) {
                runOnMainThread { result.error("DEVICE_QUERY_FAILED", e.message, null) }
            }
        }
    }

    private fun setCamera(call: MethodCall, result: Result) {
        val cameraId = call.argument<String>("id")
        if (cameraId.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "id is required", null)
            return
        }
        executor.execute {
            try {
                val dm = ensureDeviceManager()
                val stream = ensureLocalVideoStream()
                val cameras = dm?.cameras
                val target = cameras?.firstOrNull { it.id == cameraId }
                if (dm == null || stream == null || target == null) {
                    runOnMainThread { result.error("VIDEO_UNAVAILABLE", "Camera not found", null) }
                    return@execute
                }
                stream.switchSource(target).get()
                currentCamera = target
                runOnMainThread { result.success(null) }
            } catch (e: Exception) {
                runOnMainThread { result.error("SWITCH_CAMERA_FAILED", e.message, null) }
            }
        }
    }

    private fun isInLobby(result: Result) {
        val inLobby = this.call?.state == CallState.IN_LOBBY
        result.success(inLobby)
    }

    private fun hasRemoteVideo(result: Result) {
        val participants = this.call?.remoteParticipants
        if (participants == null) {
            result.success(false)
            return
        }
        executor.execute {
            try {
                val hasVideo = participants.any { participant ->
                    participant.incomingVideoStreams?.any { stream -> stream is RemoteVideoStream } == true
                }
                runOnMainThread { result.success(hasVideo) }
            } catch (e: Exception) {
                runOnMainThread { result.error("REMOTE_VIDEO_CHECK_FAILED", e.message, null) }
            }
        }
    }

    private fun attachCall(newCall: Call) {
        safeCall("attachCall") {
            cleanupCallResources()
            call = newCall
            remoteParticipantListener = ParticipantsUpdatedListener { event ->
                safeCall("remoteParticipantsUpdated") {
                    handleAddedParticipants(event.addedParticipants)
                    handleRemovedParticipants(event.removedParticipants)
                }
            }
            capabilitiesListener = CapabilitiesChangedListener { event ->
                safeCall("capabilitiesChanged") { emitCapabilitiesEvent(event) }
            }
            callStateListener = PropertyChangedListener {
                safeCall("callStateChangedListener") {
                    runOnMainThread {
                        channel.invokeMethod(
                            "callStateChanged",
                            mapOf("state" to (lobbyStateString(newCall) ?: callStateToString(newCall.state)))
                        )
                    }
                    if (newCall.state == CallState.DISCONNECTED) {
                        cleanupCallResources()
                    }
                }
            }
            newCall.addOnRemoteParticipantsUpdatedListener(remoteParticipantListener)
            capabilitiesListener?.let { newCall.feature(Features.CAPABILITIES).addOnCapabilitiesChangedListener(it) }
            newCall.addOnStateChangedListener(callStateListener)
            handleAddedParticipants(newCall.remoteParticipants)
            attachDiagnosticsListeners(newCall)
            attachMediaStatisticsListeners(newCall)
        }
    }

    private fun handleAddedParticipants(participants: List<RemoteParticipant>) {
        safeCall("handleAddedParticipants") {
            participants.forEach { participant ->
                val participantId = participant.identifier?.rawId ?: return@forEach

                // Remove any existing listeners for this participant first
                removeParticipantListeners(participant)

                emitParticipantEvent("participantAdded", participant)
                participant.incomingVideoStreams
                    ?.filterIsInstance<RemoteVideoStream>()
                    ?.forEach { subscribeRemoteStream(it) }
                // Attach to a per-participant tile if one is already mounted.
                reconcileParticipantTile(participantId)

                // Create and store listener references for proper cleanup
                val videoStreamsListener = RemoteVideoStreamsUpdatedListener { event ->
                    safeCall("videoStreamsUpdated:$participantId") {
                        event.addedRemoteVideoStreams.forEach {
                            subscribeRemoteStream(it)
                            // Watch availability so a later camera-on flip re-renders.
                            attachStreamStateListener(participantId, it)
                        }
                        event.removedRemoteVideoStreams.forEach {
                            detachStreamStateListener(participantId, it.id)
                            removeRemoteStream(it.id)
                        }
                        // Keep this participant's grid tile in sync with its streams.
                        reconcileParticipantTile(participantId)
                        emitParticipantEvent("participantUpdated", participant)
                    }
                }
                val mutedListener = PropertyChangedListener {
                    safeCall("participantMuted:$participantId") {
                        emitParticipantEvent("participantUpdated", participant)
                    }
                }
                val speakingListener = PropertyChangedListener {
                    safeCall("participantSpeaking:$participantId") {
                        emitParticipantEvent("participantUpdated", participant)
                    }
                }
                val stateListener = PropertyChangedListener {
                    safeCall("participantState:$participantId") {
                        emitParticipantEvent("participantUpdated", participant)
                    }
                }

                // Add listeners
                participant.addOnVideoStreamsUpdatedListener(videoStreamsListener)
                participant.addOnIsMutedChangedListener(mutedListener)
                participant.addOnIsSpeakingChangedListener(speakingListener)
                participant.addOnStateChangedListener(stateListener)

                // Store listener references
                participantListenersMap[participantId] = ParticipantListeners(
                    videoStreamsListener = videoStreamsListener,
                    mutedListener = mutedListener,
                    speakingListener = speakingListener,
                    stateListener = stateListener
                )

                // Watch availability of the participant's CURRENT streams so a camera
                // turned on AFTER they joined (isAvailable false->true, which fires no
                // added/removed-stream event) still re-renders their tile. Attached
                // after the listener map entry exists so the helper can track them.
                participant.incomingVideoStreams
                    ?.filterIsInstance<RemoteVideoStream>()
                    ?.forEach { attachStreamStateListener(participantId, it) }
            }
            // Re-reconcile EVERY mounted tile after a roster addition: a mid-call
            // joiner causes the grid to re-lay-out and existing tiles may be rebuilt;
            // this re-attaches any survivor renderer dropped during that rebuild and
            // attaches the joiner's tile if its stream is already available. Idempotent
            // per tile (guarded by hasContainer/isRendering).
            reconcileAllParticipantTiles()
        }
    }

    private fun handleRemovedParticipants(participants: List<RemoteParticipant>) {
        safeCall("handleRemovedParticipants") {
            participants.forEach { participant ->
                // Remove participant listeners to prevent memory leaks
                removeParticipantListeners(participant)

                participant.incomingVideoStreams
                    ?.filterIsInstance<RemoteVideoStream>()
                    ?.forEach { removeRemoteStream(it.id) }
                // Detach the participant's grid tile renderer (container kept until
                // the Flutter view is disposed).
                participant.identifier?.rawId?.let { reconcileParticipantTile(it) }
                emitParticipantEvent("participantRemoved", participant)
            }
            // Re-reconcile EVERY surviving tile after a roster removal. The grid
            // re-lays-out when a participant leaves; without this, a survivor whose
            // tile is rebuilt is left without a renderer (one-drops-all-stop). Each
            // tile's reconcile is idempotent (guarded by hasContainer/isRendering).
            reconcileAllParticipantTiles()
        }
    }

    private fun removeParticipantListeners(participant: RemoteParticipant) {
        val participantId = participant.identifier?.rawId ?: return
        val listeners = participantListenersMap.remove(participantId) ?: return

        try {
            participant.removeOnVideoStreamsUpdatedListener(listeners.videoStreamsListener)
            participant.removeOnIsMutedChangedListener(listeners.mutedListener)
            participant.removeOnIsSpeakingChangedListener(listeners.speakingListener)
            participant.removeOnStateChangedListener(listeners.stateListener)
            // Detach every per-stream availability listener so none leak after the
            // participant is gone.
            listeners.streamStateListeners.values.forEach { (stream, listener) ->
                try {
                    stream.removeOnStateChangedListener(listener)
                } catch (e: Exception) {
                    Log.e("AcsFlutterSdkPlugin", "Failed to remove stream state listener for $participantId: ${e.message}")
                }
            }
            listeners.streamStateListeners.clear()
        } catch (e: Exception) {
            Log.e("AcsFlutterSdkPlugin", "Failed to remove participant listeners for $participantId: ${e.message}")
        }
    }

    private fun clearAllParticipantListeners() {
        // Remove all stored participant listeners
        val currentCall = call ?: return
        try {
            currentCall.remoteParticipants.forEach { participant ->
                removeParticipantListeners(participant)
            }
        } catch (e: Exception) {
            Log.e("AcsFlutterSdkPlugin", "Failed to clear participant listeners: ${e.message}")
        }
        participantListenersMap.clear()
    }

    private fun subscribeRemoteStream(stream: RemoteVideoStream) {
        mainHandler.post {
            safeCall("subscribeRemoteStream:${stream.id}") {
                // Single-renderer-per-stream guard: when a per-participant grid tile is
                // mounted for this stream's owner, that tile's renderer is the sole display
                // owner. Creating the shared single-feed renderer here too would back the
                // same stream with a SECOND native VideoStreamRenderer — a second scarce
                // MediaCodec hardware decoder session acquired on the main thread — which is
                // what saturates the UI thread and freezes the call when a participant joins
                // on a physical device. Reserve the shared path for the genuine single-remote
                // (no-grid) case, where no participant tile exists.
                val ownerId = participantIdOwning(stream.id)
                if (ownerId != null && participantRegistry?.hasContainer(ownerId) == true) {
                    return@safeCall
                }
                val view = videoRegistry?.start(stream) ?: return@safeCall
                viewManager?.addRemoteView(activity, stream.id, view)
            }
        }
    }

    /**
     * Returns the raw id of the remote participant that owns the given video
     * [streamId], or null if no current participant publishes it.
     *
     * Used to enforce the single-renderer-per-stream invariant: the shared single-feed
     * path skips a stream once a per-participant grid tile owns it.
     */
    private fun participantIdOwning(streamId: Int): String? {
        return call?.remoteParticipants?.firstOrNull { participant ->
            participant.incomingVideoStreams
                ?.filterIsInstance<RemoteVideoStream>()
                ?.any { it.id == streamId } == true
        }?.identifier?.rawId
    }

    private fun removeRemoteStream(streamId: Int) {
        safeCall("removeRemoteStream:$streamId") {
            viewManager?.removeRemoteView(activity, streamId)
            videoRegistry?.stop(streamId)
        }
    }

    /**
     * Wires a per-stream availability listener so a remote stream flipping its
     * availability (e.g. a participant turning their camera on AFTER joining)
     * re-reconciles the tile and notifies Dart. Without this, a mid-call camera-on
     * is never reflected on Android, because the SDK fires no added/removed-stream
     * event for an availability flip (only iOS had an equivalent signal).
     *
     * Idempotent per (participant, streamId) and tracked in [ParticipantListeners]
     * for leak-free removal. No-op if the participant has no listener entry yet.
     */
    private fun attachStreamStateListener(participantId: String, stream: RemoteVideoStream) {
        val listeners = participantListenersMap[participantId] ?: return
        if (listeners.streamStateListeners.containsKey(stream.id)) return
        val listener = VideoStreamStateChangedListener {
            safeCall("videoStreamState:$participantId:${stream.id}") {
                if (stream.isAvailable) subscribeRemoteStream(stream) else removeRemoteStream(stream.id)
                reconcileParticipantTile(participantId)
                call?.remoteParticipants
                    ?.firstOrNull { it.identifier?.rawId == participantId }
                    ?.let { emitParticipantEvent("participantUpdated", it) }
            }
        }
        stream.addOnStateChangedListener(listener)
        listeners.streamStateListeners[stream.id] = stream to listener
    }

    /** Removes the availability listener for a single stream (on stream-removed). */
    private fun detachStreamStateListener(participantId: String, streamId: Int) {
        val listeners = participantListenersMap[participantId] ?: return
        listeners.streamStateListeners.remove(streamId)?.let { (stream, listener) ->
            try {
                stream.removeOnStateChangedListener(listener)
            } catch (e: Exception) {
                Log.e("AcsFlutterSdkPlugin", "Failed to remove stream state listener for $participantId: ${e.message}")
            }
        }
    }

    /**
     * Reconciles a single per-participant grid tile against the active call.
     *
     * Looks up the participant by raw id, finds their first available remote video
     * stream, and attaches it to the participant's tile (or detaches if none is
     * available). Called when a tile mounts and whenever a participant's streams
     * change, so each grid tile renders exactly its owner's video. The shared
     * `remoteVideoView` path is unaffected.
     */
    private fun reconcileParticipantTile(participantId: String) {
        val registry = participantRegistry ?: return
        if (!registry.hasContainer(participantId)) return
        safeCall("reconcileParticipantTile:$participantId") {
            val participant = call?.remoteParticipants?.firstOrNull {
                it.identifier?.rawId == participantId
            }
            if (participant == null) {
                registry.detach(participantId)
                return@safeCall
            }
            val available = participant.incomingVideoStreams
                ?.filterIsInstance<RemoteVideoStream>()
                ?.firstOrNull { it.isAvailable }
            if (available != null) {
                // Dispose-BEFORE-attach takeover. ACS permits exactly one
                // VideoStreamRenderer per RemoteVideoStream. During a join the shared
                // single-feed path can claim this stream's renderer before the grid tile
                // mounts; if it still holds the slot, building the tile's own renderer
                // fails and the tile never renders (infinite spinner). Free the shared
                // renderer FIRST, then attach the tile renderer into the now-open slot.
                // The brief no-renderer gap is unavoidable under the one-renderer-per-
                // stream rule and is harmless; it keeps one native decoder session per
                // stream. removeRemoteStream is a no-op when the shared path holds nothing.
                removeRemoteStream(available.id)
                registry.attach(participantId, available)
            } else {
                registry.detach(participantId)
            }
        }
    }

    /**
     * Reconciles every mounted per-participant tile, e.g. after participants are
     * added so a tile mounted before its participant existed gets attached.
     */
    private fun reconcileAllParticipantTiles() {
        val registry = participantRegistry ?: return
        registry.mountedParticipantIds().forEach { reconcileParticipantTile(it) }
    }

    private fun cleanupCallResources() {
        safeCall("cleanupCallResources") {
            if (screenShareActive || screenShareStream != null) {
                stopScreenShareInternal { _ -> }
            }
            clearAllParticipantListeners()
            call?.removeOnRemoteParticipantsUpdatedListener(remoteParticipantListener)
            call?.removeOnStateChangedListener(callStateListener)
            capabilitiesListener?.let { call?.feature(Features.CAPABILITIES)?.removeOnCapabilitiesChangedListener(it) }
            removeCaptionsListeners()
            removeDiagnosticsListeners()
            removeMediaStatisticsListeners()
            call = null
            remoteParticipantListener = null
            callStateListener = null
            capabilitiesListener = null
            incomingCall = null
            activeVideoEffect = null
            callCaptions = null
            localUserDiagnosticsFeature = null
            videoRegistry?.clear()
            participantRegistry?.clear()
            viewManager?.clearRemoteViews()
            viewManager?.clearLocalPreview()
            localVideoStream = null
        }
    }

    private fun emitParticipantEvent(type: String, participant: RemoteParticipant) {
        val sink = eventSink ?: return
        val payload = mutableMapOf<String, Any?>("type" to type, "id" to participant.identifier?.rawId)
        if (type == "participantUpdated" || type == "participantAdded") {
            payload["participant"] = serializeParticipant(participant)
        }
        runOnMainThread { safeCall("emitParticipantEvent:$type") { sink.success(payload) } }
    }

    private fun emitIncomingCallEvent(type: String, incomingCall: IncomingCall?) {
        val sink = incomingCallEventSink ?: return
        val payload = mutableMapOf<String, Any?>("type" to type)
        if (incomingCall != null) {
            payload["call"] = serializeIncomingCall(incomingCall)
        }
        runOnMainThread { safeCall("emitIncomingCallEvent:$type") { sink.success(payload) } }
    }

    private fun emitCapabilitiesEvent(event: CapabilitiesChangedEvent) {
        val sink = capabilitiesEventSink ?: return
        val changed = event.changedCapabilities.map { capability ->
            mapOf(
                "type" to (capability.type?.toString() ?: "unknown"),
                "isAllowed" to (capability.isAllowed == true),
                "reason" to (capability.reason?.toString() ?: "")
            )
        }
        val payload = mapOf(
            "reason" to (event.reason?.toString() ?: ""),
            "changedCapabilities" to changed
        )
        runOnMainThread { safeCall("emitCapabilitiesEvent") { sink.success(payload) } }
    }

    private fun serializeParticipant(p: RemoteParticipant): Map<String, Any?> {
        val videos = (p.videoStreams ?: emptyList()).map { stream ->
            mapOf(
                "id" to stream.id,
                "type" to (stream.mediaStreamType?.toString()?.lowercase() ?: "unknown"),
                "isAvailable" to (stream.isAvailable == true)
            )
        }
        return mapOf(
            "id" to (p.identifier?.rawId ?: ""),
            "displayName" to (p.displayName ?: ""),
            "state" to p.state.toString().lowercase(),
            "isMuted" to (p.isMuted == true),
            "isSpeaking" to (p.isSpeaking == true),
            "videoStreams" to videos
        )
    }

    private fun serializeIncomingCall(call: IncomingCall): Map<String, Any?> {
        val callerInfo = call.callerInfo
        return mapOf(
            "id" to call.id,
            "callerId" to (callerInfo?.identifier?.rawId ?: ""),
            "displayName" to (callerInfo?.displayName ?: ""),
            "hasVideo" to (call.isVideoEnabled == true)
        )
    }

    private fun ensureLocalVideoStream(): LocalVideoStream? {
        localVideoStream?.let { return it }

        // Check camera permission BEFORE attempting to create stream
        // This prevents crashes when camera permission is denied
        val cameraPermission = ContextCompat.checkSelfPermission(context, android.Manifest.permission.CAMERA)
        if (cameraPermission != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "Camera permission not granted, cannot create LocalVideoStream")
            return null
        }

        val dm = ensureDeviceManager() ?: return null
        val cameras = dm.cameras
        if (cameras.isNullOrEmpty()) {
            return null
        }
        if (currentCamera == null) {
            currentCamera = cameras.first()
        }
        return try {
            LocalVideoStream(currentCamera, context).also { localVideoStream = it }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create LocalVideoStream: ${e.message}", e)
            null
        }
    }

    private fun ensureLocalVideoEffectsFeature(): LocalVideoEffectsFeature? {
        val stream = ensureLocalVideoStream() ?: return null
        return stream.feature(Features.LOCAL_VIDEO_EFFECTS)
    }

    private fun ensureDeviceManager(): DeviceManager? {
        if (deviceManager != null) return deviceManager
        return try {
            val dm = callClient?.getDeviceManager(context)?.get()
            deviceManager = dm
            dm
        } catch (e: Exception) {
            null
        }
    }
    // endregion

    private fun callStateToString(state: CallState): String =
        when (state) {
            CallState.NONE -> "none"
            CallState.CONNECTING -> "connecting"
            CallState.RINGING -> "ringing"
            CallState.CONNECTED -> "connected"
            CallState.LOCAL_HOLD -> "onHold"
            CallState.DISCONNECTING -> "disconnecting"
            CallState.DISCONNECTED -> "disconnected"
            CallState.EARLY_MEDIA -> "earlyMedia"
            CallState.REMOTE_HOLD -> "remoteHold"
            else -> "unknown"
        }

    private fun lobbyStateString(call: Call?): String? =
        if (call?.state == CallState.IN_LOBBY) "inLobby" else null

    private fun logError(context: String, error: Throwable) {
        Log.e(TAG, "[ACS][Plugin][$context] ${error.message}", error)
    }

    private fun attachUiLibrary(binding: FlutterPlugin.FlutterPluginBinding) {
        try {
            val clazz = Class.forName("com.burhanrabbani.acs_flutter_sdk.AcsUiLibraryPlugin")
            val instance = clazz.getDeclaredConstructor().newInstance()
            clazz.getMethod("onAttachedToEngine", FlutterPlugin.FlutterPluginBinding::class.java)
                .invoke(instance, binding)
            uiLibraryPlugin = instance
        } catch (e: Throwable) {
            logError("attachUiLibrary", e)
            uiLibraryPlugin = null
        }
    }

    private fun detachUiLibrary(binding: FlutterPlugin.FlutterPluginBinding) {
        val instance = uiLibraryPlugin ?: return
        try {
            instance.javaClass.getMethod("onDetachedFromEngine", FlutterPlugin.FlutterPluginBinding::class.java)
                .invoke(instance, binding)
        } catch (e: Throwable) {
            logError("detachUiLibrary", e)
        } finally {
            uiLibraryPlugin = null
        }
    }

    private fun invokeUiLibrary(methodName: String, vararg args: Any) {
        val instance = uiLibraryPlugin ?: return
        try {
            val method = instance.javaClass.methods.firstOrNull { it.name == methodName && it.parameterTypes.size == args.size }
            if (method != null) {
                method.invoke(instance, *args)
            }
        } catch (e: Throwable) {
            logError("uiLibrary.$methodName", e)
        }
    }

    private inline fun safeCall(
        context: String,
        result: Result? = null,
        block: () -> Unit
    ) {
        try {
            block()
        } catch (t: Throwable) {
            logError(context, t)
            result?.let { res ->
                runOnMainThread {
                    res.error("UNEXPECTED_ERROR", "Error in $context: ${t.message}", t.toString())
                }
            }
        }
    }

    private fun runOnMainThread(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            mainHandler.post(action)
        }
    }

    private fun buildIdentifier(rawId: String): CommunicationIdentifier {
        return if (rawId.startsWith("+")) {
            PhoneNumberIdentifier(rawId)
        } else {
            CommunicationIdentifier.fromRawId(rawId)
        }
    }

    companion object {
        private const val TAG = "ACS"
        private const val PERMISSIONS_REQUEST_CODE = 9001
        private const val SCREEN_SHARE_REQUEST_CODE = 9123
        private const val SCREEN_SHARE_TARGET_FPS = 15
        private const val PLATFORM_VIEW_TYPE = "acs_video_view"
    }
}

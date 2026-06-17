package com.burhanrabbani.acs_flutter_sdk

import android.app.Activity
import android.content.Context
import android.view.View
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import com.azure.android.communication.common.CommunicationTokenCredential
import com.azure.android.communication.common.CommunicationUserIdentifier
import com.azure.android.communication.ui.calling.CallComposite
import com.azure.android.communication.ui.calling.CallCompositeBuilder
import com.azure.android.communication.ui.calling.models.CallCompositeButtonViewData
import com.azure.android.communication.ui.calling.models.CallCompositeCallScreenControlBarOptions
import com.azure.android.communication.ui.calling.models.CallCompositeCallScreenOptions
import com.azure.android.communication.ui.calling.models.CallCompositeCallStateCode
import com.azure.android.communication.ui.calling.models.CallCompositeGroupCallLocator
import com.azure.android.communication.ui.calling.models.CallCompositeLocalizationOptions
import com.azure.android.communication.ui.calling.models.CallCompositeMultitaskingOptions
import com.azure.android.communication.ui.calling.models.CallCompositeRoomLocator
import com.azure.android.communication.ui.calling.models.CallCompositeSupportedScreenOrientation
import com.azure.android.communication.ui.calling.models.CallCompositeTeamsMeetingIdLocator
import com.azure.android.communication.ui.calling.models.CallCompositeTeamsMeetingLinkLocator
import com.azure.android.communication.ui.calling.models.CallCompositeErrorCode
import com.azure.android.communication.ui.calling.models.CallCompositeLocalOptions
import java.util.Locale
import java.util.UUID

/**
 * Flutter plugin for Azure Communication Services UI Library
 *
 * This plugin provides access to pre-built UI composites (CallComposite, ChatComposite)
 * from the Azure Communication Services UI Library.
 */
class AcsUiLibraryPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var callComposite: CallComposite? = null

    companion object {
        private const val CHANNEL_NAME = "acs_ui_library"
    }

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "launchGroupCall" -> launchGroupCall(call, result)
            "launchTeamsMeeting" -> launchTeamsMeeting(call, result)
            "launchTeamsMeetingWithId" -> launchTeamsMeetingWithId(call, result)
            "launchRoomCall" -> launchRoomCall(call, result)
            "launchOutgoingCall" -> launchOutgoingCall(call, result)
            "launchChat" -> launchChat(call, result)
            "dismiss" -> dismiss(result)
            "bringToForeground" -> bringToForeground(result)
            else -> result.notImplemented()
        }
    }

    private fun launchGroupCall(call: MethodCall, result: Result) {
        try {
            val accessToken = call.argument<String>("accessToken")
                ?: return result.error("INVALID_ARGS", "accessToken is required", null)
            val groupId = call.argument<String>("groupId")
                ?: return result.error("INVALID_ARGS", "groupId is required", null)
            val options = call.argument<Map<String, Any?>>("options")
                ?: return result.error("INVALID_ARGS", "options is required", null)

            val credential = CommunicationTokenCredential(accessToken)
            val (composite, localOptions) = buildCallComposite(credential, options)
            val locator = CallCompositeGroupCallLocator(UUID.fromString(groupId))

            activity?.let {
                composite.launch(it, locator, localOptions)
                callComposite = composite
                result.success(null)
            } ?: result.error("NO_ACTIVITY", "Activity not available", null)
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, e.stackTraceToString())
        }
    }

    private fun launchTeamsMeeting(call: MethodCall, result: Result) {
        try {
            val accessToken = call.argument<String>("accessToken")
                ?: return result.error("INVALID_ARGS", "accessToken is required", null)
            val meetingLink = call.argument<String>("meetingLink")
                ?: return result.error("INVALID_ARGS", "meetingLink is required", null)
            val options = call.argument<Map<String, Any?>>("options")
                ?: return result.error("INVALID_ARGS", "options is required", null)

            val credential = CommunicationTokenCredential(accessToken)
            val (composite, localOptions) = buildCallComposite(credential, options)
            val locator = CallCompositeTeamsMeetingLinkLocator(meetingLink)

            activity?.let {
                composite.launch(it, locator, localOptions)
                callComposite = composite
                result.success(null)
            } ?: result.error("NO_ACTIVITY", "Activity not available", null)
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, e.stackTraceToString())
        }
    }

    private fun launchTeamsMeetingWithId(call: MethodCall, result: Result) {
        try {
            val accessToken = call.argument<String>("accessToken")
                ?: return result.error("INVALID_ARGS", "accessToken is required", null)
            val meetingId = call.argument<String>("meetingId")
                ?: return result.error("INVALID_ARGS", "meetingId is required", null)
            val meetingPasscode = call.argument<String>("meetingPasscode")
                ?: return result.error("INVALID_ARGS", "meetingPasscode is required", null)
            val options = call.argument<Map<String, Any?>>("options")
                ?: return result.error("INVALID_ARGS", "options is required", null)

            val credential = CommunicationTokenCredential(accessToken)
            val (composite, localOptions) = buildCallComposite(credential, options)
            val locator = CallCompositeTeamsMeetingIdLocator(meetingId, meetingPasscode)

            activity?.let {
                composite.launch(it, locator, localOptions)
                callComposite = composite
                result.success(null)
            } ?: result.error("NO_ACTIVITY", "Activity not available", null)
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, e.stackTraceToString())
        }
    }

    private fun launchRoomCall(call: MethodCall, result: Result) {
        try {
            val accessToken = call.argument<String>("accessToken")
                ?: return result.error("INVALID_ARGS", "accessToken is required", null)
            val roomId = call.argument<String>("roomId")
                ?: return result.error("INVALID_ARGS", "roomId is required", null)
            val options = call.argument<Map<String, Any?>>("options")
                ?: return result.error("INVALID_ARGS", "options is required", null)

            val credential = CommunicationTokenCredential(accessToken)
            val (composite, localOptions) = buildCallComposite(credential, options)
            val locator = CallCompositeRoomLocator(roomId)

            activity?.let {
                composite.launch(it, locator, localOptions)
                callComposite = composite
                result.success(null)
            } ?: result.error("NO_ACTIVITY", "Activity not available", null)
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, e.stackTraceToString())
        }
    }

    private fun launchOutgoingCall(call: MethodCall, result: Result) {
        try {
            val accessToken = call.argument<String>("accessToken")
                ?: return result.error("INVALID_ARGS", "accessToken is required", null)
            val participantIds = call.argument<List<String>>("participantIds")
                ?: return result.error("INVALID_ARGS", "participantIds is required", null)
            val options = call.argument<Map<String, Any?>>("options")
                ?: return result.error("INVALID_ARGS", "options is required", null)

            val credential = CommunicationTokenCredential(accessToken)
            val (composite, localOptions) = buildCallComposite(credential, options)

            val participants = participantIds.map {
                CommunicationUserIdentifier(it)
            }

            activity?.let {
                composite.launch(it, participants, localOptions)
                callComposite = composite
                result.success(null)
            } ?: result.error("NO_ACTIVITY", "Activity not available", null)
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, e.stackTraceToString())
        }
    }

    private fun launchChat(call: MethodCall, result: Result) {
        try {
            result.error("NOT_IMPLEMENTED", "ChatComposite is not available in this build.", null)
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, e.stackTraceToString())
        }
    }

    private fun dismiss(result: Result) {
        try {
            callComposite?.dismiss()
            callComposite = null
            result.success(null)
        } catch (e: Exception) {
            result.error("DISMISS_FAILED", e.message, null)
        }
    }

    /**
     * Re-displays a composite that was minimized (sent to background) via
     * multitasking. Unlike [dismiss], this keeps the call alive and does NOT null
     * [callComposite] — it only brings the existing composite Activity back to the
     * foreground so the user returns to the live call. No-op when no composite is
     * active (e.g. the call already ended).
     */
    private fun bringToForeground(result: Result) {
        try {
            callComposite?.bringToForeground(context)
            result.success(null)
        } catch (e: Exception) {
            result.error("BRING_TO_FOREGROUND_FAILED", e.message, null)
        }
    }

    /**
     * Builds a CallComposite instance with the provided options
     */
    private fun buildCallComposite(
        credential: CommunicationTokenCredential,
        options: Map<String, Any?>
    ): Pair<CallComposite, CallCompositeLocalOptions> {
        val displayName = options["displayName"] as? String ?: "User"

        val builder = CallCompositeBuilder()
            .applicationContext(context)
            .credential(credential)
            .displayName(displayName)

        val multitaskingOptions = options["multitasking"] as? Map<String, Any?>
        if (multitaskingOptions != null) {
            val enableMultitasking = multitaskingOptions["enableMultitasking"] as? Boolean ?: true
            val enablePiP = multitaskingOptions["enablePictureInPicture"] as? Boolean ?: true

            builder.multitasking(
                CallCompositeMultitaskingOptions(enableMultitasking, enablePiP)
            )
        }

        val localizationOptions = options["localization"] as? Map<String, Any?>
        if (localizationOptions != null) {
            val languageCode = localizationOptions["languageCode"] as? String
            val countryCode = localizationOptions["countryCode"] as? String
            val isRtl = localizationOptions["isRightToLeft"] as? Boolean ?: false

            if (languageCode != null) {
                val locale = if (!countryCode.isNullOrBlank()) {
                    Locale(languageCode, countryCode)
                } else {
                    Locale(languageCode)
                }
                val layoutDirection = if (isRtl) {
                    View.LAYOUT_DIRECTION_RTL
                } else {
                    View.LAYOUT_DIRECTION_LTR
                }
                builder.localization(CallCompositeLocalizationOptions(locale, layoutDirection))
            }
        }

        val orientationOption = options["orientation"] as? String
        orientationOption?.let { orientationName ->
            val orientation = when (orientationName) {
                "portrait" -> CallCompositeSupportedScreenOrientation.PORTRAIT
                "landscape" -> CallCompositeSupportedScreenOrientation.LANDSCAPE
                "landscapeRight" -> CallCompositeSupportedScreenOrientation.USER_LANDSCAPE
                "landscapeLeft" -> CallCompositeSupportedScreenOrientation.REVERSE_LANDSCAPE
                "allButUpsideDown" -> CallCompositeSupportedScreenOrientation.FULL_SENSOR
                else -> CallCompositeSupportedScreenOrientation.FULL_SENSOR
            }
            builder.callScreenOrientation(orientation)
            builder.setupScreenOrientation(orientation)
        }

        val enableCameraButton = options["enableCameraButton"] as? Boolean ?: true
        val enableMicrophoneButton = options["enableMicrophoneButton"] as? Boolean ?: true

        val controlBarOptions = CallCompositeCallScreenControlBarOptions()
            .setCameraButton(CallCompositeButtonViewData().setEnabled(enableCameraButton))
            .setMicrophoneButton(CallCompositeButtonViewData().setEnabled(enableMicrophoneButton))

        builder.callScreenOptions(
            CallCompositeCallScreenOptions().setControlBarOptions(controlBarOptions)
        )

        val skipSetupScreen = options["skipSetupScreen"] as? Boolean ?: false
        val cameraOn = options["cameraOn"] as? Boolean ?: false
        val microphoneOn = options["microphoneOn"] as? Boolean ?: false

        val localOptions = CallCompositeLocalOptions()
            .setSkipSetupScreen(skipSetupScreen)
            .setCameraOn(cameraOn)
            .setMicrophoneOn(microphoneOn)
            .setCallScreenOptions(controlBarOptions.let { CallCompositeCallScreenOptions().setControlBarOptions(it) })

        val composite = builder.build()

        composite.addOnErrorEventHandler { errorEvent ->
            val errorCode = when (errorEvent.errorCode) {
                CallCompositeErrorCode.CALL_JOIN_FAILED -> "callJoinFailed"
                CallCompositeErrorCode.CALL_END_FAILED -> "callEndFailed"
                CallCompositeErrorCode.TOKEN_EXPIRED -> "tokenExpired"
                CallCompositeErrorCode.CAMERA_FAILURE -> "cameraFailure"
                CallCompositeErrorCode.MICROPHONE_PERMISSION_NOT_GRANTED -> "microphonePermissionNotGranted"
                CallCompositeErrorCode.NETWORK_CONNECTION_NOT_AVAILABLE -> "networkConnectionNotAvailable"
                else -> "unknown"
            }

            Log.e(
                "AcsUiLibraryPlugin",
                "onError code=$errorCode native=${errorEvent.errorCode} cause=${errorEvent.cause?.message}"
            )

            channel.invokeMethod(
                "onError",
                mapOf(
                    "errorCode" to errorCode,
                    "message" to errorEvent.cause?.message,
                    "nativeCode" to errorEvent.errorCode.toString()
                )
            )
        }

        composite.addOnCallStateChangedEventHandler { callStateEvent ->
            val state = when (callStateEvent.code) {
                CallCompositeCallStateCode.NONE -> "none"
                CallCompositeCallStateCode.CONNECTING -> "connecting"
                CallCompositeCallStateCode.RINGING -> "ringing"
                CallCompositeCallStateCode.CONNECTED -> "connected"
                CallCompositeCallStateCode.LOCAL_HOLD -> "localHold"
                CallCompositeCallStateCode.REMOTE_HOLD -> "remoteHold"
                CallCompositeCallStateCode.DISCONNECTING -> "disconnecting"
                CallCompositeCallStateCode.DISCONNECTED -> "disconnected"
                CallCompositeCallStateCode.IN_LOBBY -> "inLobby"
                else -> "unknown"
            }

            Log.d(
                "AcsUiLibraryPlugin",
                "callStateChanged native=${callStateEvent.code} mapped=$state"
            )

            channel.invokeMethod(
                "onCallStateChanged",
                mapOf(
                    "state" to state,
                    "nativeState" to callStateEvent.code.toString()
                )
            )
        }

        composite.addOnDismissedEventHandler { dismissedEvent ->
            channel.invokeMethod(
                "onDismissed",
                mapOf(
                    "errorCode" to dismissedEvent.errorCode?.toString(),
                    "reason" to dismissedEvent.cause?.message
                )
            )
            callComposite = null
        }

        composite.addOnRemoteParticipantJoinedEventHandler { participantEvent ->
            val ids = participantEvent.identifiers.map { it.rawId ?: "" }
            channel.invokeMethod(
                "onRemoteParticipantJoined",
                mapOf(
                    "participantCount" to ids.size,
                    "participantIds" to ids
                )
            )
        }

        return Pair(composite, localOptions)
    }

    private fun setupChatEventHandlers() { /* ChatComposite not implemented */ }
}

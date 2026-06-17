import Flutter
import UIKit
import AzureCommunicationCommon
import AzureCommunicationUICalling
import SwiftUI

/**
 * Flutter plugin for Azure Communication Services UI Library (iOS)
 *
 * This plugin provides access to pre-built UI composites (CallComposite)
 * from the Azure Communication Services UI Library.
 */
public class AcsUiLibraryPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var callComposite: CallComposite?

    private func logError(_ context: String, _ error: Error) {
        #if DEBUG
        NSLog("[AcsUiLibraryPlugin][\(context)] \(error.localizedDescription)")
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

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "acs_ui_library",
            binaryMessenger: registrar.messenger()
        )
        let instance = AcsUiLibraryPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        safeHandle("handle:\(call.method)", result: result) {
            switch call.method {
            case "launchGroupCall":
                launchGroupCall(call: call, result: result)
            case "launchTeamsMeeting":
                launchTeamsMeeting(call: call, result: result)
            case "launchTeamsMeetingWithId":
                launchTeamsMeetingWithId(call: call, result: result)
            case "launchRoomCall":
                launchRoomCall(call: call, result: result)
            case "launchOutgoingCall":
                launchOutgoingCall(call: call, result: result)
            case "launchChat":
                launchChat(call: call, result: result)
            case "dismiss":
                dismiss(result: result)
            case "bringToForeground":
                bringToForeground(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - CallComposite Launch Methods

    private func launchGroupCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let accessToken = args["accessToken"] as? String,
              let groupId = args["groupId"] as? String,
              let options = args["options"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
            return
        }

        do {
            let credential = try CommunicationTokenCredential(token: accessToken)
            let (composite, localOptions) = try buildCallComposite(credential: credential, options: options)

            guard let uuid = UUID(uuidString: groupId) else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid group ID format", details: nil))
                return
            }

            DispatchQueue.main.async { [weak self] in
                composite.launch(locator: .groupCall(groupId: uuid), localOptions: localOptions)
                self?.callComposite = composite
                result(nil)
            }
        } catch {
            result(FlutterError(code: "LAUNCH_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func launchTeamsMeeting(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let accessToken = args["accessToken"] as? String,
              let meetingLink = args["meetingLink"] as? String,
              let options = args["options"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
            return
        }

        #if DEBUG
        let tokenLength = accessToken.count
        NSLog("[AcsUiLibraryPlugin] launchTeamsMeeting tokenLength=\(tokenLength) meetingLink=\(meetingLink.prefix(120))")
        #endif

        do {
            let credential = try CommunicationTokenCredential(token: accessToken)
            let (composite, localOptions) = try buildCallComposite(credential: credential, options: options)

            DispatchQueue.main.async { [weak self] in
                do {
                    composite.launch(locator: .teamsMeeting(teamsLink: meetingLink), localOptions: localOptions)
                    self?.callComposite = composite
                    result(nil)
                } catch {
                    let nsError = error as NSError
                    #if DEBUG
                    NSLog("[AcsUiLibraryPlugin] launchTeamsMeeting failed domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")
                    #endif
                    result(FlutterError(code: "LAUNCH_FAILED", message: nsError.localizedDescription, details: [
                        "domain": nsError.domain,
                        "code": nsError.code
                    ]))
                }
            }
        } catch {
            let nsError = error as NSError
            #if DEBUG
            NSLog("[AcsUiLibraryPlugin] launchTeamsMeeting failed during setup domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")
            #endif
            result(FlutterError(code: "LAUNCH_FAILED", message: nsError.localizedDescription, details: [
                "domain": nsError.domain,
                "code": nsError.code
            ]))
        }
    }

    private func launchTeamsMeetingWithId(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let accessToken = args["accessToken"] as? String,
              let meetingId = args["meetingId"] as? String,
              let meetingPasscode = args["meetingPasscode"] as? String,
              let options = args["options"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
            return
        }

        do {
            let credential = try CommunicationTokenCredential(token: accessToken)
            let (composite, localOptions) = try buildCallComposite(credential: credential, options: options)

            DispatchQueue.main.async { [weak self] in
                composite.launch(
                    locator: .teamsMeetingId(
                        meetingId: meetingId,
                        meetingPasscode: meetingPasscode
                    ),
                    localOptions: localOptions
                )
                self?.callComposite = composite
                result(nil)
            }
        } catch {
            result(FlutterError(code: "LAUNCH_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func launchRoomCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let accessToken = args["accessToken"] as? String,
              let roomId = args["roomId"] as? String,
              let options = args["options"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
            return
        }

        do {
            let credential = try CommunicationTokenCredential(token: accessToken)
            let (composite, localOptions) = try buildCallComposite(credential: credential, options: options)

            DispatchQueue.main.async { [weak self] in
                composite.launch(locator: .roomCall(roomId: roomId), localOptions: localOptions)
                self?.callComposite = composite
                result(nil)
            }
        } catch {
            result(FlutterError(code: "LAUNCH_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func launchOutgoingCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let accessToken = args["accessToken"] as? String,
              let participantIds = args["participantIds"] as? [String],
              let options = args["options"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
            return
        }

        do {
            let credential = try CommunicationTokenCredential(token: accessToken)
            let (composite, localOptions) = try buildCallComposite(credential: credential, options: options)

            let participants = participantIds.map {
                CommunicationUserIdentifier($0)
            }

            DispatchQueue.main.async { [weak self] in
                composite.launch(participants: participants, localOptions: localOptions)
                self?.callComposite = composite
                result(nil)
            }
        } catch {
            result(FlutterError(code: "LAUNCH_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func launchChat(call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(FlutterError(
            code: "NOT_IMPLEMENTED",
            message: "ChatComposite is not available for iOS. Use custom UI with AcsChatClient.",
            details: nil
        ))
    }

    private func dismiss(result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            self?.callComposite?.dismiss()
            self?.callComposite = nil
            result(nil)
        }
    }

    /// Re-presents a composite that was minimized (hidden) via multitasking.
    ///
    /// Unlike `dismiss`, this keeps the call alive and does NOT null the
    /// `callComposite` reference — it only restores the hidden UI. No-op when no
    /// composite is active (e.g. the call already ended).
    private func bringToForeground(result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            // `displayCallCompositeIfWasHidden()` is private in the SDK; the public
            // entry point is the `isHidden` property — setting it to false re-shows
            // a composite that was minimized to PiP/background, keeping the call alive.
            self?.callComposite?.isHidden = false
            result(nil)
        }
    }

    // MARK: - CallComposite Builder

    private func buildCallComposite(
        credential: CommunicationTokenCredential,
        options: [String: Any]
    ) throws -> (CallComposite, LocalOptions?) {
        let displayName = options["displayName"] as? String

        let themeOptions = buildThemeOptions(options["theme"] as? [String: Any])
        let localizationOptions = buildLocalizationOptions(options["localization"] as? [String: Any])
        let orientationOption = buildOrientationOption(options["orientation"] as? String)

        let multitaskingOptions = options["multitasking"] as? [String: Any]
        let enableMultitasking = multitaskingOptions?["enableMultitasking"] as? Bool ?? false
        let enablePiP = multitaskingOptions?["enablePictureInPicture"] as? Bool ?? false

        let compositeOptions = CallCompositeOptions(
            theme: themeOptions,
            localization: localizationOptions,
            setupScreenOrientation: orientationOption,
            callingScreenOrientation: orientationOption,
            enableMultitasking: enableMultitasking,
            enableSystemPictureInPictureWhenMultitasking: enablePiP,
            displayName: displayName
        )

        let composite = CallComposite(credential: credential, withOptions: compositeOptions)

        let skipSetupScreen = options["skipSetupScreen"] as? Bool ?? false
        let cameraOn = options["cameraOn"] as? Bool ?? false
        let microphoneOn = options["microphoneOn"] as? Bool ?? false

        let enableCameraButton = options["enableCameraButton"] as? Bool ?? true
        let enableMicrophoneButton = options["enableMicrophoneButton"] as? Bool ?? true

        var callScreenOptions: CallScreenOptions?
        if !enableCameraButton || !enableMicrophoneButton {
            let controlBarOptions = CallScreenControlBarOptions(
                cameraButton: ButtonViewData(enabled: enableCameraButton),
                microphoneButton: ButtonViewData(enabled: enableMicrophoneButton)
            )
            callScreenOptions = CallScreenOptions(controlBarOptions: controlBarOptions)
        }

        let localOptions = LocalOptions(
            cameraOn: cameraOn,
            microphoneOn: microphoneOn,
            skipSetupScreen: skipSetupScreen,
            callScreenOptions: callScreenOptions
        )

        setupEventHandlers(composite: composite)

        return (composite, localOptions)
    }

    private func buildThemeOptions(_ theme: [String: Any]?) -> ThemeOptions? {
        guard let theme = theme,
              let primaryColorValue = theme["primaryColor"] as? Int else {
            return nil
        }

        guard let primaryColor = color(from: primaryColorValue) else {
            return nil
        }
        let foreground = color(from: theme["foregroundOnPrimaryColor"])

        return FlutterThemeOptions(
            primary: primaryColor,
            primaryTint10: primaryColor,
            primaryTint20: primaryColor,
            primaryTint30: primaryColor,
            foregroundOnPrimary: foreground ?? .white
        )
    }

    private func buildLocalizationOptions(_ localization: [String: Any]?) -> LocalizationOptions? {
        guard let localization = localization,
              let languageCode = localization["languageCode"] as? String else {
            return nil
        }

        let locale: Locale
        if let countryCode = localization["countryCode"] as? String, !countryCode.isEmpty {
            locale = Locale(identifier: "\(languageCode)_\(countryCode)")
        } else {
            locale = Locale(identifier: languageCode)
        }

        let isRtl = localization["isRightToLeft"] as? Bool ?? false
        return LocalizationOptions(
            locale: locale,
            layoutDirection: isRtl ? .rightToLeft : .leftToRight
        )
    }

    private func buildOrientationOption(_ orientation: String?) -> OrientationOptions? {
        guard let orientation = orientation else { return nil }

        switch orientation {
        case "portrait":
            return .portrait
        case "landscape":
            return .landscape
        case "landscapeRight":
            return .landscapeRight
        case "landscapeLeft":
            return .landscapeLeft
        case "allButUpsideDown":
            return .allButUpsideDown
        default:
            return nil
        }
    }

    private func setupEventHandlers(composite: CallComposite) {
        composite.events.onError = { [weak self] errorEvent in
            let errorCode: String
            switch errorEvent.code {
            case CallCompositeErrorCode.callJoin:
                errorCode = "callJoinFailed"
            case CallCompositeErrorCode.callEnd:
                errorCode = "callEndFailed"
            case CallCompositeErrorCode.tokenExpired:
                errorCode = "tokenExpired"
            case CallCompositeErrorCode.cameraFailure:
                errorCode = "cameraFailure"
            case CallCompositeErrorCode.microphonePermissionNotGranted:
                errorCode = "microphonePermissionNotGranted"
            case CallCompositeErrorCode.networkConnectionNotAvailable:
                errorCode = "networkConnectionNotAvailable"
            case "callEvicted":
                errorCode = "callEvicted"
            case "callDeclined":
                errorCode = "callDeclined"
            default:
                errorCode = "unknown"
            }

            let nsError = errorEvent.error as NSError?
            let nativeMessage = nsError?.localizedDescription ?? errorEvent.error?.localizedDescription
            #if DEBUG
            let errorDetails = nsError != nil ? " domain=\(nsError!.domain) code=\(nsError!.code)" : ""
            NSLog("[AcsUiLibraryPlugin] onError code=\(errorCode) nativeCode=\(errorEvent.code) message=\(nativeMessage ?? "nil")\(errorDetails)")
            #endif

            DispatchQueue.main.async {
                self?.channel?.invokeMethod("onError", arguments: [
                    "errorCode": errorCode,
                    "message": nativeMessage,
                    "nativeCode": "\(errorEvent.code)",
                    "nativeDomain": nsError?.domain,
                    "nativeErrorCode": nsError?.code
                ])
            }
        }

        composite.events.onCallStateChanged = { [weak self] callStateEvent in
            let state: String
            switch callStateEvent.requestString {
            case "none":
                state = "none"
            case "connecting":
                state = "connecting"
            case "ringing":
                state = "ringing"
            case "connected":
                state = "connected"
            case "localHold":
                state = "localHold"
            case "remoteHold":
                state = "remoteHold"
            case "disconnecting":
                state = "disconnecting"
            case "disconnected":
                state = "disconnected"
            case "inLobby":
                state = "inLobby"
            default:
                state = "unknown"
            }

            #if DEBUG
            NSLog("[AcsUiLibraryPlugin] callStateChanged nativeState=\(callStateEvent.requestString) mapped=\(state) "
                  + "endCode=\(callStateEvent.callEndReasonCodeInt ?? -1) "
                  + "endSubCode=\(callStateEvent.callEndReasonSubCodeInt ?? -1) "
                  + "callId=\(callStateEvent.callId ?? "nil")")
            #endif

            DispatchQueue.main.async {
                self?.channel?.invokeMethod("onCallStateChanged", arguments: [
                    "state": state,
                    "nativeState": callStateEvent.requestString,
                    "callEndReasonCode": callStateEvent.callEndReasonCodeInt,
                    "callEndReasonSubCode": callStateEvent.callEndReasonSubCodeInt,
                    "callId": callStateEvent.callId
                ])
            }
        }

        composite.events.onDismissed = { [weak self] dismissedEvent in
            var args: [String: Any?] = [:]
            if let errorCode = dismissedEvent.errorCode {
                args["errorCode"] = "\(errorCode)"
            }
            let reason = dismissedEvent.error?.localizedDescription
            args["reason"] = reason

            #if DEBUG
            NSLog("[AcsUiLibraryPlugin] dismissed errorCode=\(args["errorCode"] ?? "nil") reason=\(reason ?? "nil")")
            #endif

            DispatchQueue.main.async {
                self?.channel?.invokeMethod("onDismissed", arguments: args)
                self?.callComposite = nil
            }
        }

        composite.events.onRemoteParticipantJoined = { [weak self] participantEvent in
            let ids = participantEvent.map { $0.rawId }
            DispatchQueue.main.async {
                self?.channel?.invokeMethod("onRemoteParticipantJoined", arguments: [
                    "participantCount": ids.count,
                    "participantIds": ids
                ])
            }
        }
    }

    private func color(from value: Any?) -> UIColor? {
        guard let colorValue = value as? Int else { return nil }

        let alpha = CGFloat((colorValue >> 24) & 0xFF) / 255.0
        let red = CGFloat((colorValue >> 16) & 0xFF) / 255.0
        let green = CGFloat((colorValue >> 8) & 0xFF) / 255.0
        let blue = CGFloat(colorValue & 0xFF) / 255.0

        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private struct FlutterThemeOptions: ThemeOptions {
    let primaryColor: UIColor
    let primaryColorTint10: UIColor
    let primaryColorTint20: UIColor
    let primaryColorTint30: UIColor
    let foregroundOnPrimaryColor: UIColor

    var colorSchemeOverride: UIUserInterfaceStyle {
        return .unspecified
    }

    init(primary: UIColor,
         primaryTint10: UIColor,
         primaryTint20: UIColor,
         primaryTint30: UIColor,
         foregroundOnPrimary: UIColor) {
        self.primaryColor = primary
        self.primaryColorTint10 = primaryTint10
        self.primaryColorTint20 = primaryTint20
        self.primaryColorTint30 = primaryTint30
        self.foregroundOnPrimaryColor = foregroundOnPrimary
    }
}

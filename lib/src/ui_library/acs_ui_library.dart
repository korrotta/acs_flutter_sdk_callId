/// Azure Communication Services UI Library wrapper for Flutter
///
/// This class provides access to pre-built UI components from the Azure
/// Communication Services UI Library, offering a turn-key solution for
/// calling and chat experiences.
library;

import 'package:flutter/services.dart';

import 'ui_library_events.dart';
import 'ui_library_options.dart';

export 'ui_library_events.dart';
export 'ui_library_options.dart';

/// Main entry point for Azure Communication Services UI Library
///
/// Use this class to launch pre-built UI composites for calling and chat.
/// This is an alternative to building custom UI with [AcsFlutterSdk].
class AcsUiLibrary {
  /// Method channel for communicating with native platforms
  static const MethodChannel _channel = MethodChannel('acs_ui_library');

  /// Singleton instance
  static AcsUiLibrary? _instance;

  /// Error event handler
  AcsUiErrorHandler? onError;

  /// Call state changed event handler
  AcsCallStateChangedHandler? onCallStateChanged;

  /// Composite dismissed event handler
  AcsCompositeDismissedHandler? onDismissed;

  /// Remote participant joined event handler
  AcsRemoteParticipantJoinedHandler? onRemoteParticipantJoined;

  /// Private constructor
  AcsUiLibrary._() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Factory constructor - returns singleton instance
  factory AcsUiLibrary() {
    _instance ??= AcsUiLibrary._();
    return _instance!;
  }

  /// Handles method calls from native platform
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    final args = call.arguments as Map<dynamic, dynamic>?;
    final map = args?.cast<String, dynamic>() ?? {};

    switch (call.method) {
      case 'onError':
        onError?.call(AcsUiErrorEvent.fromMap(map));
        break;
      case 'onCallStateChanged':
        onCallStateChanged?.call(AcsCallStateChangedEvent.fromMap(map));
        break;
      case 'onDismissed':
        onDismissed?.call(AcsCompositeDismissedEvent.fromMap(map));
        break;
      case 'onRemoteParticipantJoined':
        onRemoteParticipantJoined
            ?.call(AcsRemoteParticipantJoinedEvent.fromMap(map));
        break;
    }
  }

  /// Launches the CallComposite for a group call
  ///
  /// [accessToken] - Azure Communication Services access token
  /// [groupId] - The UUID of the group call to join
  /// [options] - Configuration options for the call composite
  ///
  /// Throws [PlatformException] if the call fails to launch
  Future<void> launchGroupCall({
    required String accessToken,
    required String groupId,
    required CallCompositeOptions options,
  }) async {
    await _channel.invokeMethod('launchGroupCall', {
      'accessToken': accessToken,
      'groupId': groupId,
      'options': options.toMap(),
    });
  }

  /// Launches the CallComposite for a Teams meeting via meeting link
  ///
  /// [accessToken] - Azure Communication Services access token
  /// [meetingLink] - The Teams meeting URL
  /// [options] - Configuration options for the call composite
  ///
  /// Throws [PlatformException] if the call fails to launch
  Future<void> launchTeamsMeeting({
    required String accessToken,
    required String meetingLink,
    required CallCompositeOptions options,
  }) async {
    await _channel.invokeMethod('launchTeamsMeeting', {
      'accessToken': accessToken,
      'meetingLink': meetingLink,
      'options': options.toMap(),
    });
  }

  /// Launches the CallComposite for a Teams meeting using meeting ID and passcode
  ///
  /// [accessToken] - Azure Communication Services access token
  /// [meetingId] - The Teams meeting ID (typically 12 digits)
  /// [meetingPasscode] - The Teams meeting passcode
  /// [options] - Configuration options for the call composite
  ///
  /// Throws [PlatformException] if the call fails to launch
  Future<void> launchTeamsMeetingWithId({
    required String accessToken,
    required String meetingId,
    required String meetingPasscode,
    required CallCompositeOptions options,
  }) async {
    await _channel.invokeMethod('launchTeamsMeetingWithId', {
      'accessToken': accessToken,
      'meetingId': meetingId,
      'meetingPasscode': meetingPasscode,
      'options': options.toMap(),
    });
  }

  /// Launches the CallComposite for a Rooms call
  ///
  /// [accessToken] - Azure Communication Services access token
  /// [roomId] - The Room ID to join
  /// [options] - Configuration options for the call composite
  ///
  /// Throws [PlatformException] if the call fails to launch
  Future<void> launchRoomCall({
    required String accessToken,
    required String roomId,
    required CallCompositeOptions options,
  }) async {
    await _channel.invokeMethod('launchRoomCall', {
      'accessToken': accessToken,
      'roomId': roomId,
      'options': options.toMap(),
    });
  }

  /// Launches the CallComposite for a 1:1 or 1:N outgoing call
  ///
  /// [accessToken] - Azure Communication Services access token
  /// [participantIds] - List of ACS user IDs to call
  /// [options] - Configuration options for the call composite
  ///
  /// Throws [PlatformException] if the call fails to launch
  Future<void> launchOutgoingCall({
    required String accessToken,
    required List<String> participantIds,
    required CallCompositeOptions options,
  }) async {
    await _channel.invokeMethod('launchOutgoingCall', {
      'accessToken': accessToken,
      'participantIds': participantIds,
      'options': options.toMap(),
    });
  }

  /// Launches the ChatComposite for a chat thread
  ///
  /// [accessToken] - Azure Communication Services access token
  /// [endpoint] - The ACS endpoint URL (e.g., https://your-resource.communication.azure.com)
  /// [threadId] - The chat thread ID
  /// [userId] - The communication user ID of the local user
  /// [options] - Configuration options for the chat composite
  ///
  /// Throws [PlatformException] if the chat fails to launch
  Future<void> launchChat({
    required String accessToken,
    required String endpoint,
    required String threadId,
    required String userId,
    required ChatCompositeOptions options,
  }) async {
    await _channel.invokeMethod('launchChat', {
      'accessToken': accessToken,
      'endpoint': endpoint,
      'threadId': threadId,
      'userId': userId,
      'options': options.toMap(),
    });
  }

  /// Dismisses the currently active composite
  ///
  /// Call this to programmatically close the call or chat UI
  Future<void> dismiss() async {
    await _channel.invokeMethod('dismiss');
  }

  /// Re-displays a call composite that the user previously minimized.
  ///
  /// When multitasking is enabled, tapping the composite's back/minimize
  /// affordance hides the call UI while keeping the call connected. Call this to
  /// bring that hidden composite back to the foreground (e.g. from an in-app
  /// "Back to Call" control). No-op if no composite is currently active.
  ///
  /// Side effects: on Android brings the composite Activity to the foreground; on
  /// iOS re-presents the hidden composite window. Does NOT start a new call.
  ///
  /// Throws [PlatformException] if the native bring-to-foreground call fails.
  Future<void> bringToForeground() async {
    await _channel.invokeMethod('bringToForeground');
  }

  /// Disposes resources and clears event handlers
  void dispose() {
    onError = null;
    onCallStateChanged = null;
    onDismissed = null;
    onRemoteParticipantJoined = null;
  }
}

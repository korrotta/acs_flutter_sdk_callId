/// Event models for Azure Communication Services UI Library
library;

/// Error codes that can be returned by the UI Library
enum AcsUiErrorCode {
  /// Failed to join the call
  callJoinFailed,

  /// Failed to end the call
  callEndFailed,

  /// Token has expired
  tokenExpired,

  /// Camera failure
  cameraFailure,

  /// Microphone permission not granted
  microphonePermissionNotGranted,

  /// Network connection not available
  networkConnectionNotAvailable,

  /// Call was evicted (removed by organizer)
  callEvicted,

  /// Call was declined
  callDeclined,

  /// Unknown error
  unknown,
}

/// Call state values
enum AcsCallState {
  /// No call state
  none,

  /// Connecting to the call
  connecting,

  /// Call is ringing
  ringing,

  /// Connected to the call
  connected,

  /// Call is on hold locally
  localHold,

  /// Call is on hold remotely
  remoteHold,

  /// Disconnecting from the call
  disconnecting,

  /// Disconnected from the call
  disconnected,

  /// In lobby waiting to be admitted
  inLobby,

  /// Unknown state
  unknown,
}

/// Event fired when an error occurs in the UI Library
class AcsUiErrorEvent {
  /// The error code
  final AcsUiErrorCode errorCode;

  /// Optional error message
  final String? message;

  const AcsUiErrorEvent({
    required this.errorCode,
    this.message,
  });

  factory AcsUiErrorEvent.fromMap(Map<String, dynamic> map) {
    return AcsUiErrorEvent(
      errorCode: _parseErrorCode(map['errorCode'] as String?),
      message: map['message'] as String?,
    );
  }

  static AcsUiErrorCode _parseErrorCode(String? code) {
    switch (code) {
      case 'callJoinFailed':
        return AcsUiErrorCode.callJoinFailed;
      case 'callEndFailed':
        return AcsUiErrorCode.callEndFailed;
      case 'tokenExpired':
        return AcsUiErrorCode.tokenExpired;
      case 'cameraFailure':
        return AcsUiErrorCode.cameraFailure;
      case 'microphonePermissionNotGranted':
        return AcsUiErrorCode.microphonePermissionNotGranted;
      case 'networkConnectionNotAvailable':
        return AcsUiErrorCode.networkConnectionNotAvailable;
      case 'callEvicted':
        return AcsUiErrorCode.callEvicted;
      case 'callDeclined':
        return AcsUiErrorCode.callDeclined;
      default:
        return AcsUiErrorCode.unknown;
    }
  }
}

/// Event fired when the call state changes
class AcsCallStateChangedEvent {
  /// The new call state
  final AcsCallState state;

  /// The call ID
  final String? callId;

  const AcsCallStateChangedEvent({required this.state, this.callId});

  factory AcsCallStateChangedEvent.fromMap(Map<String, dynamic> map) {
    return AcsCallStateChangedEvent(
      state: _parseCallState(map['state'] as String?),
      callId: map['callId'] as String?,
    );
  }

  static AcsCallState _parseCallState(String? state) {
    switch (state) {
      case 'none':
        return AcsCallState.none;
      case 'connecting':
        return AcsCallState.connecting;
      case 'ringing':
        return AcsCallState.ringing;
      case 'connected':
        return AcsCallState.connected;
      case 'localHold':
        return AcsCallState.localHold;
      case 'remoteHold':
        return AcsCallState.remoteHold;
      case 'disconnecting':
        return AcsCallState.disconnecting;
      case 'disconnected':
        return AcsCallState.disconnected;
      case 'inLobby':
        return AcsCallState.inLobby;
      default:
        return AcsCallState.unknown;
    }
  }
}

/// Event fired when the composite is dismissed
class AcsCompositeDismissedEvent {
  /// Optional error code if dismissed due to error
  final AcsUiErrorCode? errorCode;

  /// Reason for dismissal (if available)
  final String? reason;

  const AcsCompositeDismissedEvent({
    this.errorCode,
    this.reason,
  });

  factory AcsCompositeDismissedEvent.fromMap(Map<String, dynamic> map) {
    final code = map['errorCode'] as String?;
    return AcsCompositeDismissedEvent(
      errorCode: code != null ? AcsUiErrorEvent._parseErrorCode(code) : null,
      reason: map['reason'] as String?,
    );
  }
}

/// Event fired when remote participants change
class AcsRemoteParticipantJoinedEvent {
  /// Number of participants who joined
  final int participantCount;

  /// List of participant identifiers
  final List<String> participantIds;

  const AcsRemoteParticipantJoinedEvent({
    required this.participantCount,
    required this.participantIds,
  });

  factory AcsRemoteParticipantJoinedEvent.fromMap(Map<String, dynamic> map) {
    return AcsRemoteParticipantJoinedEvent(
      participantCount: map['participantCount'] as int? ?? 0,
      participantIds: (map['participantIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

/// Callback type definitions
typedef AcsUiErrorHandler = void Function(AcsUiErrorEvent event);
typedef AcsCallStateChangedHandler = void Function(
    AcsCallStateChangedEvent event);
typedef AcsCompositeDismissedHandler = void Function(
    AcsCompositeDismissedEvent event);
typedef AcsRemoteParticipantJoinedHandler = void Function(
    AcsRemoteParticipantJoinedEvent event);

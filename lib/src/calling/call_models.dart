// Data models for Azure Communication Services calling operations.
//
// This file contains the core data classes used by [AcsCallClient].

/// Represents an active call
class Call {
  /// The unique identifier for the call
  final String id;

  /// The current state of the call
  final CallState state;

  /// Creates a new [Call] instance
  const Call({
    required this.id,
    required this.state,
  });

  /// Creates a [Call] from a map
  factory Call.fromMap(Map<String, dynamic> map) {
    return Call(
      id: map['id'] as String,
      state: CallState.values.firstWhere(
        (e) => e.toString() == 'CallState.${map['state']}',
        orElse: () => CallState.disconnected,
      ),
    );
  }

  /// Converts this [Call] to a map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'state': state.toString().split('.').last,
    };
  }

  @override
  String toString() => 'Call(id: $id, state: $state)';
}

/// Represents the state of a call
enum CallState {
  /// Call has no active state yet.
  none,

  /// Call is in early media state
  earlyMedia,

  /// Call is being connected
  connecting,

  /// Call is connected and active
  connected,

  /// Call is on hold
  onHold,

  /// Call is on hold by remote
  remoteHold,

  /// Call is disconnecting
  disconnecting,

  /// Call is disconnected
  disconnected,

  /// Call is ringing
  ringing,

  /// Call is waiting in lobby
  inLobby,
}

/// Exception thrown by calling operations
class AcsCallingException implements Exception {
  /// Error code
  final String code;

  /// Error message
  final String message;

  /// Additional error details
  final dynamic details;

  /// Creates a new [AcsCallingException]
  const AcsCallingException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() =>
      'AcsCallingException($code): $message${details != null ? ' - $details' : ''}';
}

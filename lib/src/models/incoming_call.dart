/// Details about an incoming call.
class IncomingCallInfo {
  final String id;
  final String? callerId;
  final String? displayName;
  final bool hasVideo;

  const IncomingCallInfo({
    required this.id,
    this.callerId,
    this.displayName,
    this.hasVideo = false,
  });

  factory IncomingCallInfo.fromMap(Map<String, dynamic> map) {
    return IncomingCallInfo(
      id: map['id']?.toString() ?? '',
      callerId: map['callerId']?.toString(),
      displayName: map['displayName']?.toString(),
      hasVideo: map['hasVideo'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        if (callerId != null) 'callerId': callerId,
        if (displayName != null) 'displayName': displayName,
        'hasVideo': hasVideo,
      };
}

/// Incoming call event types.
enum IncomingCallEventType {
  incoming,
  ended,
}

/// Event emitted for incoming call lifecycle changes.
class IncomingCallEvent {
  final IncomingCallEventType type;
  final IncomingCallInfo? call;

  const IncomingCallEvent({
    required this.type,
    this.call,
  });

  factory IncomingCallEvent.fromMap(Map<String, dynamic> map) {
    final type = IncomingCallEventType.values.firstWhere(
      (e) => e.toString() == 'IncomingCallEventType.${map['type']}',
      orElse: () => IncomingCallEventType.incoming,
    );
    final callMap = map['call'] as Map<String, dynamic>?;
    return IncomingCallEvent(
      type: type,
      call: callMap != null ? IncomingCallInfo.fromMap(callMap) : null,
    );
  }
}

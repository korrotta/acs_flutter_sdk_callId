/// Describes a capability and whether it is currently allowed.
class ParticipantCapability {
  final String type;
  final bool isAllowed;
  final String? reason;

  const ParticipantCapability({
    required this.type,
    required this.isAllowed,
    this.reason,
  });

  factory ParticipantCapability.fromMap(Map<String, dynamic> map) {
    return ParticipantCapability(
      type: map['type']?.toString() ?? 'unknown',
      isAllowed: map['isAllowed'] == true,
      reason: map['reason']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        'isAllowed': isAllowed,
        if (reason != null) 'reason': reason,
      };
}

/// Event emitted when call capabilities change.
class CapabilitiesChangedEvent {
  final String? reason;
  final List<ParticipantCapability> changedCapabilities;

  const CapabilitiesChangedEvent({
    required this.changedCapabilities,
    this.reason,
  });

  factory CapabilitiesChangedEvent.fromMap(Map<String, dynamic> map) {
    final list = (map['changedCapabilities'] as List<dynamic>? ?? [])
        .map((e) => ParticipantCapability.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    return CapabilitiesChangedEvent(
      reason: map['reason']?.toString(),
      changedCapabilities: list,
    );
  }
}

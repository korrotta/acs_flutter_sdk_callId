/// Describes a remote video stream (camera or screen share).
class RemoteVideoInfo {
  final int id;
  final String type; // e.g. "video" or "screenshare"
  final bool isAvailable;

  const RemoteVideoInfo({
    required this.id,
    required this.type,
    required this.isAvailable,
  });

  factory RemoteVideoInfo.fromMap(Map<String, dynamic> map) {
    return RemoteVideoInfo(
      id: (map['id'] as num?)?.toInt() ?? 0,
      type: map['type']?.toString() ?? 'unknown',
      isAvailable: map['isAvailable'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'isAvailable': isAvailable,
      };

  /// Value equality so that re-emitted, content-identical stream descriptors are
  /// treated as equal. Without this, every native participant event produces new
  /// instances that defeat the call state's equality check, causing the video grid
  /// to rebuild (and re-create native renderers) on every event.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteVideoInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          isAvailable == other.isAvailable;

  @override
  int get hashCode => Object.hash(id, type, isAvailable);
}

/// Snapshot of a remote participant's state.
class RemoteParticipantState {
  final String id;
  final String displayName;
  final String state;
  final bool isMuted;
  final bool isSpeaking;
  final List<RemoteVideoInfo> videoStreams;

  /// Whether the participant's video tile has painted its first frame.
  ///
  /// A participant's stream can report `isAvailable` before any pixels reach the
  /// screen; the tile shows a connecting spinner in that window. This flag is
  /// raised once the native renderer signals first-frame for the participant,
  /// letting the UI clear the spinner only when real video is on screen. It is
  /// never sent down inside a participant snapshot (the native first-frame
  /// signal arrives as its own event); consumers fold it in via [copyWith].
  final bool isVideoRendering;

  const RemoteParticipantState({
    required this.id,
    required this.displayName,
    required this.state,
    required this.isMuted,
    required this.isSpeaking,
    required this.videoStreams,
    this.isVideoRendering = false,
  });

  factory RemoteParticipantState.fromMap(Map<String, dynamic> map) {
    final videos = (map['videoStreams'] as List<dynamic>? ?? [])
        .map((e) => RemoteVideoInfo.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    return RemoteParticipantState(
      id: map['id']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? '',
      state: map['state']?.toString() ?? 'unknown',
      isMuted: map['isMuted'] == true,
      isSpeaking: map['isSpeaking'] == true,
      videoStreams: videos,
      // The native snapshot may omit this; default false until first-frame.
      isVideoRendering: map['isVideoRendering'] == true,
    );
  }

  /// Returns a copy with the given fields replaced, preserving immutability.
  ///
  /// Used by consumers to fold the out-of-band first-frame signal into an
  /// existing snapshot (e.g. `copyWith(isVideoRendering: true)`) without
  /// mutating the original instance.
  RemoteParticipantState copyWith({
    String? id,
    String? displayName,
    String? state,
    bool? isMuted,
    bool? isSpeaking,
    List<RemoteVideoInfo>? videoStreams,
    bool? isVideoRendering,
  }) {
    return RemoteParticipantState(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      state: state ?? this.state,
      isMuted: isMuted ?? this.isMuted,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      videoStreams: videoStreams ?? this.videoStreams,
      isVideoRendering: isVideoRendering ?? this.isVideoRendering,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'displayName': displayName,
        'state': state,
        'isMuted': isMuted,
        'isSpeaking': isSpeaking,
        'videoStreams': videoStreams.map((e) => e.toMap()).toList(),
        'isVideoRendering': isVideoRendering,
      };

  /// Value equality (deep, including the video-stream list) so a re-emitted
  /// participant snapshot with unchanged content compares equal. This lets the
  /// call state's equality check dedup repeated participant/dominant-speaker
  /// events instead of rebuilding the video grid — and re-creating native video
  /// renderers — on every event. [RemoteVideoInfo] provides element equality.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RemoteParticipantState || runtimeType != other.runtimeType) {
      return false;
    }
    if (id != other.id ||
        displayName != other.displayName ||
        state != other.state ||
        isMuted != other.isMuted ||
        isSpeaking != other.isSpeaking ||
        isVideoRendering != other.isVideoRendering ||
        videoStreams.length != other.videoStreams.length) {
      return false;
    }
    for (var i = 0; i < videoStreams.length; i++) {
      if (videoStreams[i] != other.videoStreams[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        state,
        isMuted,
        isSpeaking,
        isVideoRendering,
        Object.hashAll(videoStreams),
      );
}

/// Event emitted from the native layer about participant changes.
///
/// Known [type] values:
/// - `participantAdded` / `participantRemoved` / `participantUpdated` — roster
///   lifecycle, carry a full [participant] snapshot (or [id] on removal).
/// - `participantVideoRendering` — the participant's video tile has painted its
///   first frame; carries only [id] (no [participant] snapshot). Consumers
///   should raise `isVideoRendering` for that participant to clear its spinner.
class RemoteParticipantEvent {
  final String type;
  final RemoteParticipantState? participant;
  final String? id;

  const RemoteParticipantEvent({
    required this.type,
    this.participant,
    this.id,
  });

  /// True when this event signals that the participant's renderer painted its
  /// first frame. For these events only [id] is populated; [participant] is
  /// null, so callers fold the signal into their existing snapshot via
  /// [RemoteParticipantState.copyWith].
  bool get isVideoRenderingEvent => type == 'participantVideoRendering';

  /// Parses a native participant event map.
  ///
  /// Unknown or missing [type] falls back to `'unknown'` and is ignored by
  /// consumers, so adding new native event types never breaks this decode path.
  /// [participant] is only built when a snapshot is present, so signal-only
  /// events such as `participantVideoRendering` parse with just [id].
  factory RemoteParticipantEvent.fromMap(Map<String, dynamic> map) {
    final participantRaw = map['participant'];
    final participantMap = participantRaw is Map
        ? Map<String, dynamic>.from(participantRaw)
        : null;
    return RemoteParticipantEvent(
      type: map['type']?.toString() ?? 'unknown',
      id: map['id']?.toString(),
      participant: participantMap != null
          ? RemoteParticipantState.fromMap(participantMap)
          : null,
    );
  }
}

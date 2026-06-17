import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/remote_participant.dart';
import '../models/device_info.dart';
import '../models/capabilities.dart';
import '../models/incoming_call.dart';
import '../models/call_features.dart';
import 'call_models.dart';

/// Client for managing Azure Communication Services calling operations
///
/// This client provides methods for making and receiving voice and video calls.
class AcsCallClient {
  final MethodChannel _channel;
  final StreamController<CallState> _callStateController =
      StreamController<CallState>.broadcast();
  final EventChannel _eventChannel =
      const EventChannel('acs_flutter_sdk/events');
  final EventChannel _capabilitiesChannel =
      const EventChannel('acs_flutter_sdk/capabilities');
  final EventChannel _incomingCallChannel =
      const EventChannel('acs_flutter_sdk/incoming_calls');
  final EventChannel _callFeaturesChannel =
      const EventChannel('acs_flutter_sdk/call_features');
  final EventChannel _captionsChannel =
      const EventChannel('acs_flutter_sdk/captions');
  final EventChannel _realTimeTextChannel =
      const EventChannel('acs_flutter_sdk/real_time_text');
  final EventChannel _dataChannelChannel =
      const EventChannel('acs_flutter_sdk/data_channel');
  final EventChannel _mediaStatisticsChannel =
      const EventChannel('acs_flutter_sdk/media_statistics');
  final EventChannel _diagnosticsChannel =
      const EventChannel('acs_flutter_sdk/diagnostics');

  // Event streams initialized eagerly to avoid race conditions
  late final Stream<RemoteParticipantEvent> _participantEventStream;
  late final Stream<CapabilitiesChangedEvent> _capabilitiesEventStream;
  late final Stream<IncomingCallEvent> _incomingCallEventStream;
  late final Stream<CallFeatureEvent> _callFeatureEventStream;
  late final Stream<CaptionsEvent> _captionsEventStream;
  late final Stream<RealTimeTextEvent> _realTimeTextEventStream;
  late final Stream<DataChannelEvent> _dataChannelEventStream;
  late final Stream<MediaStatisticsEvent> _mediaStatisticsEventStream;
  late final Stream<DiagnosticsEvent> _diagnosticsEventStream;

  /// Creates a new [AcsCallClient] instance
  ///
  /// [channel] is the method channel for communicating with native code
  AcsCallClient(this._channel) {
    _channel.setMethodCallHandler(_handleNativeCallback);
    _initEventStreams();
  }

  void _initEventStreams() {
    _participantEventStream = _safeEventStream(
      _eventChannel,
      'participants',
      (event) => RemoteParticipantEvent.fromMap(
        Map<String, dynamic>.from(event as Map),
      ),
    );
    _capabilitiesEventStream = _safeEventStream(
      _capabilitiesChannel,
      'capabilities',
      (event) => CapabilitiesChangedEvent.fromMap(
        Map<String, dynamic>.from(event as Map),
      ),
    );
    _incomingCallEventStream = _safeEventStream(
      _incomingCallChannel,
      'incoming_calls',
      (event) => IncomingCallEvent.fromMap(
        Map<String, dynamic>.from(event as Map),
      ),
    );
    _callFeatureEventStream = _safeEventStream(
      _callFeaturesChannel,
      'call_features',
      (event) => CallFeatureEvent.fromMap(
        Map<String, dynamic>.from(event as Map),
      ),
    );
    _captionsEventStream = _safeEventStream(
      _captionsChannel,
      'captions',
      (event) => CaptionsEvent.fromMap(
        Map<String, dynamic>.from(event as Map),
      ),
    );
    _realTimeTextEventStream = _safeEventStream(
      _realTimeTextChannel,
      'real_time_text',
      (event) => RealTimeTextEvent.fromMap(
        Map<String, dynamic>.from(event as Map),
      ),
    );
    _dataChannelEventStream = _safeEventStream(
      _dataChannelChannel,
      'data_channel',
      (event) => DataChannelEvent.fromMap(
        Map<String, dynamic>.from(event as Map),
      ),
    );
    _mediaStatisticsEventStream = _safeEventStream(
      _mediaStatisticsChannel,
      'media_statistics',
      (event) => MediaStatisticsEvent.fromMap(
        Map<String, dynamic>.from(event as Map),
      ),
    );
    _diagnosticsEventStream = _safeEventStream(
      _diagnosticsChannel,
      'diagnostics',
      (event) => DiagnosticsEvent.fromMap(
        Map<String, dynamic>.from(event as Map),
      ),
    );
  }

  void _logError(String context, Object error, [StackTrace? stackTrace]) {
    // Only log in debug mode to avoid pub.dev analyzer warnings
    assert(() {
      final details = stackTrace != null ? '\n$stackTrace' : '';
      debugPrint('[ACS][Dart][$context] $error$details');
      return true;
    }());
  }

  /// Helper for invoking method channel calls with consistent error handling.
  ///
  /// Wraps [PlatformException] into [AcsCallingException] with the provided
  /// [errorMessage] as a fallback.
  Future<T?> _invokeMethod<T>(String method,
      [Map<String, dynamic>? args, String? errorMessage]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? errorMessage ?? 'Failed to $method',
        details: e.details,
      );
    }
  }

  Stream<T> _safeEventStream<T>(
    EventChannel channel,
    String name,
    T Function(dynamic event) mapper,
  ) {
    return channel
        .receiveBroadcastStream()
        .map((event) {
          try {
            return mapper(event);
          } catch (e, st) {
            _logError('eventStream:$name', e, st);
            return null;
          }
        })
        .where((value) => value != null)
        .map((value) => value as T)
        .handleError((error, stackTrace) {
          _logError('eventStream:$name', error, stackTrace);
        });
  }

  /// Stream of call state changes
  Stream<CallState> get callStateStream => _callStateController.stream;

  /// Stream of participant events (added/removed/updated) from the native layer.
  Stream<RemoteParticipantEvent> get participantEvents =>
      _participantEventStream;

  /// Stream of capability change events for the active call.
  Stream<CapabilitiesChangedEvent> get capabilitiesChangedStream =>
      _capabilitiesEventStream;

  /// Stream of incoming call lifecycle events.
  Stream<IncomingCallEvent> get incomingCallStream => _incomingCallEventStream;

  /// Stream of call feature events (recording, transcription, dominant speakers, raise hand, spotlight).
  Stream<CallFeatureEvent> get callFeatureEvents => _callFeatureEventStream;

  /// Stream of captions events (state changes and caption text).
  Stream<CaptionsEvent> get captionsEvents => _captionsEventStream;

  /// Stream of real-time text (RTT) events.
  Stream<RealTimeTextEvent> get realTimeTextEvents => _realTimeTextEventStream;

  /// Stream of data channel events.
  Stream<DataChannelEvent> get dataChannelEvents => _dataChannelEventStream;

  /// Stream of media statistics reports.
  Stream<MediaStatisticsEvent> get mediaStatisticsEvents =>
      _mediaStatisticsEventStream;

  /// Stream of diagnostics change events.
  Stream<DiagnosticsEvent> get diagnosticsEvents => _diagnosticsEventStream;

  Future<void> _handleNativeCallback(MethodCall call) async {
    try {
      switch (call.method) {
        case 'callStateChanged':
          final args = call.arguments is Map ? call.arguments as Map : const {};
          final state = CallState.values.firstWhere(
            (e) => e.toString() == 'CallState.${args['state']}',
            orElse: () => CallState.disconnected,
          );
          _callStateController.add(state);
          break;
        default:
          break;
      }
    } catch (e, st) {
      _logError('nativeCallback:${call.method}', e, st);
    }
  }

  /// Requests microphone and camera permissions on the host platform.
  Future<void> requestPermissions() async {
    await _invokeMethod<void>(
        'requestPermissions', null, 'Failed to request permissions');
  }

  /// Initializes the calling client with an access token
  ///
  /// [accessToken] is the Azure Communication Services access token
  ///
  /// Throws an [AcsCallingException] if initialization fails
  Future<void> initialize(String accessToken,
      {String? displayName,
      bool disableInternalPushForIncomingCall = false}) async {
    try {
      await _channel.invokeMethod('initializeCalling', {
        'accessToken': accessToken,
        if (displayName != null) 'displayName': displayName,
        'disableInternalPushForIncomingCall':
            disableInternalPushForIncomingCall,
      });
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to initialize calling client',
        details: e.details,
      );
    }
  }

  /// Adds one or more participants to the active call.
  Future<void> addParticipants(List<String> participants) =>
      _invokeMethod<void>('addParticipants', {'participants': participants});

  /// Removes one or more participants from the active call.
  Future<void> removeParticipants(List<String> participants) =>
      _invokeMethod<void>('removeParticipants', {'participants': participants});

  /// Starts a new call to the specified participants
  ///
  /// [participants] is a list of user IDs to call
  /// [withVideo] indicates whether to start with video enabled
  ///
  /// Returns a [Call] object representing the active call
  ///
  /// Throws an [AcsCallingException] if the call fails to start
  Future<Call> startCall(List<String> participants,
      {bool withVideo = false}) async {
    try {
      final result = await _channel.invokeMethod('startCall', {
        'participants': participants,
        'withVideo': withVideo,
      });
      return Call.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to start call',
        details: e.details,
      );
    }
  }

  /// Joins an existing call using a group call ID
  ///
  /// [groupCallId] is the ID of the group call to join
  /// [withVideo] indicates whether to join with video enabled
  ///
  /// Returns a [Call] object representing the active call
  ///
  /// Throws an [AcsCallingException] if joining fails
  Future<Call> joinCall(String groupCallId, {bool withVideo = false}) async {
    try {
      final result = await _channel.invokeMethod('joinCall', {
        'groupCallId': groupCallId,
        'withVideo': withVideo,
      });
      return Call.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to join call',
        details: e.details,
      );
    }
  }

  /// Joins a Teams meeting using the full meeting link.
  ///
  /// [withVideo] starts the local camera as part of the join.
  ///
  /// [noiseSuppressionMode] optionally applies an outgoing-audio noise
  /// suppression filter at join time. Accepted values: `off`, `auto`, `low`,
  /// `high` (case-insensitive). When set, acoustic echo cancellation is also
  /// enabled alongside it. `null` (default) keeps the platform SDK defaults.
  /// Unknown values are ignored by the native layer (defaults preserved).
  Future<Call> joinTeamsMeeting(String meetingLink,
      {bool withVideo = false, String? noiseSuppressionMode}) async {
    try {
      final result = await _channel.invokeMethod('joinTeamsMeeting', {
        'meetingLink': meetingLink,
        'withVideo': withVideo,
        // Only sent when requested so older native code paths keep receiving
        // the exact payload they did before this option existed. Lower-cased
        // here so the documented case-insensitivity is guaranteed Dart-side
        // regardless of native matching.
        if (noiseSuppressionMode != null)
          'noiseSuppressionMode': noiseSuppressionMode.toLowerCase(),
      });
      return Call.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to join Teams meeting',
        details: e.details,
      );
    }
  }

  /// Ends the current call
  ///
  /// Throws an [AcsCallingException] if ending the call fails
  Future<void> endCall() => _invokeMethod<void>('endCall');

  /// Mutes the local audio
  ///
  /// Throws an [AcsCallingException] if muting fails
  Future<void> muteAudio() => _invokeMethod<void>('muteAudio');

  /// Unmutes the local audio
  ///
  /// Throws an [AcsCallingException] if unmuting fails
  Future<void> unmuteAudio() => _invokeMethod<void>('unmuteAudio');

  /// Starts the local video
  ///
  /// Throws an [AcsCallingException] if starting video fails.
  Future<void> startVideo() => _invokeMethod<void>('startVideo');

  /// Stops the local video
  ///
  /// Throws an [AcsCallingException] if stopping video fails.
  Future<void> stopVideo() => _invokeMethod<void>('stopVideo');

  /// Returns true if the current call is waiting in the lobby.
  Future<bool> isInLobby() async {
    try {
      final result = await _channel.invokeMethod('isInLobby');
      return result == true;
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to check lobby state',
        details: e.details,
      );
    }
  }

  /// Returns the raw IDs of remote participants in the active call.
  Future<List<String>> getRemoteParticipants() async {
    try {
      final result = await _channel.invokeMethod('getRemoteParticipants');
      return (result as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to get remote participants',
        details: e.details,
      );
    }
  }

  /// Returns rich state for all remote participants (id, displayName, mute/speaking/video state).
  Future<List<RemoteParticipantState>> getRemoteParticipantStates() async {
    try {
      final result = await _channel.invokeMethod('getRemoteParticipantStates');
      final list = (result as List<dynamic>? ?? [])
          .map((e) =>
              RemoteParticipantState.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      return list;
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to get remote participant states',
        details: e.details,
      );
    }
  }

  /// Returns the current capabilities for the local participant.
  Future<List<ParticipantCapability>> getCapabilities() async {
    try {
      final result = await _channel.invokeMethod('getCapabilities');
      return (result as List<dynamic>? ?? [])
          .map((e) =>
              ParticipantCapability.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to get capabilities',
        details: e.details,
      );
    }
  }

  /// Accepts the current incoming call (if any).
  Future<void> acceptIncomingCall({bool withVideo = false}) =>
      _invokeMethod<void>('acceptIncomingCall', {'withVideo': withVideo});

  /// Rejects the current incoming call (if any).
  Future<void> rejectIncomingCall() =>
      _invokeMethod<void>('rejectIncomingCall');

  /// Registers the device token for incoming call push notifications.
  Future<void> registerPushNotifications(String token) =>
      _invokeMethod<void>('registerPushNotifications', {'token': token});

  /// Unregisters the device token from incoming call push notifications.
  Future<void> unregisterPushNotifications() =>
      _invokeMethod<void>('unregisterPushNotifications');

  /// Handles a push notification payload to surface an incoming call.
  Future<void> handlePushNotification(Map<String, dynamic> payload) =>
      _invokeMethod<void>('handlePushNotification', {'payload': payload});

  /// Switches the active camera source when local video is enabled.
  Future<void> switchCamera() => _invokeMethod<void>('switchCamera');

  /// Disposes of this client and releases all resources.
  ///
  /// This should be called when the client is no longer needed to prevent memory leaks.
  /// After calling dispose(), the client should not be used again.
  void dispose() {
    _callStateController.close();
    _channel.setMethodCallHandler(null);
  }

  /// Starts live captions (if available in the current call).
  Future<void> startCaptions({String? spokenLanguage}) => _invokeMethod<void>(
      'startCaptions',
      spokenLanguage != null ? {'spokenLanguage': spokenLanguage} : null);

  /// Stops live captions.
  Future<void> stopCaptions() => _invokeMethod<void>('stopCaptions');

  /// Sets the spoken language for captions.
  Future<void> setSpokenLanguage(String language) =>
      _invokeMethod<void>('setSpokenLanguage', {'language': language});

  /// Sets the caption language (Teams captions).
  Future<void> setCaptionLanguage(String language) =>
      _invokeMethod<void>('setCaptionLanguage', {'language': language});

  /// Returns whether server-side recording is active.
  Future<bool> isRecordingActive() async {
    try {
      final result = await _channel.invokeMethod('isRecordingActive');
      return result == true;
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to query recording state',
        details: e.details,
      );
    }
  }

  /// Returns whether transcription is active.
  Future<bool> isTranscriptionActive() async {
    try {
      final result = await _channel.invokeMethod('isTranscriptionActive');
      return result == true;
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to query transcription state',
        details: e.details,
      );
    }
  }

  /// Gets the current dominant speaker identifiers.
  Future<List<String>> getDominantSpeakers() async {
    try {
      final result = await _channel.invokeMethod('getDominantSpeakers');
      return (result as List<dynamic>).cast<String>();
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to get dominant speakers',
        details: e.details,
      );
    }
  }

  /// Raises the local user's hand in the call.
  Future<void> raiseHand() => _invokeMethod<void>('raiseHand');

  /// Lowers the local user's hand in the call.
  Future<void> lowerHand() => _invokeMethod<void>('lowerHand');

  /// Lowers all raised hands in the call (requires permission).
  Future<void> lowerAllHands() => _invokeMethod<void>('lowerAllHands');

  /// Lowers hands for specific participants.
  Future<void> lowerHands(List<String> identifiers) =>
      _invokeMethod<void>('lowerHands', {'identifiers': identifiers});

  /// Gets the list of raised hands with order.
  Future<List<RaisedHandInfo>> getRaisedHands() async {
    try {
      final result = await _channel.invokeMethod('getRaisedHands');
      return (result as List<dynamic>)
          .map((e) => RaisedHandInfo.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to get raised hands',
        details: e.details,
      );
    }
  }

  /// Gets the maximum number of spotlighted participants supported.
  Future<int> getMaxSpotlightedParticipants() async {
    try {
      final result =
          await _channel.invokeMethod('getMaxSpotlightedParticipants');
      return result as int? ?? 0;
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to get max spotlighted participants',
        details: e.details,
      );
    }
  }

  /// Gets the currently spotlighted participant identifiers.
  Future<List<String>> getSpotlightedParticipants() async {
    try {
      final result = await _channel.invokeMethod('getSpotlightedParticipants');
      return (result as List<dynamic>).cast<String>();
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to get spotlighted participants',
        details: e.details,
      );
    }
  }

  /// Spotlights the specified participants.
  Future<void> spotlightParticipants(List<String> identifiers) =>
      _invokeMethod<void>(
          'spotlightParticipants', {'identifiers': identifiers});

  /// Cancels spotlight for specified participants.
  Future<void> cancelSpotlights(List<String> identifiers) =>
      _invokeMethod<void>('cancelSpotlights', {'identifiers': identifiers});

  /// Cancels spotlight for all participants.
  Future<void> cancelAllSpotlights() =>
      _invokeMethod<void>('cancelAllSpotlights');

  /// Sends a real-time text (RTT) message.
  Future<void> sendRealTimeText(String text, {bool finalized = true}) =>
      _invokeMethod<void>(
          'sendRealTimeText', {'text': text, 'finalized': finalized});

  /// Fetches the current captions state.
  Future<CaptionsState> getCaptionsState() async {
    try {
      final result = await _channel.invokeMethod('getCaptionsState');
      return CaptionsState.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to get captions state',
        details: e.details,
      );
    }
  }

  /// Updates the media statistics report interval (in seconds).
  Future<void> setMediaStatisticsReportInterval(int seconds) =>
      _invokeMethod<void>('setMediaStatisticsReportInterval',
          {'reportIntervalInSeconds': seconds});

  /// Gets the current media statistics report interval (in seconds).
  Future<int> getMediaStatisticsReportInterval() async {
    try {
      final result =
          await _channel.invokeMethod('getMediaStatisticsReportInterval');
      return result as int? ?? 0;
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to get media statistics interval',
        details: e.details,
      );
    }
  }

  /// Fetches the latest local diagnostics snapshot.
  Future<Map<String, dynamic>> getLatestDiagnostics() async {
    try {
      final result = await _channel.invokeMethod('getLatestDiagnostics');
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to get diagnostics',
        details: e.details,
      );
    }
  }

  /// Creates a data channel sender for sending custom payloads.
  /// [priority] supports `normal` or `high`.
  /// [reliability] supports `lossy` or `durable`.
  Future<DataChannelSenderInfo> createDataChannelSender({
    int? channelId,
    int? bitrateInKbps,
    String priority = 'normal',
    String reliability = 'lossy',
    List<String>? participants,
  }) async {
    try {
      final result = await _channel.invokeMethod('createDataChannelSender', {
        if (channelId != null) 'channelId': channelId,
        if (bitrateInKbps != null) 'bitrateInKbps': bitrateInKbps,
        'priority': priority,
        'reliability': reliability,
        if (participants != null) 'participants': participants,
      });
      return DataChannelSenderInfo.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to create data channel sender',
        details: e.details,
      );
    }
  }

  /// Sends a data channel payload.
  Future<void> sendDataChannelMessage(int channelId, Uint8List data) =>
      _invokeMethod<void>(
          'sendDataChannelMessage', {'channelId': channelId, 'data': data});

  /// Updates the participant list for a data channel sender.
  Future<void> setDataChannelParticipants(
          int channelId, List<String> participants) =>
      _invokeMethod<void>('setDataChannelParticipants', {
        'channelId': channelId,
        'participants': participants,
      });

  /// Closes a data channel sender.
  Future<void> closeDataChannelSender(int channelId) =>
      _invokeMethod<void>('closeDataChannelSender', {'channelId': channelId});

  /// Starts a call survey and returns a handle to populate before submitting.
  Future<CallSurveyHandle> startSurvey() async {
    try {
      final result = await _channel.invokeMethod('startSurvey');
      return CallSurveyHandle.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to start survey',
        details: e.details,
      );
    }
  }

  /// Submits a call survey.
  Future<CallSurveyResult> submitSurvey(CallSurveySubmission submission) async {
    try {
      final result =
          await _channel.invokeMethod('submitSurvey', submission.toMap());
      return CallSurveyResult.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to submit survey',
        details: e.details,
      );
    }
  }

  /// Discards a pending call survey without submitting.
  Future<void> discardSurvey(CallSurveyHandle handle) =>
      _invokeMethod<void>('discardSurvey', {'handle': handle.handle});

  /// Enables background blur on the local video (device support required).
  Future<void> enableBackgroundBlur() =>
      _invokeMethod<void>('enableBackgroundBlur');

  /// Enables background replacement on the local video using the provided image buffer.
  Future<void> enableBackgroundReplacement(Uint8List buffer) =>
      _invokeMethod<void>('enableBackgroundReplacement', {'buffer': buffer});

  /// Disables any active local video effects.
  Future<void> disableVideoEffects() =>
      _invokeMethod<void>('disableVideoEffects');

  /// Mutes the speaker (incoming audio).
  Future<void> muteIncomingAudio() => _invokeMethod<void>('muteIncomingAudio');

  /// Unmutes the speaker (incoming audio).
  Future<void> unmuteIncomingAudio() =>
      _invokeMethod<void>('unmuteIncomingAudio');

  /// Mutes all remote participants (if permitted by service policy).
  Future<void> muteAllRemoteParticipants() =>
      _invokeMethod<void>('muteAllRemoteParticipants');

  /// Admit the specified identifiers from the lobby.
  Future<void> admitLobbyParticipants(List<String> identifiers) =>
      _invokeMethod<void>(
          'admitLobbyParticipants', {'identifiers': identifiers});

  /// Admit all participants from lobby.
  Future<void> admitAllFromLobby() => _invokeMethod<void>('admitAllFromLobby');

  /// Reject a participant from lobby.
  Future<void> rejectLobbyParticipant(String identifier) =>
      _invokeMethod<void>('rejectLobbyParticipant', {'identifier': identifier});

  /// Get the current lobby participants (identifiers).
  Future<List<String>> getLobbyParticipants() async {
    try {
      final result = await _channel.invokeMethod('getLobbyParticipants');
      return (result as List<dynamic>).cast<String>();
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to fetch lobby participants',
        details: e.details,
      );
    }
  }

  /// Puts the active call on hold.
  Future<void> holdCall() => _invokeMethod<void>('holdCall');

  /// Resumes a call that is on hold.
  Future<void> resumeCall() => _invokeMethod<void>('resumeCall');

  /// Transfers the active call to the target raw identifier.
  Future<void> transferCall(String targetRawId) =>
      _invokeMethod<void>('transferCall', {'target': targetRawId});

  /// Starts local screen sharing if supported on the current platform/SDK version.
  Future<void> startScreenShare() => _invokeMethod<void>('startScreenShare');

  /// Stops local screen sharing.
  Future<void> stopScreenShare() => _invokeMethod<void>('stopScreenShare');

  /// Lists available cameras on the device.
  Future<List<DeviceInfo>> listCameras() async {
    try {
      final result = await _channel.invokeMethod('listCameras');
      return (result as List<dynamic>? ?? [])
          .map((e) => DeviceInfo.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to list cameras',
        details: e.details,
      );
    }
  }

  /// Selects a camera by identifier (if supported).
  Future<void> setCamera(String cameraId) =>
      _invokeMethod<void>('setCamera', {'id': cameraId});

  /// Returns true if any remote participant currently has an incoming video stream.
  Future<bool> hasRemoteVideo() async {
    try {
      final result = await _channel.invokeMethod('hasRemoteVideo');
      return result == true;
    } on PlatformException catch (e) {
      throw AcsCallingException(
        code: e.code,
        message: e.message ?? 'Failed to check remote video availability',
        details: e.details,
      );
    }
  }
}

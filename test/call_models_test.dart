import 'dart:typed_data';
import 'package:acs_flutter_sdk/acs_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Call', () {
    test('creates instance with id and state', () {
      const call = Call(id: 'call-123', state: CallState.connected);
      expect(call.id, 'call-123');
      expect(call.state, CallState.connected);
    });

    test('fromMap creates instance from map', () {
      final call = Call.fromMap({'id': 'call-456', 'state': 'ringing'});
      expect(call.id, 'call-456');
      expect(call.state, CallState.ringing);
    });

    test('fromMap handles unknown state as disconnected', () {
      final call = Call.fromMap({'id': 'call-789', 'state': 'unknownState'});
      expect(call.id, 'call-789');
      expect(call.state, CallState.disconnected);
    });

    test('toMap converts to map', () {
      const call = Call(id: 'call-123', state: CallState.connecting);
      final map = call.toMap();
      expect(map['id'], 'call-123');
      expect(map['state'], 'connecting');
    });

    test('toString includes id and state', () {
      const call = Call(id: 'call-123', state: CallState.connected);
      expect(call.toString(), contains('call-123'));
      expect(call.toString(), contains('connected'));
    });
  });

  group('CallState', () {
    test('has all expected values', () {
      expect(
          CallState.values,
          containsAll([
            CallState.none,
            CallState.earlyMedia,
            CallState.connecting,
            CallState.connected,
            CallState.onHold,
            CallState.remoteHold,
            CallState.disconnecting,
            CallState.disconnected,
            CallState.ringing,
            CallState.inLobby,
          ]));
    });
  });

  group('AcsCallingException', () {
    test('creates exception with code and message', () {
      const exception = AcsCallingException(
        code: 'CALL_ERROR',
        message: 'Call failed',
      );
      expect(exception.code, 'CALL_ERROR');
      expect(exception.message, 'Call failed');
      expect(exception.details, isNull);
    });

    test('creates exception with details', () {
      const exception = AcsCallingException(
        code: 'CALL_ERROR',
        message: 'Call failed',
        details: {'reason': 'network'},
      );
      expect(exception.details, {'reason': 'network'});
    });

    test('toString includes code and message', () {
      const exception = AcsCallingException(
        code: 'ERROR_CODE',
        message: 'Error message',
      );
      expect(exception.toString(), contains('ERROR_CODE'));
      expect(exception.toString(), contains('Error message'));
    });

    test('toString includes details when present', () {
      const exception = AcsCallingException(
        code: 'ERROR',
        message: 'Failed',
        details: 'extra info',
      );
      expect(exception.toString(), contains('extra info'));
    });
  });

  group('CallFeatureEvent', () {
    test('fromMap creates instance with type', () {
      final event = CallFeatureEvent.fromMap({
        'type': 'recordingStateChanged',
        'isActive': true,
      });
      expect(event.type, 'recordingStateChanged');
      expect(event.isActive, true);
    });

    test('speakers returns empty list when not present', () {
      final event = CallFeatureEvent.fromMap({'type': 'test'});
      expect(event.speakers, isEmpty);
    });

    test('speakers returns list when present', () {
      final event = CallFeatureEvent.fromMap({
        'type': 'dominantSpeakersChanged',
        'speakers': ['user-1', 'user-2'],
      });
      expect(event.speakers, ['user-1', 'user-2']);
    });

    test('raisedHands parses raised hand info list', () {
      final event = CallFeatureEvent.fromMap({
        'type': 'raiseHandChanged',
        'raisedHands': [
          {'identifier': 'user-1', 'order': 1},
          {'identifier': 'user-2', 'order': 2},
        ],
      });
      expect(event.raisedHands, hasLength(2));
      expect(event.raisedHands[0].identifier, 'user-1');
      expect(event.raisedHands[0].order, 1);
    });

    test('spotlightedParticipants returns list when present', () {
      final event = CallFeatureEvent.fromMap({
        'type': 'spotlightChanged',
        'spotlightedParticipants': ['user-1'],
      });
      expect(event.spotlightedParticipants, ['user-1']);
    });
  });

  group('CaptionsEvent', () {
    test('fromMap creates instance with typed properties', () {
      final event = CaptionsEvent.fromMap({
        'type': 'captionsReceived',
        'spokenText': 'Hello world',
        'captionText': 'Hola mundo',
        'speakerRawId': 'user-123',
        'speakerName': 'John Doe',
        'resultType': 'final',
      });
      expect(event.type, 'captionsReceived');
      expect(event.spokenText, 'Hello world');
      expect(event.captionText, 'Hola mundo');
      expect(event.speakerRawId, 'user-123');
      expect(event.speakerName, 'John Doe');
      expect(event.resultType, 'final');
    });

    test('isActive returns boolean when present', () {
      final event = CaptionsEvent.fromMap({
        'type': 'captionsActiveChanged',
        'isActive': true,
      });
      expect(event.isActive, true);
    });

    test('nullable properties return null when not present', () {
      final event = CaptionsEvent.fromMap({'type': 'test'});
      expect(event.spokenText, isNull);
      expect(event.captionText, isNull);
      expect(event.speakerRawId, isNull);
    });
  });

  group('RealTimeTextEvent', () {
    test('fromMap creates instance with typed properties', () {
      final event = RealTimeTextEvent.fromMap({
        'type': 'messageReceived',
        'text': 'Hello',
        'senderRawId': 'user-1',
        'senderName': 'Alice',
        'sequenceId': 42,
        'isFinalized': true,
      });
      expect(event.text, 'Hello');
      expect(event.senderRawId, 'user-1');
      expect(event.senderName, 'Alice');
      expect(event.sequenceId, 42);
      expect(event.isFinalized, true);
    });
  });

  group('DataChannelEvent', () {
    test('fromMap creates instance', () {
      final event = DataChannelEvent.fromMap({
        'type': 'messageReceived',
        'channelId': 1,
        'senderRawId': 'user-1',
      });
      expect(event.type, 'messageReceived');
      expect(event.channelId, 1);
      expect(event.senderRawId, 'user-1');
    });

    test('payload handles Uint8List', () {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final event = DataChannelEvent.fromMap({
        'type': 'messageReceived',
        'data': data,
      });
      expect(event.payload, data);
    });

    test('payload handles List<int>', () {
      final event = DataChannelEvent.fromMap({
        'type': 'messageReceived',
        'data': [1, 2, 3],
      });
      expect(event.payload, isA<Uint8List>());
      expect(event.payload, [1, 2, 3]);
    });

    test('payload returns null when not present', () {
      final event = DataChannelEvent.fromMap({'type': 'test'});
      expect(event.payload, isNull);
    });
  });

  group('MediaStatisticsEvent', () {
    test('fromMap creates instance with report structure', () {
      // iOS SDK sends data wrapped in "report" key
      final event = MediaStatisticsEvent.fromMap({
        'type': 'mediaStatisticsReport',
        'report': {
          'lastUpdated': 1234567890,
          'outgoing': {
            'audio': [
              {'codecName': 'opus', 'bitrateInBps': 32000},
            ],
          },
        },
      });
      expect(event.type, 'mediaStatisticsReport');
      expect(event.timestamp, 1234567890);
      expect(event.outgoingAudio?['codecName'], 'opus');
      expect(event.outgoingAudio?['bitrateInBps'], 32000);
    });

    test('incomingVideo returns empty list when not present', () {
      final event = MediaStatisticsEvent.fromMap({'type': 'test'});
      expect(event.incomingVideo, isEmpty);
    });
  });

  group('DiagnosticsEvent', () {
    test('fromMap creates instance with typed properties', () {
      final event = DiagnosticsEvent.fromMap({
        'type': 'diagnosticChanged',
        'diagnostic': 'networkUnavailable',
        'value': true,
        'isFlagDiagnostic': true,
      });
      expect(event.type, 'diagnosticChanged');
      expect(event.diagnostic, 'networkUnavailable');
      expect(event.valueBool, true);
      expect(event.isFlagDiagnostic, true);
    });

    test('valueQuality returns quality string', () {
      final event = DiagnosticsEvent.fromMap({
        'type': 'diagnosticChanged',
        'diagnostic': 'networkReconnectionQuality',
        'valueQuality': 'poor',
        'isFlagDiagnostic': false,
      });
      expect(event.valueQuality, 'poor');
      expect(event.isFlagDiagnostic, false);
    });
  });

  group('CaptionsState', () {
    test('fromMap creates instance with all fields', () {
      final state = CaptionsState.fromMap({
        'available': true,
        'isEnabled': true,
        'type': 'teamsCaptions',
        'activeSpokenLanguage': 'en-US',
        'activeCaptionLanguage': 'es',
        'supportedSpokenLanguages': ['en-US', 'es-ES'],
        'supportedCaptionLanguages': ['en', 'es', 'fr'],
      });
      expect(state.available, true);
      expect(state.isEnabled, true);
      expect(state.type, 'teamsCaptions');
      expect(state.activeSpokenLanguage, 'en-US');
      expect(state.activeCaptionLanguage, 'es');
      expect(state.supportedSpokenLanguages, ['en-US', 'es-ES']);
      expect(state.supportedCaptionLanguages, ['en', 'es', 'fr']);
    });

    test('fromMap handles missing fields with defaults', () {
      final state = CaptionsState.fromMap({});
      expect(state.available, true); // defaults to true
      expect(state.isEnabled, false);
      expect(state.type, 'unknown');
      expect(state.activeSpokenLanguage, '');
      expect(state.activeCaptionLanguage, isNull);
      expect(state.supportedSpokenLanguages, isEmpty);
      expect(state.supportedCaptionLanguages, isEmpty);
    });
  });

  group('RaisedHandInfo', () {
    test('fromMap creates instance', () {
      final info = RaisedHandInfo.fromMap({
        'identifier': 'user-123',
        'order': 5,
      });
      expect(info.identifier, 'user-123');
      expect(info.order, 5);
    });

    test('fromMap handles missing fields', () {
      final info = RaisedHandInfo.fromMap({});
      expect(info.identifier, '');
      expect(info.order, 0);
    });
  });

  group('DataChannelSenderInfo', () {
    test('fromMap creates instance', () {
      final info = DataChannelSenderInfo.fromMap({
        'channelId': 42,
        'maxMessageSizeInBytes': 65536,
      });
      expect(info.channelId, 42);
      expect(info.maxMessageSizeInBytes, 65536);
    });
  });

  group('CallSurveyHandle', () {
    test('fromMap creates instance', () {
      final handle = CallSurveyHandle.fromMap({'handle': 'survey-123'});
      expect(handle.handle, 'survey-123');
    });
  });

  group('CallSurveyResult', () {
    test('fromMap creates instance', () {
      final result = CallSurveyResult.fromMap({
        'surveyId': 'survey-1',
        'callId': 'call-1',
        'anonymizedParticipantId': 'anon-1',
      });
      expect(result.surveyId, 'survey-1');
      expect(result.callId, 'call-1');
      expect(result.anonymizedParticipantId, 'anon-1');
    });
  });

  group('CallSurveySubmission', () {
    test('toMap includes all fields', () {
      final submission = CallSurveySubmission(
        handle: const CallSurveyHandle('survey-1'),
        overallScore: const CallSurveyScoreInput(score: 5),
        audioScore: CallSurveyScoreInput(
          score: 4,
          scale: const CallSurveyRatingScaleInput(
            lowerBound: 1,
            upperBound: 5,
          ),
        ),
        overallIssues: 0,
      );
      final map = submission.toMap();
      expect(map['handle'], 'survey-1');
      expect(map['overallScore'], isA<Map>());
      expect(map['overallScore']['score'], 5);
      expect(map['audioScore']['scale']['lowerBound'], 1);
      expect(map['overallIssues'], 0);
    });

    test('toMap excludes null fields', () {
      final submission = CallSurveySubmission(
        handle: const CallSurveyHandle('survey-1'),
      );
      final map = submission.toMap();
      expect(map.containsKey('overallScore'), false);
      expect(map.containsKey('audioScore'), false);
      expect(map.containsKey('videoScore'), false);
    });
  });
}

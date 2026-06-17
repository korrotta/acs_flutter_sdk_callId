import 'dart:async';
import 'package:acs_flutter_sdk/acs_flutter_sdk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('acs_flutter_sdk');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('AcsCallClient Event Streams', () {
    late AcsCallClient client;

    setUp(() {
      final sdk = AcsFlutterSdk();
      client = sdk.createCallClient();
    });

    tearDown(() {
      client.dispose();
    });

    test('callStateStream is broadcast stream', () {
      final stream = client.callStateStream;
      expect(stream.isBroadcast, isTrue);
    });

    test('participantEvents stream getter returns stream', () {
      final stream = client.participantEvents;
      expect(stream, isA<Stream<RemoteParticipantEvent>>());
    });

    test('capabilitiesChangedStream getter returns stream', () {
      final stream = client.capabilitiesChangedStream;
      expect(stream, isA<Stream<CapabilitiesChangedEvent>>());
    });

    test('incomingCallStream getter returns stream', () {
      final stream = client.incomingCallStream;
      expect(stream, isA<Stream<IncomingCallEvent>>());
    });

    test('callFeatureEvents getter returns stream', () {
      final stream = client.callFeatureEvents;
      expect(stream, isA<Stream<CallFeatureEvent>>());
    });

    test('captionsEvents getter returns stream', () {
      final stream = client.captionsEvents;
      expect(stream, isA<Stream<CaptionsEvent>>());
    });

    test('realTimeTextEvents getter returns stream', () {
      final stream = client.realTimeTextEvents;
      expect(stream, isA<Stream<RealTimeTextEvent>>());
    });

    test('dataChannelEvents getter returns stream', () {
      final stream = client.dataChannelEvents;
      expect(stream, isA<Stream<DataChannelEvent>>());
    });

    test('mediaStatisticsEvents getter returns stream', () {
      final stream = client.mediaStatisticsEvents;
      expect(stream, isA<Stream<MediaStatisticsEvent>>());
    });

    test('diagnosticsEvents getter returns stream', () {
      final stream = client.diagnosticsEvents;
      expect(stream, isA<Stream<DiagnosticsEvent>>());
    });

    test('dispose closes callStateStream', () async {
      final sdk = AcsFlutterSdk();
      final testClient = sdk.createCallClient();

      // Get stream before dispose
      final stream = testClient.callStateStream;

      // Dispose should close the stream
      testClient.dispose();

      // Stream should be done after dispose
      final completer = Completer<bool>();
      stream.listen(
        (_) {},
        onDone: () => completer.complete(true),
        onError: (_) => completer.complete(false),
      );

      // Give a small delay for the stream to close
      await Future.delayed(const Duration(milliseconds: 10));
      expect(completer.isCompleted, isTrue);
    });
  });

  group('RemoteParticipantEvent', () {
    test('fromMap creates event with type and id', () {
      final event = RemoteParticipantEvent.fromMap({
        'type': 'participantAdded',
        'id': 'user-123',
      });
      expect(event.type, 'participantAdded');
      expect(event.id, 'user-123');
    });

    test('fromMap creates event with participant state', () {
      final event = RemoteParticipantEvent.fromMap({
        'type': 'participantUpdated',
        'id': 'user-456',
        'participant': {
          'id': 'user-456',
          'displayName': 'John Doe',
          'state': 'connected',
          'isMuted': true,
          'isSpeaking': false,
          'videoStreams': [],
        },
      });
      expect(event.type, 'participantUpdated');
      expect(event.participant, isNotNull);
      expect(event.participant!.id, 'user-456');
      expect(event.participant!.displayName, 'John Doe');
      expect(event.participant!.isMuted, true);
    });

    test('fromMap handles missing participant', () {
      final event = RemoteParticipantEvent.fromMap({
        'type': 'participantRemoved',
        'id': 'user-789',
      });
      expect(event.type, 'participantRemoved');
      expect(event.participant, isNull);
    });

    test('fromMap handles missing type as unknown', () {
      final event = RemoteParticipantEvent.fromMap({
        'id': 'user-1',
      });
      expect(event.type, 'unknown');
    });

    test('parses the participantVideoRendering first-frame signal (id only)', () {
      final event = RemoteParticipantEvent.fromMap({
        'type': 'participantVideoRendering',
        'id': 'user-42',
      });
      expect(event.type, 'participantVideoRendering');
      expect(event.id, 'user-42');
      expect(event.isVideoRenderingEvent, isTrue);
      // First-frame signal carries no participant snapshot.
      expect(event.participant, isNull);
    });

    test('isVideoRenderingEvent is false for ordinary participant events', () {
      final event = RemoteParticipantEvent.fromMap({
        'type': 'participantAdded',
        'id': 'user-1',
      });
      expect(event.isVideoRenderingEvent, isFalse);
    });
  });

  group('RemoteParticipantState', () {
    test('fromMap creates state with all fields', () {
      final state = RemoteParticipantState.fromMap({
        'id': 'user-123',
        'displayName': 'Jane Smith',
        'state': 'connected',
        'isMuted': true,
        'isSpeaking': true,
        'videoStreams': [
          {'id': 1, 'type': 'video', 'isAvailable': true},
        ],
      });
      expect(state.id, 'user-123');
      expect(state.displayName, 'Jane Smith');
      expect(state.state, 'connected');
      expect(state.isMuted, true);
      expect(state.isSpeaking, true);
      expect(state.videoStreams, hasLength(1));
      expect(state.videoStreams[0].type, 'video');
    });

    test('fromMap handles missing videoStreams', () {
      final state = RemoteParticipantState.fromMap({
        'id': 'user-456',
        'displayName': 'Bob',
        'state': 'connecting',
        'isMuted': false,
        'isSpeaking': false,
      });
      expect(state.videoStreams, isEmpty);
    });

    test('toMap converts to map', () {
      const state = RemoteParticipantState(
        id: 'user-1',
        displayName: 'Test',
        state: 'connected',
        isMuted: false,
        isSpeaking: true,
        videoStreams: [],
      );
      final map = state.toMap();
      expect(map['id'], 'user-1');
      expect(map['displayName'], 'Test');
      expect(map['state'], 'connected');
    });

    test('isVideoRendering defaults to false and round-trips through fromMap', () {
      const defaulted = RemoteParticipantState(
        id: 'u', displayName: 'd', state: 'connected',
        isMuted: false, isSpeaking: false, videoStreams: [],
      );
      expect(defaulted.isVideoRendering, isFalse);

      final parsed = RemoteParticipantState.fromMap({
        'id': 'u', 'displayName': 'd', 'state': 'connected',
        'isMuted': false, 'isSpeaking': false, 'videoStreams': [],
        'isVideoRendering': true,
      });
      expect(parsed.isVideoRendering, isTrue);
    });

    test('copyWith(isVideoRendering: true) flips the flag and affects equality', () {
      const base = RemoteParticipantState(
        id: 'u', displayName: 'd', state: 'connected',
        isMuted: false, isSpeaking: false, videoStreams: [],
      );
      final rendering = base.copyWith(isVideoRendering: true);
      expect(rendering.isVideoRendering, isTrue);
      // The flag participates in value equality (drives a tile rebuild).
      expect(rendering, isNot(equals(base)));
      expect(base.copyWith(isVideoRendering: false), equals(base));
    });
  });

  group('RemoteVideoInfo', () {
    test('fromMap creates video info', () {
      final info = RemoteVideoInfo.fromMap({
        'id': 42,
        'type': 'screenshare',
        'isAvailable': true,
      });
      expect(info.id, 42);
      expect(info.type, 'screenshare');
      expect(info.isAvailable, true);
    });

    test('toMap converts to map', () {
      const info = RemoteVideoInfo(id: 1, type: 'video', isAvailable: false);
      final map = info.toMap();
      expect(map['id'], 1);
      expect(map['type'], 'video');
      expect(map['isAvailable'], false);
    });
  });

  group('CapabilitiesChangedEvent', () {
    test('fromMap creates event with changed capabilities', () {
      final event = CapabilitiesChangedEvent.fromMap({
        'changedCapabilities': [
          {'type': 'unmuteMicrophone', 'isAllowed': true, 'reason': null},
          {'type': 'turnVideoOn', 'isAllowed': false, 'reason': 'restricted'},
        ],
      });
      expect(event.changedCapabilities, hasLength(2));
      expect(event.changedCapabilities[0].type, 'unmuteMicrophone');
      expect(event.changedCapabilities[0].isAllowed, true);
      expect(event.changedCapabilities[1].type, 'turnVideoOn');
      expect(event.changedCapabilities[1].isAllowed, false);
      expect(event.changedCapabilities[1].reason, 'restricted');
    });

    test('fromMap handles empty capabilities list', () {
      final event = CapabilitiesChangedEvent.fromMap({
        'changedCapabilities': [],
      });
      expect(event.changedCapabilities, isEmpty);
    });

    test('fromMap handles missing capabilities', () {
      final event = CapabilitiesChangedEvent.fromMap({});
      expect(event.changedCapabilities, isEmpty);
    });
  });

  group('ParticipantCapability', () {
    test('fromMap creates capability', () {
      final cap = ParticipantCapability.fromMap({
        'type': 'shareScreen',
        'isAllowed': true,
        'reason': 'organizer',
      });
      expect(cap.type, 'shareScreen');
      expect(cap.isAllowed, true);
      expect(cap.reason, 'organizer');
    });

    test('toMap converts to map', () {
      const cap = ParticipantCapability(
        type: 'muteOthers',
        isAllowed: false,
        reason: 'not_allowed',
      );
      final map = cap.toMap();
      expect(map['type'], 'muteOthers');
      expect(map['isAllowed'], false);
      expect(map['reason'], 'not_allowed');
    });
  });

  group('IncomingCallEvent', () {
    test('fromMap creates incoming event with call info', () {
      final event = IncomingCallEvent.fromMap({
        'type': 'incoming',
        'call': {
          'id': 'call-123',
          'callerId': 'user-caller-1',
          'displayName': 'Jane Smith',
          'hasVideo': true,
        },
      });
      expect(event.type, IncomingCallEventType.incoming);
      expect(event.call, isNotNull);
      expect(event.call!.id, 'call-123');
      expect(event.call!.callerId, 'user-caller-1');
      expect(event.call!.displayName, 'Jane Smith');
      expect(event.call!.hasVideo, true);
    });

    test('fromMap creates ended event', () {
      final event = IncomingCallEvent.fromMap({
        'type': 'ended',
      });
      expect(event.type, IncomingCallEventType.ended);
      expect(event.call, isNull);
    });

    test('fromMap defaults to incoming for unknown type', () {
      final event = IncomingCallEvent.fromMap({
        'type': 'unknownType',
      });
      expect(event.type, IncomingCallEventType.incoming);
    });
  });

  group('IncomingCallInfo', () {
    test('fromMap creates call info', () {
      final info = IncomingCallInfo.fromMap({
        'id': 'call-abc',
        'callerId': 'user-def',
        'displayName': 'Caller Name',
        'hasVideo': true,
      });
      expect(info.id, 'call-abc');
      expect(info.callerId, 'user-def');
      expect(info.displayName, 'Caller Name');
      expect(info.hasVideo, true);
    });

    test('hasVideo defaults to false', () {
      final info = IncomingCallInfo.fromMap({
        'id': 'call-xyz',
      });
      expect(info.hasVideo, false);
    });

    test('toMap converts to map', () {
      const info = IncomingCallInfo(
        id: 'call-1',
        callerId: 'user-1',
        displayName: 'Test Caller',
        hasVideo: false,
      );
      final map = info.toMap();
      expect(map['id'], 'call-1');
      expect(map['callerId'], 'user-1');
      expect(map['displayName'], 'Test Caller');
      expect(map['hasVideo'], false);
    });
  });

  group('Multiple client instances', () {
    test('can create multiple client instances', () {
      final sdk = AcsFlutterSdk();
      final client1 = sdk.createCallClient();
      final client2 = sdk.createCallClient();

      expect(client1, isNot(same(client2)));

      // Both should have independent streams
      expect(client1.callStateStream, isNot(same(client2.callStateStream)));

      client1.dispose();
      client2.dispose();
    });
  });
}

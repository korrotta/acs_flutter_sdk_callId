import 'package:acs_flutter_sdk/acs_flutter_sdk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build verification tests that ensure the SDK compiles correctly
/// and all public exports are accessible.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('acs_flutter_sdk');
  final List<MethodCall> log = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      switch (methodCall.method) {
        case 'getPlatformVersion':
          return 'Android 14';
        case 'initializeIdentity':
          return {'status': 'initialized'};
        case 'initializeCalling':
          return {'status': 'initialized'};
        case 'initializeChat':
          return {'status': 'initialized'};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('AcsFlutterSdk', () {
    test('getPlatformVersion returns platform version', () async {
      final sdk = AcsFlutterSdk();
      final version = await sdk.getPlatformVersion();
      expect(version, 'Android 14');
      expect(log, <Matcher>[
        isMethodCall('getPlatformVersion', arguments: null),
      ]);
    });

    test('createIdentityClient returns AcsIdentityClient instance', () {
      final sdk = AcsFlutterSdk();
      final client = sdk.createIdentityClient();
      expect(client, isA<AcsIdentityClient>());
    });

    test('createCallClient returns AcsCallClient instance', () {
      final sdk = AcsFlutterSdk();
      final client = sdk.createCallClient();
      expect(client, isA<AcsCallClient>());
    });

    test('createChatClient throws UnsupportedError (removed feature)', () {
      final sdk = AcsFlutterSdk();
      // ignore: deprecated_member_use_from_same_package
      expect(() => sdk.createChatClient(), throwsUnsupportedError);
    });
  });

  group('Models', () {
    group('CommunicationUser', () {
      test('creates instance with id', () {
        const user = CommunicationUser(id: 'user-123');
        expect(user.id, 'user-123');
      });

      test('fromMap creates instance from map', () {
        final user = CommunicationUser.fromMap({'id': 'user-456'});
        expect(user.id, 'user-456');
      });

      test('toMap converts to map', () {
        const user = CommunicationUser(id: 'user-789');
        final map = user.toMap();
        expect(map, {'id': 'user-789'});
      });

      test('equality works correctly', () {
        const user1 = CommunicationUser(id: 'user-1');
        const user2 = CommunicationUser(id: 'user-1');
        const user3 = CommunicationUser(id: 'user-2');
        expect(user1, equals(user2));
        expect(user1, isNot(equals(user3)));
      });

      test('hashCode works correctly', () {
        const user1 = CommunicationUser(id: 'user-1');
        const user2 = CommunicationUser(id: 'user-1');
        expect(user1.hashCode, equals(user2.hashCode));
      });
    });

    group('AccessToken', () {
      test('creates instance with token and expiry', () {
        final expiresOn = DateTime.now().add(const Duration(hours: 1));
        final token = AccessToken(token: 'abc123', expiresOn: expiresOn);
        expect(token.token, 'abc123');
        expect(token.expiresOn, expiresOn);
      });

      test('fromMap creates instance from map', () {
        final expiresOn = DateTime.now().add(const Duration(hours: 1));
        final token = AccessToken.fromMap({
          'token': 'xyz789',
          'expiresOn': expiresOn.toIso8601String(),
        });
        expect(token.token, 'xyz789');
        expect(token.expiresOn.toIso8601String(), expiresOn.toIso8601String());
      });

      test('toMap converts to map', () {
        final expiresOn = DateTime.now().add(const Duration(hours: 1));
        final token = AccessToken(token: 'token123', expiresOn: expiresOn);
        final map = token.toMap();
        expect(map['token'], 'token123');
        expect(map['expiresOn'], expiresOn.toIso8601String());
      });

      test('isExpired returns true for expired token', () {
        final expiresOn = DateTime.now().subtract(const Duration(hours: 1));
        final token = AccessToken(token: 'expired', expiresOn: expiresOn);
        expect(token.isExpired, isTrue);
      });

      test('isExpired returns false for valid token', () {
        final expiresOn = DateTime.now().add(const Duration(hours: 1));
        final token = AccessToken(token: 'valid', expiresOn: expiresOn);
        expect(token.isExpired, isFalse);
      });

      test('isValid returns true for valid token', () {
        final expiresOn = DateTime.now().add(const Duration(hours: 1));
        final token = AccessToken(token: 'valid', expiresOn: expiresOn);
        expect(token.isValid, isTrue);
      });

      test('isValid returns false for expired token', () {
        final expiresOn = DateTime.now().subtract(const Duration(hours: 1));
        final token = AccessToken(token: 'expired', expiresOn: expiresOn);
        expect(token.isValid, isFalse);
      });
    });
  });

  group('Package Export Verification', () {
    test('AcsFlutterSdk class is exported', () {
      expect(AcsFlutterSdk, isNotNull);
      expect(AcsFlutterSdk(), isA<AcsFlutterSdk>());
    });

    test('AcsIdentityClient class is exported', () {
      expect(AcsIdentityClient, isNotNull);
    });

    test('AcsCallClient class is exported', () {
      expect(AcsCallClient, isNotNull);
    });

    test('CommunicationUser model is exported', () {
      const user = CommunicationUser(id: 'test');
      expect(user, isA<CommunicationUser>());
    });

    test('AccessToken model is exported', () {
      final token = AccessToken(
        token: 'test',
        expiresOn: DateTime.now(),
      );
      expect(token, isA<AccessToken>());
    });

    test('CallFeatureEvent class is exported', () {
      final event = CallFeatureEvent.fromMap({
        'type': 'test',
      });
      expect(event, isA<CallFeatureEvent>());
    });

    test('CaptionsEvent class is exported', () {
      final event = CaptionsEvent.fromMap({
        'type': 'captionsReceived',
      });
      expect(event, isA<CaptionsEvent>());
    });

    test('RealTimeTextEvent class is exported', () {
      final event = RealTimeTextEvent.fromMap({
        'type': 'messageReceived',
      });
      expect(event, isA<RealTimeTextEvent>());
    });

    test('DataChannelEvent class is exported', () {
      final event = DataChannelEvent.fromMap({
        'type': 'messageReceived',
      });
      expect(event, isA<DataChannelEvent>());
    });

    test('MediaStatisticsEvent class is exported', () {
      final event = MediaStatisticsEvent.fromMap({
        'type': 'mediaStatisticsReport',
        'report': {},
      });
      expect(event, isA<MediaStatisticsEvent>());
    });

    test('DiagnosticsEvent class is exported', () {
      final event = DiagnosticsEvent.fromMap({
        'type': 'networkDiagnostic',
      });
      expect(event, isA<DiagnosticsEvent>());
    });

    test('RemoteParticipantState model is exported', () {
      final participant = RemoteParticipantState.fromMap({
        'id': 'test-id',
        'displayName': 'Test User',
        'state': 'connected',
        'isMuted': false,
        'isSpeaking': false,
        'videoStreams': [],
      });
      expect(participant, isA<RemoteParticipantState>());
    });

    test('IncomingCallInfo model is exported', () {
      final call = IncomingCallInfo.fromMap({
        'id': 'call-id',
        'callerId': 'caller-id',
        'displayName': 'Caller',
      });
      expect(call, isA<IncomingCallInfo>());
    });

    test('DeviceInfo model is exported', () {
      final device = DeviceInfo.fromMap({
        'id': 'device-id',
        'name': 'Device Name',
        'deviceType': 'speaker',
      });
      expect(device, isA<DeviceInfo>());
    });

    test('CallState enum is exported', () {
      expect(CallState.values, isNotEmpty);
      expect(CallState.connected, isA<CallState>());
      expect(CallState.disconnected, isA<CallState>());
    });

    test('IncomingCallEventType enum is exported', () {
      expect(IncomingCallEventType.values, isNotEmpty);
      expect(IncomingCallEventType.incoming, isA<IncomingCallEventType>());
      expect(IncomingCallEventType.ended, isA<IncomingCallEventType>());
    });
  });

  group('Call Features Model Integration', () {
    test('CallFeatureEvent parses all properties', () {
      final event = CallFeatureEvent.fromMap({
        'type': 'dominantSpeakersChanged',
        'speakers': ['user-1', 'user-2'],
        'isActive': true,
      });

      expect(event.type, 'dominantSpeakersChanged');
      expect(event.speakers, ['user-1', 'user-2']);
      expect(event.isActive, isTrue);
    });

    test('CaptionsEvent parses all properties', () {
      final event = CaptionsEvent.fromMap({
        'type': 'captionsReceived',
        'spokenText': 'Hello world',
        'captionText': 'Hola mundo',
        'speakerRawId': 'user-id',
        'speakerName': 'John Doe',
        'spokenLanguage': 'en-US',
        'captionLanguage': 'es',
        'resultType': 'final',
        'timestamp': 1704672000,
      });

      expect(event.type, 'captionsReceived');
      expect(event.spokenText, 'Hello world');
      expect(event.captionText, 'Hola mundo');
      expect(event.speakerRawId, 'user-id');
      expect(event.speakerName, 'John Doe');
      expect(event.spokenLanguage, 'en-US');
      expect(event.captionLanguage, 'es');
      expect(event.resultType, 'final');
      expect(event.timestamp, 1704672000);
    });

    test('MediaStatisticsEvent parses nested report structure', () {
      final event = MediaStatisticsEvent.fromMap({
        'type': 'mediaStatisticsReport',
        'report': {
          'lastUpdated': 1704672000,
          'outgoing': {
            'audio': [
              {'codecName': 'opus', 'bitrateInBps': 32000},
            ],
            'video': [
              {'codecName': 'H264', 'frameRate': 30},
            ],
          },
          'incoming': {
            'audio': [
              {'codecName': 'opus'},
            ],
            'video': [
              {'participantIdentifier': 'remote-user'},
            ],
          },
        },
      });

      expect(event.type, 'mediaStatisticsReport');
      expect(event.timestamp, 1704672000);
      expect(event.outgoingAudio?['codecName'], 'opus');
      expect(event.outgoingVideo?['codecName'], 'H264');
      expect(event.incomingAudio?['codecName'], 'opus');
      expect(event.incomingVideo.length, 1);
    });

    test('DiagnosticsEvent parses network and media diagnostics', () {
      final event = DiagnosticsEvent.fromMap({
        'type': 'diagnosticsSnapshot',
        'network': {
          'networkUnavailable': false,
          'networkSendQuality': 'good',
        },
        'media': {
          'cameraFrozen': false,
          'noOutgoingAudio': false,
        },
      });

      expect(event.type, 'diagnosticsSnapshot');
      expect(event.networkDiagnostics?['networkUnavailable'], isFalse);
      expect(event.networkDiagnostics?['networkSendQuality'], 'good');
      expect(event.mediaDiagnostics?['cameraFrozen'], isFalse);
    });
  });
}

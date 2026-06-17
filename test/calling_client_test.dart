import 'package:acs_flutter_sdk/acs_flutter_sdk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('acs_flutter_sdk');
  final List<MethodCall> log = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      switch (methodCall.method) {
        case 'initializeCalling':
          return {'status': 'initialized'};
        case 'startCall':
          return {
            'id': 'call-123',
            'state': 'connecting',
          };
        case 'joinCall':
          return {
            'id': 'call-456',
            'state': 'connecting',
          };
        case 'joinTeamsMeeting':
          return {
            'id': 'call-789',
            'state': 'connecting',
          };
        case 'endCall':
          return null;
        case 'muteAudio':
          return null;
        case 'unmuteAudio':
          return null;
        case 'startVideo':
          return null;
        case 'stopVideo':
          return null;
        case 'requestPermissions':
          return null;
        case 'switchCamera':
          return null;
        case 'addParticipants':
          return {
            'added': (methodCall.arguments['participants'] as List).length
          };
        case 'removeParticipants':
          return {
            'removed': (methodCall.arguments['participants'] as List).length,
            'missing': <String>[],
          };
        default:
          throw PlatformException(code: 'NOT_IMPLEMENTED');
      }
    });
  });

  tearDown(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('AcsCallClient', () {
    late AcsCallClient client;

    setUp(() {
      final sdk = AcsFlutterSdk();
      client = sdk.createCallClient();
      log.clear();
    });

    test('initialize calls platform method with token', () async {
      await client.initialize('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...');

      expect(log, hasLength(1));
      expect(log[0].method, 'initializeCalling');
      expect(log[0].arguments['accessToken'],
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...');
    });

    test('initialize throws AcsCallingException on platform error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        throw PlatformException(
            code: 'INIT_ERROR', message: 'Failed to initialize');
      });

      expect(
        () => client.initialize('invalid'),
        throwsA(isA<AcsCallingException>()
            .having((e) => e.code, 'code', 'INIT_ERROR')),
      );
    });

    test('startCall calls platform method with participants', () async {
      final call = await client.startCall(['user-1', 'user-2']);

      expect(log, hasLength(1));
      expect(log[0].method, 'startCall');
      expect(log[0].arguments['participants'], ['user-1', 'user-2']);
      expect(call, isA<Call>());
      expect(call.id, 'call-123');
      expect(call.state, CallState.connecting);
    });

    test('startCall with video enabled', () async {
      final call = await client.startCall(['user-1'], withVideo: true);

      expect(log, hasLength(1));
      expect(log[0].method, 'startCall');
      expect(log[0].arguments['withVideo'], true);
      expect(call, isA<Call>());
    });

    test('startCall throws AcsCallingException on platform error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        throw PlatformException(
            code: 'CALL_ERROR', message: 'Failed to start call');
      });

      expect(
        () => client.startCall(['user-1']),
        throwsA(isA<AcsCallingException>()
            .having((e) => e.code, 'code', 'CALL_ERROR')),
      );
    });

    test('joinCall calls platform method with callId', () async {
      final call = await client.joinCall('group-call-123');

      expect(log, hasLength(1));
      expect(log[0].method, 'joinCall');
      expect(log[0].arguments['groupCallId'], 'group-call-123');
      expect(call, isA<Call>());
      expect(call.id, 'call-456');
    });

    test('joinCall with video enabled', () async {
      final call = await client.joinCall('group-call-123', withVideo: true);

      expect(log, hasLength(1));
      expect(log[0].arguments['withVideo'], true);
      expect(call, isA<Call>());
    });

    test('joinTeamsMeeting calls platform method with link', () async {
      final call =
          await client.joinTeamsMeeting('https://teams.microsoft.com/fake');

      expect(log, hasLength(1));
      expect(log[0].method, 'joinTeamsMeeting');
      expect(
          log[0].arguments['meetingLink'], 'https://teams.microsoft.com/fake');
      expect(call.id, 'call-789');
    });

    test('joinTeamsMeeting omits noiseSuppressionMode when not requested',
        () async {
      // Backward-compatibility contract: when the caller does not request a
      // noise-suppression mode, the payload must NOT carry the key at all, so
      // native code paths that predate the option receive the exact arguments
      // they always did.
      await client.joinTeamsMeeting('https://teams.microsoft.com/fake');

      expect(log[0].arguments.containsKey('noiseSuppressionMode'), isFalse);
    });

    test('joinTeamsMeeting forwards noiseSuppressionMode to platform',
        () async {
      // When requested, the mode is sent across the channel so the native
      // layer can build the outgoing-audio filter.
      await client.joinTeamsMeeting(
        'https://teams.microsoft.com/fake',
        noiseSuppressionMode: 'auto',
      );

      expect(log[0].method, 'joinTeamsMeeting');
      expect(log[0].arguments['noiseSuppressionMode'], 'auto');
    });

    test('joinTeamsMeeting lower-cases noiseSuppressionMode before sending',
        () async {
      // The documented case-insensitivity is guaranteed Dart-side, so the
      // native matcher always receives a canonical lower-case token regardless
      // of how the caller spelled it.
      await client.joinTeamsMeeting(
        'https://teams.microsoft.com/fake',
        noiseSuppressionMode: 'Auto',
      );

      expect(log[0].arguments['noiseSuppressionMode'], 'auto');
    });

    test('endCall calls platform method', () async {
      await client.endCall();

      expect(log, hasLength(1));
      expect(log[0].method, 'endCall');
    });

    test('muteAudio calls platform method', () async {
      await client.muteAudio();

      expect(log, hasLength(1));
      expect(log[0].method, 'muteAudio');
    });

    test('unmuteAudio calls platform method', () async {
      await client.unmuteAudio();

      expect(log, hasLength(1));
      expect(log[0].method, 'unmuteAudio');
    });

    test('startVideo calls platform method', () async {
      await client.startVideo();

      expect(log, hasLength(1));
      expect(log[0].method, 'startVideo');
    });

    test('stopVideo calls platform method', () async {
      await client.stopVideo();

      expect(log, hasLength(1));
      expect(log[0].method, 'stopVideo');
    });

    test('requestPermissions calls platform method', () async {
      await client.requestPermissions();

      expect(log, hasLength(1));
      expect(log[0].method, 'requestPermissions');
    });

    test('switchCamera calls platform method', () async {
      await client.switchCamera();

      expect(log, hasLength(1));
      expect(log[0].method, 'switchCamera');
    });

    test('addParticipants calls platform method with ids', () async {
      await client.addParticipants(['user-3', 'user-4']);

      expect(log, hasLength(1));
      expect(log[0].method, 'addParticipants');
      expect(log[0].arguments['participants'], ['user-3', 'user-4']);
    });

    test('removeParticipants calls platform method with ids', () async {
      await client.removeParticipants(['user-2']);

      expect(log, hasLength(1));
      expect(log[0].method, 'removeParticipants');
      expect(log[0].arguments['participants'], ['user-2']);
    });
  });

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

    test('fromMap handles all CallState values', () {
      expect(Call.fromMap({'id': '1', 'state': 'connecting'}).state,
          CallState.connecting);
      expect(Call.fromMap({'id': '2', 'state': 'connected'}).state,
          CallState.connected);
      expect(
          Call.fromMap({'id': '3', 'state': 'onHold'}).state, CallState.onHold);
      expect(Call.fromMap({'id': '4', 'state': 'disconnecting'}).state,
          CallState.disconnecting);
      expect(Call.fromMap({'id': '5', 'state': 'disconnected'}).state,
          CallState.disconnected);
      expect(Call.fromMap({'id': '6', 'state': 'ringing'}).state,
          CallState.ringing);
      expect(Call.fromMap({'id': '7', 'state': 'none'}).state, CallState.none);
      expect(Call.fromMap({'id': '8', 'state': 'earlyMedia'}).state,
          CallState.earlyMedia);
      expect(Call.fromMap({'id': '9', 'state': 'remoteHold'}).state,
          CallState.remoteHold);
    });

    test('fromMap defaults to disconnected for unknown state', () {
      final call = Call.fromMap({'id': 'call-789', 'state': 'unknown'});
      expect(call.state, CallState.disconnected);
    });

    test('toMap converts to map', () {
      const call = Call(id: 'call-123', state: CallState.connected);
      final map = call.toMap();
      expect(map['id'], 'call-123');
      expect(map['state'], 'connected');
    });
  });

  group('CallState', () {
    test('enum has all expected values', () {
      expect(CallState.values, hasLength(10));
      expect(CallState.values, contains(CallState.none));
      expect(CallState.values, contains(CallState.earlyMedia));
      expect(CallState.values, contains(CallState.connecting));
      expect(CallState.values, contains(CallState.connected));
      expect(CallState.values, contains(CallState.onHold));
      expect(CallState.values, contains(CallState.remoteHold));
      expect(CallState.values, contains(CallState.disconnecting));
      expect(CallState.values, contains(CallState.disconnected));
      expect(CallState.values, contains(CallState.ringing));
      expect(CallState.values, contains(CallState.inLobby));
    });
  });

  group('AcsCallingException', () {
    test('creates exception with code and message', () {
      const exception =
          AcsCallingException(code: 'CALL_ERROR', message: 'Call failed');
      expect(exception.code, 'CALL_ERROR');
      expect(exception.message, 'Call failed');
      expect(exception.details, isNull);
    });

    test('toString includes code and message', () {
      const exception =
          AcsCallingException(code: 'CALL_ERROR', message: 'Call failed');
      expect(exception.toString(), contains('CALL_ERROR'));
      expect(exception.toString(), contains('Call failed'));
    });
  });
}

import 'package:acs_flutter_sdk/acs_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiagnosticsEvent', () {
    group('fromMap', () {
      test('extracts type from map', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkUnavailable',
          'value': true,
        });

        expect(event.type, 'networkDiagnostic');
      });

      test('defaults type to unknown when missing', () {
        final event = DiagnosticsEvent.fromMap({});

        expect(event.type, 'unknown');
      });

      test('preserves raw data', () {
        final rawData = {
          'type': 'networkDiagnostic',
          'diagnostic': 'networkQuality',
          'extraField': 'extraValue',
        };
        final event = DiagnosticsEvent.fromMap(rawData);

        expect(event.data['type'], 'networkDiagnostic');
        expect(event.data['extraField'], 'extraValue');
      });
    });

    group('diagnostic', () {
      test('extracts diagnostic name', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkUnavailable',
        });

        expect(event.diagnostic, 'networkUnavailable');
      });

      test('returns null when diagnostic is missing', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
        });

        expect(event.diagnostic, isNull);
      });
    });

    group('valueBool', () {
      test('extracts boolean value when true', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkUnavailable',
          'value': true,
        });

        expect(event.valueBool, isTrue);
      });

      test('extracts boolean value when false', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkUnavailable',
          'value': false,
        });

        expect(event.valueBool, isFalse);
      });

      test('returns null when value is missing', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkUnavailable',
        });

        expect(event.valueBool, isNull);
      });

      test('throws when value is not a boolean', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkQuality',
          'value': 'good', // String, not bool
        });

        // SDK uses direct cast, so non-bool values throw TypeError
        expect(() => event.valueBool, throwsA(isA<TypeError>()));
      });
    });

    group('valueQuality', () {
      test('extracts quality value - good', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkQuality',
          'valueQuality': 'good',
        });

        expect(event.valueQuality, 'good');
      });

      test('extracts quality value - poor', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkQuality',
          'valueQuality': 'poor',
        });

        expect(event.valueQuality, 'poor');
      });

      test('extracts quality value - bad', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkQuality',
          'valueQuality': 'bad',
        });

        expect(event.valueQuality, 'bad');
      });

      test('returns null when valueQuality is missing', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkUnavailable',
          'value': true,
        });

        expect(event.valueQuality, isNull);
      });
    });

    group('isFlagDiagnostic', () {
      test('returns true when isFlagDiagnostic is true', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkUnavailable',
          'isFlagDiagnostic': true,
        });

        expect(event.isFlagDiagnostic, isTrue);
      });

      test('returns false when isFlagDiagnostic is false', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkQuality',
          'isFlagDiagnostic': false,
        });

        expect(event.isFlagDiagnostic, isFalse);
      });

      test('defaults to true when isFlagDiagnostic is missing', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkUnavailable',
        });

        expect(event.isFlagDiagnostic, isTrue);
      });
    });

    group('networkDiagnostics', () {
      test('extracts network diagnostics map', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'diagnosticsSnapshot',
          'network': {
            'networkUnavailable': false,
            'networkRelaysUnreachable': false,
            'networkReconnectionQuality': 'good',
            'networkReceiveQuality': 'good',
            'networkSendQuality': 'good',
          },
        });

        final network = event.networkDiagnostics;
        expect(network, isNotNull);
        expect(network!['networkUnavailable'], isFalse);
        expect(network['networkReconnectionQuality'], 'good');
      });

      test('returns null when network is missing', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'diagnosticsSnapshot',
        });

        expect(event.networkDiagnostics, isNull);
      });

      test('handles nested Map<Object?, Object?> from platform channel', () {
        // Platform channels may return Map<Object?, Object?> which needs conversion
        final Map<Object?, Object?> platformMap = {
          'networkUnavailable': false,
          'networkQuality': 'good',
        };
        final event = DiagnosticsEvent.fromMap({
          'type': 'diagnosticsSnapshot',
          'network': platformMap,
        });

        final network = event.networkDiagnostics;
        expect(network, isNotNull);
        expect(network!['networkUnavailable'], isFalse);
        expect(network['networkQuality'], 'good');
      });
    });

    group('mediaDiagnostics', () {
      test('extracts media diagnostics map', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'diagnosticsSnapshot',
          'media': {
            'noIncomingAudio': false,
            'noOutgoingAudio': false,
            'cameraFrozen': false,
            'cameraStartFailed': false,
            'microphoneMuted': false,
            'speakerMuted': false,
          },
        });

        final media = event.mediaDiagnostics;
        expect(media, isNotNull);
        expect(media!['noIncomingAudio'], isFalse);
        expect(media['cameraFrozen'], isFalse);
      });

      test('returns null when media is missing', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'diagnosticsSnapshot',
        });

        expect(event.mediaDiagnostics, isNull);
      });

      test('handles nested Map<Object?, Object?> from platform channel', () {
        final Map<Object?, Object?> platformMap = {
          'cameraFrozen': true,
          'noOutgoingAudio': false,
        };
        final event = DiagnosticsEvent.fromMap({
          'type': 'diagnosticsSnapshot',
          'media': platformMap,
        });

        final media = event.mediaDiagnostics;
        expect(media, isNotNull);
        expect(media!['cameraFrozen'], isTrue);
        expect(media['noOutgoingAudio'], isFalse);
      });
    });

    group('real-world diagnostic scenarios', () {
      test('network unavailable diagnostic event', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkUnavailable',
          'value': true,
          'isFlagDiagnostic': true,
        });

        expect(event.type, 'networkDiagnostic');
        expect(event.diagnostic, 'networkUnavailable');
        expect(event.valueBool, isTrue);
        expect(event.isFlagDiagnostic, isTrue);
        expect(event.valueQuality, isNull);
      });

      test('network quality diagnostic event', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'networkDiagnostic',
          'diagnostic': 'networkReceiveQuality',
          'valueQuality': 'poor',
          'isFlagDiagnostic': false,
        });

        expect(event.type, 'networkDiagnostic');
        expect(event.diagnostic, 'networkReceiveQuality');
        expect(event.valueQuality, 'poor');
        expect(event.isFlagDiagnostic, isFalse);
        expect(event.valueBool, isNull);
      });

      test('media diagnostic - camera frozen', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'mediaDiagnostic',
          'diagnostic': 'cameraFrozen',
          'value': true,
          'isFlagDiagnostic': true,
        });

        expect(event.type, 'mediaDiagnostic');
        expect(event.diagnostic, 'cameraFrozen');
        expect(event.valueBool, isTrue);
      });

      test('full diagnostics snapshot', () {
        final event = DiagnosticsEvent.fromMap({
          'type': 'diagnosticsSnapshot',
          'network': {
            'networkUnavailable': false,
            'networkRelaysUnreachable': false,
            'networkReconnectionQuality': 'good',
            'networkReceiveQuality': 'good',
            'networkSendQuality': 'good',
          },
          'media': {
            'noIncomingAudio': false,
            'noOutgoingAudio': false,
            'cameraFrozen': false,
            'cameraStartFailed': false,
            'microphoneMuted': false,
            'speakerMuted': false,
            'speakerBusy': false,
            'speakerNotFunctioning': false,
            'microphoneNotFunctioning': false,
          },
        });

        expect(event.type, 'diagnosticsSnapshot');

        final network = event.networkDiagnostics;
        expect(network, isNotNull);
        expect(network!['networkUnavailable'], isFalse);
        expect(network['networkSendQuality'], 'good');

        final media = event.mediaDiagnostics;
        expect(media, isNotNull);
        expect(media!['cameraFrozen'], isFalse);
        expect(media['microphoneMuted'], isFalse);
      });
    });
  });
}

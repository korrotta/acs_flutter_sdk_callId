import 'package:acs_flutter_sdk/acs_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaStatisticsEvent', () {
    group('outgoingAudio', () {
      test('returns first audio stream from report.outgoing.audio', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {
            'outgoing': {
              'audio': [
                {
                  'codecName': 'opus',
                  'bitrateInBps': 32000,
                  'jitterInMs': 5,
                  'packetCount': 100,
                },
                {
                  'codecName': 'opus-2',
                  'bitrateInBps': 64000,
                },
              ],
            },
          },
        });

        final audio = event.outgoingAudio;
        expect(audio, isNotNull);
        expect(audio!['codecName'], 'opus');
        expect(audio['bitrateInBps'], 32000);
        expect(audio['jitterInMs'], 5);
        expect(audio['packetCount'], 100);
      });

      test('returns null when report is missing', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
        });

        expect(event.outgoingAudio, isNull);
      });

      test('returns null when outgoing is missing', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {},
        });

        expect(event.outgoingAudio, isNull);
      });

      test('returns null when audio array is empty', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {
            'outgoing': {
              'audio': [],
            },
          },
        });

        expect(event.outgoingAudio, isNull);
      });
    });

    group('outgoingAudioList', () {
      test('returns all audio streams', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {
            'outgoing': {
              'audio': [
                {'codecName': 'opus-1'},
                {'codecName': 'opus-2'},
              ],
            },
          },
        });

        final audioList = event.outgoingAudioList;
        expect(audioList.length, 2);
        expect(audioList[0]['codecName'], 'opus-1');
        expect(audioList[1]['codecName'], 'opus-2');
      });

      test('returns empty list when report is missing', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
        });

        expect(event.outgoingAudioList, isEmpty);
      });
    });

    group('outgoingVideo', () {
      test('returns first video stream with all properties', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {
            'outgoing': {
              'video': [
                {
                  'codecName': 'H264',
                  'bitrateInBps': 174224,
                  'frameRate': 15,
                  'frameWidth': 640,
                  'frameHeight': 480,
                  'packetCount': 500,
                },
              ],
            },
          },
        });

        final video = event.outgoingVideo;
        expect(video, isNotNull);
        expect(video!['codecName'], 'H264');
        expect(video['bitrateInBps'], 174224);
        expect(video['frameRate'], 15);
        expect(video['frameWidth'], 640);
        expect(video['frameHeight'], 480);
        expect(video['packetCount'], 500);
      });

      test('returns null when video array is empty', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {
            'outgoing': {
              'video': [],
            },
          },
        });

        expect(event.outgoingVideo, isNull);
      });
    });

    group('incomingAudio', () {
      test('returns first incoming audio stream', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {
            'incoming': {
              'audio': [
                {
                  'codecName': 'opus',
                  'jitterInMs': 10,
                  'packetsLostPerSecond': 2,
                },
              ],
            },
          },
        });

        final audio = event.incomingAudio;
        expect(audio, isNotNull);
        expect(audio!['codecName'], 'opus');
        expect(audio['jitterInMs'], 10);
        expect(audio['packetsLostPerSecond'], 2);
      });

      test('returns null when incoming is missing', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {},
        });

        expect(event.incomingAudio, isNull);
      });
    });

    group('incomingVideo', () {
      test('returns list of remote participant video stats', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {
            'incoming': {
              'video': [
                {
                  'participantIdentifier': 'user-1',
                  'codecName': 'H264',
                  'bitrateInBps': 14912,
                  'jitterInMs': 95,
                  'packetsLostPerSecond': 0,
                  'frameRate': 6,
                  'frameWidth': 160,
                  'frameHeight': 212,
                  'totalFreezeDurationInMs': 0,
                },
                {
                  'participantIdentifier': 'user-2',
                  'codecName': 'VP8',
                  'bitrateInBps': 25000,
                },
              ],
            },
          },
        });

        final videoList = event.incomingVideo;
        expect(videoList.length, 2);
        expect(videoList[0]['participantIdentifier'], 'user-1');
        expect(videoList[0]['codecName'], 'H264');
        expect(videoList[0]['bitrateInBps'], 14912);
        expect(videoList[0]['jitterInMs'], 95);
        expect(videoList[0]['frameRate'], 6);
        expect(videoList[0]['frameWidth'], 160);
        expect(videoList[0]['frameHeight'], 212);
        expect(videoList[1]['participantIdentifier'], 'user-2');
      });

      test('returns empty list when incoming is missing', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {},
        });

        expect(event.incomingVideo, isEmpty);
      });

      test('returns empty list when video is missing', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {
            'incoming': {},
          },
        });

        expect(event.incomingVideo, isEmpty);
      });
    });

    group('outgoingScreenShare', () {
      test('returns first screen share stream', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {
            'outgoing': {
              'screenShare': [
                {
                  'codecName': 'H264',
                  'bitrateInBps': 500000,
                  'frameRate': 30,
                },
              ],
            },
          },
        });

        final screenShare = event.outgoingScreenShare;
        expect(screenShare, isNotNull);
        expect(screenShare!['codecName'], 'H264');
        expect(screenShare['bitrateInBps'], 500000);
      });

      test('returns null when screenShare is missing', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {
            'outgoing': {},
          },
        });

        expect(event.outgoingScreenShare, isNull);
      });
    });

    group('incomingScreenShare', () {
      test('returns list of incoming screen share streams', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {
            'incoming': {
              'screenShare': [
                {'codecName': 'H264', 'bitrateInBps': 1000000},
              ],
            },
          },
        });

        final screenShareList = event.incomingScreenShare;
        expect(screenShareList.length, 1);
        expect(screenShareList[0]['codecName'], 'H264');
      });

      test('returns empty list when screenShare is missing', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {
            'incoming': {},
          },
        });

        expect(event.incomingScreenShare, isEmpty);
      });
    });

    group('timestamp', () {
      test('extracts from report.lastUpdated', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {
            'lastUpdated': 1704672000,
          },
        });

        expect(event.timestamp, 1704672000);
      });

      test('falls back to data.timestamp when report missing', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'timestamp': 1704672001,
        });

        expect(event.timestamp, 1704672001);
      });

      test('returns null when no timestamp available', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
        });

        expect(event.timestamp, isNull);
      });
    });

    group('type', () {
      test('extracts event type', () {
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {},
        });

        expect(event.type, 'mediaStatisticsReport');
      });

      test('defaults to unknown when type is missing', () {
        final event = MediaStatisticsEvent.fromMap({});

        expect(event.type, 'unknown');
      });
    });

    group('data', () {
      test('preserves raw event data', () {
        final rawData = {
          'type': 'mediaStatisticsReport',
          'report': {'key': 'value'},
          'extraField': 'extraValue',
        };
        final event = MediaStatisticsEvent.fromMap(rawData);

        expect(event.data['type'], 'mediaStatisticsReport');
        expect(event.data['extraField'], 'extraValue');
      });
    });

    group('complete iOS SDK payload', () {
      test('handles full iOS SDK structure', () {
        // This is the actual structure sent by iOS SDK
        final event = MediaStatisticsEvent.fromMap({
          'type': 'mediaStatisticsReport',
          'report': {
            'lastUpdated': 1704672000,
            'outgoing': {
              'audio': [
                {
                  'codecName': 'opus',
                  'bitrateInBps': 32000,
                  'jitterInMs': 5,
                  'packetCount': 1000,
                },
              ],
              'video': [
                {
                  'codecName': 'H264',
                  'bitrateInBps': 174224,
                  'frameRate': 15,
                  'frameWidth': 640,
                  'frameHeight': 480,
                  'packetCount': 500,
                },
              ],
              'screenShare': [],
              'dataChannel': [],
            },
            'incoming': {
              'audio': [
                {
                  'codecName': 'opus',
                  'jitterInMs': 10,
                  'packetsLostPerSecond': 0,
                },
              ],
              'video': [
                {
                  'participantIdentifier': '8:acs:user-guid',
                  'codecName': 'H264',
                  'bitrateInBps': 14912,
                  'jitterInMs': 95,
                  'packetsLostPerSecond': 0,
                  'frameRate': 6,
                  'frameWidth': 160,
                  'frameHeight': 212,
                  'framesReceived': 100,
                  'framesDropped': 2,
                  'framesDecoded': 98,
                  'totalFreezeDurationInMs': 0,
                  'longestFreezeDurationInMs': 0,
                },
              ],
              'screenShare': [],
              'dataChannel': [],
            },
          },
        });

        // Verify outgoing audio
        expect(event.outgoingAudio!['codecName'], 'opus');
        expect(event.outgoingAudio!['bitrateInBps'], 32000);

        // Verify outgoing video
        expect(event.outgoingVideo!['codecName'], 'H264');
        expect(event.outgoingVideo!['frameRate'], 15);

        // Verify incoming audio
        expect(event.incomingAudio!['codecName'], 'opus');

        // Verify incoming video
        expect(event.incomingVideo.length, 1);
        expect(
            event.incomingVideo[0]['participantIdentifier'], '8:acs:user-guid');
        expect(event.incomingVideo[0]['jitterInMs'], 95);

        // Verify timestamp
        expect(event.timestamp, 1704672000);
      });
    });
  });
}

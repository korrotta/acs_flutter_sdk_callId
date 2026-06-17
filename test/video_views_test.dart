import 'package:acs_flutter_sdk/acs_flutter_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AcsLocalVideoView', () {
    testWidgets('builds without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AcsLocalVideoView(),
          ),
        ),
      );

      expect(find.byType(AcsLocalVideoView), findsOneWidget);
    });

    testWidgets('is a StatelessWidget', (tester) async {
      const widget = AcsLocalVideoView();
      expect(widget, isA<StatelessWidget>());
    });

    testWidgets('can be used in a sized container', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 150,
              child: AcsLocalVideoView(),
            ),
          ),
        ),
      );

      final sizedBox = find.byType(SizedBox).first;
      expect(sizedBox, findsOneWidget);
    });

    testWidgets('can be placed in a Column', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(child: AcsLocalVideoView()),
                Text('Controls'),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(AcsLocalVideoView), findsOneWidget);
      expect(find.text('Controls'), findsOneWidget);
    });
  });

  group('AcsRemoteVideoView', () {
    testWidgets('builds without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AcsRemoteVideoView(),
          ),
        ),
      );

      expect(find.byType(AcsRemoteVideoView), findsOneWidget);
    });

    testWidgets('is a StatelessWidget', (tester) async {
      const widget = AcsRemoteVideoView();
      expect(widget, isA<StatelessWidget>());
    });

    testWidgets('can be used in a sized container', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 240,
              child: AcsRemoteVideoView(),
            ),
          ),
        ),
      );

      final sizedBox = find.byType(SizedBox).first;
      expect(sizedBox, findsOneWidget);
    });

    testWidgets('can be placed in a Stack with overlay', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const AcsRemoteVideoView(),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Container(
                    width: 100,
                    height: 75,
                    color: Colors.black54,
                    child: const AcsLocalVideoView(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(AcsRemoteVideoView), findsOneWidget);
      expect(find.byType(AcsLocalVideoView), findsOneWidget);
    });
  });

  group('Video view combinations', () {
    testWidgets('both views can exist together', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(child: AcsRemoteVideoView()),
                SizedBox(
                  height: 100,
                  child: AcsLocalVideoView(),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(AcsLocalVideoView), findsOneWidget);
      expect(find.byType(AcsRemoteVideoView), findsOneWidget);
    });

    testWidgets('multiple remote views can exist', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(child: AcsRemoteVideoView()),
                Expanded(child: AcsRemoteVideoView()),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(AcsRemoteVideoView), findsNWidgets(2));
    });

    testWidgets('views respond to parent constraints', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 300,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: AcsRemoteVideoView(),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AspectRatio), findsOneWidget);
      expect(find.byType(AcsRemoteVideoView), findsOneWidget);
    });
  });

  group('Video view widget properties', () {
    test('AcsLocalVideoView has const constructor', () {
      // This test verifies the const constructor works
      const local1 = AcsLocalVideoView(key: ValueKey('local1'));
      const local2 = AcsLocalVideoView(key: ValueKey('local2'));
      expect(local1.key, isNot(equals(local2.key)));
    });

    test('AcsRemoteVideoView has const constructor', () {
      // This test verifies the const constructor works
      const remote1 = AcsRemoteVideoView(key: ValueKey('remote1'));
      const remote2 = AcsRemoteVideoView(key: ValueKey('remote2'));
      expect(remote1.key, isNot(equals(remote2.key)));
    });

    testWidgets('widgets can be keyed for identification', (tester) async {
      const localKey = ValueKey('local-video');
      const remoteKey = ValueKey('remote-video');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(child: AcsRemoteVideoView(key: remoteKey)),
                SizedBox(
                  height: 100,
                  child: AcsLocalVideoView(key: localKey),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(localKey), findsOneWidget);
      expect(find.byKey(remoteKey), findsOneWidget);
    });
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Displays the local ACS video preview rendered by the platform layer.
class AcsLocalVideoView extends StatelessWidget {
  const AcsLocalVideoView({super.key});

  @override
  Widget build(BuildContext context) {
    return _AcsPlatformVideoView(viewKey: 'localVideoView');
  }
}

/// Displays a remote participant video feed rendered by the platform layer.
///
/// Two modes are supported, selected by whether [participantId] is provided:
///
/// * **Shared mode** (`participantId == null`, default / back-compat): renders
///   the legacy shared `remoteVideoView` container. The native side stacks every
///   active remote stream into this single container. This preserves the exact
///   behaviour that existed before per-participant rendering was added, so any
///   existing caller using `AcsRemoteVideoView()` is unaffected.
///
/// * **Per-participant mode** (`participantId != null`): the native side resolves
///   the [RemoteParticipant] whose raw identifier matches [participantId] from the
///   active call, creates a dedicated renderer for that participant's video stream,
///   and shows only that participant's feed in this view. This is the building
///   block for a multi-participant grid where each tile owns one renderer.
///
/// The native layer caps the number of concurrent per-participant renderers at 9
/// (the ACS native simultaneous-render limit); requesting more than 9 distinct
/// participants results in the surplus tiles staying blank until a slot frees up.
class AcsRemoteVideoView extends StatelessWidget {
  /// Creates a remote video view.
  ///
  /// [participantId] is the ACS raw identifier (e.g. the value of
  /// `RemoteParticipant.identifier.rawId`) of the participant whose video should
  /// be shown. When omitted the legacy shared remote container is used.
  const AcsRemoteVideoView({super.key, this.participantId});

  /// Raw ACS identifier of the participant to render, or `null` for the shared
  /// legacy remote container. Optional to keep the public API additive.
  final String? participantId;

  @override
  Widget build(BuildContext context) {
    return _AcsPlatformVideoView(
      viewKey: 'remoteVideoView',
      participantId: participantId,
    );
  }
}

class _AcsPlatformVideoView extends StatelessWidget {
  const _AcsPlatformVideoView({required this.viewKey, this.participantId});

  final String viewKey;

  /// Optional participant raw id forwarded to the platform layer so it can
  /// create a dedicated per-participant renderer instead of using the shared
  /// container. `null` selects the legacy shared-container behaviour.
  final String? participantId;

  static const String _viewType = 'acs_video_view';

  /// Builds the platform creation params, including [participantId] only when it
  /// is non-null so that the legacy shared-container code path on the native side
  /// (which keys solely on `viewKey`) keeps receiving the exact same payload it
  /// did before per-participant rendering was introduced.
  Map<String, dynamic> _buildCreationParams() {
    final params = <String, dynamic>{'viewKey': viewKey};
    if (participantId != null) {
      params['participantId'] = participantId;
    }
    return params;
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: _viewType,
        creationParams: _buildCreationParams(),
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }

    // Wrap in SafeArea so the platform surface respects system insets (status/nav bars)
    // when used inside Android activities/fragments. This avoids content being drawn
    // under system UI in fullscreen native integrations while keeping iOS behavior unchanged.
    return SafeArea(
      child: PlatformViewLink(
        viewType: _viewType,
        surfaceFactory: (context, controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (params) {
          return PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: _viewType,
            layoutDirection: TextDirection.ltr,
            creationParams: _buildCreationParams(),
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create();
        },
      ),
    );
  }
}

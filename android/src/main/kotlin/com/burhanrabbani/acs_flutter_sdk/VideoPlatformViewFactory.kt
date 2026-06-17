package com.burhanrabbani.acs_flutter_sdk

import android.content.Context
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Factory for the `acs_video_view` platform view.
 *
 * Resolves three cases from the Flutter creation params:
 * - `viewKey == "localVideoView"` -> shared local preview container.
 * - `viewKey == "remoteVideoView"` with no `participantId` -> shared remote grid
 *   container (legacy multi-stream behaviour; unchanged).
 * - `viewKey == "remoteVideoView"` with a `participantId` -> a dedicated
 *   per-participant tile from [ParticipantVideoRegistry]. On dispose the tile is
 *   torn down.
 *
 * @param viewManager Shared local/remote container manager (legacy path).
 * @param participantRegistry Registry owning per-participant tiles, or null if the
 *   per-participant grid path is not wired (defensive; falls back to legacy).
 * @param onParticipantViewCreated Callback fired with a participantId right after its
 *   tile is created, letting the plugin reconcile any available stream.
 */
class VideoPlatformViewFactory(
    private val viewManager: VideoViewManager,
    private val participantRegistry: ParticipantVideoRegistry<*>? = null,
    private val onParticipantViewCreated: ((String) -> Unit)? = null
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<String, Any?>()
        val viewType = params["viewKey"] as? String ?: ""
        val participantId = (params["participantId"] as? String)?.takeIf { it.isNotEmpty() }

        // Per-participant grid tile path.
        if (viewType == "remoteVideoView" && participantId != null && participantRegistry != null) {
            val container = participantRegistry.containerForParticipant(participantId)
            // Reconcile after creation so an already-available stream attaches now.
            onParticipantViewCreated?.invoke(participantId)
            return object : PlatformView {
                override fun getView(): View = container
                override fun dispose() {
                    participantRegistry.dispose(participantId)
                }
            }
        }

        val view: View? = when (viewType) {
            "localVideoView" -> viewManager.localContainer
            "remoteVideoView" -> viewManager.remoteContainer
            else -> null
        }
        return object : PlatformView {
            override fun getView(): View? = view
            override fun dispose() = Unit
        }
    }
}

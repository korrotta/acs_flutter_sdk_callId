package com.burhanrabbani.acs_flutter_sdk

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import com.azure.android.communication.calling.CreateViewOptions
import com.azure.android.communication.calling.RemoteVideoStream
import com.azure.android.communication.calling.ScalingMode
import com.azure.android.communication.calling.VideoStreamRenderer

/**
 * Handle to a single attached renderer: the [View] embedded in a tile container and
 * a [dispose] hook that releases the underlying native renderer.
 *
 * Decouples the registry's slot bookkeeping from the concrete ACS renderer so the
 * cap/backfill logic can be unit-tested with a fake factory (no ACS SDK on the test
 * classpath).
 */
class RendererHandle(val view: View, val dispose: () -> Unit)

/**
 * Creates a [RendererHandle] for a stream of type [S], or null if a renderer could
 * not be created. The production implementation is [AcsRendererFactory] (with
 * `S = RemoteVideoStream`); tests inject a fake parameterised on a trivial stream
 * type (e.g. `String`) that returns a plain [View] handle, so the registry's
 * cap/backfill bookkeeping runs without the native ACS renderer — and without having
 * to mock the final ACS `RemoteVideoStream` class.
 */
fun interface RendererFactory<S> {
    fun create(stream: S, context: Context): RendererHandle?
}

/**
 * Production [RendererFactory] that builds a real ACS [VideoStreamRenderer] and a FIT
 * view for it. This is the ONLY place the registry path touches the ACS renderer API,
 * which is what keeps the registry itself unit-testable.
 */
class AcsRendererFactory : RendererFactory<RemoteVideoStream> {
    override fun create(stream: RemoteVideoStream, context: Context): RendererHandle? {
        return try {
            val renderer = VideoStreamRenderer(stream, context)
            val view = renderer.createView(CreateViewOptions(ScalingMode.FIT))
            RendererHandle(view) { renderer.dispose() }
        } catch (e: Exception) {
            Log.e("ACS", "[AcsRendererFactory] renderer create failed", e)
            null
        }
    }
}

/**
 * Registry of per-participant video tiles for the multi-participant grid path on
 * Android.
 *
 * Responsibility: own one container [FrameLayout] per participant (keyed by the ACS
 * `identifier.rawId`) and, when that participant has an available remote video
 * stream, own a dedicated renderer ([RendererHandle]) embedded in the container.
 * Independent of [VideoStreamRegistry] (which drives the legacy shared
 * `remoteVideoView` grid), so the two surfaces coexist: a stream may be rendered both
 * in the shared grid and in a per-participant tile via two separate renderers.
 *
 * Lifecycle / invariants:
 * - [containerForParticipant] is called by the platform-view factory when an
 *   `AcsRemoteVideoView(participantId:)` widget mounts; returns (creating if needed)
 *   a stable container so Flutter always has a view to show.
 * - [attach] is called when the participant's stream becomes available;
 *   [detach] tears the renderer down (container kept); [dispose] removes the tile.
 * - At most [MAX_RENDERERS] (9, the ACS native simultaneous-render limit) renderers
 *   exist concurrently; attach beyond the cap is queued FIFO and promoted when a slot
 *   frees (see [backfillFreedSlot]).
 *
 * All methods are posted to the main thread.
 *
 * @param S The stream type; `RemoteVideoStream` in production (see [AcsRendererFactory]).
 * @param context Android context used to build tile containers.
 * @param rendererFactory Builds the per-tile renderer. Injected so tests can
 *   substitute a fake (parameterised on a trivial stream type) and exercise the
 *   cap/backfill bookkeeping without the native ACS renderer.
 */
class ParticipantVideoRegistry<S>(
    private val context: Context,
    private val rendererFactory: RendererFactory<S>,
) {

    private data class Holder(
        val container: FrameLayout,
        var handle: RendererHandle? = null,
    )

    private val holders = mutableMapOf<String, Holder>()
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Participants whose [attach] was refused because the [MAX_RENDERERS] cap was
     * reached, in arrival order (LinkedHashMap = FIFO). When a renderer slot frees
     * up ([detach]/[dispose]), the oldest waiter is attached automatically so a
     * >9th participant gets video as soon as capacity exists instead of waiting
     * for the next stream event. Main-thread only, like all registry state.
     */
    private val pendingAttach = LinkedHashMap<String, S>()

    /**
     * Returns the stable container for a participant, creating an empty one on first
     * request so the platform view always has something to display. Must run on main.
     */
    fun containerForParticipant(participantId: String): FrameLayout {
        var result: FrameLayout? = null
        runOnMainSync {
            val existing = holders[participantId]
            if (existing != null) {
                result = existing.container
                return@runOnMainSync
            }
            val container = FrameLayout(context)
            holders[participantId] = Holder(container = container)
            result = container
        }
        // containerForParticipant is invoked from the platform-view factory on the
        // main thread, so runOnMainSync executes inline and result is set.
        return result ?: FrameLayout(context)
    }

    /** True if a renderer is currently attached for the participant. */
    fun isRendering(participantId: String): Boolean = holders[participantId]?.handle != null

    /** True if any tile (container) exists for the participant. */
    fun hasContainer(participantId: String): Boolean = holders.containsKey(participantId)

    /** Snapshot of participant ids that currently have a mounted tile. */
    fun mountedParticipantIds(): List<String> = holders.keys.toList()

    /**
     * Attaches a remote video stream to the participant's tile, creating a dedicated
     * renderer (via [rendererFactory]) and embedding its view. No-ops if no container
     * is mounted, a renderer is already attached, or the concurrent-renderer cap is
     * reached (queued instead).
     */
    fun attach(participantId: String, stream: S) {
        runOnMain {
            try {
                val holder = holders[participantId] ?: return@runOnMain
                if (holder.handle != null) return@runOnMain

                val activeRenderers = holders.values.count { it.handle != null }
                if (activeRenderers >= MAX_RENDERERS) {
                    // Queue instead of dropping: the participant is attached
                    // automatically when a slot frees (see backfillFreedSlot).
                    pendingAttach[participantId] = stream
                    Log.w(TAG, "[ParticipantVideoRegistry] renderer cap ($MAX_RENDERERS) reached; queued $participantId")
                    return@runOnMain
                }
                // Attaching now — drop any stale queue entry for this participant.
                pendingAttach.remove(participantId)

                // Build the renderer via the injected factory. A null result means
                // creation failed; the slot is NOT consumed so a later stream event
                // (or backfill) can retry.
                val handle = rendererFactory.create(stream, context) ?: return@runOnMain
                (handle.view.parent as? ViewGroup)?.removeView(handle.view)
                holder.container.removeAllViews()
                holder.container.addView(
                    handle.view,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                )
                holder.handle = handle
            } catch (e: Exception) {
                Log.e(TAG, "[ParticipantVideoRegistry] attach failed for $participantId", e)
            }
        }
    }

    /**
     * Detaches the renderer for a participant but keeps the (empty) container so the
     * tile can re-attach when the stream becomes available again.
     */
    fun detach(participantId: String) {
        runOnMain {
            try {
                val holder = holders[participantId] ?: return@runOnMain
                holder.container.removeAllViews()
                holder.handle?.dispose?.invoke()
                holder.handle = null
                // A renderer slot just freed — promote the oldest waiter, if any.
                backfillFreedSlot()
            } catch (e: Exception) {
                Log.e(TAG, "[ParticipantVideoRegistry] detach failed for $participantId", e)
            }
        }
    }

    /**
     * Attaches the oldest queued participant (FIFO) when renderer capacity exists.
     * Skips (and drops) waiters whose tile was disposed while queued. Runs on the
     * main thread by virtue of being called only from [detach]/[dispose] blocks.
     */
    private fun backfillFreedSlot() {
        while (pendingAttach.isNotEmpty()) {
            val activeRenderers = holders.values.count { it.handle != null }
            if (activeRenderers >= MAX_RENDERERS) return
            val (waiterId, waiterStream) = pendingAttach.entries.first()
            pendingAttach.remove(waiterId)
            // Tile gone while queued → drop and try the next waiter.
            if (!holders.containsKey(waiterId)) continue
            Log.i(TAG, "[ParticipantVideoRegistry] backfilling freed slot with $waiterId")
            attach(waiterId, waiterStream)
            return
        }
    }

    /** Removes a participant's tile entirely. Called when the platform view disposes. */
    fun dispose(participantId: String) {
        runOnMain {
            try {
                pendingAttach.remove(participantId)
                val holder = holders.remove(participantId) ?: return@runOnMain
                holder.container.removeAllViews()
                val hadRenderer = holder.handle != null
                holder.handle?.dispose?.invoke()
                // Slot freed by tile removal — promote the oldest waiter, if any.
                if (hadRenderer) backfillFreedSlot()
            } catch (e: Exception) {
                Log.e(TAG, "[ParticipantVideoRegistry] dispose failed for $participantId", e)
            }
        }
    }

    /** Tears down all tiles and renderers (call cleanup). */
    fun clear() {
        runOnMain {
            try {
                holders.values.forEach { holder ->
                    holder.container.removeAllViews()
                    holder.handle?.dispose?.invoke()
                }
                holders.clear()
                pendingAttach.clear()
            } catch (e: Exception) {
                Log.e(TAG, "[ParticipantVideoRegistry] clear failed", e)
            }
        }
    }

    private fun runOnMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) action() else mainHandler.post(action)
    }

    private fun runOnMainSync(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            // Factory create() runs on the platform-views (main) thread, so this
            // branch is not expected; post as a defensive fallback.
            mainHandler.post(action)
        }
    }

    private companion object {
        private const val TAG = "ACS"
        private const val MAX_RENDERERS = 9
    }
}

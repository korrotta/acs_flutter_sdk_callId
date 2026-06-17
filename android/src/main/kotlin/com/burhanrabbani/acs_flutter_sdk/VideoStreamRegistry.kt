package com.burhanrabbani.acs_flutter_sdk

import android.content.Context
import android.util.Log
import com.azure.android.communication.calling.CreateViewOptions
import com.azure.android.communication.calling.RemoteVideoStream
import com.azure.android.communication.calling.ScalingMode
import com.azure.android.communication.calling.VideoStreamRenderer
import com.azure.android.communication.calling.VideoStreamRendererView

/**
 * Tracks active remote video renderers so they can be disposed safely.
 */
class VideoStreamRegistry(private val context: Context) {

    private val streams = mutableMapOf<Int, StreamHolder>()

    @Synchronized
    fun start(stream: RemoteVideoStream): VideoStreamRendererView? {
        return try {
            val existing = streams[stream.id]
            if (existing != null) {
                return existing.rendererView
            }

            val renderer = VideoStreamRenderer(stream, context)
            val rendererView = renderer.createView(CreateViewOptions(ScalingMode.FIT))
            streams[stream.id] = StreamHolder(renderer, rendererView)
            rendererView
        } catch (e: Exception) {
            Log.e(TAG, "[VideoStreamRegistry] start failed for streamId=${stream.id}", e)
            null
        }
    }

    @Synchronized
    fun stop(streamId: Int) {
        try {
            streams.remove(streamId)?.let { holder ->
                holder.rendererView = null
                holder.renderer.dispose()
            }
        } catch (e: Exception) {
            Log.e(TAG, "[VideoStreamRegistry] stop failed for streamId=$streamId", e)
        }
    }

    @Synchronized
    fun clear() {
        try {
            streams.values.forEach { holder ->
                holder.renderer.dispose()
            }
            streams.clear()
        } catch (e: Exception) {
            Log.e(TAG, "[VideoStreamRegistry] clear failed", e)
        }
    }

    private data class StreamHolder(
        val renderer: VideoStreamRenderer,
        var rendererView: VideoStreamRendererView?
    )

    private companion object {
        private const val TAG = "ACS"
    }
}

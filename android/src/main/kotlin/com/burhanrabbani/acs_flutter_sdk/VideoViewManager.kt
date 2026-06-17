package com.burhanrabbani.acs_flutter_sdk

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.GridLayout
import com.azure.android.communication.calling.CreateViewOptions
import com.azure.android.communication.calling.LocalVideoStream
import com.azure.android.communication.calling.ScalingMode
import com.azure.android.communication.calling.VideoStreamRenderer

/**
 * Holds local and remote video containers and provides helpers to manage them.
 */
class VideoViewManager(context: Context) {
    val localContainer: GridLayout = GridLayout(context)
    val remoteContainer: GridLayout = GridLayout(context).apply {
        rowCount = 2
        columnCount = 2
        useDefaultMargins = false
    }
    private var previewRenderer: VideoStreamRenderer? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun showLocalPreview(context: Context, stream: LocalVideoStream?) {
        if (stream == null) return
        runOnMain {
            try {
                if (previewRenderer != null) return@runOnMain
                previewRenderer = VideoStreamRenderer(stream, context).also { renderer ->
                    val previewView = renderer.createView(CreateViewOptions(ScalingMode.FIT))
                    previewView.tag = LOCAL_PREVIEW_TAG
                    localContainer.removeAllViews()
                    // Fill the cell so the renderer view is sized at attach (avoids the
                    // zero-sized GridLayout WRAP_CONTENT child → black preview).
                    localContainer.addView(previewView, fillCellParams())
                }
                Unit
            } catch (e: Exception) {
                Log.e(TAG, "[VideoViewManager] showLocalPreview failed", e)
                Unit
            }
        }
    }

    fun clearLocalPreview() {
        runOnMain {
            try {
                previewRenderer?.let { renderer ->
                    renderer.dispose()
                    previewRenderer = null
                }
                localContainer.removeAllViews()
                Unit
            } catch (e: Exception) {
                Log.e(TAG, "[VideoViewManager] clearLocalPreview failed", e)
                Unit
            }
        }
    }

    fun addRemoteView(activity: Activity?, streamId: Int, view: View) {
        val addAction: () -> Unit = {
            try {
                view.tag = streamId
                // Detach from any existing parent to avoid IllegalStateException when re-adding.
                (view.parent as? ViewGroup)?.removeView(view)

                // Ensure only one view per stream ID inside the container.
                for (index in remoteContainer.childCount - 1 downTo 0) {
                    val child = remoteContainer.getChildAt(index)
                    if (child?.tag == streamId && child !== view) {
                        remoteContainer.removeViewAt(index)
                    }
                }

                // Fill the cell so the renderer view is sized at attach (avoids the
                // zero-sized GridLayout WRAP_CONTENT child → black remote video).
                remoteContainer.addView(view, fillCellParams())
                rebalanceGrid()
                Unit
            } catch (e: Exception) {
                Log.e(TAG, "[VideoViewManager] addRemoteView failed for streamId=$streamId", e)
                Unit
            }
        }
        if (activity != null) {
            activity.runOnUiThread(addAction)
        } else {
            runOnMain(addAction)
        }
    }

    fun removeRemoteView(activity: Activity?, streamId: Int) {
        val removeAction: () -> Unit = {
            try {
                for (index in 0 until remoteContainer.childCount) {
                    val child = remoteContainer.getChildAt(index)
                    if (child?.tag == streamId) {
                        remoteContainer.removeViewAt(index)
                        break
                    }
                }
                rebalanceGrid()
                Unit
            } catch (e: Exception) {
                Log.e(TAG, "[VideoViewManager] removeRemoteView failed for streamId=$streamId", e)
                Unit
            }
        }
        if (activity != null) {
            activity.runOnUiThread { removeAction() }
        } else {
            runOnMain(removeAction)
        }
    }

    fun clearRemoteViews() {
        runOnMain {
            try {
                remoteContainer.removeAllViews()
                rebalanceGrid()
                Unit
            } catch (e: Exception) {
                Log.e(TAG, "[VideoViewManager] clearRemoteViews failed", e)
                Unit
            }
        }
    }

    /**
     * Builds GridLayout params that make a child FILL its cell. A GridLayout child added
     * with no params defaults to WRAP_CONTENT; an ACS renderer view has zero intrinsic
     * size before its first decoded frame, so it would resolve to a ~0x0 cell at attach
     * and the decoder surface starts against a zero-sized view (the "remote/local video
     * stays black" class of bug). Weight 1 on both axes + FILL gravity stretches the view
     * to the cell, mirroring the per-participant tile path (FrameLayout MATCH_PARENT).
     *
     * A fresh instance is returned per child — LayoutParams must not be shared.
     */
    private fun fillCellParams(): GridLayout.LayoutParams =
        GridLayout.LayoutParams().apply {
            width = 0
            height = 0
            rowSpec = GridLayout.spec(GridLayout.UNDEFINED, 1f)
            columnSpec = GridLayout.spec(GridLayout.UNDEFINED, 1f)
            setGravity(Gravity.FILL)
        }

    private fun rebalanceGrid() {
        try {
            val count = remoteContainer.childCount.coerceAtLeast(1)
            val columns = kotlin.math.ceil(kotlin.math.sqrt(count.toDouble())).toInt().coerceAtLeast(1)
            val rows = kotlin.math.ceil(count.toDouble() / columns).toInt().coerceAtLeast(1)
            remoteContainer.columnCount = columns
            remoteContainer.rowCount = rows
            Unit
        } catch (e: Exception) {
            Log.e(TAG, "[VideoViewManager] rebalanceGrid failed", e)
            Unit
        }
    }

    private fun runOnMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            mainHandler.post(action)
        }
    }

    companion object {
        private const val LOCAL_PREVIEW_TAG = "local_preview"
        private const val TAG = "ACS"
    }
}

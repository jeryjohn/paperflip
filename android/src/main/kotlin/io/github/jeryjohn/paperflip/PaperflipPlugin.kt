package io.github.jeryjohn.paperflip

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.Window
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel

class PaperflipPlugin : FlutterPlugin, ActivityAware, EventChannel.StreamHandler {
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var activity: Activity? = null
    private var originalCallback: Window.Callback? = null
    private var isIntercepting: Boolean = false
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        eventChannel = EventChannel(binding.binaryMessenger, CHANNEL_NAME)
        eventChannel?.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        eventChannel?.setStreamHandler(null)
        eventChannel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        if (eventSink != null) {
            startIntercepting()
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        stopIntercepting()
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        if (eventSink != null) {
            startIntercepting()
        }
    }

    override fun onDetachedFromActivity() {
        stopIntercepting()
        activity = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        startIntercepting()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        stopIntercepting()
    }

    private fun startIntercepting() {
        if (isIntercepting) return
        val currentActivity = activity ?: return
        val window = currentActivity.window ?: return
        val currentCallback = window.callback ?: return
        originalCallback = currentCallback
        window.callback = VolumeKeyCallback(currentCallback) { direction ->
            mainHandler.post {
                eventSink?.success(direction)
            }
        }
        isIntercepting = true
    }

    private fun stopIntercepting() {
        if (!isIntercepting) return
        val currentActivity = activity
        val savedOriginal = originalCallback
        if (currentActivity != null && savedOriginal != null) {
            val window = currentActivity.window
            if (window != null && window.callback is VolumeKeyCallback) {
                window.callback = savedOriginal
            }
        }
        originalCallback = null
        isIntercepting = false
    }

    private class VolumeKeyCallback(
        private val delegate: Window.Callback,
        private val onVolumeKey: (String) -> Unit
    ) : Window.Callback by delegate {

        override fun dispatchKeyEvent(event: KeyEvent?): Boolean {
            if (event != null) {
                val keyCode = event.keyCode
                if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
                    if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                        val direction = if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down"
                        onVolumeKey(direction)
                    }
                    // Consume both ACTION_DOWN and ACTION_UP (and repeats) so system volume does not change
                    return true
                }
            }
            return delegate.dispatchKeyEvent(event)
        }
    }

    companion object {
        const val CHANNEL_NAME = "io.github.jeryjohn.paperflip/volume_keys"
    }
}

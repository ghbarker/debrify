package com.debrify.app.memory

import android.app.ActivityManager
import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Fresh OS headroom for the optional decoded-artwork cache allowance. */
internal object DeviceMemoryChannel {
    fun register(engine: FlutterEngine, context: Context) {
        val application = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.debrify.app/memory")
            .setMethodCallHandler { call, result ->
                if (call.method != "getMemoryInfo") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val manager = application.getSystemService(Context.ACTIVITY_SERVICE)
                        as? ActivityManager
                    if (manager == null) {
                        result.error("memory_unavailable", "Memory information is unavailable", null)
                        return@setMethodCallHandler
                    }
                    val info = ActivityManager.MemoryInfo()
                    manager.getMemoryInfo(info)
                    result.success(mapOf(
                        "availableBytes" to info.availMem,
                        "totalBytes" to info.totalMem,
                        "thresholdBytes" to info.threshold,
                        "lowMemory" to info.lowMemory,
                        "lowRamDevice" to manager.isLowRamDevice,
                    ))
                } catch (_: Exception) {
                    // Dart retains the conservative allowance when this read fails.
                    result.error("memory_unavailable", "Memory information is unavailable", null)
                }
            }
    }
}

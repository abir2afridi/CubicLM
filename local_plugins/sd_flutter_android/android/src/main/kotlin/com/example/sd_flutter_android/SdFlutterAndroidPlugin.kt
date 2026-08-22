package com.example.sd_flutter_android

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*

class SdFlutterAndroidPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private var context: Context? = null
  private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

  // Callback object passed to JNI; JNI calls onProgress(step, total) from worker threads
  inner class ProgressCallback {
    fun onProgress(step: Int, total: Int) {
      // Marshal back to main thread for MethodChannel
      CoroutineScope(Dispatchers.Main).launch {
        channel.invokeMethod("onProgress", mapOf("step" to step, "total" to total))
      }
    }
  }

  // Native methods (linked to sd_jni_wrapper.cpp)
  private external fun detectGpuVendorNative(): String
  private external fun initModel(path: String, useGpu: Boolean): Boolean
  private external fun generateImage(prompt: String, steps: Int, callback: ProgressCallback): ByteArray?
  private external fun unloadModel()

  /**
   * Detect GPU vendor without requiring a Vulkan or GL context.
   * Falls back to sysfs probing and Build.HARDWARE heuristics.
   */
  private fun detectGpuVendor(): String {
    val vendor = detectGpuVendorNative()
    if (vendor != "unknown") {
      return vendor
    }

    // 1. Adreno via kgsl sysfs (Qualcomm devices)
    try {
      val kgslModel = java.io.File("/sys/class/kgsl/kgsl-3d0/gpu_model").readText().trim().lowercase()
      if (kgslModel.contains("adreno")) {
        return "adreno"
      }
    } catch (_: Exception) { }

    // 2. Mali via sysfs
    try {
      java.io.File("/sys/class/misc/mali0/device/clock").readText().trim()
      return "mali"
    } catch (_: Exception) { }

    try {
      java.io.File("/sys/class/misc/mali0/device/utgard_clock").readText().trim()
      return "mali"
    } catch (_: Exception) { }

    // 3. Hardware heuristic fallback
    val hw = Build.HARDWARE.lowercase()
    val board = Build.BOARD.lowercase()
    val hardwareText = "$hw $board"
    return when {
      hardwareText.contains("qcom") || hardwareText.contains("sdm") || hardwareText.contains("sm8") || hardwareText.contains("sm7") -> "adreno"
      hardwareText.contains("exynos") || hardwareText.contains("s5e") -> "xclipse"
      hardwareText.contains("gs1") || hardwareText.contains("mt6") || hardwareText.contains("mt") || hardwareText.contains("unisoc") -> "mali"
      else -> "unknown"
    }
  }

  init {
    System.loadLibrary("sd_jni")
  }

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "sd_flutter_android")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "getPlatformVersion" -> {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
      }
      "detectGpuVendor" -> {
        scope.launch {
          try {
            val vendor = detectGpuVendor()
            withContext(Dispatchers.Main) { result.success(vendor) }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) { result.error("DETECT_FAILED", e.message, null) }
          }
        }
      }
      "getDeviceMemory" -> {
        scope.launch {
          try {
            val memInfo = ActivityManager.MemoryInfo()
            val am = context?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            am?.getMemoryInfo(memInfo)
            val totalMb = (memInfo.totalMem / (1024 * 1024)).toInt()
            withContext(Dispatchers.Main) { result.success(totalMb) }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) { result.error("MEMORY_FAILED", e.message, null) }
          }
        }
      }
      "getAvailableMemory" -> {
        scope.launch {
          try {
            val memInfo = ActivityManager.MemoryInfo()
            val am = context?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            am?.getMemoryInfo(memInfo)
            val availableMb = (memInfo.availMem / (1024 * 1024)).toInt()
            withContext(Dispatchers.Main) { result.success(availableMb) }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) { result.error("MEMORY_FAILED", e.message, null) }
          }
        }
      }
      "initModel" -> {
        val path = call.argument<String>("path")
        val useGpu = call.argument<Boolean>("useGpu") ?: true
        if (path != null) {
          scope.launch {
            try {
              val success = initModel(path, useGpu)
              withContext(Dispatchers.Main) { result.success(success) }
            } catch (e: Exception) {
              withContext(Dispatchers.Main) { result.error("INIT_FAILED", e.message, null) }
            }
          }
        } else {
          result.error("INVALID_ARGUMENT", "Path is null", null)
        }
      }
      "generateImage" -> {
        val prompt = call.argument<String>("prompt")
        val steps = call.argument<Int>("steps") ?: 20
        if (prompt != null) {
          scope.launch {
            try {
              val callback = ProgressCallback()
              val bytes = generateImage(prompt, steps, callback)
              withContext(Dispatchers.Main) {
                if (bytes != null) {
                  result.success(bytes)
                } else {
                  result.error("GENERATION_FAILED", "Image generation returned null", null)
                }
              }
            } catch (e: Exception) {
              withContext(Dispatchers.Main) {
                result.error("GENERATION_FAILED", e.message, null)
              }
            }
          }
        } else {
          result.error("INVALID_ARGUMENT", "Prompt is null", null)
        }
      }
      "unloadModel" -> {
        scope.launch {
          try {
            unloadModel()
            withContext(Dispatchers.Main) { result.success(null) }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) { result.error("UNLOAD_FAILED", e.message, null) }
          }
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    scope.cancel()
  }
}

package com.write4me.llama_flutter_android

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicBoolean

class LlamaFlutterAndroidPlugin : FlutterPlugin, LlamaHostApi {
    private lateinit var context: Context
    private lateinit var flutterApi: LlamaFlutterApi
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var generationJob: Job? = null
    private val isStopping = AtomicBoolean(false)
    private val loadMutex = Mutex()
    private var nativeLoadError: Throwable? = null

    // ── Multi-model residency bookkeeping ────────────────────────────────────
    // The C++ layer keeps MAX_SLOTS models resident; this map tracks which
    // path lives in which slot so repeat loads become instant switches.
    companion object {
        private const val TAG = "LlamaFlutterPlugin"
        private const val MAX_SLOTS = 2
        private const val MULTI_CHANNEL = "llama_flutter_android/multimodel"
    }
    private val slotPaths = arrayOfNulls<String?>(MAX_SLOTS)
    private val lruOrder = mutableListOf<String>()   // least → most recently used
    @Volatile private var activePath: String? = null
    private lateinit var multiChannel: MethodChannel

    private fun slotIndexOf(path: String): Int =
        slotPaths.indexOfFirst { it == path }

    private fun touchLru(path: String) {
        lruOrder.remove(path)
        lruOrder.add(path)
    }

    private fun removeFromLru(path: String) {
        lruOrder.remove(path)
    }

    /// True only when the tracked active path maps to a genuinely loaded
    /// native slot. Repairs bookkeeping when the two layers disagree.
    private fun activeSlotValid(): Boolean {
        val p = activePath ?: return false
        val s = slotIndexOf(p)
        return s >= 0 && nativeIsSlotLoaded(s)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.i(TAG, "Attaching llama Flutter plugin")
        context = binding.applicationContext
        flutterApi = LlamaFlutterApi(binding.binaryMessenger)
        LlamaHostApi.setUp(binding.binaryMessenger, this)

        // Plain MethodChannel for multi-model residency control (kept outside
        // the Pigeon API so the generated interfaces stay untouched).
        multiChannel = MethodChannel(binding.binaryMessenger, MULTI_CHANNEL)
        multiChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "residentModels" -> result.success(slotPaths.filterNotNull())
                    "activeModel" -> result.success(activePath)
                    "switchTo" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("invalid_args", "path is required", null)
                            return@setMethodCallHandler
                        }
                        // Only succeed when the model is genuinely resident —
                        // never claim success for an unknown path, or Dart
                        // will skip the real load and native will throw.
                        val slot = slotIndexOf(path)
                        if (slot >= 0 && nativeIsSlotLoaded(slot) && nativeSelectSlot(slot)) {
                            activePath = path
                            touchLru(path)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "freeByPath" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("invalid_args", "path is required", null)
                            return@setMethodCallHandler
                        }
                        val slot = slotIndexOf(path)
                        if (slot >= 0) {
                            nativeFreeSlot(slot)
                            slotPaths[slot] = null
                            removeFromLru(path)
                            if (activePath == path) activePath = null
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("multi_model_error", t.message, null)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        scope.cancel()
        multiChannel.setMethodCallHandler(null)
        if (slotPaths.any { it != null }) {
            nativeFreeModel()
        }
        LlamaHostApi.setUp(binding.binaryMessenger, null)
    }

    override fun loadModel(config: ModelConfig, callback: (Result<Unit>) -> Unit) {
        ensureNativeLoaded()?.let {
            callback(Result.failure(it))
            return
        }

        scope.launch {
            try {
                loadMutex.withLock {
                    val requestedPath = config.modelPath

                    // ── Instant switch: model already resident ───────────
                    val residentSlot = slotIndexOf(requestedPath)
                    if (residentSlot >= 0 && nativeIsSlotLoaded(residentSlot)) {
                        nativeSelectSlot(residentSlot)
                        activePath = requestedPath
                        touchLru(requestedPath)
                        Log.i(TAG, "Instant switch to resident slot $residentSlot: $requestedPath")
                        withContext(Dispatchers.Main) {
                            callback(Result.success(Unit))
                        }
                        return@launch
                    }

                    // Start foreground service for long-running task
                    val intent = Intent(context, InferenceService::class.java)
                    ContextCompat.startForegroundService(context, intent)

                    // ── Pick a slot: existing mapping → empty → LRU victim ──
                    var slot = slotIndexOf(requestedPath)
                    if (slot < 0) {
                        slot = slotPaths.indexOfFirst { it == null }
                        if (slot < 0) {
                            // Evict least-recently-used, never the active one
                            val victim = lruOrder.firstOrNull { it != activePath }
                                ?: lruOrder.firstOrNull()
                            slot = if (victim != null) slotIndexOf(victim) else 0
                            Log.i(TAG, "Pool full — evicting '$victim' from slot $slot")
                        }
                        if (slot < 0) slot = 0
                    }

                    // Load into the chosen slot; C++ frees that slot first.
                    // Other slots stay resident.
                    nativeLoadModel(
                        config.modelPath,
                        config.nThreads,
                        config.contextSize,
                        config.nGpuLayers ?: 0L,
                        slot
                    ) { progress ->
                        scope.launch {
                            withContext(Dispatchers.Main) {
                                flutterApi.onLoadProgress(progress) { result ->
                                    // Handle result if needed
                                }
                            }
                        }
                    }

                    slotPaths[slot] = requestedPath
                    activePath = requestedPath
                    touchLru(requestedPath)

                    withContext(Dispatchers.Main) {
                        callback(Result.success(Unit))
                    }
                }
            } catch (e: Exception) {
                scope.launch {
                    withContext(Dispatchers.Main) {
                        flutterApi.onError(e.message ?: "Failed to load model") { result ->
                            // Handle result if needed
                        }
                        callback(Result.failure(e))
                    }
                }
            }
        }
    }

    override fun generate(request: GenerateRequest, callback: (Result<Unit>) -> Unit) {
        ensureNativeLoaded()?.let {
            callback(Result.failure(it))
            return
        }

        if (!activeSlotValid()) {
            // Bookkeeping/native desync — repair instead of letting native throw.
            activePath = null
            callback(Result.failure(IllegalStateException("Model not loaded")))
            return
        }

        isStopping.set(false)
        generationJob = scope.launch {
            try {
                nativeGenerate(
                    request.prompt,
                    request.maxTokens,
                    request.temperature,
                    request.topP,
                    request.topK,
                    request.minP,
                    request.typicalP,
                    request.repeatPenalty,
                    request.frequencyPenalty,
                    request.presencePenalty,
                    request.repeatLastN,
                    request.mirostat,
                    request.mirostatTau,
                    request.mirostatEta,
                    request.seed ?: -1L,  // Use -1 for random seed
                    request.penalizeNewline
                ) { token ->
                    if (!isStopping.get()) {
                        scope.launch {
                            withContext(Dispatchers.Main) {
                                flutterApi.onToken(token) { result ->
                                    // Handle result if needed
                                }
                            }
                        }
                    }
                }

                if (!isStopping.get()) {
                    scope.launch {
                        withContext(Dispatchers.Main) {
                            flutterApi.onDone { result ->
                                // Handle result if needed
                            }
                        }
                    }
                }

                withContext(Dispatchers.Main) {
                    callback(Result.success(Unit))
                }
            } catch (e: Exception) {
                if (!isStopping.get()) {
                    scope.launch {
                        withContext(Dispatchers.Main) {
                            flutterApi.onError(e.message ?: "Generation failed") { result ->
                                // Handle result if needed
                            }
                            callback(Result.failure(e))
                        }
                    }
                }
            }
        }
    }

    override fun stop(callback: (Result<Unit>) -> Unit) {
        isStopping.set(true)
        generationJob?.cancel()
        if (nativeLoadError == null) {
            nativeStop()
        }
        callback(Result.success(Unit))
    }

    override fun dispose(callback: (Result<Unit>) -> Unit) {
        scope.launch {
            try {
                stop { }
                if (slotPaths.any { it != null }) {
                    nativeFreeModel()
                    slotPaths.fill(null)
                    lruOrder.clear()
                    activePath = null
                }

                // Stop foreground service
                val intent = Intent(context, InferenceService::class.java)
                context.stopService(intent)

                withContext(Dispatchers.Main) {
                    callback(Result.success(Unit))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    callback(Result.failure(e))
                }
            }
        }
    }

    override fun generateChat(request: ChatRequest, callback: (Result<Unit>) -> Unit) {
        ensureNativeLoaded()?.let {
            callback(Result.failure(it))
            return
        }

        if (!activeSlotValid()) {
            // Bookkeeping/native desync — repair instead of letting native throw.
            activePath = null
            callback(Result.failure(IllegalStateException("Model not loaded")))
            return
        }

        isStopping.set(false)
        generationJob = scope.launch {
            try {
                // Format the chat messages using the template manager
                val formattedPrompt = ChatTemplateManager.formatMessages(
                    request.messages.map { msg -> TemplateChatMessage(msg.role, msg.content) },
                    request.template,
                    activePath
                )

                nativeGenerate(
                    formattedPrompt,
                    request.maxTokens.toLong(),
                    request.temperature.toDouble(),
                    request.topP.toDouble(),
                    request.topK.toLong(),
                    request.minP.toDouble(),
                    request.typicalP.toDouble(),
                    request.repeatPenalty.toDouble(),
                    request.frequencyPenalty.toDouble(),
                    request.presencePenalty.toDouble(),
                    request.repeatLastN.toLong(),
                    request.mirostat.toLong(),
                    request.mirostatTau.toDouble(),
                    request.mirostatEta.toDouble(),
                    request.seed ?: -1L,  // Use -1 for random seed
                    request.penalizeNewline
                ) { token ->
                    if (!isStopping.get()) {
                        scope.launch {
                            withContext(Dispatchers.Main) {
                                flutterApi.onToken(token) { result ->
                                    // Handle result if needed
                                }
                            }
                        }
                    }
                }

                if (!isStopping.get()) {
                    scope.launch {
                        withContext(Dispatchers.Main) {
                            flutterApi.onDone { result ->
                                // Handle result if needed
                            }
                        }
                    }
                }

                withContext(Dispatchers.Main) {
                    callback(Result.success(Unit))
                }
            } catch (e: Exception) {
                if (!isStopping.get()) {
                    scope.launch {
                        withContext(Dispatchers.Main) {
                            flutterApi.onError(e.message ?: "Generation failed") { result ->
                                // Handle result if needed
                            }
                            callback(Result.failure(e))
                        }
                    }
                }
            }
        }
    }

    override fun getSupportedTemplates(): List<String> {
        return ChatTemplateManager.getSupportedTemplates()
    }

    override fun isModelLoaded(): Boolean {
        return activePath != null
    }

    override fun getContextInfo(): ContextInfo {
        ensureNativeLoaded()?.let { throw it }

        val tokensUsed = nativeGetTokensUsed().toLong()
        val contextSize = nativeGetContextSize().toLong()
        val usagePercentage = if (contextSize > 0) {
            (tokensUsed.toDouble() / contextSize.toDouble() * 100.0)
        } else {
            0.0
        }
        
        return ContextInfo(
            tokensUsed = tokensUsed,
            contextSize = contextSize,
            usagePercentage = usagePercentage
        )
    }

    override fun clearContext(callback: (Result<Unit>) -> Unit) {
        ensureNativeLoaded()?.let {
            callback(Result.failure(it))
            return
        }

        scope.launch {
            try {
                nativeClearContext()
                withContext(Dispatchers.Main) {
                    callback(Result.success(Unit))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    callback(Result.failure(e))
                }
            }
        }
    }

    override fun setSystemPromptLength(length: Long) {
        ensureNativeLoaded()?.let { throw it }
        nativeSetSystemPromptLength(length.toInt())
    }

    /**
     * Register a custom chat template
     * Allows users to provide their own template format at runtime
     */
    override fun registerCustomTemplate(name: String, content: String) {
        ChatTemplateManager.registerCustomTemplate(name, content)
    }

    /**
     * Unregister a custom chat template
     * Removes a previously registered custom template
     */
    override fun unregisterCustomTemplate(name: String) {
        ChatTemplateManager.unregisterCustomTemplate(name)
    }

    override fun detectGpu(callback: (Result<GpuInfo>) -> Unit) {
        ensureNativeLoaded()?.let {
            callback(Result.failure(it))
            return
        }

        scope.launch {
            try {
                val outStats = LongArray(2) { -1L }
                val gpuName: String? = nativeDetectGpu(outStats)
                val vulkanSupported = gpuName != null
                val apiVersion = outStats[0]
                val deviceLocalMemory = outStats[1]

                val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val memInfo = ActivityManager.MemoryInfo()
                activityManager.getMemoryInfo(memInfo)
                val freeRamBytes = memInfo.availMem

                val recommendedGpuLayers = computeRecommendedLayers(
                    vulkanSupported = vulkanSupported,
                    gpuName = gpuName ?: "",
                    freeRamBytes = freeRamBytes,
                    deviceLocalMemoryBytes = deviceLocalMemory
                )

                withContext(Dispatchers.Main) {
                    callback(Result.success(GpuInfo(
                        vulkanSupported = vulkanSupported,
                        gpuName = gpuName ?: "None",
                        vulkanApiVersion = apiVersion,
                        deviceLocalMemoryBytes = deviceLocalMemory,
                        freeRamBytes = freeRamBytes,
                        recommendedGpuLayers = recommendedGpuLayers.toLong()
                    )))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    callback(Result.success(GpuInfo(
                        vulkanSupported = false,
                        gpuName = "None",
                        vulkanApiVersion = -1L,
                        deviceLocalMemoryBytes = -1L,
                        freeRamBytes = -1L,
                        recommendedGpuLayers = 0L
                    )))
                }
            }
        }
    }

    private fun ensureNativeLoaded(): Throwable? {
        nativeLoadError?.let { return it }

        return try {
            System.loadLibrary("llama_jni")
            null
        } catch (t: Throwable) {
            nativeLoadError = t
            Log.e(TAG, "Failed to load llama native library", t)
            IllegalStateException("Failed to load llama native library: ${t.message}", t)
        }
    }

    private fun computeRecommendedLayers(
        vulkanSupported: Boolean,
        gpuName: String,
        freeRamBytes: Long,
        deviceLocalMemoryBytes: Long
    ): Int {
        val GB = 1_073_741_824L
        val safeRam = (freeRamBytes * 0.7).toLong()
        return when {
            !vulkanSupported -> 0
            gpuName.contains("Mali", ignoreCase = true) -> 0
            safeRam < GB -> 0                                          // < 1 GB — truly too low
            safeRam < 2 * GB && deviceLocalMemoryBytes < 3 * GB -> 0  // low RAM + low VRAM
            safeRam < 3 * GB || deviceLocalMemoryBytes < 2 * GB -> 16 // partial offload
            else -> 99                                                  // full offload
        }
    }

    // Native methods
    private external fun nativeLoadModel(
        path: String,
        nThreads: Long,
        contextSize: Long,
        nGpuLayers: Long,
        slot: Int,
        progressCallback: (Double) -> Unit
    )

    private external fun nativeGenerate(
        prompt: String,
        maxTokens: Long,
        temperature: Double,
        topP: Double,
        topK: Long,
        minP: Double,
        typicalP: Double,
        repeatPenalty: Double,
        frequencyPenalty: Double,
        presencePenalty: Double,
        repeatLastN: Long,
        mirostat: Long,
        mirostatTau: Double,
        mirostatEta: Double,
        seed: Long,
        penalizeNewline: Boolean,
        tokenCallback: (String) -> Unit
    )

    private external fun nativeStop()
    private external fun nativeFreeModel()
    private external fun nativeSelectSlot(slot: Int): Boolean
    private external fun nativeIsSlotLoaded(slot: Int): Boolean
    private external fun nativeFreeSlot(slot: Int)
    private external fun nativeGetTokensUsed(): Int
    private external fun nativeGetContextSize(): Int
    private external fun nativeClearContext()
    private external fun nativeSetSystemPromptLength(length: Int)
    private external fun nativeDetectGpu(outStats: LongArray): String?
    // outStats[0] = vulkanApiVersion, outStats[1] = deviceLocalMemoryBytes
}

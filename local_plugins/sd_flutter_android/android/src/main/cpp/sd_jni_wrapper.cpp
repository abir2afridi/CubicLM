#include <jni.h>
#include <string>
#include <vector>
#include <algorithm>
#include <android/log.h>
#ifdef SD_JNI_HAVE_VULKAN
#include <vulkan/vulkan.h>
#endif
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <stdlib.h>
#include "stable-diffusion.h"

#define TAG "SD_JNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

static sd_ctx_t* g_sd_ctx = nullptr;
static JavaVM* g_jvm = nullptr;
static jobject g_progress_callback = nullptr;
static std::string g_model_path;

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_jvm = vm;
    return JNI_VERSION_1_6;
}

void sd_log_cb(enum sd_log_level_t level, const char* text, void* data) {
    LOGI("[SD Core] %s", text);
}

// Thread-local guard: attaches a native worker thread to the JVM once and
// automatically detaches it when the thread exits. This prevents the JNI
// thread-leak that crashes ART when stable-diffusion.cpp spawns many
// short-lived worker threads for inference.
struct JniEnvGuard {
    JNIEnv* env = nullptr;
    bool attached = false;

    ~JniEnvGuard() {
        if (attached && g_jvm) {
            g_jvm->DetachCurrentThread();
        }
    }

    JNIEnv* get() {
        if (env) {
            // Make sure we are still attached (in case something else detached us)
            JNIEnv* current = nullptr;
            if (g_jvm->GetEnv((void**)&current, JNI_VERSION_1_6) == JNI_OK) {
                return env;
            }
            env = nullptr;
            attached = false;
        }
        jint ret = g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6);
        if (ret == JNI_EDETACHED) {
            if (g_jvm->AttachCurrentThread(&env, nullptr) == JNI_OK) {
                attached = true;
            } else {
                env = nullptr;
            }
        } else if (ret != JNI_OK) {
            env = nullptr;
        }
        return env;
    }
};

void sd_progress_cb(int step, int steps, float time, void* data) {
    if (!g_progress_callback || !g_jvm) return;

    thread_local JniEnvGuard guard;
    JNIEnv* env = guard.get();
    if (!env) return;

    jclass clazz = env->GetObjectClass(g_progress_callback);
    if (!clazz) return;

    jmethodID method = env->GetMethodID(clazz, "onProgress", "(II)V");
    if (method) {
        env->CallVoidMethod(g_progress_callback, method, (jint)step, (jint)steps);
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
        }
    }
    env->DeleteLocalRef(clazz);
}

// ---------------------------------------------------------------------------
// Universal GPU vendor detection via EGL/GLES2 (works on all Android GPUs)
// ---------------------------------------------------------------------------
static std::string detectGpuViaEGL() {
    EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display == EGL_NO_DISPLAY) {
        return "";
    }
    if (eglInitialize(display, nullptr, nullptr) == EGL_FALSE) {
        return "";
    }

    EGLint attribs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };
    EGLConfig config;
    EGLint numConfigs = 0;
    if (eglChooseConfig(display, attribs, &config, 1, &numConfigs) == EGL_FALSE || numConfigs == 0) {
        eglTerminate(display);
        return "";
    }

    EGLint contextAttribs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttribs);
    if (context == EGL_NO_CONTEXT) {
        eglTerminate(display);
        return "";
    }

    EGLint pbufferAttribs[] = {EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE};
    EGLSurface pbuffer = eglCreatePbufferSurface(display, config, pbufferAttribs);
    if (pbuffer == EGL_NO_SURFACE) {
        eglDestroyContext(display, context);
        eglTerminate(display);
        return "";
    }

    if (eglMakeCurrent(display, pbuffer, pbuffer, context) == EGL_FALSE) {
        eglDestroySurface(display, pbuffer);
        eglDestroyContext(display, context);
        eglTerminate(display);
        return "";
    }

    const char* renderer = reinterpret_cast<const char*>(glGetString(GL_RENDERER));
    std::string result = renderer ? renderer : "";

    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroySurface(display, pbuffer);
    eglDestroyContext(display, context);
    eglTerminate(display);

    return result;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_sd_1flutter_1android_SdFlutterAndroidPlugin_detectGpuVendorNative(
    JNIEnv* env, jobject thiz) {

    // 1. Try EGL first — works on every Android device regardless of backend build flags
    std::string eglRenderer = detectGpuViaEGL();
    if (!eglRenderer.empty()) {
        std::string lower = eglRenderer;
        std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
        const char* vendor = "unknown";
        if (lower.find("adreno") != std::string::npos) {
            vendor = "adreno";
        } else if (lower.find("mali") != std::string::npos) {
            vendor = "mali";
        } else if (lower.find("powervr") != std::string::npos || lower.find("imagination") != std::string::npos) {
            vendor = "powervr";
        } else if (lower.find("nvidia") != std::string::npos || lower.find("tegra") != std::string::npos) {
            vendor = "nvidia";
        } else if (lower.find("intel") != std::string::npos) {
            vendor = "intel";
        } else if (lower.find("xclipse") != std::string::npos) {
            vendor = "xclipse";
        } else if (lower.find("amd") != std::string::npos || lower.find("radeon") != std::string::npos) {
            vendor = "amd";
        }
        LOGI("GPU vendor detected via EGL: %s (renderer: %s)", vendor, eglRenderer.c_str());
        return env->NewStringUTF(vendor);
    }

#ifdef SD_JNI_HAVE_VULKAN
    // 2. Fallback to Vulkan if compiled in
    VkInstance instance = VK_NULL_HANDLE;
    VkInstanceCreateInfo createInfo = {};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    VkResult result = vkCreateInstance(&createInfo, nullptr, &instance);
    if (result != VK_SUCCESS || instance == VK_NULL_HANDLE) {
        return env->NewStringUTF("unknown");
    }

    uint32_t deviceCount = 0;
    result = vkEnumeratePhysicalDevices(instance, &deviceCount, nullptr);
    if (result != VK_SUCCESS || deviceCount == 0) {
        vkDestroyInstance(instance, nullptr);
        return env->NewStringUTF("unknown");
    }

    std::vector<VkPhysicalDevice> devices(deviceCount);
    result = vkEnumeratePhysicalDevices(instance, &deviceCount, devices.data());
    if (result != VK_SUCCESS || deviceCount == 0) {
        vkDestroyInstance(instance, nullptr);
        return env->NewStringUTF("unknown");
    }

    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(devices[0], &props);
    std::string deviceName(props.deviceName);

    const char* vendor = "unknown";
    if (props.vendorID == 0x5143 || deviceName.find("Adreno") != std::string::npos) {
        vendor = "adreno";
    } else if (deviceName.find("Mali") != std::string::npos) {
        vendor = "mali";
    } else if (deviceName.find("NVIDIA") != std::string::npos || deviceName.find("GeForce") != std::string::npos) {
        vendor = "nvidia";
    } else if (deviceName.find("Radeon") != std::string::npos || deviceName.find("AMD") != std::string::npos) {
        vendor = "amd";
    }

    LOGI("GPU vendor detected via Vulkan: %s (device: %s)", vendor, deviceName.c_str());
    vkDestroyInstance(instance, nullptr);
    return env->NewStringUTF(vendor);
#else
    return env->NewStringUTF("unknown");
#endif
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_sd_1flutter_1android_SdFlutterAndroidPlugin_initModel(
    JNIEnv* env, jobject thiz, jstring model_path, jboolean use_gpu) {

    if (g_sd_ctx) {
        free_sd_ctx(g_sd_ctx);
        g_sd_ctx = nullptr;
    }

    const char* path = env->GetStringUTFChars(model_path, nullptr);
    g_model_path = path;

    sd_set_log_callback(sd_log_cb, nullptr);
    sd_set_progress_callback(sd_progress_cb, nullptr);

#ifdef SD_JNI_HAVE_VULKAN
    if (use_gpu == JNI_FALSE) {
        // Hide all Vulkan devices from ggml to force CPU fallback
        setenv("GGML_VK_VISIBLE_DEVICES", "", 1);
        LOGI("useGpu=false — forcing CPU fallback via GGML_VK_VISIBLE_DEVICES");
    } else {
        // Clear any previous CPU-fallback setting
        unsetenv("GGML_VK_VISIBLE_DEVICES");
        // Set conservative mobile Vulkan flags for stability
        setenv("GGML_VK_DISABLE_COOPMAT", "1", 1);
        setenv("GGML_VK_DISABLE_GRAPH_OPTIMIZE", "1", 1);
        setenv("GGML_VK_PREFER_HOST_MEMORY", "1", 1);
        LOGI("useGpu=true — enabling Vulkan with conservative mobile flags");
    }
#else
    (void)use_gpu; // unused when Vulkan is disabled
    LOGI("Vulkan not compiled in — using CPU only");
#endif

    sd_ctx_params_t params;
    sd_ctx_params_init(&params);
    params.model_path = path;

    // Limit threads on mobile to reduce memory pressure and thermal throttling.
    int cores = sd_get_num_physical_cores();
    params.n_threads = (cores > 4) ? 4 : cores;

    // Match iOS behaviour: keep buffers alive between generations.
    params.free_params_immediately = false;

    LOGI("Initializing SD model from: %s (threads=%d, useGpu=%d)", path, params.n_threads, use_gpu == JNI_TRUE ? 1 : 0);
    g_sd_ctx = new_sd_ctx(&params);

    env->ReleaseStringUTFChars(model_path, path);

    return g_sd_ctx != nullptr ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_example_sd_1flutter_1android_SdFlutterAndroidPlugin_generateImage(
    JNIEnv* env, jobject thiz, jstring prompt, jint steps, jobject callback) {

    if (!g_sd_ctx) {
        LOGE("SD context not initialized");
        return nullptr;
    }

    // Store callback as global ref so it remains valid across threads
    if (g_progress_callback) {
        env->DeleteGlobalRef(g_progress_callback);
    }
    g_progress_callback = env->NewGlobalRef(callback);

    const char* p_str = env->GetStringUTFChars(prompt, nullptr);

    sd_img_gen_params_t params;
    sd_img_gen_params_init(&params);
    params.prompt = p_str;
    params.sample_params.sample_steps = steps;
    params.width = 512;
    params.height = 512;
    params.sample_params.sample_method = EULER_A_SAMPLE_METHOD;

    // Distilled models (SDXS, LCM, etc.) break with standard CFG=7.0
    if (g_model_path.find("distilled") != std::string::npos ||
        g_model_path.find("sdxs") != std::string::npos ||
        g_model_path.find("lcm") != std::string::npos) {
        params.sample_params.guidance.txt_cfg = 1.0f;
        LOGI("Distilled model detected — using CFG=1.0");
    }

    LOGI("Generating image for prompt: %s", p_str);

    // Fire a step-0 callback immediately so the UI shows progress right away
    // (stable-diffusion.cpp only calls progress after step 1 completes)
    if (g_progress_callback && env) {
        jclass clazz = env->GetObjectClass(g_progress_callback);
        if (clazz) {
            jmethodID method = env->GetMethodID(clazz, "onProgress", "(II)V");
            if (method) {
                env->CallVoidMethod(g_progress_callback, method, 0, steps);
                if (env->ExceptionCheck()) env->ExceptionClear();
            }
            env->DeleteLocalRef(clazz);
        }
    }

    sd_image_t* result = generate_image(g_sd_ctx, &params);

    if (result) {
        LOGI("Image generated: %dx%d channels=%d", result->width, result->height, result->channel);
        if (result->channel >= 3 && result->data) {
            LOGI("First pixel RGB: %d %d %d", result->data[0], result->data[1], result->data[2]);
        }
    }

    env->ReleaseStringUTFChars(prompt, p_str);

    if (g_progress_callback) {
        env->DeleteGlobalRef(g_progress_callback);
        g_progress_callback = nullptr;
    }

    if (!result) {
        LOGE("Generation failed");
        return nullptr;
    }

    size_t size = result->width * result->height * result->channel;
    jbyteArray array = env->NewByteArray(size);
    if (!array) {
        LOGE("Failed to allocate ByteArray of size %zu (OOM?)", size);
        free(result->data);
        free(result);
        return nullptr;
    }
    env->SetByteArrayRegion(array, 0, size, (jbyte*)result->data);

    free(result->data);
    free(result);

    return array;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_sd_1flutter_1android_SdFlutterAndroidPlugin_unloadModel(
    JNIEnv* env, jobject thiz) {
    if (g_sd_ctx) {
        free_sd_ctx(g_sd_ctx);
        g_sd_ctx = nullptr;
    }
    if (g_progress_callback) {
        env->DeleteGlobalRef(g_progress_callback);
        g_progress_callback = nullptr;
    }
}

// ============================================================================
// C FFI exports for Dart FFI (no JNI / no MethodChannel)
// ============================================================================

// FFI context is separate from JNI global context so both APIs can coexist
// during the transition period.
static sd_ctx_t* g_ffi_sd_ctx = nullptr;
static std::string g_ffi_model_path;

// FFI callback function pointers (C-style, no JVM involved)
typedef void (*sd_ffi_progress_fn)(int step, int steps, float time);
typedef void (*sd_ffi_log_fn)(int level, const char* text);

static sd_ffi_progress_fn g_ffi_progress = nullptr;
static sd_ffi_log_fn g_ffi_log = nullptr;

static void sd_ffi_progress_trampoline(int step, int steps, float time, void* data) {
    if (g_ffi_progress) {
        g_ffi_progress(step, steps, time);
    }
}

static void sd_ffi_log_trampoline(enum sd_log_level_t level, const char* text, void* data) {
    if (g_ffi_log) {
        g_ffi_log((int)level, text);
    }
}

// Visibility macro to force-export symbols from the shared library
#if defined(__GNUC__) || defined(__clang__)
    #define SD_FFI_API __attribute__((visibility("default")))
#else
    #define SD_FFI_API
#endif

extern "C" {

// Set progress callback (C function pointer).
// Call with NULL to clear.
SD_FFI_API void sd_ffi_set_progress_callback(sd_ffi_progress_fn cb) {
    g_ffi_progress = cb;
    sd_set_progress_callback(cb ? sd_ffi_progress_trampoline : nullptr, nullptr);
}

// Set log callback (C function pointer).
// Call with NULL to clear.
SD_FFI_API void sd_ffi_set_log_callback(sd_ffi_log_fn cb) {
    g_ffi_log = cb;
    sd_set_log_callback(cb ? sd_ffi_log_trampoline : nullptr, nullptr);
}

// Extended init with full stable-diffusion.cpp parameter exposure.
// Paths may be NULL to use defaults / embedded components.
SD_FFI_API void* sd_ffi_init_ex(const char* model_path,
                                int n_threads,
                                bool flash_attn,
                                bool vae_tiling,
                                const char* taesd_path,
                                const char* vae_path,
                                const char* clip_l_path,
                                int wtype,
                                int backend,
                                bool offload_params_to_cpu,
                                bool enable_mmap,
                                bool keep_vae_on_cpu,
                                float max_vram) {
    if (g_ffi_sd_ctx) {
        free_sd_ctx(g_ffi_sd_ctx);
        g_ffi_sd_ctx = nullptr;
    }
    g_ffi_model_path = model_path ? model_path : "";

    // Backend selection via environment variables
    // backend: 0=CPU, 1=Vulkan, 2=OpenCL
    if (backend == 0) {
        // Force CPU: hide all Vulkan devices from ggml
        setenv("GGML_VK_VISIBLE_DEVICES", "", 1);
        LOGI("[FFI] Backend: CPU (forced via GGML_VK_VISIBLE_DEVICES)");
    } else if (backend == 1) {
        // Allow Vulkan with conservative mobile settings
        unsetenv("GGML_VK_VISIBLE_DEVICES");
        setenv("GGML_VK_DISABLE_COOPMAT", "1", 1);
        setenv("GGML_VK_DISABLE_GRAPH_OPTIMIZE", "1", 1);
        setenv("GGML_VK_PREFER_HOST_MEMORY", "1", 1);
        LOGI("[FFI] Backend: Vulkan (mobile conservative flags)");
    } else if (backend == 2) {
        unsetenv("GGML_VK_VISIBLE_DEVICES");
        LOGI("[FFI] Backend: OpenCL");
    }

    sd_ctx_params_t params;
    sd_ctx_params_init(&params);
    params.model_path = model_path ? model_path : "";
    params.n_threads = (n_threads > 0) ? n_threads : sd_get_num_physical_cores();
    params.flash_attn = flash_attn;
    params.free_params_immediately = false;
    params.wtype = (sd_type_t)wtype;
    params.offload_params_to_cpu = offload_params_to_cpu;
    params.enable_mmap = enable_mmap;
    params.keep_vae_on_cpu = keep_vae_on_cpu;
    if (max_vram > 0.0f) {
        params.max_vram = max_vram;
    }

    // NOTE: vae_tiling is NOT a member of sd_ctx_params_t.
    // It belongs to sd_img_gen_params_t and is applied per-generation in sd_ffi_generate().
    (void)vae_tiling;

    if (vae_path && vae_path[0] != '\0') {
        params.vae_path = vae_path;
        LOGI("[FFI] Using separate VAE: %s", vae_path);
    }
    if (clip_l_path && clip_l_path[0] != '\0') {
        params.clip_l_path = clip_l_path;
        LOGI("[FFI] Using separate CLIP-L: %s", clip_l_path);
    }

    // TAESD: tiny autoencoder for much faster VAE decode (10-30s saved per image)
    if (taesd_path && taesd_path[0] != '\0') {
        params.taesd_path = taesd_path;
        LOGI("[FFI] Using TAESD for fast decode: %s", taesd_path);
    }

    LOGI("[FFI] Initializing SD model: %s (threads=%d, flash_attn=%d, wtype=%d, backend=%d, offload=%d, mmap=%d, keep_vae_cpu=%d)",
         model_path, params.n_threads, flash_attn, wtype, backend,
         offload_params_to_cpu, enable_mmap, keep_vae_on_cpu);

    g_ffi_sd_ctx = new_sd_ctx(&params);
    return g_ffi_sd_ctx;
}

// Convenience wrapper around sd_ffi_init_ex with defaults for optional params.
SD_FFI_API void* sd_ffi_init(const char* model_path, int n_threads, bool flash_attn, bool vae_tiling, const char* taesd_path, int wtype, int backend) {
    return sd_ffi_init_ex(model_path, n_threads, flash_attn, vae_tiling, taesd_path, nullptr, nullptr, wtype, backend, false, false, false, 0.0f);
}

// Free model context.
SD_FFI_API void sd_ffi_free(void* ctx) {
    if (ctx) {
        free_sd_ctx((sd_ctx_t*)ctx);
    }
    if (g_ffi_sd_ctx == ctx) {
        g_ffi_sd_ctx = nullptr;
    }
}

// Generate image. Returns malloc'd RGB buffer (caller must free).
// out_size: receives buffer size in bytes (width * height * 3).
// Returns NULL on failure.
SD_FFI_API uint8_t* sd_ffi_generate(void* ctx,
                         const char* prompt,
                         const char* negative_prompt,
                         int width,
                         int height,
                         int steps,
                         int64_t seed,
                         float cfg_scale,
                         int sample_method,
                         int schedule,
                         bool vae_tiling,
                         size_t* out_size) {
    if (!ctx || !out_size) return nullptr;
    *out_size = 0;

    sd_img_gen_params_t params;
    sd_img_gen_params_init(&params);
    params.prompt = prompt ? prompt : "";
    params.negative_prompt = negative_prompt ? negative_prompt : "";
    params.width = width > 0 ? width : 512;
    params.height = height > 0 ? height : 512;
    params.seed = seed;
    params.batch_count = 1;

    params.sample_params.sample_method = (sample_method_t)sample_method;
    params.sample_params.scheduler = (scheduler_t)schedule;
    params.sample_params.sample_steps = steps > 0 ? steps : 4;
    params.sample_params.guidance.txt_cfg = cfg_scale;
    params.sample_params.eta = 0.0f;

    if (vae_tiling) {
        params.vae_tiling_params.enabled = true;
        params.vae_tiling_params.tile_size_x = 64;
        params.vae_tiling_params.tile_size_y = 64;
    }

    // Distilled models need CFG=1.0
    if (g_ffi_model_path.find("distilled") != std::string::npos ||
        g_ffi_model_path.find("sdxs") != std::string::npos ||
        g_ffi_model_path.find("lcm") != std::string::npos) {
        params.sample_params.guidance.txt_cfg = 1.0f;
    }

    LOGI("[FFI] Generating: %s (%dx%d, steps=%d, seed=%ld, cfg=%.1f, method=%d, sched=%d)",
         params.prompt, params.width, params.height, steps, (long)seed, cfg_scale,
         sample_method, schedule);

    // Fire step-0 callback immediately (upstream only calls after step 1 completes)
    if (g_ffi_progress) {
        g_ffi_progress(0, steps, 0.0f);
    }

    LOGI("[FFI] [PHASE] Calling generate_image()...");
    sd_image_t* result = generate_image((sd_ctx_t*)ctx, &params);
    LOGI("[FFI] [PHASE] generate_image() returned");

    if (!result) {
        LOGE("[FFI] generate_image returned null");
        return nullptr;
    }
    if (result->channel != 3) {
        LOGE("[FFI] Unexpected channel count: %d", result->channel);
        free(result->data);
        free(result);
        return nullptr;
    }

    size_t pixel_count = (size_t)result->width * result->height * result->channel;
    LOGI("[FFI] [PHASE] Copying result buffer: %dx%d x %d channels = %zu bytes",
         result->width, result->height, result->channel, pixel_count);
    uint8_t* buf = (uint8_t*)malloc(pixel_count);
    if (buf) {
        memcpy(buf, result->data, pixel_count);
        *out_size = pixel_count;
        LOGI("[FFI] Generated %dx%d RGB (%zu bytes)", result->width, result->height, pixel_count);
    } else {
        LOGE("[FFI] malloc failed for %zu bytes", pixel_count);
    }

    free(result->data);
    free(result);
    LOGI("[FFI] [PHASE] Returning buffer to Dart");
    return buf;
}

// Get number of physical CPU cores.
SD_FFI_API int sd_ffi_get_cores(void) {
    return sd_get_num_physical_cores();
}

} // extern "C"

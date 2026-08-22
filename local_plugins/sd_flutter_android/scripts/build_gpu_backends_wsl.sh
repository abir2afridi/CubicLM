#!/bin/bash
# Build GPU backend .so files for Android in WSL2 Ubuntu
#
# Prerequisites (run once):
#   sudo apt-get install -y build-essential curl python3
#   mkdir -p ~/tools && cd ~/tools
#   curl -L -o cmake.tar.gz https://github.com/Kitware/CMake/releases/download/v4.0.0/cmake-4.0.0-linux-x86_64.tar.gz
#   tar xzf cmake.tar.gz
#   curl -L -o ninja.zip https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-linux.zip
#   python3 -m zipfile -e ninja.zip .
#   chmod +x ninja
#   curl -L -o ndk.zip https://dl.google.com/android/repository/android-ndk-r27c-linux.zip
#   python3 -m zipfile -e ndk.zip .
#   # Fix broken symlinks in NDK (Python zipfile doesn't preserve them):
#   # Run the fix_ndk_symlinks.py script included in this repo
#
# Usage:
#   cd /mnt/c/.../CubicLM
#   bash local_plugins/sd_flutter_android/scripts/build_gpu_backends_wsl.sh

set -e

export PATH="$HOME/tools/cmake-4.0.0-linux-x86_64/bin:$HOME/tools:$PATH"
export ANDROID_NDK="$HOME/tools/android-ndk-r27c"

CMAKE="$HOME/tools/cmake-4.0.0-linux-x86_64/bin/cmake"
NINJA="$HOME/tools/ninja"

# Resolve project root from script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$PLUGIN_DIR/android"
BUILD_BASE="$HOME/build_sd_release"
OUT_DIR="$SRC/src/main/jniLibs/arm64-v8a"

ANDROID_ABI="arm64-v8a"
ANDROID_PLATFORM="android-28"
TOOLCHAIN="$ANDROID_NDK/build/cmake/android.toolchain.cmake"

echo "=== SD Android GPU Backend Build ==="
echo "CMake: $CMAKE"
echo "Ninja: $NINJA"
echo "NDK:   $ANDROID_NDK"
echo "Src:   $SRC"
echo "Out:   $OUT_DIR"

mkdir -p "$OUT_DIR"

OPENCL_STUB_DIR="$BUILD_BASE/opencl-stub"
OPENCL_STUB_LIB="$OPENCL_STUB_DIR/libOpenCL.so"

build_opencl_stub() {
    mkdir -p "$OPENCL_STUB_DIR"
    cat > "$OPENCL_STUB_DIR/opencl_stub.c" <<'EOF'
#include <stdint.h>

typedef void * cl_platform_id;
typedef void * cl_device_id;
typedef void * cl_context;
typedef void * cl_command_queue;
typedef void * cl_mem;
typedef void * cl_program;
typedef void * cl_kernel;
typedef void * cl_event;
typedef int32_t cl_int;
typedef uint32_t cl_uint;
typedef uint64_t cl_ulong;
typedef uintptr_t cl_bitfield;
typedef cl_bitfield cl_mem_flags;
typedef cl_bitfield cl_command_queue_properties;
typedef intptr_t cl_context_properties;
typedef intptr_t cl_mem_properties;
typedef intptr_t cl_device_type;
typedef uint32_t cl_bool;

cl_int clBuildProgram(cl_program p, cl_uint n, const cl_device_id *d, const char *o, void (*cb)(cl_program, void *), void *u) { return 0; }
cl_mem clCreateBuffer(cl_context c, cl_mem_flags f, uintptr_t s, void *h, cl_int *e) { return 0; }
cl_mem clCreateBufferWithProperties(cl_context c, const cl_mem_properties *p, cl_mem_flags f, uintptr_t s, void *h, cl_int *e) { return 0; }
cl_command_queue clCreateCommandQueue(cl_context c, cl_device_id d, cl_command_queue_properties p, cl_int *e) { return 0; }
cl_context clCreateContext(const cl_context_properties *p, cl_uint n, const cl_device_id *d, void (*cb)(const char *, const void *, uintptr_t, void *), void *u, cl_int *e) { return 0; }
cl_mem clCreateImage(cl_context c, cl_mem_flags f, const void *fmt, const void *desc, void *h, cl_int *e) { return 0; }
cl_kernel clCreateKernel(cl_program p, const char *n, cl_int *e) { return 0; }
cl_program clCreateProgramWithSource(cl_context c, cl_uint n, const char **s, const uintptr_t *l, cl_int *e) { return 0; }
cl_mem clCreateSubBuffer(cl_mem b, cl_mem_flags f, cl_uint t, const void *i, cl_int *e) { return 0; }
cl_int clEnqueueBarrierWithWaitList(cl_command_queue q, cl_uint n, const cl_event *w, cl_event *e) { return 0; }
cl_int clEnqueueCopyBuffer(cl_command_queue q, cl_mem s, cl_mem d, uintptr_t so, uintptr_t dof, uintptr_t cb, cl_uint n, const cl_event *w, cl_event *e) { return 0; }
cl_int clEnqueueFillBuffer(cl_command_queue q, cl_mem b, const void *p, uintptr_t ps, uintptr_t o, uintptr_t s, cl_uint n, const cl_event *w, cl_event *e) { return 0; }
cl_int clEnqueueMarkerWithWaitList(cl_command_queue q, cl_uint n, const cl_event *w, cl_event *e) { return 0; }
cl_int clEnqueueNDRangeKernel(cl_command_queue q, cl_kernel k, cl_uint wd, const uintptr_t *gwo, const uintptr_t *gws, const uintptr_t *lws, cl_uint n, const cl_event *w, cl_event *e) { return 0; }
cl_int clEnqueueReadBuffer(cl_command_queue q, cl_mem b, cl_bool block, uintptr_t o, uintptr_t s, void *p, cl_uint n, const cl_event *w, cl_event *e) { return 0; }
cl_int clEnqueueWriteBuffer(cl_command_queue q, cl_mem b, cl_bool block, uintptr_t o, uintptr_t s, const void *p, cl_uint n, const cl_event *w, cl_event *e) { return 0; }
cl_int clFinish(cl_command_queue q) { return 0; }
cl_int clFlush(cl_command_queue q) { return 0; }
cl_int clGetDeviceIDs(cl_platform_id p, cl_device_type t, cl_uint n, cl_device_id *d, cl_uint *c) { return 0; }
cl_int clGetDeviceInfo(cl_device_id d, cl_uint p, uintptr_t s, void *v, uintptr_t *r) { return 0; }
cl_int clGetKernelWorkGroupInfo(cl_kernel k, cl_device_id d, cl_uint p, uintptr_t s, void *v, uintptr_t *r) { return 0; }
cl_int clGetPlatformIDs(cl_uint n, cl_platform_id *p, cl_uint *c) { return 0; }
cl_int clGetPlatformInfo(cl_platform_id p, cl_uint name, uintptr_t s, void *v, uintptr_t *r) { return 0; }
cl_int clGetProgramBuildInfo(cl_program p, cl_device_id d, cl_uint name, uintptr_t s, void *v, uintptr_t *r) { return 0; }
cl_int clReleaseContext(cl_context c) { return 0; }
cl_int clReleaseEvent(cl_event e) { return 0; }
cl_int clReleaseMemObject(cl_mem m) { return 0; }
cl_int clReleaseProgram(cl_program p) { return 0; }
cl_int clSetKernelArg(cl_kernel k, cl_uint i, uintptr_t s, const void *v) { return 0; }
cl_int clWaitForEvents(cl_uint n, const cl_event *e) { return 0; }
EOF
    "$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android28-clang" \
        -shared \
        -Wl,-soname,libOpenCL.so \
        -o "$OPENCL_STUB_LIB" \
        "$OPENCL_STUB_DIR/opencl_stub.c"
}

COMMON_ARGS=(
    -G Ninja
    -DCMAKE_MAKE_PROGRAM="$NINJA"
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
    -DANDROID_ABI="$ANDROID_ABI"
    -DANDROID_PLATFORM="$ANDROID_PLATFORM"
    -DCMAKE_BUILD_TYPE=Release
    -DSD_BUILD_EXAMPLES=OFF
    -DSD_BUILD_SHARED_LIBS=OFF
    -DGGML_OPENMP=ON
)

# ------------------------------------------------------------------
# CPU variant
# ------------------------------------------------------------------
echo ""
echo "=== [1/3] Building CPU variant ==="
CPU_BUILD="$BUILD_BASE/cpu"
rm -rf "$CPU_BUILD"
mkdir -p "$CPU_BUILD"
cd "$CPU_BUILD"
"$CMAKE" "${COMMON_ARGS[@]}" -DSD_VULKAN=OFF -DSD_OPENCL=OFF "$SRC"
"$NINJA" -j"$(nproc)" sd_jni
cp "$CPU_BUILD/libsd_jni.so" "$OUT_DIR/libsd_jni.so"
echo "CPU OK"

# ------------------------------------------------------------------
# Vulkan variant
# ------------------------------------------------------------------
echo ""
echo "=== [2/3] Building Vulkan variant ==="
VULKAN_BUILD="$BUILD_BASE/vulkan"
rm -rf "$VULKAN_BUILD"
mkdir -p "$VULKAN_BUILD"
cd "$VULKAN_BUILD"
"$CMAKE" "${COMMON_ARGS[@]}" -DSD_VULKAN=ON -DSD_OPENCL=OFF -DSD_JNI_OUTPUT_NAME=sd_jni_vulkan "$SRC"
"$NINJA" -j"$(nproc)" sd_jni
cp "$VULKAN_BUILD/libsd_jni_vulkan.so" "$OUT_DIR/libsd_jni_vulkan.so"
echo "Vulkan OK"

# ------------------------------------------------------------------
# OpenCL variant
# ------------------------------------------------------------------
echo ""
echo "=== [3/3] Building OpenCL variant ==="
build_opencl_stub
OPENCL_BUILD="$BUILD_BASE/opencl"
rm -rf "$OPENCL_BUILD"
mkdir -p "$OPENCL_BUILD"
cd "$OPENCL_BUILD"
"$CMAKE" "${COMMON_ARGS[@]}" -DSD_VULKAN=OFF -DSD_OPENCL=ON \
    -DSD_JNI_OUTPUT_NAME=sd_jni_opencl \
    -DOpenCL_INCLUDE_DIRS="$HOME/tools/opencl-headers/OpenCL-Headers-2024.10.24" \
    -DOpenCL_LIBRARIES="$OPENCL_STUB_LIB" \
    "$SRC"
"$NINJA" -j"$(nproc)" sd_jni
cp "$OPENCL_BUILD/libsd_jni_opencl.so" "$OUT_DIR/libsd_jni_opencl.so"
echo "OpenCL OK"

# ------------------------------------------------------------------
# Copy OpenMP runtime
# ------------------------------------------------------------------
echo ""
echo "=== Copying OpenMP runtime ==="
cp "$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/18/lib/linux/aarch64/libomp.so" "$OUT_DIR/libomp.so"
echo "libomp.so OK"

# ------------------------------------------------------------------
# Strip debug symbols
# ------------------------------------------------------------------
echo ""
echo "=== Stripping debug symbols ==="
STRIP="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
for f in "$OUT_DIR"/libsd_jni.so "$OUT_DIR"/libsd_jni_vulkan.so "$OUT_DIR"/libsd_jni_opencl.so "$OUT_DIR"/libomp.so; do
    "$STRIP" --strip-debug "$f"
done

echo ""
echo "=== Verifying variant SONAMEs ==="
READELF="$(command -v readelf)"
"$READELF" -d "$OUT_DIR/libsd_jni.so" | grep 'SONAME.*libsd_jni.so'
"$READELF" -d "$OUT_DIR/libsd_jni_vulkan.so" | grep 'SONAME.*libsd_jni_vulkan.so'
"$READELF" -d "$OUT_DIR/libsd_jni_opencl.so" | grep 'SONAME.*libsd_jni_opencl.so'
"$READELF" -d "$OUT_DIR/libsd_jni_opencl.so" | grep 'NEEDED.*libOpenCL.so'

echo ""
echo "=== All builds completed ==="
ls -lh "$OUT_DIR"/*.so

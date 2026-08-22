cmake_minimum_required(VERSION 3.22.1)

project(sd_jni)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(SD_JNI_OUTPUT_NAME "sd_jni" CACHE STRING "Output name for the SD JNI shared library")

# Aggressive optimizations for CPU inference speed
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -DNDEBUG -ffast-math -fno-finite-math-only -funroll-loops")
set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -O3 -DNDEBUG -ffast-math -fno-finite-math-only -funroll-loops")

# Android 15 16KB page size compliance
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-z,max-page-size=16384 -Wl,--unresolved-symbols=ignore-all")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384 -Wl,--unresolved-symbols=ignore-all")

# Vulkan is enabled on Android with runtime Adreno detection and CPU fallback.
# Adreno GPUs are blacklisted due to known GGML shader compiler crashes.
# NOTE: Building with SD_VULKAN=ON on Windows requires a host C++ compiler
# (Visual Studio, MinGW, or LLVM) to build the vulkan-shaders-gen tool.
set(SD_VULKAN OFF CACHE BOOL "Enable Vulkan backend")

# Use custom FindVulkan that works with Android NDK cross-compilation
list(INSERT CMAKE_MODULE_PATH 0 "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

if(SD_VULKAN)
    find_package(Vulkan REQUIRED)
    add_definitions(-DSD_JNI_HAVE_VULKAN=1)
endif()

# OpenMP is now enabled — libomp.so is bundled in jniLibs/arm64-v8a/
# This gives 2-4x CPU speedup for matrix operations in ggml
set(GGML_OPENMP ON CACHE BOOL "Enable OpenMP for CPU parallelization")

# Add stable-diffusion.cpp
set(SD_BUILD_EXAMPLES OFF CACHE BOOL "Disable SD examples")
set(SD_BUILD_SHARED_LIBS OFF CACHE BOOL "Build SD as static")
add_subdirectory(src/main/cpp/stable-diffusion.cpp)

# ggml-base is linked as a standalone shared object and contains C++ sources.
# On Android/NDK it must explicitly link libc++ or symbols such as operator new
# and std::runtime_error stay unresolved during the native build.
if(ANDROID)
    foreach(target ggml-base ggml stable-diffusion)
        if(TARGET ${target})
            target_link_libraries(${target} PRIVATE c++_shared)
        endif()
    endforeach()
endif()

# JNI wrapper library
add_library(sd_jni SHARED
    src/main/cpp/sd_jni_wrapper.cpp
)

set_target_properties(sd_jni PROPERTIES
    OUTPUT_NAME "${SD_JNI_OUTPUT_NAME}"
)

target_link_libraries(sd_jni PRIVATE
    stable-diffusion
    c++_shared
    android
    log
    EGL
    GLESv2
)

if(SD_VULKAN)
    target_link_libraries(sd_jni PRIVATE Vulkan::Vulkan)
endif()

if(SD_OPENCL AND OpenCL_LIBRARIES)
    target_link_libraries(sd_jni PRIVATE ${OpenCL_LIBRARIES})
endif()

target_include_directories(sd_jni PRIVATE
    src/main/cpp/stable-diffusion.cpp/include
    src/main/cpp/stable-diffusion.cpp/src
)

if(SD_VULKAN)
    target_include_directories(sd_jni PRIVATE ${Vulkan_INCLUDE_DIRS})
endif()

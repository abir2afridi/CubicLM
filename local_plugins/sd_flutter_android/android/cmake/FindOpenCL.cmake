# Dummy FindOpenCL for Android cross-compilation
# OpenCL is provided by the Android system at runtime.
# The real library is loaded dynamically; we only need headers for compilation.
if(NOT OpenCL_INCLUDE_DIRS)
    message(FATAL_ERROR "OpenCL_INCLUDE_DIRS must be set when cross-compiling for Android")
endif()
set(OpenCL_FOUND TRUE)
set(OpenCL_INCLUDE_DIR "${OpenCL_INCLUDE_DIRS}")
set(OpenCL_LIBRARY "")
set(OpenCL_LIBRARIES "")

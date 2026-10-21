# CMake toolchain file for cross-compiling ITGmania to aarch64 Linux
# (Allwinner H700 handhelds running muOS, e.g. Anbernic RG SP / RG35XX).
#
# Usage: cmake -DCMAKE_TOOLCHAIN_FILE=<repo>/h700/cross/toolchain-aarch64.cmake ...
#
# Expects the cross toolchain (aarch64-linux-gnu-gcc/g++) and the populated
# sysroot at h700/cross/sysroot-aarch64 -- h700/build.sh sets both up.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)

get_filename_component(H700_CROSS_SYSROOT "${CMAKE_CURRENT_LIST_DIR}/sysroot-aarch64" ABSOLUTE)
set(CMAKE_SYSROOT "${H700_CROSS_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH "${H700_CROSS_SYSROOT}")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

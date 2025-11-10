cmake_minimum_required(VERSION 3.15)
# stop cmake from taking make from CMAKE_SYSROOT
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
project(runner LANGUAGES CXX)

set(BINARY_NAME "demo1")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Basically we use this include when we got the following error:
#  fatal error: 'bits/c++config.h' file not found
include_directories(SYSTEM ${FLUTTER_SYSTEM_INCLUDE_DIRECTORIES})
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

# Configure build options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Configure build option to target backend.
if (NOT FLUTTER_TARGET_BACKEND_TYPE)
  set(FLUTTER_TARGET_BACKEND_TYPE "wayland" CACHE
    STRING "Flutter target backend type" FORCE)
  set_property(CACHE FLUTTER_TARGET_BACKEND_TYPE PROPERTY STRINGS
    "wayland" "gbm" "eglstream" "x11")
endif()

# Compilation settings that should be applied to most targets.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")

# Flutter library and tool build rules.
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build
add_subdirectory("runner")

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# --- FFI plugin auto-bundling (fallback) ---
# If plugins don't declare eLinux support, try bundling .so produced by
# Linux build or native_assets so they are available in the eLinux bundle.
# This helps cases like flutter_soloud which build a Linux .so but aren't
# registered in eLinux generated_plugins.cmake.

# Map CMAKE_SYSTEM_PROCESSOR to Flutter's arch folder names.
set(FLUTTER_LINUX_ARCH "")
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64")
  set(FLUTTER_LINUX_ARCH "x64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "arm64")
  set(FLUTTER_LINUX_ARCH "arm64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "armv7" OR CMAKE_SYSTEM_PROCESSOR MATCHES "arm")
  set(FLUTTER_LINUX_ARCH "arm")
endif()

# Try to pick up plugin .so from Linux bundle built by `flutter build linux`.
if(FLUTTER_LINUX_ARCH)
  set(LINUX_BUNDLE_LIB_DIR "${PROJECT_DIR}/build/linux/${FLUTTER_LINUX_ARCH}/release/bundle/lib")
  if(EXISTS "${LINUX_BUNDLE_LIB_DIR}")
    file(GLOB LINUX_PLUGIN_LIBS "${LINUX_BUNDLE_LIB_DIR}/lib*_plugin.so")
    if(LINUX_PLUGIN_LIBS)
      list(APPEND PLUGIN_BUNDLED_LIBRARIES ${LINUX_PLUGIN_LIBS})
    endif()
  endif()
endif()

# Also try native assets produced by Dart/Flutter's native assets pipeline.
set(NATIVE_ASSETS_DIR "${PROJECT_DIR}/build/native_assets/linux")
if(EXISTS "${NATIVE_ASSETS_DIR}")
  file(GLOB_RECURSE NATIVE_PLUGIN_LIBS "${NATIVE_ASSETS_DIR}/*.so")
  if(NATIVE_PLUGIN_LIBS)
    list(APPEND PLUGIN_BUNDLED_LIBRARIES ${NATIVE_PLUGIN_LIBS})
  endif()
endif()

# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
install(FILES "${FLUTTER_EMBEDDER_LIBRARY}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

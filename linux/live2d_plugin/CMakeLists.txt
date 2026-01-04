# Live2D Plugin CMakeLists.txt

set(LIVE2D_PLUGIN_NAME "live2d_plugin")

# Find required packages
find_package(PkgConfig REQUIRED)
find_package(OpenGL REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# Cubism SDK paths
set(CUBISM_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../CubismNativeSamples")
set(CUBISM_CORE "${CUBISM_ROOT}/Core")
set(CUBISM_FRAMEWORK "${CUBISM_ROOT}/Framework")
set(CUBISM_SAMPLES "${CUBISM_ROOT}/Samples")
set(THIRD_PARTY "${CUBISM_ROOT}/Samples/OpenGL/thirdParty")

# Plugin source files
set(LIVE2D_PLUGIN_SOURCES
  "live2d_plugin.cc"
  "live2d_texture.cc"
  "live2d_cubism_renderer.cc"
)

# Cubism Framework sources
set(CUBISM_FRAMEWORK_SOURCES
  "${CUBISM_FRAMEWORK}/src/CubismFramework.cpp"
  "${CUBISM_FRAMEWORK}/src/CubismDefaultParameterId.cpp"
  "${CUBISM_FRAMEWORK}/src/CubismModelSettingJson.cpp"
  "${CUBISM_FRAMEWORK}/src/Effect/CubismBreath.cpp"
  "${CUBISM_FRAMEWORK}/src/Effect/CubismEyeBlink.cpp"
  "${CUBISM_FRAMEWORK}/src/Effect/CubismPose.cpp"
  "${CUBISM_FRAMEWORK}/src/Id/CubismId.cpp"
  "${CUBISM_FRAMEWORK}/src/Id/CubismIdManager.cpp"
  "${CUBISM_FRAMEWORK}/src/Math/CubismMath.cpp"
  "${CUBISM_FRAMEWORK}/src/Math/CubismMatrix44.cpp"
  "${CUBISM_FRAMEWORK}/src/Math/CubismModelMatrix.cpp"
  "${CUBISM_FRAMEWORK}/src/Math/CubismTargetPoint.cpp"
  "${CUBISM_FRAMEWORK}/src/Math/CubismVector2.cpp"
  "${CUBISM_FRAMEWORK}/src/Math/CubismViewMatrix.cpp"
  "${CUBISM_FRAMEWORK}/src/Model/CubismModel.cpp"
  "${CUBISM_FRAMEWORK}/src/Model/CubismModelUserData.cpp"
  "${CUBISM_FRAMEWORK}/src/Model/CubismModelUserDataJson.cpp"
  "${CUBISM_FRAMEWORK}/src/Model/CubismMoc.cpp"
  "${CUBISM_FRAMEWORK}/src/Model/CubismUserModel.cpp"
  "${CUBISM_FRAMEWORK}/src/Motion/CubismExpressionMotion.cpp"
  "${CUBISM_FRAMEWORK}/src/Motion/CubismExpressionMotionManager.cpp"
  "${CUBISM_FRAMEWORK}/src/Motion/CubismMotion.cpp"
  "${CUBISM_FRAMEWORK}/src/Motion/CubismMotionJson.cpp"
  "${CUBISM_FRAMEWORK}/src/Motion/CubismMotionManager.cpp"
  "${CUBISM_FRAMEWORK}/src/Motion/CubismMotionQueueEntry.cpp"
  "${CUBISM_FRAMEWORK}/src/Motion/CubismMotionQueueManager.cpp"
  "${CUBISM_FRAMEWORK}/src/Motion/ACubismMotion.cpp"
  "${CUBISM_FRAMEWORK}/src/Physics/CubismPhysics.cpp"
  "${CUBISM_FRAMEWORK}/src/Physics/CubismPhysicsJson.cpp"
  "${CUBISM_FRAMEWORK}/src/Rendering/CubismRenderer.cpp"
  "${CUBISM_FRAMEWORK}/src/Rendering/OpenGL/CubismRenderer_OpenGLES2.cpp"
  "${CUBISM_FRAMEWORK}/src/Rendering/OpenGL/CubismShader_OpenGLES2.cpp"
  "${CUBISM_FRAMEWORK}/src/Rendering/OpenGL/CubismOffscreenSurface_OpenGLES2.cpp"
  "${CUBISM_FRAMEWORK}/src/Type/csmRectF.cpp"
  "${CUBISM_FRAMEWORK}/src/Type/csmString.cpp"
  "${CUBISM_FRAMEWORK}/src/Utils/CubismDebug.cpp"
  "${CUBISM_FRAMEWORK}/src/Utils/CubismJson.cpp"
  "${CUBISM_FRAMEWORK}/src/Utils/CubismString.cpp"
)

# Common sample sources
set(CUBISM_COMMON_SOURCES
  "${CUBISM_SAMPLES}/Common/LAppAllocator_Common.cpp"
)

# GLEW source (static)
set(GLEW_SOURCES
  "${THIRD_PARTY}/glew/src/glew.c"
)

# Add plugin library
add_library(${LIVE2D_PLUGIN_NAME} STATIC
  ${LIVE2D_PLUGIN_SOURCES}
  ${CUBISM_FRAMEWORK_SOURCES}
  ${CUBISM_COMMON_SOURCES}
  ${GLEW_SOURCES}
)

# Include directories
target_include_directories(${LIVE2D_PLUGIN_NAME} PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}
  "${CMAKE_CURRENT_SOURCE_DIR}/../flutter/ephemeral"
  ${GTK_INCLUDE_DIRS}
  "${CUBISM_CORE}/include"
  "${CUBISM_FRAMEWORK}/src"
  "${THIRD_PARTY}/stb"
  "${THIRD_PARTY}/glew/include"
  "${CUBISM_SAMPLES}/OpenGL/Demo/proj.linux.cmake/src"
  "${CUBISM_SAMPLES}/Common"
)

# Link Cubism Core library
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
  set(CUBISM_CORE_LIB "${CUBISM_CORE}/lib/linux/x86_64/libLive2DCubismCore.a")
else()
  set(CUBISM_CORE_LIB "${CUBISM_CORE}/lib/linux/x86/libLive2DCubismCore.a")
endif()

# Link libraries
target_link_libraries(${LIVE2D_PLUGIN_NAME} PUBLIC
  PkgConfig::GTK
  ${CUBISM_CORE_LIB}
  OpenGL::GL
  EGL
  GLESv2
)

# Compile options
target_compile_features(${LIVE2D_PLUGIN_NAME} PRIVATE cxx_std_17)
target_compile_options(${LIVE2D_PLUGIN_NAME} PRIVATE -Wall -Wno-error -Wno-inconsistent-missing-override)
target_compile_definitions(${LIVE2D_PLUGIN_NAME} PRIVATE CSM_TARGET_LINUX_GLES2 GLEW_STATIC)

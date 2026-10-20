cmake_minimum_required(VERSION 3.24)
set(CMAKE_OSX_DEPLOYMENT_TARGET 12.0 CACHE STRING "Minimum macOS")
project(WyrmMac VERSION 0.1.0 LANGUAGES C CXX OBJC)
if(NOT APPLE)
  message(FATAL_ERROR "Build on macOS with Xcode command-line tools")
endif()
set(ENGINE "${CMAKE_SOURCE_DIR}/Generated")
file(GLOB_RECURSE ENGINE_C CONFIGURE_DEPENDS "${ENGINE}/app/src/*.c" "${ENGINE}/thermite/src/*.c")
file(GLOB_RECURSE ENGINE_CPP CONFIGURE_DEPENDS "${ENGINE}/app/src/*.cpp" "${ENGINE}/thermite/src/*.cpp")
list(FILTER ENGINE_CPP EXCLUDE REGEX "imgui_impl_glfw\\.cpp$")
file(GLOB SDL_FRAMEWORK "${CMAKE_SOURCE_DIR}/Vendor/SDL3.xcframework/macos-*/SDL3.framework")
file(GLOB MVK_LIBRARY "${CMAKE_SOURCE_DIR}/Vendor/MoltenVK.xcframework/macos-*/libMoltenVK.a")
if(NOT SDL_FRAMEWORK OR NOT MVK_LIBRARY)
  message(FATAL_ERROR "Run Scripts/fetch-dependencies.sh first")
endif()
execute_process(COMMAND /usr/libexec/java_home OUTPUT_VARIABLE JDK OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
add_executable(Wyrm MACOSX_BUNDLE ${ENGINE_C} ${ENGINE_CPP}
  Sources/MacHost.m Sources/MacUI.c Sources/AppleVulkan.c)
target_compile_features(Wyrm PRIVATE c_std_11 cxx_std_17)
target_compile_definitions(Wyrm PRIVATE SETTINGS_VERSION="2.8" CIMGUI_NO_EXPORT
  CGLM_FORCE_DEPTH_ZERO_TO_ONE MG_ENABLE_IPV6=1 WYRM_SDL_JNI=1 WYRM_DESKTOP=1
  WYRM_MACOS=1 SDL_MAIN_HANDLED=1 APP_VERSION="0.1.0")
target_include_directories(Wyrm PRIVATE Sources "${ENGINE}/app/src"
  "${ENGINE}/thermite/include" "${ENGINE}/thermite/src"
  "${SDL_FRAMEWORK}/Headers" "${CMAKE_SOURCE_DIR}/Vendor/MoltenVK/include"
  "${JDK}/include" "${JDK}/include/darwin")
# Framework headers use <SDL3/SDL.h>; the generated include alias is portable.
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/include")
file(CREATE_LINK "${SDL_FRAMEWORK}/Headers" "${CMAKE_BINARY_DIR}/include/SDL3" SYMBOLIC)
target_include_directories(Wyrm PRIVATE "${CMAKE_BINARY_DIR}/include")
target_compile_options(Wyrm PRIVATE -include "${CMAKE_SOURCE_DIR}/Sources/MacCompat.h"
  -Wno-unused-parameter -Wno-unused-function -Wno-unused-variable
  -Wno-missing-braces -Wno-sign-compare -Wno-deprecated-declarations
  -Wno-nullability-completeness
  "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>" "$<$<CONFIG:Release>:-O3>")
target_link_libraries(Wyrm PRIVATE "${SDL_FRAMEWORK}" "${MVK_LIBRARY}"
  "-framework AppKit" "-framework Foundation" "-framework Metal"
  "-framework QuartzCore" "-framework IOSurface" "-framework IOKit" "-framework CoreVideo" c++)
# SDL discovers the statically linked Vulkan entrypoint via dlsym.
target_link_options(Wyrm PRIVATE -Wl,-export_dynamic -Wl,-u,_vkGetInstanceProcAddr)
set_target_properties(Wyrm PROPERTIES MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/Sources/Info.plist"
  BUILD_RPATH "@executable_path/../Frameworks" INSTALL_RPATH "@executable_path/../Frameworks")
add_custom_command(TARGET Wyrm POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:Wyrm>/Contents/Frameworks"
  COMMAND ditto "${SDL_FRAMEWORK}" "$<TARGET_BUNDLE_DIR:Wyrm>/Contents/Frameworks/SDL3.framework"
  COMMAND ditto "${ENGINE}/app/res" "$<TARGET_BUNDLE_DIR:Wyrm>/Contents/Resources/app/res"
  COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/LICENSE" "${CMAKE_SOURCE_DIR}/NOTICE.md"
          "${CMAKE_SOURCE_DIR}/PRIVACY.md" "$<TARGET_BUNDLE_DIR:Wyrm>/Contents/Resources/")

cmake_minimum_required(VERSION 3.16)
project(csi_camera LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(GODOT_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/godot-cpp" CACHE PATH "Path to matching godot-cpp checkout")

find_package(PkgConfig REQUIRED)
pkg_check_modules(GSTREAMER REQUIRED IMPORTED_TARGET gstreamer-1.0 gstreamer-app-1.0)

add_library(csi_camera SHARED
    src/csi_camera.cpp
    src/register.cpp
)

target_include_directories(csi_camera PRIVATE
    src
    "${GODOT_CPP_DIR}/include"
    "${GODOT_CPP_DIR}/gen/include"
)
add_library(godot_cpp STATIC IMPORTED GLOBAL)
set_target_properties(godot_cpp PROPERTIES
    IMPORTED_LOCATION "${GODOT_CPP_DIR}/bin/libgodot-cpp.linux.template_release.arm64.a"
)
target_link_libraries(csi_camera PRIVATE godot_cpp PkgConfig::GSTREAMER)
set_target_properties(csi_camera PROPERTIES
    OUTPUT_NAME "csi_camera.linux.arm64"
    PREFIX "lib"
)

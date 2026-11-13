cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "local_auth_linux")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "local_auth_linux_plugin")

add_library(${PLUGIN_NAME} SHARED
  "local_auth_linux_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

set(local_auth_linux_bundled_libraries
  ""
  PARENT_SCOPE
)

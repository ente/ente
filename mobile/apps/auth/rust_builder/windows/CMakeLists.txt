cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "ente_auth_frb")
project(${PROJECT_NAME} LANGUAGES CXX)

include("${CMAKE_SOURCE_DIR}/../../../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../../../../../../../../../rust/bindings/frb/auth ente_auth_frb "")

set(ente_auth_frb_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)

cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES C CXX)

find_program(GLIB_COMPILE_RESOURCES glib-compile-resources)
if(NOT GLIB_COMPILE_RESOURCES)
  message(FATAL_ERROR "glib-compile-resources is required to embed the app icon")
endif()
set(APP_RESOURCES "${CMAKE_CURRENT_BINARY_DIR}/app_resources.c")
add_custom_command(
  OUTPUT "${APP_RESOURCES}"
  COMMAND "${GLIB_COMPILE_RESOURCES}"
    "${CMAKE_CURRENT_SOURCE_DIR}/app_resources.gresource.xml"
    --sourcedir "${CMAKE_CURRENT_SOURCE_DIR}/../../assets"
    --target "${APP_RESOURCES}" --generate-source --c-name red_flowers
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/app_resources.gresource.xml"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../assets/icon.png"
  VERBATIM
)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${APP_RESOURCES}"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

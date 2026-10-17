cmake_minimum_required(VERSION 3.18)
project(rainlink_kde_proxy LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(PkgConfig REQUIRED)
pkg_check_modules(QT_CORE REQUIRED IMPORTED_TARGET Qt6Core>=6.6)
pkg_check_modules(QT_DBUS REQUIRED IMPORTED_TARGET Qt6DBus>=6.6)
# Only ConfigCore is needed. Importing the full KF6Config package on some
# distributions also requires QML/GUI development packages for unused targets.
find_path(KCONFIG_CORE_INCLUDE_DIR KConfig PATH_SUFFIXES KF6/KConfigCore REQUIRED)
find_path(KCONFIG_VERSION_INCLUDE_DIR kconfig_version.h PATH_SUFFIXES KF6/KConfig REQUIRED)
find_library(KCONFIG_CORE_LIBRARY NAMES KF6ConfigCore REQUIRED)

add_executable(rainlink-kde-proxy main.cpp)
target_include_directories(rainlink-kde-proxy PRIVATE "${KCONFIG_CORE_INCLUDE_DIR}" "${KCONFIG_VERSION_INCLUDE_DIR}")
target_link_libraries(rainlink-kde-proxy PRIVATE "${KCONFIG_CORE_LIBRARY}" PkgConfig::QT_CORE PkgConfig::QT_DBUS)
target_compile_options(rainlink-kde-proxy PRIVATE -Wall -Wextra -Werror)
install(TARGETS rainlink-kde-proxy RUNTIME DESTINATION .)

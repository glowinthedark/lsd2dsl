cmake_minimum_required (VERSION 3.21)

project(lsd2dsl VERSION 0.6.0 LANGUAGES C CXX)

option(ENABLE_DUDEN "Enable Duden support, requires Qt6WebEngine" ON)

configure_file (
    "${CMAKE_SOURCE_DIR}/lib/common/version.h.in"
    "${CMAKE_BINARY_DIR}/common/version.h"
)

include_directories("${PROJECT_SOURCE_DIR}/lib")
include_directories("${CMAKE_BINARY_DIR}")

set(CMAKE_CXX_STANDARD 20)

# CMake >= 3.30 removed the FindBoost module; use upstream BoostConfig.cmake
if(POLICY CMP0167)
    cmake_policy(SET CMP0167 NEW)
endif()

find_package(Boost 1.60 REQUIRED COMPONENTS program_options)

# Boost >= 1.89 removed the stub libraries of header-only components
# (Boost.System is header-only since 1.69). Provide a fallback interface
# target so existing Boost::system link references keep working.
if(NOT TARGET Boost::system)
    add_library(Boost::system INTERFACE IMPORTED)
    set_target_properties(Boost::system PROPERTIES
        INTERFACE_LINK_LIBRARIES Boost::headers
    )
endif()

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

# Note: on macOS the compiler ID is AppleClang, not Clang
add_compile_options($<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Werror>)
add_compile_options($<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wno-error=array-bounds>)
add_compile_options($<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wall>)

add_compile_options($<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-fno-char8_t>)
add_compile_options($<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wno-deprecated-declarations>)
add_compile_options($<$<COMPILE_LANG_AND_ID:CXX,MSVC>:/Zc:char8_t->)

if(WIN32)
    add_compile_definitions(WIN32)
endif()
if(ENABLE_DUDEN)
    add_compile_definitions(ENABLE_DUDEN)
endif()

add_subdirectory(lib)

enable_testing()
add_subdirectory(tests)
add_subdirectory(app)

if(WIN32)
    if(ENABLE_DUDEN)
        set(CPACK_PACKAGE_FILE_NAME "lsd2dsl-${lsd2dsl_VERSION}-duden-win64")
    else()
        set(CPACK_PACKAGE_FILE_NAME "lsd2dsl-${lsd2dsl_VERSION}-win64")
    endif()
    set(CPACK_GENERATOR "ZIP")
    include(CPack)
endif()

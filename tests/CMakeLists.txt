find_package(GTest CONFIG QUIET)

if(NOT GTest_FOUND)
    # No system GTest: fetch and build it as part of the project
    include(FetchContent)
    FetchContent_Declare(googletest
        URL https://github.com/google/googletest/archive/refs/tags/v1.15.2.tar.gz
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    )
    # Windows: use shared CRT so gtest matches the rest of the project
    set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
    set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(googletest)
endif()

include(GoogleTest)

add_executable(lingvo-tests lingvo-tests.cpp)
target_link_libraries(lingvo-tests lingvo GTest::gtest_main)
gtest_discover_tests(lingvo-tests)

if(ENABLE_DUDEN)
    add_executable(duden-tests duden-tests.cpp)
    target_link_libraries(duden-tests common duden GTest::gtest_main)
    gtest_discover_tests(duden-tests)
endif()

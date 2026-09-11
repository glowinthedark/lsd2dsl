project(lsd2dsl)

set(CMAKE_INCLUDE_CURRENT_DIR ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Widgets)
set(SRC
    decoder.cpp
    MainWindow.cpp
)

# Deliberately not a WIN32 executable: the Windows entry point in decoder.cpp is
# wmain() (console subsystem, UTF-16 argv converted to UTF-8). A WIN32 target
# would link Qt6::EntryPoint's WinMain, which calls main() -- unresolved here --
# and would also detach stdout, which this converter writes its progress to.
add_executable(${PROJECT_NAME} ${SRC} ${QT_RESOURCES})
target_link_libraries(${PROJECT_NAME} PRIVATE lingvo Qt6::Core Qt6::Widgets Boost::program_options)

if(ENABLE_DUDEN)
    target_link_libraries(${PROJECT_NAME} PRIVATE duden)
endif()

if(APPLE)
    # LSMinimumSystemVersion must be an explicit decision, not whatever SDK the
    # build machine happens to carry: set MACOSX_DEPLOYMENT_TARGET in the
    # environment (or -DCMAKE_OSX_DEPLOYMENT_TARGET=) to pin it.
    if(CMAKE_OSX_DEPLOYMENT_TARGET)
        set(LSD2DSL_MIN_MACOS "${CMAKE_OSX_DEPLOYMENT_TARGET}")
    else()
        execute_process(COMMAND sw_vers -productVersion
            OUTPUT_VARIABLE _macos_version OUTPUT_STRIP_TRAILING_WHITESPACE)
        string(REGEX REPLACE "^([0-9]+).*" "\\1.0" LSD2DSL_MIN_MACOS "${_macos_version}")
        message(STATUS "CMAKE_OSX_DEPLOYMENT_TARGET unset; "
                       "LSMinimumSystemVersion defaults to the host: ${LSD2DSL_MIN_MACOS}")
    endif()
    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
                   "${CMAKE_CURRENT_BINARY_DIR}/Info.plist" @ONLY)
    set_target_properties(${PROJECT_NAME} PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_BINARY_DIR}/Info.plist"
    )
endif()

# The Qt deployment API (macdeployqt / windeployqt under the hood) resolves the
# executable at ${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_BINDIR}; install next to
# the archive root so the layout matches the shipped zips.
if(NOT DEFINED CMAKE_INSTALL_BINDIR)
    set(CMAKE_INSTALL_BINDIR ".")
endif()

install(TARGETS ${PROJECT_NAME}
    BUNDLE  DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

if(WIN32)
    install(FILES $<TARGET_RUNTIME_DLLS:${PROJECT_NAME}> DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()

# Qt >= 6.3 ships a first-class deployment API; it replaces the hand-rolled DLL
# copying that install.cmake.in used to do. https://doc.qt.io/qt-6/cmake-deployment.html
if(WIN32 OR APPLE)
    if(COMMAND qt_generate_deploy_app_script)
        qt_generate_deploy_app_script(
            TARGET ${PROJECT_NAME}
            OUTPUT_SCRIPT deploy_script
            NO_UNSUPPORTED_PLATFORM_ERROR
        )
        install(SCRIPT ${deploy_script})
    else()
        message(WARNING "Qt deployment API unavailable (Qt < 6.3): "
                        "the install tree will not be self-contained")
    endif()
endif()

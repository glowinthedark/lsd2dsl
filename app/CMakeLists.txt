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
    # $<TARGET_RUNTIME_DLLS> only covers DLLs reachable through imported CMake
    # targets: vcpkg's zlib/ogg/vorbis are linked as raw .lib paths, and
    # libsndfile's own dependencies (FLAC, opus, mpg123, mp3lame) are not link
    # dependencies of this executable at all. Walk the PE import tables instead.
    # Search dirs, in order of reliability: explicitly configured (the CI passes
    # the vcpkg bin dir), vcpkg's own variables when the toolchain exports them,
    # and the build dir, which vcpkg's applocal deployment already populated.
    set(LSD2DSL_RUNTIME_DLL_DIRS "" CACHE STRING
        "Extra directories searched for runtime DLLs when packaging")
    set(_lsd2dsl_dll_dirs ${LSD2DSL_RUNTIME_DLL_DIRS})
    foreach(_root IN ITEMS "${VCPKG_INSTALLED_DIR}" "${_VCPKG_INSTALLED_DIR}")
        if(_root AND VCPKG_TARGET_TRIPLET AND IS_DIRECTORY "${_root}/${VCPKG_TARGET_TRIPLET}/bin")
            list(APPEND _lsd2dsl_dll_dirs "${_root}/${VCPKG_TARGET_TRIPLET}/bin")
        endif()
    endforeach()
    list(APPEND _lsd2dsl_dll_dirs "${CMAKE_CURRENT_BINARY_DIR}")
    list(REMOVE_DUPLICATES _lsd2dsl_dll_dirs)
    message(STATUS "runtime DLL search path: ${_lsd2dsl_dll_dirs}")

    install(CODE "set(LSD2DSL_DLL_DIRS \"${_lsd2dsl_dll_dirs}\")")
    install(CODE "set(LSD2DSL_BINDIR \"${CMAKE_INSTALL_BINDIR}\")")
    install(CODE [[
        set(_bindir "${CMAKE_INSTALL_PREFIX}/${LSD2DSL_BINDIR}")
        file(GET_RUNTIME_DEPENDENCIES
            EXECUTABLES "${_bindir}/lsd2dsl.exe"
            RESOLVED_DEPENDENCIES_VAR _resolved
            UNRESOLVED_DEPENDENCIES_VAR _unresolved
            DIRECTORIES ${LSD2DSL_DLL_DIRS}
            PRE_EXCLUDE_REGEXES "^api-ms-" "^ext-ms-" "^hvsifiletrust" "^pdmutilities"
                                "^wpaxholder" "^wtd" "^azureattest"
        )
        # Qt is windeployqt's job; the rest ship with Windows or the VC++
        # redistributable. Filtering happens here rather than through
        # PRE/POST_EXCLUDE_REGEXES because the case of the names CMake matches
        # against is not guaranteed on Windows.
        set(_skip "^qt6" "^d3d" "^dxgi" "^opengl32" "^vcruntime" "^msvcp" "^concrt" "^ucrtbase")

        function(lsd2dsl_is_skipped _path _out)
            get_filename_component(_name "${_path}" NAME)
            string(TOLOWER "${_name}" _lname)
            string(TOLOWER "${_path}" _lpath)
            if(_lpath MATCHES "[/\\](system32|syswow64|windows)[/\\]")
                set(${_out} TRUE PARENT_SCOPE)
                return()
            endif()
            foreach(_re IN LISTS _skip)
                if(_lname MATCHES "${_re}")
                    set(${_out} TRUE PARENT_SCOPE)
                    return()
                endif()
            endforeach()
            set(${_out} FALSE PARENT_SCOPE)
        endfunction()

        set(_staged "")
        foreach(_dll IN LISTS _resolved)
            file(TO_CMAKE_PATH "${_dll}" _path)
            lsd2dsl_is_skipped("${_path}" _skipped)
            if(_skipped)
                continue()
            endif()
            file(INSTALL
                DESTINATION "${_bindir}"
                TYPE SHARED_LIBRARY
                FOLLOW_SYMLINK_CHAIN
                FILES "${_path}")
            get_filename_component(_name "${_path}" NAME)
            list(APPEND _staged "${_name}")
        endforeach()
        message(STATUS "staged runtime DLLs: ${_staged}")

        # "Unresolved" only means "not found in the directories above", which is
        # true of every DLL Windows itself provides (and of Qt, deployed by
        # windeployqt). It is informational; the packaging gate is the archive
        # content check in .github/workflows/release.yml.
        set(_external "")
        foreach(_dep IN LISTS _unresolved)
            lsd2dsl_is_skipped("${_dep}" _skipped)
            if(NOT _skipped)
                list(APPEND _external "${_dep}")
            endif()
        endforeach()
        if(_external)
            message(STATUS "runtime dependencies provided by the system: ${_external}")
        endif()
    ]])
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

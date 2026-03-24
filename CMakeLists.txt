cmake_minimum_required(VERSION 3.16)

project(Orbital VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 必须开启 AUTOMOC，否则 Qt6 无法为 C++ 类生成 QML 元数据
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# 查找 Qt 库
find_package(Qt6 COMPONENTS Quick Core Network REQUIRED)

# Adopt current Qt QML module policies explicitly.
qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

# 获取当前 Git 提交的短哈希值
find_package(Git)
if(GIT_FOUND)
    execute_process(
        COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_HASH
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    # 检测是否有未提交的更改
    execute_process(
        COMMAND ${GIT_EXECUTABLE} status --porcelain
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_DIRTY
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(NOT "${GIT_DIRTY}" STREQUAL "")
        set(GIT_HASH "${GIT_HASH}-dirty")
    endif()
endif()

# 如果没获取到（比如源码不是git克隆的），给个默认值
if("${GIT_HASH}" STREQUAL "")
    set(GIT_HASH "dev-build")
endif()

message(STATUS "Current Git Hash: ${GIT_HASH}")

# 添加可执行文件
qt_add_executable(appOrbital
    src/main.cpp
    src/SystemMonitor.h
    src/SystemMonitor.cpp
    src/backend/SystemHelpers.h
    src/backend/SystemStatsBackend.h
    src/backend/SystemStatsBackend.cpp
    src/backend/DisplayBackend.h
    src/backend/DisplayBackend.cpp
    src/backend/WifiBackend.h
    src/backend/WifiBackend.cpp
    src/backend/TerminalLineModel.h
    src/backend/TerminalLineModel.cpp
    src/backend/TerminalBackend.h
    src/backend/TerminalBackend.cpp
)

target_compile_definitions(appOrbital
    PRIVATE
    GIT_COMMIT_HASH="${GIT_HASH}" 
)

set_target_properties(appOrbital PROPERTIES
    OUTPUT_NAME "Orbital"
)

# 注册 QML 模块
qt_add_qml_module(appOrbital
    URI "MyDesktop.Backend"
    VERSION 1.0
    RESOURCE_PREFIX "/"
    QML_FILES 
        qml/Main.qml
        qml/CircleProgress.qml
        qml/LineChart.qml
        qml/SettingsPage.qml
        qml/WifiPage.qml
        qml/CustomKeyboard.qml
        qml/WifiConnectPage.qml
        qml/AboutPage.qml
        qml/TerminalView.qml
        qml/TerminalPage.qml
    RESOURCES
        assets/logo.svg
        assets/power.svg
        assets/restart.svg
        assets/refresh.svg
        assets/settings.svg
        assets/lock.svg
        assets/check.svg
        assets/wifi.svg
        assets/brightness.svg
        assets/wifi-off.svg
        assets/wifi_4.svg
        assets/wifi_3.svg
        assets/wifi_2.svg
        assets/wifi_1.svg
        assets/wifi_0.svg
        assets/eye.svg
        assets/eye-off.svg
        assets/info.svg
        assets/delete.svg
        assets/back.svg
        assets/shift.svg
        assets/shift-filled.svg
        assets/backspace.svg
        assets/terminal.svg
)

# 链接库
target_link_libraries(appOrbital
    PRIVATE Qt6::Quick Qt6::Core Qt6::Network
)

find_library(UTIL_LIBRARY util)
if(UTIL_LIBRARY)
    target_link_libraries(appOrbital PRIVATE ${UTIL_LIBRARY})
endif()

# 将scripts/run.sh复制到构建目录
configure_file(${CMAKE_SOURCE_DIR}/scripts/run.sh ${CMAKE_BINARY_DIR}/run.sh COPYONLY)

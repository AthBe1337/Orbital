cmake_minimum_required(VERSION 3.16)

project(Orbital VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 必须开启 AUTOMOC，否则 Qt6 无法为 C++ 类生成 QML 元数据
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# 查找 Qt 库
find_package(Qt6 COMPONENTS Quick Core REQUIRED)

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
)

target_compile_definitions(appOrbital
    PRIVATE
    GIT_COMMIT_HASH="${GIT_HASH}" 
)

# 注册 QML 模块
qt_add_qml_module(appOrbital
    URI "MyDesktop.Backend"
    VERSION 1.0
    QML_FILES 
        qml/Main.qml
        qml/CircleProgress.qml
        qml/LineChart.qml
        qml/SettingsPage.qml
    RESOURCES
        assets/logo.svg
        assets/power.svg
        assets/restart.svg
        assets/refresh.svg
        assets/settings.svg
)

# 链接库
target_link_libraries(appOrbital
    PRIVATE Qt6::Quick Qt6::Core
)

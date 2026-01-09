cmake_minimum_required(VERSION 3.16)

project(Op6T_Desktop VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 必须开启 AUTOMOC，否则 Qt6 无法为 C++ 类生成 QML 元数据
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# 查找 Qt 库
find_package(Qt6 COMPONENTS Quick Core REQUIRED)

# 添加可执行文件
qt_add_executable(appOp6T_Desktop
    src/main.cpp
    src/SystemMonitor.h
)

# 注册 QML 模块
qt_add_qml_module(appOp6T_Desktop
    URI "MyDesktop.Backend"
    VERSION 1.0
    QML_FILES 
        qml/Main.qml
        qml/CircleProgress.qml
)

# 链接库
target_link_libraries(appOp6T_Desktop
    PRIVATE Qt6::Quick Qt6::Core
)

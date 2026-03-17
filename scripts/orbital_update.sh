#!/bin/bash

# 遇到任何错误立即退出，保证脚本运行的安全性
set -e

PROJECT_DIR="/root/Orbital"
BUILD_DIR="$PROJECT_DIR/build"
BACKUP_DIR="$BUILD_DIR/.backup"

show_help() {
    echo "Orbital 更新脚本"
    echo "用法: $0 [参数]"
    echo ""
    echo "参数:"
    echo "  -h, --help      显示此帮助信息并退出"
    echo "  -r, --restore   恢复备份（当更新出现问题时使用）"
    echo "  (无参数)        更新 Orbital"
}

restart_and_check_service() {
    echo "=> 正在重启 orbital.service..."
    systemctl restart orbital.service
    
    local max_retries=3
    local retry_count=0
    local wait_time=4
    local error_msg="Could not queue DRM page flip on screen DSI1"

    while [ $retry_count -lt $max_retries ]; do
        echo "=> 正在等待 ${wait_time} 秒以检查服务日志..."
        sleep $wait_time

        # 检查最近 50 行日志中是否包含该 DRM 错误
        if journalctl -u orbital.service -n 50 --no-pager | grep -q "$error_msg"; then
            retry_count=$((retry_count + 1))
            echo "=> [警告] 检测到 DRM 页面翻转权限错误 (尝试 $retry_count/$max_retries)。"
            echo "=> 正在重新启动 orbital.service..."
            systemctl restart orbital.service
        else
            echo "=> 服务运行正常，未检测到 DRM 错误！"
            echo "=> 当前服务状态摘要："
            systemctl status orbital.service --no-pager | head -n 8
            return 0
        fi
    done

    echo "=> [错误] 连续 $max_retries 次重启后仍然出现 DRM 错误，请尝试手动执行 sudo systemctl restart orbital.service 或检查显示权限，如果 Orbital 已正常显示请忽略。"
    # 返回非 0 状态但不中断脚本
    return 1
}

restore_backup() {
    echo "=> 准备恢复备份..."
    if [ ! -d "$BUILD_DIR" ]; then
        echo "错误: 构建目录 $BUILD_DIR 不存在！"
        exit 1
    fi

    cd "$BUILD_DIR"

    if [ -d "$BACKUP_DIR" ]; then
        echo "=> 正在清理当前出错的构建文件 (保留 .backup)..."
        find . -mindepth 1 -maxdepth 1 ! -name ".backup" -exec rm -rf {} +

        echo "=> 正在从 .backup 恢复文件..."
        find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -exec cp -a {} . \;
        echo "=> 备份恢复成功！"
        
        # 调用带检测的重启函数
        restart_and_check_service
    else
        echo "错误: 备份目录 $BACKUP_DIR 不存在，无法恢复！"
        exit 1
    fi
}

build_project() {
    echo "=> 1. 切换到项目目录: $PROJECT_DIR"
    cd "$PROJECT_DIR"

    echo "=> 2. 拉取最新代码..."
    git pull

    echo "=> 3. 切换到构建目录: $BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    echo "=> 4. 处理备份目录: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    # 清空现有的备份内容，以实现“如果存在则覆盖”的逻辑
    find "$BACKUP_DIR" -mindepth 1 -delete

    echo "=> 5. 正在备份当前构建文件到 .backup..."
    # 查找除了 .backup 之外的所有文件和隐藏文件并复制
    find . -mindepth 1 -maxdepth 1 ! -name ".backup" -exec cp -a {} "$BACKUP_DIR/" \;

    echo "=> 6. 正在清理 build 目录下的旧文件..."
    find . -mindepth 1 -maxdepth 1 ! -name ".backup" -exec rm -rf {} +

    echo "=> 7. 运行 CMake ..."
    cmake -DCMAKE_BUILD_TYPE=Release ..

    echo "=> 8. 正在编译..."
    make -j$(nproc)

    echo "=> 9. 启动服务..."
    # 调用带检测的重启函数
    restart_and_check_service

    echo "=> Orbital 更新已完成！"
}

# 参数解析
if [ "$#" -eq 0 ]; then
    build_project
else
    case "$1" in
        -h|--help)
            show_help
            ;;
        -r|--restore)
            restore_backup
            ;;
        *)
            echo "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
fi
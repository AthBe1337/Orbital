![](https://imagehost.athbe.cn/wp-content/uploads/2026/01/1768156951-Orbital-logo.png)

# Orbital

**Orbital** 是一个专为 Linux 移动设备设计的现代化、轻量级桌面环境（Dashboard）。

它基于 **Qt 6** 和 **QML** 构建，旨在以极低的资源占用提供流畅的动画效果和直观的交互体验。

## 截图

![](https://imagehost.athbe.cn/wp-content/uploads/2026/01/1768156959-pintu-fulicat.com-1768156829261.jpg)

## 主要功能

### 主仪表盘
- **CPU、内存、存储、电池**：环形进度卡，点击可查看详细信息
- **网络**：实时上传/下载速率，点击查看各网卡接口详情
- **历史折线图**：CPU、内存、网络 I/O 历史曲线
- **截图**：同时按下音量+ 和音量- 触发，保存到 `--screenshot-dir` 指定目录，未指定时默认保存到 `~/Pictures/Orbital/Screenshots`

### 设置
- 屏幕亮度调节
- WiFi 管理
- LED 控制
- 系统详情
- 关于

### WiFi 管理
- 开关 WiFi，自动扫描周边热点
- 连接新网络（内置软键盘输入密码）
- 已保存网络的自动连接开关、忘记网络
- 已连接网络的 IP、MAC、信号强度详情

### LED 控制
- 统一切换所有 LED 的 trigger 模式（manual、default-on、heartbeat 等）
- 全局亮度调节
- 闪光灯亮度与时长控制
- 每个 LED 独立调节

### 系统详情
- 主机名、运行时间、IP 地址、系统与内核版本、系统负载、根分区使用量
- 各 CPU 核心当前频率
- Top 进程列表（按 CPU 占用排序，可选显示 3 / 5 / 8 / 10 条）
- 温度传感器列表

### 终端
- 持久化 PTY Shell，自动适配终端尺寸
- 工具栏快捷键：Ctrl+C/D/L、Home/End、PgUp/PgDn、粘贴、清屏、重置、字号调节
- 文本选择与复制
- 内置软键盘，终端模式下附加 Esc、Tab、方向键、Ctrl、Alt 功能键

---

## 编译

### 编译依赖

#### Debian / Ubuntu
```bash
sudo apt install cmake g++ git qt6-base-dev qt6-declarative-dev libgl-dev libegl-dev
```

#### Arch Linux
```bash
sudo pacman -S cmake gcc git qt6-base qt6-declarative
```

### 编译步骤

```bash
git clone https://github.com/AthBe1337/Orbital.git
cd Orbital
cmake -B build
cmake --build build -j$(nproc)
```

---

## 运行时依赖

| 功能 | 依赖 |
|------|------|
| WiFi 管理 | NetworkManager（`nmcli`） |
| 显示输出 | Qt eglfs / kms 后端 |
| 触摸输入 | Linux evdev 驱动，Qt evdev 插件 |
| 亮度调节 | `/sys/class/backlight/` 节点可写 |
| LED 控制 | `/sys/class/leds/` 节点可写 |

#### Debian / Ubuntu 运行时包
```bash
sudo apt install libqt6quick6 libqt6qml6 qml6-module-qtquick \
    qml6-module-qtquick-controls qml6-module-qtquick-layouts network-manager
```

---

## 运行

```bash
cd build
./run.sh [选项]
```

### 选项

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `--scale <值>` | Qt 缩放因子 | `2.2` |
| `--touch-input-path <路径>` | 触摸屏 evdev 设备路径 | `/dev/input/event5` |
| `--touch-inhibit-path <路径>` | 触摸抑制 sysfs 路径 | `/sys/devices/...input5/inhibited` |
| `--power-key-path <路径>` | 电源键 evdev 设备路径 | `/dev/input/event0` |
| `--volume-key-path <路径>` | 音量键 evdev 设备路径 | `/dev/input/event3` |
| `--screenshot-dir <路径>` | 截图保存目录 | 空（默认 `~/Pictures/Orbital/Screenshots`） |

`run.sh` 使用 `QT_QPA_PLATFORM=eglfs`，直接在 framebuffer 上运行，无需 X11 或 Wayland。

---

## 移植说明

目前仅在**一加 6T**（Snapdragon 845）上测试通过。移植到其他设备时需根据实际情况调整以下参数：

- **触摸输入路径**：`--touch-input-path`（用 `evtest` 确认正确设备）
- **触摸抑制路径**：`--touch-inhibit-path`（不支持的设备可指向不存在的路径）
- **电源键/音量键路径**：`--power-key-path`、`--volume-key-path`
- **缩放因子**：`--scale`（根据屏幕分辨率和 DPI 调整）

## 贡献

欢迎提交 Issue 或 Pull Request！如果你有关于性能优化或新功能的建议，请随时联系。

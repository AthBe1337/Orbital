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

### Modem 管理
- 查看 3GPP modem 的厂商、型号、IMEI、固件、注册状态、运营商、接入技术和信号质量
- 启用或禁用 modem，查看 SIM 卡标识及 PIN 锁定状态（不在 Orbital 中保存或处理 PIN）
- 查看、创建、编辑、连接、断开和删除 NetworkManager GSM 配置
- APN 配置支持连接名、APN 和自动连接开关，优先从现有连接、ModemManager bearer 和运营商数据库自动发现；输入时使用内置虚拟键盘
- 页面每 5 秒自动刷新 modem、SIM 和连接状态

---

## 编译

### 编译依赖

#### Debian / Ubuntu
```bash
sudo apt install build-essential cmake pkg-config git \
    qt6-base-dev qt6-declarative-dev qt6-qpa-plugins \
    libgl-dev libegl-dev libdrm-dev
```

#### Arch Linux
```bash
sudo pacman -S cmake gcc git qt6-base qt6-declarative
```

### 编译步骤

```bash
git clone https://github.com/Alan-mx/Orbital.git
cd Orbital
cmake -B build -DCMAKE_BUILD_TYPE=Release -DORBITAL_BUILD_PLUGINS=ON
cmake --build build -j$(nproc)
```

---

## 运行时依赖

| 功能 | 依赖 |
|------|------|
| WiFi 管理 | NetworkManager（`nmcli`） |
| 蜂窝 modem 管理 | ModemManager（`mmcli`）、NetworkManager（`nmcli`）；自动推荐 APN 可选用 `mobile-broadband-provider-info` |
| 显示输出 | Qt eglfs / kms 后端 |
| 触摸输入 | Linux evdev 驱动，Qt evdev 插件 |
| 亮度调节 | `/sys/class/backlight/` 节点可写 |
| LED 控制 | `/sys/class/leds/` 节点可写 |

#### Debian / Ubuntu 运行时包
```bash
sudo apt install libqt6quick6 libqt6qml6 qml6-module-qtquick \
    qml6-module-qtquick-controls qml6-module-qtquick-layouts \
    qml6-module-qtquick-shapes network-manager
```

使用 Modem 插件还需要安装并运行 ModemManager：

```bash
sudo apt install modemmanager mobile-broadband-provider-info
sudo systemctl enable --now ModemManager
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
| `--scale <值>` | Qt 缩放因子 | OnePlus 6 为 `2.15`，OnePlus 6T/未知设备为 `2.2` |
| `--touch-input-path <路径>` | 触摸屏 evdev 设备路径 | 自动发现；OnePlus 6T 可回退 `/dev/input/event5` |
| `--touch-inhibit-path <路径>` | 触摸抑制 sysfs 路径 | 自动发现 RMI4 设备节点 |
| `--power-key-path <路径>` | 电源键 evdev 设备路径 | 自动发现；OnePlus 6T 可回退 `/dev/input/event0` |
| `--volume-key-path <路径>` | 音量键 evdev 设备路径 | 自动发现；OnePlus 6T 可回退 `/dev/input/event3` |
| `--screenshot-dir <路径>` | 截图保存目录 | 空（默认 `~/Pictures/Orbital/Screenshots`） |

`run.sh` 使用 `QT_QPA_PLATFORM=eglfs`，直接在 framebuffer 上运行，无需 X11 或 Wayland。

---

## 设备适配

启动脚本会根据设备树自动识别 OnePlus 6 和 OnePlus 6T：

| 设备 | 设备树 compatible | 默认缩放 | 分辨率 |
|---|---|---|---|
| OnePlus 6 | `oneplus,enchilada` | `2.15` | `1080 × 2280` |
| OnePlus 6T | `oneplus,fajita` | `2.2` | `1080 × 2340` |

触摸屏、电源键和音量键通过 sysfs 设备名称与真实路径自动发现。发现结果不唯一时不会猜测 event 编号。可使用 `ORBITAL_DEVICE` 强制选择 profile：

```bash
ORBITAL_DEVICE=oneplus-enchilada ./run.sh
```

启动时会输出最终 profile、缩放和输入设备来源。以下环境变量仍可覆盖自动发现：

```bash
ORBITAL_TOUCH_INPUT_PATH=/dev/input/eventX
ORBITAL_POWER_KEY_PATH=/dev/input/eventY
ORBITAL_VOLUME_KEY_PATH=/dev/input/eventZ
ORBITAL_TOUCH_INHIBIT_PATH=/sys/.../inhibited
```

运行设备 profile 自动测试：

```bash
bash scripts/tests/device-profile-test.sh
bash scripts/tests/run-config-test.sh
```

---

## 移植说明

当前支持配置为 **OnePlus 6 / OnePlus 6T**（Snapdragon 845）。移植到其他设备时需根据实际情况调整以下参数：

- **触摸输入路径**：`--touch-input-path`（用 `evtest` 确认正确设备）
- **触摸抑制路径**：`--touch-inhibit-path`（不支持的设备可指向不存在的路径）
- **电源键/音量键路径**：`--power-key-path`、`--volume-key-path`
- **缩放因子**：`--scale`（根据屏幕分辨率和 DPI 调整）

### WiFi 连接排查

如果 WiFi 列表正常但连接失败，先通过 SSH 验证 NetworkManager：

```bash
systemctl is-active NetworkManager
nmcli -t -f DEVICE,TYPE,STATE device status
nmcli dev wifi connect "SSID" password "PASSWORD"
journalctl -u NetworkManager -n 100 --no-pager
```

Orbital 会在连接失败、`nmcli` 不可用或等待超过 45 秒时显示错误提示。新网络密码页的 Connect 按钮固定在软键盘上方，并与键盘 Done 键共用一次提交逻辑。

## 贡献

欢迎提交 Issue 或 Pull Request！如果你有关于性能优化或新功能的建议，请随时联系。

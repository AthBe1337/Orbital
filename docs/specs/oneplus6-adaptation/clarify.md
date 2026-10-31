# 需求疑问清单（G1）

> 需求名：OnePlus 6 适配 ｜ 日期：2026-10-28 ｜ 输入：用户口头需求 + https://github.com/Alan-mx/Orbital

## 一、歧义项

| # | 问题描述 | 涉及位置 | 建议默认答案 |
|---|---|---|---|
| 1 | “适配 OnePlus 6”是否同时包含 WiFi 页面输入密码后无法点击 Connect 的问题？ | `qml/WifiConnectPage.qml`、`qml/CustomKeyboard.qml` | 包含。把 WiFi 连接按钮移到键盘上方的固定操作区，并保留可观测的点击/连接状态。 |
| 2 | “缩放不准”具体是整体过大/过小、局部页面溢出，还是触摸位置与显示位置不一致？ | `qml/Main.qml` 及各页面固定像素；`scripts/run.sh` | 先同时解决整体默认缩放和设备输入路径；局部溢出以 OnePlus 6 实机截图为准做最小修正。 |
| 3 | 输入设备编号是否要求固定写死为 OnePlus 6 的值？ | `scripts/run.sh`、`src/backend/DisplayBackend.cpp` | 不写死。按设备树识别 OnePlus 6/6T，并支持运行时自动发现和命令行覆盖。 |
| 4 | 是否要求继续兼容 OnePlus 6T 和现有命令行参数？ | `scripts/run.sh`、QML 页面 | 必须兼容。OnePlus 6 作为新增设备配置，不改变 6T 现有默认行为。 |
| 5 | 是否需要把固定像素布局全面改成响应式布局？ | `qml/*.qml` | 不做全面重构。只抽取设备级默认缩放并修正一加 6 上实际出现溢出的页面，避免大范围回归。 |
| 6 | 最终交付以源码修改为主，还是还要产出可直接部署的二进制/安装包？ | 仓库整体 | 先交付源码修改、构建说明和验证步骤；当前 Windows 环境不能原生编译 aarch64 Qt 应用，实机验证由用户在 OnePlus 6 执行。 |

## 二、缺失项

- 设备识别：需要确认 OnePlus 6 实机设备树兼容字符串。建议默认按 `oneplus-enchilada` 识别，并保留 `ORBITAL_DEVICE` 手动覆盖。
- 输入路径：缺少 OnePlus 6 的触摸、电源键、音量键实际 event 路径。建议实现按设备能力和名称自动发现，同时允许 `--touch-input-path`、`--power-key-path`、`--volume-key-path` 覆盖。
- 屏幕参数：OnePlus 6 为 `1080 × 2280`，OnePlus 6T 为 `1080 × 2340`。建议 OnePlus 6 初始缩放从 `2.15` 开始，并允许 `--scale` 覆盖。
- WiFi 现象：需要区分“按住按钮没有视觉反馈”“有反馈但页面不返回”“整个应用冻结”三种情况。建议先按触摸命中/键盘遮挡修复，若仍复现再单独走 Bug 根因流程。
- 验证证据：需要用户在 OnePlus 6 上提供主界面、设置页、WiFi 连接页截图，以及 `/proc/bus/input/devices` 输出。
- 构建环境：当前 Windows 主机没有 Qt6、CMake、Make 和 aarch64 工具链。建议先完成静态检查与差异审查，再由用户在设备或 Linux 构建机编译验证。

## 三、与现有逻辑冲突项

| # | 冲突描述 | 现有实现位置 | 建议 |
|---|---|---|---|
| 1 | 默认缩放 `2.2` 和所有 evdev 路径按 OnePlus 6T 写死 | `scripts/run.sh` 第 6-10 行、第 132-136 行 | 增加设备配置层，OnePlus 6 默认使用独立缩放与输入配置，同时保留 CLI 覆盖。 |
| 2 | 触摸抑制路径属于 OnePlus 6T 的具体 I2C/input 路径 | `scripts/run.sh` 第 8 行 | 自动发现失败时允许空路径或设备配置覆盖，避免错误路径影响普通触摸。 |
| 3 | WiFi 密码页的 Connect 按钮位于 ScrollView 内容中，且自定义键盘以高层级覆盖底部 | `qml/WifiConnectPage.qml` 第 267-377 行；`qml/CustomKeyboard.qml` | 将 Connect 放到键盘上方的固定操作栏，并增加忙碌/结果反馈，避免命中区域被遮挡。 |
| 4 | 主窗口使用固定 `360 × 720`，多个页面混用固定像素和比例尺寸 | `qml/Main.qml` 第 10-12 行及各页面 | 不全面重写布局；优先通过设备默认缩放和局部尺寸修正解决实机问题。 |
| 5 | 设备专属参数目前没有集中配置，直接散落在脚本和 QML 中 | `scripts/run.sh`、`src/backend/DisplayBackend.cpp` | 新增统一设备 profile，避免后续 OnePlus 6/6T 或其它 SDM845 设备继续复制硬编码。 |

## 用户回答区

请逐条回答 1-6；缺失项中的实机输出也请一并提供。

建议直接执行并粘贴结果：

```bash
tr -d '\0' </sys/firmware/devicetree/base/compatible
cat /proc/bus/input/devices
cat /sys/class/drm/card0-DSI-1/modes
```

# 规格（G2）

> 需求名：OnePlus 6 适配 ｜ 日期：2026-10-28 ｜ 状态：已确认

## 背景与目标

Orbital 当前按 OnePlus 6T 的屏幕缩放、触摸设备和硬件按键路径调优，在 OnePlus 6 上存在总体尺寸不准确、输入设备编号不一定匹配，以及 WiFi 密码页连接按钮可能被软键盘遮挡或无法命中触摸的问题。

本次目标是在保留 OnePlus 6T 现有行为的前提下，为 OnePlus 6 增加可自动识别、可手动覆盖的设备配置，并修复 WiFi 新网络连接按钮在软键盘弹出后无法可靠点击的问题。

## 用户故事

作为 OnePlus 6 用户，我要 Orbital 自动识别我的设备和输入硬件并使用合适缩放，以便界面完整显示且触摸、电源键和音量键可用。

作为 OnePlus 6 用户，我要在输入 WiFi 密码后可靠点击 Connect，以便完成网络连接而无需 SSH 手工执行 `nmcli`。

作为 OnePlus 6T 或其它设备用户，我要现有启动参数继续可用，以便适配不会造成已有设备回归。

## 验收标准（EARS）

- AC1: WHEN 设备树兼容字符串包含 `oneplus,enchilada` 或兼容关键字 `oneplus-enchilada` 且用户未显式指定缩放值时，THE SYSTEM SHALL 使用 `2.15` 作为默认 Qt 缩放值。
- AC2: WHEN 设备树兼容字符串包含 `oneplus,fajita` 或兼容关键字 `oneplus-fajita` 或无法识别设备时，THE SYSTEM SHALL 保持现有 OnePlus 6T 默认缩放值 `2.2`。
- AC3: WHEN 用户通过 `--scale`、`QT_SCALE_FACTOR` 或现有环境变量指定设备参数时，THE SYSTEM SHALL 使用用户值覆盖设备 profile 默认值。
- AC4: WHEN Orbital 在 OnePlus 6 上启动且触摸屏、电源键、音量键可被系统中唯一识别时，THE SYSTEM SHALL 自动选择对应 evdev 设备，无需用户手工填写 event 编号。
- AC5: IF 自动发现无法唯一确定输入设备，THEN THE SYSTEM SHALL 保留现有 `--touch-input-path`、`--power-key-path`、`--volume-key-path` 参数及环境变量覆盖能力，且不得导致启动失败。
- AC6: WHEN WiFi 密码输入框获得焦点并显示内置软键盘时，THE SYSTEM SHALL 将新网络 Connect 按钮保持在软键盘上方的可见、可点击区域。
- AC7: WHEN 用户点击新网络 Connect 按钮或软键盘 Done 键时，THE SYSTEM SHALL 隐藏软键盘、提交一次 `nmcli` 连接请求、关闭连接详情页并返回 WiFi 列表。
- AC8: WHEN 用户长按 Connect 按钮时，THE SYSTEM SHALL 显示明确按压反馈；操作提交后 SHALL 有可观察的连接中或结果反馈。
- AC9: WHEN 未安装 `nmcli`、NetworkManager 不可用或连接失败时，THE SYSTEM SHALL 保持 Orbital 界面可响应，并展示失败信息而不是静默无响应。
- AC10: WHEN 在 OnePlus 6 横竖屏原生分辨率 `1080 × 2280` 下运行主页面、设置页和 WiFi 页面时，THE SYSTEM SHALL 不出现可交互控件被永久裁切或不可点击。
- AC11: WHEN 在 OnePlus 6T 上使用现有启动方式时，THE SYSTEM SHALL 保持原默认缩放、输入路径和 WiFi 操作流程可用。
- AC12: WHEN 开发者在 Ubuntu 24.04 arm64 环境按 README 安装依赖并执行 CMake Release 构建时，THE SYSTEM SHALL 成功生成 Orbital 可执行文件。

## 字段口径

| 字段 | 类型 | 字典/枚举 | 必填 | 默认 | 说明 |
|---|---|---|---|---|---|
| `device_id` | string | `oneplus-enchilada`、`oneplus-fajita`、`unknown` | 是 | `unknown` | 由设备树兼容字符串推导，并允许环境变量覆盖 |
| `scale` | number | 大于 0 | 是 | 一加 6 为 `2.15`，其它为 `2.2` | 传给 `QT_SCALE_FACTOR`；显式 CLI 参数优先 |
| `screen_width` | integer | 大于 0 | 否 | 一加 6 为 `1080` | 原生像素宽度，用于校验和配置记录 |
| `screen_height` | integer | 大于 0 | 否 | 一加 6 为 `2280` | 原生像素高度，用于校验和配置记录 |
| `touch_input_path` | path | `/dev/input/event*` | 否 | 自动发现 | 触摸屏输入设备 |
| `touch_inhibit_path` | path | sysfs 路径 | 否 | 空或自动发现 | 仅用于屏幕关闭期间的触摸抑制 |
| `power_key_path` | path | `/dev/input/event*` | 否 | 自动发现 | 电源键输入设备 |
| `volume_key_path` | path | `/dev/input/event*` | 否 | 自动发现 | 音量键输入设备 |
| `wifi_connect_state` | enum | `idle`、`connecting`、`success`、`error` | 是 | `idle` | WiFi 连接操作的界面状态 |

## 状态流转

| 当前状态 | 触发 | 目标状态 | 触发者 |
|---|---|---|---|
| `idle` | 点击 Connect 或软键盘 Done | `connecting` | OnePlus 6 用户 |
| `connecting` | `nmcli` 返回成功 | `success` | WifiBackend |
| `connecting` | `nmcli` 返回失败、启动失败或超时 | `error` | WifiBackend |
| `success` | WiFi 列表重新扫描 | `idle` | WifiPage |
| `error` | 用户确认错误或返回 WiFi 列表 | `idle` | OnePlus 6 用户 |

## 权限矩阵

| 操作 | 角色 | 范围 |
|---|---|---|
| 读取设备树、输入设备列表和 DRM 模式 | 本机运行用户 | 只读 |
| 打开触摸屏、电源键、音量键 evdev 设备 | Orbital 运行用户 | 仅已识别的设备节点 |
| 切换 WiFi、读取或写入 NetworkManager 连接 | Orbital 运行用户经 `nmcli` | 当前设备网络连接 |
| 覆盖设备 profile 参数 | 启动 Orbital 的本机管理员 | 当前进程 |

## 非目标

- 不全面重构所有 QML 页面为响应式布局。
- 不新增 GNOME、KDE 或其它桌面环境。
- 不打包或发布 aarch64 二进制、APK、系统镜像或安装包。
- 不修改内核、initramfs、rootfs 或网络驱动。
- 不保证未提供实机验证的其它 SDM845 设备。
- 不自动提交或推送 git。

## 影响面

- 涉及模块：启动配置、设备识别、输入设备发现、WiFi 连接页面、WiFi 后端状态反馈、README。
- 涉及表：无。
- 关联端是否同步：无其它端；保持 GitHub fork 内源码可独立构建。

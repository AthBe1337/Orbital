# 设计（G3）

> 需求名：OnePlus 6 适配 ｜ 日期：2026-10-28 ｜ 阶段：1. 数据结构设计（待确认）

## 证据与修正

- pmOS/SDM845 设备树中，一加 6 的兼容字符串是 `oneplus,enchilada`，一加 6T 是 `oneplus,fajita`。
- G2 AC1 写的是 `oneplus-enchilada`，这是识别关键字的不准确表述；行为目标不变。
- 数据结构同时接受规范值 `oneplus,enchilada` 和兼容关键字 `oneplus-enchilada`，设备树规范值优先。
- 两款设备在公共设备树中使用同一个 Synaptics RMI4 触摸控制器，以及同一组电源/音量键定义，因此不应把固定 `eventN` 当作设备身份。

## 设计决定

1. 设备 profile 放在启动层，以 Bash 数据结构维护。原因是缩放必须在启动 Qt 前设置，输入路径也通过现有 `ORBITAL_*` 环境变量传给 C++，无需引入新进程或数据库。
2. 配置优先级固定为：命令行参数 > 环境变量 > 设备 profile > 旧版 OnePlus 6T 默认值。
3. 自动发现输入设备只读取 `/sys/class/input/event*` 和 `/sys/devices`，不新增 Python、libinput、evtest 等运行时依赖。
4. 自动发现不能唯一确定设备时保留空值或旧默认值，并继续启动，不能因为识别失败阻断 Orbital。
5. WiFi 操作状态由 `WifiPage` 持有，因为 `WifiConnectPage` 会在提交后关闭；`WifiConnectPage` 只产生连接请求，不持有最终结果。

## 数据结构一：设备 profile

### 静态 profile 表

每个 profile 由相同字段组成：

| 字段 | 示例：OnePlus 6 | 示例：OnePlus 6T | 说明 |
|---|---|---|---|
| `id` | `oneplus-enchilada` | `oneplus-fajita` | 稳定的设备标识 |
| `model` | `OnePlus 6` | `OnePlus 6T` | 用于日志与文档 |
| `compatible_tokens` | `oneplus,enchilada`、`oneplus-enchilada` | `oneplus,fajita`、`oneplus-fajita` | 设备树匹配关键字，按顺序匹配 |
| `scale` | `2.15` | `2.2` | 默认 `QT_SCALE_FACTOR` |
| `screen_width` | `1080` | `1080` | 原生像素宽度 |
| `screen_height` | `2280` | `2340` | 原生像素高度 |
| `touch_name_patterns` | `synaptics`、`rmi4`、`touch` | 同左 | 触摸设备名称候选 |
| `touch_path_patterns` | `/rmi4-` | `/rmi4-` | 解析设备真实路径时的匹配 |
| `touch_inhibit_glob` | `*/rmi4-00/input/input*/inhibited` | 同左 | sysfs 触摸抑制节点 |
| `power_name_patterns` | `pm8941_pwrkey`、`pwrkey`、`Power Button` | 同左 | 电源键名称候选 |
| `volume_name_patterns` | `Volume keys`、`volume` | 同左 | 音量键名称候选 |
| `legacy_touch_path` | 空 | `/dev/input/event5` | 自动发现失败时只供 6T 回退 |
| `legacy_power_path` | 空 | `/dev/input/event0` | 自动发现失败时只供 6T 回退 |
| `legacy_volume_path` | 空 | `/dev/input/event3` | 自动发现失败时只供 6T 回退 |

### 运行时配置对象

启动脚本解析后形成一组只读运行时字段：

| 字段 | 类型 | 来源 | 规则 |
|---|---|---|---|
| `ORBITAL_PROFILE_ID` | string | 自动识别或 `ORBITAL_DEVICE` | 未识别时为 `unknown` |
| `ORBITAL_PROFILE_MODEL` | string | profile | 用于启动日志 |
| `SCALE_VALUE` | decimal string | CLI、环境、profile | 必须能由 `awk` 判定为大于 0 的数字 |
| `TOUCH_INPUT_PATH` | path | CLI、环境、自动发现、legacy | 不存在时不得导出无效 `QT_QPA_GENERIC_PLUGINS` |
| `TOUCH_INHIBIT_PATH` | path | 环境、自动发现、profile | 不存在时允许为空 |
| `POWER_KEY_PATH` | comma path list | CLI、环境、自动发现、legacy | C++ 已支持逗号分隔多路径 |
| `VOLUME_KEY_PATH` | comma path list | CLI、环境、自动发现、legacy | C++ 已支持逗号分隔多路径 |
| `ORBITAL_INPUT_SOURCE` | enum | 启动脚本 | `override`、`auto`、`legacy`、`unresolved` |

## 数据结构二：输入设备候选

扫描 `/sys/class/input/event*/device/name` 时，每个候选项包含：

| 字段 | 类型 | 说明 |
|---|---|---|
| `event_path` | path | `/dev/input/eventN` |
| `name` | string | sysfs 中的设备名，匹配时统一转小写 |
| `resolved_sysfs_path` | path | `realpath` 后的 sysfs 路径 |
| `kind` | enum | `touch`、`power`、`volume`、`other` |

分类规则：

1. `touch`：名称包含触摸关键字，或真实路径包含 `/rmi4-`。
2. `volume`：名称包含 `volume`，优先精确匹配 `volume keys`。
3. `power`：名称包含 `pwrkey` 或 `power button`。
4. 同一类别恰好一个候选时自动使用；零个或多个候选时不猜测。
5. 自动发现结果不得覆盖显式 CLI 或环境变量。

## 数据结构三：WiFi 操作状态

`WifiPage` 新增并持有一个活动操作对象：

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `operation` | enum | 空 | 当前支持的值为 `connect`、`disconnect`、`forget`、`toggle` |
| `ssid` | string | 空 | 本次操作对应的网络；`toggle` 允许为空 |
| `state` | enum | `idle` | `idle`、`connecting`、`success`、`error` |
| `message` | string | 空 | 用户可读结果或 `nmcli` 错误摘要 |
| `requestId` | integer | 0 | 防止旧异步结果覆盖新操作 |

`WifiConnectPage` 只保留：

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `password` | string | 空 | 当前输入的密码 |
| `isSubmitting` | bool | `false` | 防止重复点击 |
| `keyboardVisible` | bool | 自动 | 与内置软键盘可见状态同步 |

状态变化规则：

1. 提交时设置 `isSubmitting=true`，立即隐藏键盘并发送一次连接请求。
2. `WifiPage.state` 从 `idle` 进入 `connecting`，显示“正在连接 SSID”。
3. 成功进入 `success`，失败或启动 `nmcli` 失败进入 `error`。
4. 只有与当前 `requestId` 相同的结果才能改变状态。
5. 操作结束后重新扫描 WiFi，状态在结果提示完成后回到 `idle`。

## 文件归属

| 文件 | 数据结构职责 |
|---|---|
| `scripts/device-profile.sh`（新增） | OnePlus 6/6T 静态 profile、设备树识别结果、输入候选与解析结果 |
| `scripts/run.sh` | 合并 CLI/环境/profile 优先级，导出最终运行时字段 |
| `qml/WifiPage.qml` | 持有 WiFi 活动操作状态和用户提示 |
| `qml/WifiConnectPage.qml` | 持有密码、提交锁和键盘状态 |
| `src/backend/WifiBackend.*` | 生成可区分成功、执行失败、启动失败和超时的操作结果；不持有 QML 状态 |

## 接口清单（阶段 2）

### 启动脚本接口

新增 `scripts/device-profile.sh`，只定义函数和静态 profile，不在 source 时执行有副作用的操作。

| 接口 | 入参 | 输出 / 返回 | 职责 |
|---|---|---|---|
| `orbital_detect_device_id` | 环境变量 `ORBITAL_DEVICE`（可选） | stdout：`oneplus-enchilada`、`oneplus-fajita`、`unknown`；返回 0 | 读取设备树 compatible；显式 `ORBITAL_DEVICE` 优先；同时接受规范值和兼容关键字 |
| `orbital_profile_get <profile-id> <field>` | profile id、字段名 | stdout：字段值；未知 profile/字段返回 1 | 提供 `scale`、分辨率、名称/路径匹配模式、legacy 路径 |
| `orbital_discover_input_path <kind>` | `touch`、`power`、`volume` | stdout：唯一 `/dev/input/eventN`；零个或多个候选返回 1 | 扫描 event 名称和真实路径，不输出歧义结果 |
| `orbital_discover_touch_inhibit_path <profile-id>` | profile id | stdout：存在的 `inhibited` 文件路径；未找到返回 1 | 按 profile glob 查找 OnePlus 6/6T 的 RMI4 触摸抑制节点 |
| `orbital_validate_scale <value>` | 缩放字符串 | 有效返回 0，无效返回 1 | 要求为大于 0 的十进制数 |

测试用可选环境变量：

| 变量 | 默认 | 用途 |
|---|---|---|
| `ORBITAL_DEVICE` | 自动检测 | 强制选择 profile |
| `ORBITAL_DEVICE_TREE_COMPATIBLE_FILE` | `/sys/firmware/devicetree/base/compatible` | 设备识别测试夹具 |
| `ORBITAL_SYS_CLASS_INPUT_ROOT` | `/sys/class/input` | 输入设备发现测试夹具 |
| `ORBITAL_DEV_INPUT_ROOT` | `/dev/input` | 输入设备发现结果的测试路径前缀 |
| `ORBITAL_EXECUTABLE` | `./Orbital` | 测试时替换真实 Qt 可执行文件 |

### `scripts/run.sh` 接口与优先级

保留现有 CLI 和环境变量，不新增用户必须学习的参数：

| 参数 / 环境变量 | 优先级 | 缺省行为 |
|---|---|---|
| `--scale` | 最高 | 使用 `QT_SCALE_FACTOR` 环境变量，否则使用 profile scale |
| `QT_SCALE_FACTOR` | 次高 | 使用 profile scale |
| `--touch-input-path` / `ORBITAL_TOUCH_INPUT_PATH` | 高于自动发现 | 自动发现唯一触摸设备；OnePlus 6T 可回退 `/dev/input/event5` |
| `--power-key-path` / `ORBITAL_POWER_KEY_PATH` | 高于自动发现 | 自动发现唯一电源键；OnePlus 6T 可回退 `/dev/input/event0` |
| `--volume-key-path` / `ORBITAL_VOLUME_KEY_PATH` | 高于自动发现 | 自动发现唯一音量键；OnePlus 6T 可回退 `/dev/input/event3` |
| `--touch-inhibit-path` / `ORBITAL_TOUCH_INHIBIT_PATH` | 高于自动发现 | 自动查找；失败时允许为空 |

输出规则：

1. 启动时向 stderr 打印一次 profile id、scale 和最终输入来源，便于实机排查。
2. 触摸路径为空时不得设置带空设备值的 `QT_QPA_GENERIC_PLUGINS`。
3. 无效缩放值打印错误并回退到 profile scale，不阻断启动。
4. 无效手动输入路径打印警告，但不阻断界面启动。
5. 既有 `ORBITAL_TOUCH_INPUT_PATH`、`ORBITAL_POWER_KEY_PATH`、`ORBITAL_VOLUME_KEY_PATH` 行为保持兼容。

### WiFi 后端接口

| 接口 | 入参 | 输出 / 返回 | 职责 |
|---|---|---|---|
| `int WifiBackend::connectToWifi(QString ssid, QString password)` | SSID、密码 | 本次请求的递增 `requestId` | 启动异步 `nmcli dev wifi connect`，关联请求与结果 |
| `signal WifiBackend::wifiConnectResult(int requestId, bool success, QString message)` | 请求 id、结果、消息 | 无 | 只用于 connect，避免旧逻辑无法区分请求、启动失败与超时 |
| `signal WifiBackend::wifiOperationResult(QString operation, bool success, QString message)` | 操作名、结果、消息 | 无 | 继续服务 disconnect、forget、toggle，不改变现有行为 |

错误覆盖：

1. `QProcess::FailedToStart` 立即产生一次失败结果，消息为 `nmcli unavailable` 或等价可读文本。
2. 进程 45 秒未退出时终止进程并产生一次超时失败结果。
3. 正常非零退出使用 stderr；stderr 为空时提供非空通用错误消息。
4. 同一请求最多产生一次结果，避免 finished、errorOccurred、timeout 重复上报。

### WiFi QML 接口

| 接口 | 入参 | 输出 / 返回 | 职责 |
|---|---|---|---|
| `WifiConnectPage.connectionRequested(String ssid, String password)` | 新网络 SSID、密码 | 无 | 密码页只在用户提交时发出一次连接请求 |
| `WifiConnectPage.submitConnection()` | 无 | 无 | 校验非提交中状态、隐藏键盘、发出信号并关闭页面 |
| `WifiPage.beginConnect(String ssid, String password)` | SSID、密码 | 无 | 调用后端获取 requestId，保存活动状态并显示连接中提示 |
| `WifiPage.handleConnectResult(int requestId, bool success, String message)` | 请求 id、结果、消息 | 无 | 仅处理当前 requestId；成功显示成功提示，失败显示错误并恢复列表 |
| `WifiPage.connectState` | 无 | `idle`、`connecting`、`success`、`error` | 供页面显示 Toast 或行内状态 |

页面行为：

1. 新网络 Connect 放在独立底部操作栏，`anchors.bottom` 跟随软键盘顶部。
2. Connect 和键盘 Done 共用 `submitConnection()`，`isSubmitting` 防止重复提交。
3. 提交后密码页关闭，`WifiPage` 显示 `Connecting to <SSID>`。
4. 匹配 `requestId` 的结果到达后显示成功或错误；不影响当前仍可操作的 WiFi 列表。
5. 已保存网络的 Connect 也改走 `WifiPage.beginConnect()`，避免两套连接流程。

## 实现任务清单

| 任务 | 修改位置 | 内容 | 覆盖 AC |
|---|---|---|---|
| T1 | `scripts/device-profile.sh`（新增） | 静态 profile、设备识别、输入发现、触摸抑制发现、缩放校验 | AC1、AC2、AC4、AC5 |
| T2 | `scripts/run.sh` | source profile；实现 CLI > 环境 > profile > legacy 的优先级；安全导出 Qt/Orbital 环境变量 | AC1、AC2、AC3、AC4、AC5、AC11 |
| T3 | `scripts/tests/device-profile-test.sh`（新增） | 用临时 compatible/sysfs 夹具验证设备识别、唯一/歧义输入、缩放校验 | AC1、AC2、AC4、AC5 |
| T4 | `src/backend/WifiBackend.h/.cpp` | requestId、专用 connect 结果、FailedToStart、超时和单次结果保护 | AC7、AC9 |
| T5 | `qml/WifiPage.qml` | 持有活动连接状态，处理 requestId 结果，连接中和错误提示；已保存网络统一走新流程 | AC7、AC8、AC9、AC11 |
| T6 | `qml/WifiConnectPage.qml` | 固定底部 Connect 操作栏、Done 统一提交、提交锁、隐藏键盘 | AC6、AC7、AC8、AC9、AC10 |
| T7 | `README.md` | 设备差异、依赖、构建、OnePlus 6 使用和故障排查说明 | AC10、AC11、AC12 |
| T8 | 构建与静态检查 | Shell 测试、QML 静态检查/构建命令、设备端验证清单 | AC12 |

## AC 覆盖自检

| AC | 对应任务 |
|---|---|
| AC1 | T1、T2、T3 |
| AC2 | T1、T2、T3 |
| AC3 | T2 |
| AC4 | T1、T2、T3 |
| AC5 | T1、T2、T3 |
| AC6 | T6 |
| AC7 | T4、T5、T6 |
| AC8 | T5、T6 |
| AC9 | T4、T5、T6 |
| AC10 | T6、T7 |
| AC11 | T2、T5 |
| AC12 | T7、T8 |

无未覆盖 AC。

## 实现级裁决

- 不新增 `--device` CLI，使用 `ORBITAL_DEVICE` 作为测试和手动覆盖入口，避免扩大用户参数面。
- WiFi connect 使用专用信号，不改变其它 WiFi 操作的现有信号，降低回归范围。
- 连接超时定为 45 秒，覆盖 DHCP 与认证的常见等待时间。

## 待确认

- 是否确认上述脚本函数、保留参数与实际优先级。
- 是否确认 WiFi 使用新增 `wifiConnectResult(requestId, success, message)`，其它操作继续使用原信号。
- 是否确认实现任务 T1-T8 的拆分与 AC 映射。

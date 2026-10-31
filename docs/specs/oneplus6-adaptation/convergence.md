# 收敛检查（G5）

> 需求：OnePlus 6 适配 ｜ 日期：2026-10-28 ｜ 结论：待实机验证

## 本次可重复验证

| 检查 | 结果 |
|---|---|
| `bash -n scripts/device-profile.sh scripts/run.sh scripts/tests/device-profile-test.sh scripts/tests/run-config-test.sh` | 通过 |
| `bash scripts/tests/device-profile-test.sh` | 通过，输出 `All device profile tests passed` |
| `bash scripts/tests/run-config-test.sh` | 通过，输出 `All run configuration tests passed` |
| QML 括号静态检查 | `WifiPage.qml`、`WifiConnectPage.qml` 均为 0 差 |
| `git diff --check` | 通过 |
| C++/Qt 构建 | 未执行：当前 Windows 主机无 CMake、Qt6 和 aarch64 构建环境 |
| OnePlus 6 实机触摸/缩放/WiFi | 未执行：当前会话无设备访问 |

## AC 逐条检查

| AC | 状态 | 证据 / 差距 |
|---|---|---|
| AC1 | 通过（静态） | OnePlus 6 profile 输出 `2.15`；规范化 compatible 与兼容关键字均有测试 |
| AC2 | 通过（静态） | OnePlus 6T profile 输出 `2.2`；未知设备使用同一默认值 |
| AC3 | 通过 | `run-config-test.sh` 验证 CLI 缩放覆盖环境变量，非法值回退 profile |
| AC4 | 通过（夹具） | 唯一触摸/电源/音量设备发现测试通过 |
| AC5 | 通过（夹具） | 多个触摸候选时拒绝猜测；环境/CLI 覆盖测试通过 |
| AC6 | 待实机 | Connect 已固定在软键盘上方，需在 OnePlus 6 验证触摸命中 |
| AC7 | 待实机 | 新网络与已保存网络统一提交，需验证页面返回和 `nmcli` 调用 |
| AC8 | 待实机 | 按压颜色与连接中 Toast 已实现，需肉眼验证 |
| AC9 | 待构建/实机 | `nmcli` 启动失败和 45 秒超时已实现，需编译后制造失败场景 |
| AC10 | 待实机 | 需主界面、设置页、WiFi 页 `1080 × 2280` 截图 |
| AC11 | 待实机 | 需 OnePlus 6T 回归，至少验证启动、触摸、WiFi |
| AC12 | 待构建 | 需 Qt6/CMake 环境执行 Release 构建 |

## 当前结论

实现和可离线验证的部分已完成。AC6-AC12 缺少本轮构建或实机证据，因此不能声明完全收敛。

## 设备端验证命令

```bash
sudo apt update
sudo apt install -y build-essential cmake pkg-config git \
  qt6-base-dev qt6-declarative-dev qt6-qpa-plugins \
  libgl-dev libegl-dev libdrm-dev \
  libqt6quick6 libqt6qml6 \
  qml6-module-qtquick qml6-module-qtquick-controls \
  qml6-module-qtquick-layouts qml6-module-qtquick-shapes \
  network-manager modemmanager mobile-broadband-provider-info

bash scripts/tests/device-profile-test.sh
bash scripts/tests/run-config-test.sh

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DORBITAL_BUILD_PLUGINS=ON
cmake --build build -j"$(nproc)"

sudo systemctl stop orbital.service
sudo ./build/run.sh
```

验证重点：

1. 启动日志应显示 `OnePlus 6 (oneplus-enchilada), scale=2.15`。
2. 触摸、电源键、音量键应显示为 `auto`；若为 `unresolved`，记录启动日志。
3. WiFi 输入密码后 Connect 应始终位于键盘上方并能点击。
4. 成功和失败都应在 WiFi 列表页出现 Toast。

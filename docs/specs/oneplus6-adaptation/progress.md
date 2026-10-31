# 实施进度

> 需求：OnePlus 6 适配 ｜ 开始日期：2026-10-28

| 任务 | 状态 | 验证证据 | 裁决记录 |
|---|---|---|---|
| T1 设备 profile 与输入发现函数 | 完成 | `bash -n scripts/device-profile.sh` 返回 0；`ORBITAL_DEVICE=oneplus-enchilada` 输出正确 id 与 `2.15`；非法缩放被拒绝 | 无 |
| T2 启动脚本接入 profile | 完成 | `bash -n scripts/run.sh` 返回 0；OnePlus 6 默认输出 `scale=2.15`；`--scale 2.05` 覆盖成功；非法缩放回退到 `2.15` | C++ 环境读取改为“变量已设置即采用”，使显式空触摸抑制路径不会回退到 6T 路径；代价是调用方需避免设置无意义空值 |
| T3 设备 profile 自动测试 | 完成 | `bash -n scripts/tests/device-profile-test.sh` 返回 0；`bash scripts/tests/device-profile-test.sh` 输出 `All device profile tests passed` | 增加 `ORBITAL_DEV_INPUT_ROOT` 作为测试夹具；仅影响测试，不改变设备默认路径 |
| T4 WiFi 后端请求编号与错误处理 | 实现完成，构建待验证 | 静态检查确认 `connectToWifi` 返回 `int`、`wifiConnectResult` 已从 `WifiBackend` 转发到 `SystemMonitor`；当前 Windows 环境无 Qt 工具链，无法编译 | 无 |
| T5 WiFi 页面连接状态 | 实现完成，QML 运行待验证 | `WifiPage.qml` 已保存 `activeConnectRequestId`/`connectState`；旧直接 `backend.connectToWifi` 仅保留在 `beginConnect()`；QML 括号静态检查通过 | 使用 `StackView.push()` 返回页面对象后连接 `connectionRequested` 信号，沿用现有 QML 导航方式 |
| T6 WiFi 固定连接操作栏 | 实现完成，实机触摸待验证 | Connect 已移出 ScrollView，底部操作栏跟随软键盘顶部；Connect 与 Done 共用 `submitConnection()`；`isSubmitting` 防止重复提交；QML 括号静态检查通过 | 保留页面提交后立即关闭的现有交互，连接结果改由 WiFi 列表页提示 |
| T7 README 与构建说明 | 完成 | README 已补充 OnePlus 6/6T profile、依赖、自动输入发现、覆盖变量、测试命令与 WiFi 排查 | 构建命令默认启用内置插件 |
| T8 构建与设备验证 | 阻塞，待设备验证 | Shell 测试、run 配置测试、QML 括号检查、`git diff --check` 均通过；当前主机无 Qt/CMake，无法执行 CMake 构建和实机触摸测试 | 不把静态检查冒充构建或实机验证 |

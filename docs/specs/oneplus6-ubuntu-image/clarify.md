# 需求疑问清单（G1）

> 需求名：OnePlus 6 Ubuntu 系统镜像 ｜ 日期：2026-10-28 ｜ 输入：用户口头需求 + pmOS/Nura `v26.06` 官方包

## 一、歧义项

| # | 问题描述 | 涉及位置 | 建议默认答案 |
|---|---|---|---|
| 1 | “做这个 img”是只制作基础 Ubuntu 24.04 ARM64 系统，还是同时编入当前 `D:\workspace\Orbital` 并作为默认图形界面启动？ | `rootfs` 内容、Orbital 启动服务 | 同时编入当前 `D:\workspace\Orbital`。基础版只作为启动失败时的诊断备用目标。 |
| 2 | Orbital 使用当前工作区中尚未提交的源码，还是使用 GitHub 上已发布的某个版本？ | `D:\workspace\Orbital`、`rootfs/opt/orbital` | 使用当前工作区源码；在镜像清单中记录 git commit 和未提交差异，保证可追溯。 |
| 3 | “使用 `v26.06`”是固定 pmOS 稳定分支中的内核、设备、固件二进制包，还是从该分支重新编译全部组件？ | `linux-postmarketos-qcom-sdm845 7.1_rc1-r0`、`device-oneplus-enchilada` | 优先使用 `v26.06` 已打包的 aarch64 二进制包；只有 initramfs 或 boot image 需要本地重新组装。 |
| 4 | 最终产物是否要求完整包含 `boot.img`、同版本内核模块、固件和 Android sparse rootfs，而不是复用分享中的旧 `boot.img`？ | `boot.img`、`/lib/modules`、`/lib/firmware`、`rootfs-*.img` | 是。全部基于同一个 `v26.06` 内核构建，禁止与作者旧镜像混用。 |

## 二、缺失项

- 构建环境：当前 Windows 主机已安装 Docker Desktop，但服务未启动；没有 WSL Linux 发行版、fastboot、adb、CMake 和 Qt6。建议使用 Docker Desktop 的 Ubuntu 24.04 容器配合 `qemu-user-static` 构建 ARM64 rootfs。
- 磁盘空间：`D:\` 当前可用约 195.6 GiB，足够保存 10 GiB rootfs、临时解包目录和最终镜像；建议所有大文件放在 `D:\workspace`，不占 C 盘。
- 存储规格：用户的一加 6 可能是 64/128/256 GiB。建议 rootfs 固定为 10 GiB，小于任意一加 6 的 `userdata`，不重新分区。
- 登录方式：创建普通用户 `orbital`，启用 SSH 账号密码登录；root 密码保持锁定，同时启用 USB RNDIS 网络。
- 网络配置：建议首要保证 USB 网络可登录；WiFi 由 NetworkManager 在设备启动后配置，不把 Wi-Fi 密码写入镜像。
- 实机条件：刷入会清空 `userdata`；一加 6 需要已解锁 bootloader，并接受擦除 `dtbo` 后当前 Android 无法启动。
- 实机验证：当前环境无法代替用户完成触摸、显示、WiFi、电源键和音量键验证；交付物需要包含设备端验证命令和日志采集方式。

## 三、与现有逻辑冲突项

| # | 冲突描述 | 现有实现位置 | 建议 |
|---|---|---|---|
| 1 | 现有 OnePlus 6 适配规格明确“不修改内核、initramfs、rootfs”，也不打包系统镜像 | `docs/specs/oneplus6-adaptation/spec.md` 的“非目标” | 新建独立需求规格；原适配需求保持不扩张，镜像需求单独验收。 |
| 2 | 当前仓库在 Windows 上没有可用的 Linux 构建环境，也没有 Qt6/CMake 工具链 | `docs/specs/oneplus6-adaptation/convergence.md` | 先启动 Docker Desktop，用 Linux 容器完成 arm64 rootfs 和 Orbital 构建；不把静态检查冒充构建证据。 |
| 3 | 作者旧 `boot.img` 使用 `6.16.0-rc2-sdm845+`，而 `v26.06` 使用 `7.1_rc1` 内核 | 分享的成品镜像、pmOS/Nura `v26.06` 包 | 重新生成 `boot.img` 与 initramfs，并将同版本 `/lib/modules` 放入 Ubuntu rootfs；不复用旧 `boot.img`。 |

## 四、用户回答区

请逐条回答 1-4，并明确以下执行条件：

1. 是否同意启动 Docker Desktop，在 `D:\workspace` 内创建构建目录并运行 Ubuntu 24.04 容器？
2. SSH 使用用户公钥还是账号密码登录？（已选择账号密码。）
3. 一加 6 是否已解锁 bootloader，且允许清空 `userdata`、擦除 `dtbo` 做首次启动测试？
4. 最终是否只交付 `boot.img`、`rootfs-*.img`、构建脚本和刷机命令，由你手动执行 fastboot，还是要求我也调用 fastboot 刷入已连接设备？

### 2026-10-28 已收到回答

- 用户确认 Orbital 有源码，并可以在 Ubuntu 26.04 上继续适配。因此镜像默认编入 `D:\workspace\Orbital`，不使用 GitHub 成品二进制。
- 当前源码基线为 git commit `2e06f8b65a19d0dbf346dc80b02eaea9047dca12`，工作区存在未提交修改。镜像构建必须同时记录该 commit 和当前 `git diff`，避免无法追溯。
- Ubuntu 版本候选项由基础 24.04 调整为 `26.04.1 LTS`，但需用户最终确认是否正式切换。
- 用户允许启动 Docker Desktop，在 `D:\workspace` 内完成构建。
- 用户不提供 SSH 公钥，改用 `orbital` 用户的 SSH 密码登录。
- 一加 6 已解锁 bootloader；用户自行执行 fastboot 刷机，构建方不得自动刷入设备。

### 2026-10-28 登录方式调整

- SSH 使用普通用户 `orbital` 和账号密码登录，不使用 root 直接登录。
- 初始密码由构建流程随机生成，保存在本地 `state/orbital-password.txt`，镜像内只保存密码哈希。
- root 密码保持锁定，`orbital` 通过免密 `sudo` 管理系统。

### 2026-10-28 范围修正

- 用户最终只需要三个用户可见产物：
  1. 一个公共 `boot.img`；
  2. 一个不含桌面的 `rootfs-ubuntu.img`；
  3. 一个包含 Orbital 桌面并自动启动桌面的 `rootfs-orbital.img`。
- 两个 rootfs 镜像是二选一的刷机目标，不需要同时刷入。
- 两个 rootfs 必须包含相同的内核模块和固件，因此可以共用同一个 `boot.img`。
- 构建脚本、JSON 清单、日志和中间目录只用于内部构建与验证，不属于用户必须逐个操作的交付接口。
- 原设计中的 13 个构建命令接口属于实现细节，需收敛为单个构建入口和三个最终产物。

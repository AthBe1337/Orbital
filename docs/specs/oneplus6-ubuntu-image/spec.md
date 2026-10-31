# 规格（G2，三产物版）

> 需求名：OnePlus 6 Ubuntu 26.04.1 系统镜像 ｜ 日期：2026-10-28 ｜ 状态：已确认

## 背景与目标

为一加 6（`oneplus-enchilada`）制作三个可直接刷机的文件：

1. `oneplus6-boot.img`
2. `oneplus6-rootfs-ubuntu.img`
3. `oneplus6-rootfs-orbital.img`

`oneplus6-boot.img` 同时适用于两个 rootfs。两个 rootfs 都基于 Ubuntu 26.04.1 ARM64，并包含与启动内核完全匹配的 Nura `v26.06` 内核模块和固件。基础版只提供命令行、SSH 和网络能力；Orbital 版增加当前工作区源码构建的桌面并自动启动。

构建脚本、日志、清单和中间文件只用于内部制作与验证，不是用户必须操作的交付接口。

## 用户故事

作为一加 6 用户，我要刷入一个公共 `boot.img` 和一个 rootfs 镜像，以便启动 Ubuntu。

作为命令行用户，我要使用不含桌面的基础镜像，以便通过 USB 网络 SSH 登录和维护系统。

作为 Orbital 用户，我要使用包含桌面的镜像，以便开机直接进入 Orbital。

## 验收标准（EARS）

- AC1: WHEN 生成启动镜像，THE SYSTEM SHALL 输出 `oneplus6-boot.img`，其内核来自 Nura `v26.06` 的 `linux-postmarketos-qcom-sdm845 7.1_rc1-r0`。
- AC2: WHEN 生成启动镜像，THE SYSTEM SHALL 使用 `sdm845-oneplus-enchilada.dtb`、`root=/dev/sda17 rootfstype=ext4 rootwait=10 rw` 和 4096 page size。
- AC3: WHEN 生成两个 rootfs，THE SYSTEM SHALL 都基于 Canonical Ubuntu Base `26.04.1` ARM64。
- AC4: WHEN 安装内核模块，THE SYSTEM SHALL 在两个 rootfs 中都使用 `7.1.0-rc1-sdm845`，并保证与 `oneplus6-boot.img` 的内核一致。
- AC5: WHEN 安装硬件支持，THE SYSTEM SHALL 在两个 rootfs 中都放入 Nura `v26.06` 的 OnePlus 6 固件。
- AC6: WHEN 生成基础镜像，THE SYSTEM SHALL 输出 `oneplus6-rootfs-ubuntu.img`，不安装和不启动 Orbital。
- AC7: WHEN 生成桌面镜像，THE SYSTEM SHALL 输出 `oneplus6-rootfs-orbital.img`，安装当前 `D:\workspace\Orbital` 源码构建的 Orbital，并开机自动启动。
- AC8: WHEN 构建 Orbital，THE SYSTEM SHALL 启用内置插件，并在内部记录源码 commit 和工作区差异，以便定位适配问题。
- AC9: WHEN 两个 rootfs 启动完成，THE SYSTEM SHALL 提供用户 `orbital`、SSH 账号密码登录、USB RNDIS 网络和 NetworkManager。
- AC10: WHEN SSH 服务运行，THE SYSTEM SHALL 禁止 root 登录，允许 `orbital` 使用密码认证，并允许其通过 `sudo` 进行系统管理。
- AC11: WHEN 生成 rootfs 镜像，THE SYSTEM SHALL 输出 10 GiB 逻辑容量、4 KiB block 的 Android sparse ext4 镜像。
- AC12: WHEN 校验三个镜像，THE SYSTEM SHALL 确认 boot image 结构、DTB、内核 cmdline、sparse magic、逻辑容量、ext4 完整性、模块 release 和 Orbital 二进制架构。
- AC13: WHEN 用户刷机，THE SYSTEM SHALL 只要求刷入公共 `boot.img` 和任意一个 rootfs，并说明两个 rootfs 二选一。
- AC14: WHEN 用户通过 USB 连接手机，THE SYSTEM SHALL 记录默认设备地址、SSH 用户名和手动 fastboot 命令，不自动刷入设备。
- AC15: WHEN Ubuntu 软件更新，THE SYSTEM SHALL 允许 `apt update` 和 `apt upgrade` 更新用户空间，但不得自动安装 Ubuntu 内核或升级到 Ubuntu 26.10/后续大版本。
- AC16: WHEN 用户首次测试，THE SYSTEM SHALL 提供基础版与 Orbital 版各自的启动验收步骤。
- AC17: WHEN 构建结束，THE SYSTEM SHALL 只把三个 `.img` 文件作为用户交付物；其它构建文件不得成为刷机必需项。
- AC18: WHEN 重复构建，THE SYSTEM SHALL 使用固定的 Ubuntu 26.04.1、Nura `v26.06`、内核版本和 Orbital 源码快照，不得静默切换到最新版本。

## 字段口径

| 字段 | 类型 | 字典/枚举 | 必填 | 默认 | 说明 |
|---|---|---|---|---|---|
| `device_id` | string | `oneplus-enchilada` | 是 | 同名 | 一加 6 |
| `boot_image` | artifact | `oneplus6-boot.img` | 是 | 同名 | 公共启动镜像 |
| `base_rootfs` | artifact | `oneplus6-rootfs-ubuntu.img` | 是 | 同名 | 无桌面 Ubuntu |
| `desktop_rootfs` | artifact | `oneplus6-rootfs-orbital.img` | 是 | 同名 | Ubuntu + Orbital |
| `ubuntu_version` | string | `26.04.1` | 是 | 同名 | 用户空间版本 |
| `kernel_version` | string | `7.1_rc1-r0` | 是 | 同名 | Nura 内核包版本 |
| `kernel_release` | string | `7.1.0-rc1-sdm845` | 是 | 同名 | 模块目录与运行内核 |
| `dtb` | string | `sdm845-oneplus-enchilada.dtb` | 是 | 同名 | OnePlus 6 设备树 |
| `root_device` | path | `/dev/sda17` | 是 | 同名 | `userdata` 根分区 |
| `rootfs_size` | size | `10GiB` | 是 | 同名 | 两个 rootfs 的逻辑容量 |
| `ssh_user` | string | `orbital` | 是 | 同名 | SSH 普通用户 |
| `ssh_password_file` | secret file | 本地文本文件 | 是 | 构建时随机生成 | 镜像内只保存密码哈希 |
| `orbital_autostart` | boolean | `true` | 是 | `true` | 仅桌面版生效 |

## 状态流转

| 当前状态 | 触发 | 目标状态 | 触发者 |
|---|---|---|---|
| `inputs_locked` | Ubuntu、Nura 和 Orbital 输入固定 | `building` | 构建方 |
| `building` | 三个 `.img` 生成 | `verifying` | 构建方 |
| `verifying` | 结构和完整性检查通过 | `ready_to_flash` | 构建方 |
| `ready_to_flash` | 用户选择基础版或桌面版 | `device_testing` | 用户 |
| `device_testing` | 开机和对应功能通过 | `accepted` | 用户 |
| `device_testing` | 启动或功能失败 | `fixing` | 用户与构建方 |

## 权限矩阵

| 操作 | 角色 | 范围 |
|---|---|---|
| 构建三个镜像 | 构建方 | `D:\workspace` |
| 设置 `orbital` 初始密码 | 构建方 | 两个 rootfs，用户首次登录后修改 |
| 选择刷哪个 rootfs | 用户 | 一加 6 实机 |
| 执行 fastboot | 用户 | 用户自己的设备 |
| 实机验收 | 用户 | 启动、显示、触摸、USB SSH、WiFi |

## 非目标

- 不交付 ISO、Android 系统、容器或虚拟机镜像。
- 不要求用户运行 13 个构建脚本；内部实现方式不影响三个最终文件。
- 不安装 Ubuntu 内核。
- 不自动刷机、擦除 `dtbo` 或清空 `userdata`。
- 不提供第三个“基础版+桌面版合并”镜像。
- 不在基础版中安装 Orbital 运行文件。
- 不在镜像中保存 WiFi 密码、SSH 私钥或 root 明文密码。
- 不承诺 Android 双启动或未列明的其它硬件功能。

## 影响面

- 涉及模块：Ubuntu 26.04.1 ARM64 rootfs、Orbital、systemd、SSH、USB RNDIS、NetworkManager、Nura SDM845 内核与固件、Android boot image、ext4/sparse。
- 涉及表：无。
- 关联端是否同步：Orbital 为适配 Ubuntu 26.04.1 可能修改当前源码；Nura 上游包不修改。

# 设计（G3，三产物版）

> 需求名：OnePlus 6 Ubuntu 26.04.1 系统镜像 ｜ 日期：2026-10-28 ｜ 状态：已确认

## 方案概述

最终只生成三个可直接刷写的文件：

```text
oneplus6-boot.img
oneplus6-rootfs-ubuntu.img
oneplus6-rootfs-orbital.img
```

构建工程位于 `D:\workspace\oneplus6-image`。内部使用 Docker、Ubuntu 26.04.1 ARM64 Base、Nura `v26.06` 内核组件和当前 Orbital 源码。用户不需要分别运行内部步骤，也不需要保存中间文件。

两个 rootfs 先生成同一份公共系统目录，再分叉：

- 公共部分：Ubuntu Base、SSH、USB RNDIS、NetworkManager、Nura 模块与固件、系统配置。
- 基础版：保持无 Orbital，生成 `oneplus6-rootfs-ubuntu.img`。
- 桌面版：复制基础 rootfs，加入 Orbital 和自启动服务，生成 `oneplus6-rootfs-orbital.img`。

## 固定输入

| 输入 | 固定值 |
|---|---|
| 设备 | `oneplus-enchilada` |
| Ubuntu | `26.04.1` ARM64 Base |
| Nura 分支 | `v26.06` |
| 内核包 | `linux-postmarketos-qcom-sdm845 7.1_rc1-r0` |
| 内核 release | `7.1.0-rc1-sdm845` |
| 设备包 | `device-oneplus-enchilada 26-r0` |
| 固件包 | `firmware-oneplus-sdm845 14-r0` |
| AOSP mkbootimg | Ubuntu 26.04 `1:34.0.5-12build1` |
| DTB | `sdm845-oneplus-enchilada.dtb` |
| root 分区 | `/dev/sda17` |
| rootfs 容量 | `10 GiB` |
| rootfs block | `4096` |

## 内部数据结构

不设计数据库。内部只需要：

- `config/build.env`：固定版本、路径和用户名。
- `state/build-state.json`：内部阶段与日志，不作为用户交付物。
- `work/rootfs-base/`：共同 rootfs。
- `work/rootfs-orbital/`：桌面 rootfs 副本。
- `work/boot/`：内核、DTB、initramfs 和 `boot.img` 的中间文件。
- `out/`：只放三个最终 `.img`。

## 用户接口

用户只需要运行：

```powershell
.\build.ps1
```

脚本内部完成所有步骤，成功后在 `out\` 生成三个 `.img`。脚本不调用 fastboot。

## 内部构建流程

1. 启动 Ubuntu 26.04 构建容器，注册 ARM64 binfmt。
2. 校验并解包 Ubuntu Base `26.04.1`。
3. 安装 SSH、NetworkManager、Qt6、Orbital 运行依赖和构建工具。
4. 提取 Nura 内核、DTB、模块与固件。
5. 配置用户、SSH 密码认证、USB RNDIS、systemd 和软件更新限制。
6. 生成基础 rootfs 的 ext4 和 Android sparse image。
7. 复制基础 rootfs，加入 Orbital 及桌面自启动配置。
8. 生成桌面 rootfs 的 ext4 和 Android sparse image。
9. 用 BusyBox 生成挂载 `/dev/sda17` 的最小 initramfs。
10. 将内核与 DTB 拼接后，用固定参数和 AOSP `mkbootimg` 生成公共 `boot.img`。
11. 校验三个镜像并只把最终文件留在 `out\`。

## 关键决定

- 共享一个 `boot.img`，因为两个 rootfs 的内核模块 release 和固件完全一致。
- 基础版和桌面版都不安装 Ubuntu 内核。
- 用 `mke2fs -d` 生成 ext4，不依赖 loop device。
- 用 Android sparse image 输出，提升 fastboot 传输效率。
- Orbital 从当前工作区源码构建；镜像内记录 commit 和差异指纹。
- SSH 允许 `orbital` 用户密码登录；root SSH 登录关闭，root 密码保持锁定。
- 首次开机生成 SSH host key 和 machine-id。
- 不把 WiFi 密码、SSH 私钥或 root 明文密码写入镜像。

## 验证

交付前必须验证：

- `boot.img` 的内核、DTB、cmdline 和 page size。
- 两个 rootfs 的 `7.1.0-rc1-sdm845` 模块目录存在且一致。
- 两个 sparse 镜像的 magic 和 10 GiB 逻辑容量。
- 两个 ext4 文件系统均通过 `e2fsck`。
- 基础版不包含 `/opt/orbital`。
- 桌面版包含 Orbital 二进制和自启动服务。
- SSH 配置、`orbital` 密码哈希、root 锁定状态和 sudo 权限。

实机启动、显示、触摸、USB SSH 和 WiFi 由用户刷入后验证。

## 风险与回滚

- Docker ARM64 chroot 可能受 binfmt 权限影响；构建脚本会先做能力检查。
- Ubuntu 26.04 的 Qt6 包名或 Orbital 行为可能需要小幅适配。
- USB RNDIS、WiFi 和显示依赖 Nura 内核与固件，可能需要在实机日志基础上调整。
- 构建过程不操作手机；用户可继续使用已有 Android/系统恢复方式。

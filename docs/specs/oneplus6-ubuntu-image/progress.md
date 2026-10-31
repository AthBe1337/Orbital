# 实施进度

> 需求：OnePlus 6 Ubuntu 26.04.1 三产物镜像 ｜ 开始日期：2026-10-28

| 任务 | 状态 | 验证证据 | 裁决记录 |
|---|---|---|---|
| 规格与设计收敛为三产物 | 完成 | `spec.md` 与 `design.md` 已更新 | 内部脚本不作为用户交付接口 |
| Docker 构建环境 | 完成 | Ubuntu 26.04 构建镜像与 x86/qemu-user/proot 链路可用 | Docker Desktop 不支持 ARM64 容器启动，改用 proot |
| 构建工程与配置 | 完成 | `build.ps1`、`build.sh`、配置和系统服务文件已落地 | 中间文件放在 Docker volume，避免 Windows 挂载 ACL 限制 |
| Ubuntu 基础 rootfs | 完成 | 两个 rootfs 的 `/usr/lib/os-release` 均为 Ubuntu 26.04.1 LTS | systemd-tmpfiles 在 proot 下崩溃，仅构建期使用临时空实现 |
| Nura 内核组件 | 完成 | 模块目录均为 `7.1.0-rc1-sdm845`，基础版和桌面版 `modules.dep` 哈希一致 | APK 只提取模块、固件和 DTB |
| Orbital 构建与桌面 rootfs | 完成 | `Orbital` 为 ARM aarch64 ELF，桌面版启用 `orbital.service` | 使用当前工作区源码和内置插件 |
| initramfs 与 boot.img | 完成 | boot header v0、page size 4096、DTB 末尾匹配、cmdline 包含 `/dev/sda17` | 使用 mkbootimg 直接生成 |
| 两个 rootfs sparse 镜像 | 完成 | magic `0xED26FF3A`，逻辑容量 10 GiB，两镜像 `e2fsck -fn` 均通过 | 两个 rootfs 使用相同随机初始密码 |
| 结构验证 | 完成 | `verification.json`、ext4、SSH、服务、模块和二进制架构检查通过 | 测试公钥已从镜像移除 |
| SSH 账号密码 | 完成 | 两个 rootfs 均启用 `PasswordAuthentication yes`；root 密码为 `!*`，orbital 为 SHA-512 哈希 | 初始密码保存在 `state/orbital-password.txt` |
| 实机验证 | 待用户 | | 需要用户手动 fastboot 并回填启动结果 |

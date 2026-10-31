# OnePlus 6 Ubuntu 启动卡死根因报告

## 状态

根因已确认；最小修复已实现并通过静态验证，等待真机启动验证。

## 现象

- Android boot 镜像中的内核和 OnePlus 6 DTB 可以正常启动。
- UFS 存储被识别，`/dev/sda17` 和全部分区均出现在内核日志中。
- 正式 initramfs 启动后约 6 秒触发：

```text
Kernel panic - not syncing: Attempted to kill init! exitcode=0x00007f00
```

- 调试 initramfs 进一步显示：

```text
init: line 13: mount: not found
init: line 14: mount: not found
init: line 26: sleep: not found
```

## 根因

`build_initramfs` 只把 BusyBox 主程序复制为 `/bin/busybox`，没有创建 `mount`、`sleep`、`mkdir`、`switch_root` 等 applet 链接：

- `scripts/build.sh:517`
- `config/initramfs-init:9`
- `config/initramfs-init:10`
- `config/initramfs-init:20`
- `config/initramfs-init:34`

当前 BusyBox shell 无法在空 `PATH` 环境中解析未限定路径的 applet。因此：

1. 第 9 行 `mount -t proc ...` 返回 127，并输出 `mount: not found`。
2. 正式脚本启用了 `set -e`，PID 1 随即退出。
3. 内核把 PID 1 退出转换为 `Attempted to kill init` panic。

调试脚本没有启用 `set -e`，因此继续执行到等待循环；循环内 `sleep` 也不存在，最终停留在 BusyBox shell，但不会再 panic。这与两种启动日志的表现完全一致。

## 最小修复

只修改 initramfs 组装逻辑，不修改 Ubuntu rootfs：

1. 在 `$initroot/bin` 中为 BusyBox applet 创建相对软链接，至少包含：

```text
sh
mount
sleep
mkdir
switch_root
```

2. 调试 initramfs 如继续使用，额外包含：

```text
ls
readlink
chroot
```

3. 重新生成 `oneplus6-boot.img`，不重新生成两个 rootfs。

## 修复实施

- `config/initramfs-init` 显式设置 `PATH=/bin`。
- `scripts/build.sh` 为 `sh`、`mount`、`sleep`、`mkdir`、`switch_root` 创建指向 BusyBox 的相对软链接。
- `build.ps1 -BootOnly` 只重建 `oneplus6-boot.img`，不覆盖两个 rootfs。

静态验证结果：

- 从最终 `oneplus6-boot.img` 解包出的 ramdisk 包含全部所需 applet 链接。
- 新 `oneplus6-boot.img` SHA-256 为 `1E63438001265D92528DF97AFF55B1AC6CD35BE12E757389FE06A0256BC6A086`。
- 两个 rootfs 的 SHA-256 未变化。

## 验证方案

- 检查新 initramfs 中 `/bin/mount`、`/bin/sleep`、`/bin/switch_root` 均指向 `busybox`。
- 启动调试镜像，确认显示：

```text
INITDBG: root filesystem mounted
INITDBG: systemd execution exit=0
INITDBG: switching root
```

- 真机启动后确认 USB RNDIS 出现，`172.16.42.1:22` 可连接。
- 若 `switch_root` 后续还有问题，再按新的首错继续排查，不提前修改 rootfs。

# OnePlus 6 触摸和电量设备根因报告

## 状态

根因已确认；最小修复已实现并通过镜像静态验证，等待真机验证。

## 现象

- Orbital 桌面可以显示。
- 触摸无响应。
- 电量卡片没有有效数据。
- 正常系统没有 USB 网络；救援环境手动安装 RNDIS 驱动后可以访问诊断页。

## 取证

救援系统的 `/proc/bus/input/devices` 只有：

```text
pm8941_pwrkey
Alert slider
Hall effect sensor
Volume keys
```

没有触摸屏输入设备。`/sys/class/power_supply` 为空。

内核日志：

```text
bq27xxx_battery_i2c: Unknown symbol bq27xxx_battery_setup (err -2)
bq27xxx_battery_i2c: Unknown symbol bq27xxx_battery_update (err -2)
qcom_battmgr: Unknown symbol devm_pmic_glink_client_alloc (err -2)
qcom_battmgr: Unknown symbol pmic_glink_client_register (err -2)
```

已持久化的 Orbital 日志：

```text
Orbital device: OnePlus 6 (oneplus-enchilada), scale=2.15, inputs=unresolved
  touch= (unresolved)
  power= (unresolved)
  volume= (unresolved)
```

## 根因

`extract_nura_inputs()` 把 Nura 的模块树复制进 rootfs 后没有执行 `depmod`。

当前 `modules.dep` 将这些模块的依赖全部记录为空，例如：

```text
kernel/drivers/usb/gadget/function/usb_f_rndis.ko.zst:
kernel/drivers/input/rmi4/rmi_i2c.ko.zst:
kernel/drivers/power/supply/bq27xxx_battery_i2c.ko.zst:
kernel/drivers/power/supply/qcom_battmgr.ko.zst:
```

但模块自身声明的依赖是：

```text
usb_f_rndis: u_ether, libcomposite
rmi_i2c: rmi_core
bq27xxx_battery_i2c: bq27xxx_battery
qcom_battmgr: pmic_glink
```

`depmod -n` 能正确生成这些依赖。因此 `modprobe` 加载目标模块时不会先加载前置模块，最终出现未知符号或驱动不创建设备。

影响：

- `rmi_i2c` 没有加载，触摸设备不出现。
- `bq27xxx_battery_i2c` 和 `qcom_battmgr` 加载失败，`power_supply` 为空。
- 正常 rootfs 的 USB gadget 服务也受模块依赖错误影响。

## 独立问题

救援日志显示电源键和音量键设备已经存在，但 `run.sh` 仍报告 `power=... (unresolved)` 和 `volume=... (unresolved)`。这是输入自动发现的第二个问题，不能仅靠 `depmod` 解释。修复模块依赖后必须在真机重新取证，再单独定位。

## 最小修复

1. 在模块复制完成后对目标 rootfs 执行：

```bash
depmod -b "$rootfs" "$KERNEL_RELEASE"
```

2. 重新生成两个 rootfs sparse 镜像。
3. 保持现有 `boot.img` 不变。

## 修复实施

- `scripts/build.sh` 在复制 Nura 模块后执行 `depmod -b "$rootfs" -a "$KERNEL_RELEASE"`。
- `scripts/refresh-images.sh` 在重建 rootfs 前对两个工作 rootfs 再执行一次 `depmod`。

静态验证结果：

- 两个成品 ext4 镜像中的 `modules.dep` 均包含正确的依赖链。
- `e2fsck -fn` 对两个 raw rootfs 均返回 0。
- 新 Ubuntu rootfs SHA-256：`7BD8C35DBC3354CF4D03E8B9E7BE8FB3997CA694C4E19C2AD174E4A5E5FEEEB3`。
- 新 Orbital rootfs SHA-256：`F21803B6596EDD95AECD69ED585074424B30CC7BDA3D77D07C49854FA334EE9E`。
- `oneplus6-boot.img` 未变化，SHA-256：`1E63438001265D92528DF97AFF55B1AC6CD35BE12E757389FE06A0256BC6A086`。

## 验证

- 新 rootfs 中 `modules.dep` 应包含正确的依赖链。
- 正常系统启动后 `/proc/bus/input/devices` 应出现触摸设备。
- `/sys/class/power_supply` 应出现电池节点。
- 重新检查 Orbital journal 中的 `touch/power/volume` 路径。

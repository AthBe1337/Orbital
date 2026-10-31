# OnePlus 6 卡顿与电源键行为根因报告

## 状态

- GPU 性能问题：根因已确认，修复已实现。
- 电源键行为：根因已确认，修复已实现。
- WiFi 扫描：根因已确认，修复已实现。
- USB 网络：根因已确认，修复已实现。
- 以上修复已通过镜像静态验证，等待真机验证。

## 卡顿和 CPU 暴增

内核日志：

```text
Direct firmware load for qcom/a630_sqe.fw failed with error -2
```

Orbital 日志：

```text
Running on a software rasterizer (LLVMpipe), expect limited performance.
MESA: error: fd_pipe_new2: allocation failed
```

当前 rootfs 只有 `a630_zap.mbn`，缺少：

```text
/usr/lib/firmware/qcom/a630_gmu.bin
/usr/lib/firmware/qcom/a630_sqe.fw
```

根因是缺少 Nura 仓库的 Adreno A630 GMU/SQE 固件包。GPU 无法初始化，Qt/Mesa 回退到 CPU 软件渲染，因此任何交互重绘都会显著增加 CPU 使用并造成卡顿。

最小修复：

- 在 `fetch_inputs` 中增加根包 `firmware-qcom-adreno-a630`。
- 该包会通过依赖带入 `firmware-qcom-adreno-a630-sqe`。
- 重新生成 rootfs，不需要修改内核或 boot image。

## 电源键

镜像中的 systemd 默认配置：

```text
#HandlePowerKey=poweroff
#HandlePowerKeyLongPress=ignore
```

当前没有 `/etc/systemd/logind.conf.d` 覆盖。短按由 systemd-logind 直接执行关机，Orbital 无法接管。

同时 OnePlus 6 profile 没有电源键和音量键回退路径，输入自动发现失败时会导出空路径。

目标行为：

- 短按：灭屏；再短按：亮屏。
- 长按 1.5 秒：只重启 Orbital 桌面进程，不重启手机。

DisplayBackend 已实现上述短按和长按逻辑。最小修复是：

1. 新增 logind drop-in，将 `HandlePowerKey` 和 `HandlePowerKeyLongPress` 设为 `ignore`。
2. 为 OnePlus 6 增加 `/dev/input/event0` 电源键和 `/dev/input/event3` 音量键回退路径。

## WiFi

设备树 `qcom,wcn3990-wifi` 节点正常。内核日志显示：

```text
bluetooth hci0: Direct firmware load for qca/crbtfw21.tlv failed with error -2
```

成品镜像中实际路径是：

```text
/usr/lib/firmware/postmarketos/qca/crbtfw21.tlv
```

内核请求的是：

```text
/usr/lib/firmware/qca/crbtfw21.tlv
```

缺少标准固件路径映射，导致 WCN3990 固件加载失败。还必须提供 `qca/crnv21.bin` 到 OnePlus 6 板级文件的映射。

修复固件路径后，最新日志中 `crbtfw21.tlv` 错误已消失，但仍没有 `ath10k_snoc` 探测记录。根因是设备包没有显式加载 `ath10k_snoc`，Ubuntu udev 也没有触发该 OF modalias。

最小修复：

```text
qca/crbtfw21.tlv -> ../postmarketos/qca/crbtfw21.tlv
qca/crnv21.bin -> OnePlus/enchilada/crnv21.bin
```

同时通过 `modules-load.d/orbital-wifi.conf` 显式加载：

```text
pwrseq_qcom_wcn
ath10k_snoc
```

进一步对照设备包依赖后发现，`firmware-oneplus-sdm845` 还依赖 Alpine 仓库的 `linux-firmware-ath10k`。此前构建只解析 Nura 仓库，静默漏掉了该包，最终缺少：

```text
/usr/lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin.zst
/usr/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin.zst
```

构建流程现已解析 Alpine edge 固件索引并下载 `linux-firmware-ath10k`。

## USB 网络

正常系统 journal：

```text
orbital-usb-gadget.service: Finished
NetworkManager: (usb0): new Ethernet device
```

但 NetworkManager 没有激活连接；Windows 侧 RNDIS 驱动安装正常，网卡状态仍为 `Disconnected`。救援环境同样创建 RNDIS gadget，并在执行 `ip link set usb0 up` 后 Windows 立即可用。

根因是正常 rootfs 的 gadget 服务只写入 UDC，没有等待并拉起 `usb0`。NetworkManager 因链路未建立而没有应用 `orbital-usb` 共享网络。

最小修复：

- RNDIS function 创建后等待 `usb0` 出现。
- 执行 `ip link set usb0 up`。
- 将 `usb0` 从 NetworkManager 自动管理改为独立服务。
- 独立服务固定 `172.16.42.1/24` 并通过 dnsmasq 提供 DHCP。

## 输入设备

最新 journal 已确认输入自动发现正常：

```text
inputs=auto
touch=/dev/input/event5 (auto)
power=/dev/input/event0 (auto)
volume=/dev/input/event3 (auto)
```

因此不需要再改设备匹配规则。

## 修复实施

- `fetch_inputs` 增加根包 `firmware-qcom-adreno-a630`，由依赖带入 A630 SQE 固件。
- 构建时校验 `a630_gmu.bin`、`a630_sqe.fw`、`crbtfw21.tlv` 和 `crnv21.bin` 均存在。
- 建立 WCN3990 标准固件路径映射。
- 安装 logind drop-in，将短按和长按电源键都交给 Orbital 处理。
- USB gadget 服务等待 `usb0` 出现并执行 `ip link set usb0 up`。

新成品 SHA-256：

```text
oneplus6-rootfs-ubuntu.img
98105E2E5BD1D914777220C6068625AEB635EE8248A25B6B0759675143D67711

oneplus6-rootfs-orbital.img
A0F7719D6C801161C96737CE3B1DD4AE44DC3E475CAA951F21FF456EFDA0D2B9

oneplus6-boot.img
1E63438001265D92528DF97AFF55B1AC6CD35BE12E757389FE06A0256BC6A086
```

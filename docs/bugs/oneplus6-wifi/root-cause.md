# OnePlus 6 WiFi 无法创建 wlan0 根因报告

## 状态

根因已确认，是一组缺失的 Qualcomm 用户态启动链，而不是单一组件：

```text
tqftpserv + pd-mapper + rmtfs + MSS/WLFW
```

运行中补齐 `rmtfs` 后，QRTR 立即出现服务 `69`（ATH10k WLAN firmware
service），ath10k 完成 WMI 初始化，创建 `wlan0` 并成功扫描到接入点。
完整启动链已写入最终 rootfs，等待最后一次冷启动确认。

## 现象

- `ath10k_snoc`、`ath10k_core`、`mac80211`、`cfg80211` 均已加载。
- `pwrseq_qcom_wcn` 已绑定到 `wcn3990-pmu`，临时 DTB 中删除错误
  `pinctrl-0` 后，原 `/sys/.../unbind` 触发的 SPMI `-EPERM` 已消失。
- `18800000.wifi` 由 `ath10k_snoc` 绑定，设备树和 IOMMU 资源正常。
- `remoteproc0..3` 均为 `running`，包括 `4080000.remoteproc`。
- 系统始终没有 `wlan0`，`nmcli dev status` 只显示 `lo`、`usb0`、`sit0`。
- WCN3990、ath10k、蓝牙和 Adreno 所需固件文件均存在于
  `/usr/lib/firmware`。

## 复现

1. 使用 `oneplus6-boot-wifi-dtb-test.img` 启动 OnePlus 6。
2. 确认 `pwrseq-qcom_wcn` 已绑定，启动 `remoteproc3`。
3. 执行：

```bash
ip -br link
nmcli dev status
sudo dmesg | grep -Ei 'ath10k|wlfw|wlan|qmi|qrtr|wcn3990'
```

4. 结果稳定为只有 `lo`、`usb0`、`sit0`，没有 `wlan0`，也没有 WLFW
   QMI 服务或 ath10k 固件下载记录。

## 跨组件边界取证

### ath10k 等待 WLFW QMI 服务

内核 `ath10k/qmi.c` 注册的是 `WLFW_SERVICE_ID_V01 = 0x45`：

```text
WLFW_SERVICE_ID_V01 0x45
WLFW_SERVICE_VERS_V01 0x01
```

设备树中没有 `wifi-firmware` 子节点，因此 `ath10k_fw_init()` 设置
`ar_snoc->use_tz = true`。这条路径要求 WCN 固件先由 TrustZone/WCN 侧启动，
随后再通过 QRTR 发布 WLFW QMI 服务，而不是由 Linux 直接加载 WLAN MSA 固件。

### Linux 侧没有 WLFW 服务响应

系统中可以看到 QRTR 内核工作线程，但没有 WLFW 服务端；当前也没有
`wlan0`。在启动完成后临时运行 `tqftpserv`，没有收到任何 TFTP 请求，说明
本次启动中的固件启动阶段早已结束。该实验不能反向证明 `tqftpserv` 无效，
反而说明它必须参与开机时序。

### pmOS 正常样本要求 tqftpserv

当前 pmOS `v26.06` 的 `device-oneplus-enchilada` 依赖 `soc-qcom`，
而 `soc-qcom` 的 APKBUILD 明确依赖 `tqftpserv`：

```text
device-oneplus-enchilada
  -> soc-qcom
       -> tqftpserv
```

`tqftpserv` 是 AF_QIPCRTR 上的 TFTP 服务，负责把 TrustZone/远程处理器请求的
`/readonly/firmware/image/...` 路径翻译到 Linux 的 `/lib/firmware`，并在需要时
解压 `.xz`/`.zst` 固件。当前 Ubuntu rootfs 中没有该二进制、systemd unit
或运行进程。

### 已排除项

- 不是缺少 `wlanmdsp.mbn`：文件存在于 OnePlus 6 的固件目录。
- 不是模块依赖问题：ath10k、pwrseq、qcom_common 依赖链已正确加载。
- 不是 MSS 未启动：`remoteproc3` 手动启动后为 `running`。
- 不是单纯 SPMI pinctrl 问题：删除错误 pinctrl 后绑定正常，但 WiFi 仍不出现。
- 不是启动后临时运行即可解决：WCN 固件启动已经完成，晚启动的服务收不到请求。

## 首次修复与验证结论

首次修复基于以下假设：自制 Ubuntu rootfs 只复制了 pmOS 的内核、模块和固件，
没有复制 pmOS `soc-qcom` 启动链中的 `tqftpserv`。WCN/TrustZone 在开机阶段需要
读取 WLAN 固件时没有 QRTR TFTP 服务可用，WLFW QMI 服务没有发布，ath10k 无法
完成初始化，最终没有 `wlan0`。

补齐 `tqftpserv` 后，真机验证结果：

- `tqftpserv.service` 为 `active (running)`。
- QRTR 中能看到服务 `4096`（TFTP）。
- 手动启动 `remoteproc3` 后状态为 `running`。
- QRTR 服务列表仍没有 WLFW 服务 `0x45`。
- 系统仍没有 `wlan0`。
- `/sys/kernel/debug/pwrseq` 中 WLAN/Bluetooth 的 enable count 均为 0。

结论：`tqftpserv` 必须保留，但“缺少 tqftpserv”不足以解释当前故障。

## 第二个缺失组件

pmOS v26.06 的 `device-oneplus-enchilada` APKBUILD 明确包含：

```text
soc-qcom-pd-mapper
```

该包依赖 `pd-mapper`，负责通过 QRTR 发布 Qualcomm 远程处理器的 protection
domain 映射。临时运行原生 arm64 `pd-mapper` 后，QRTR 中成功出现服务 `64`
（Service registry locator），证明服务本身工作。但当前运行系统已经在没有
`pd-mapper` 的情况下完成过启动和 WCN 初始化，运行中补服务无法重建完整冷启动
状态，因此必须把它固化进 rootfs 后重新冷启动验证。

## RMTFS 与 MSS/WLFW

pmOS 的 OnePlus 6 设备包还通过 `soc-qcom-modem`/`msm-modem` 依赖 `rmtfs`。
MSS（`4080000.remoteproc`）内部承载 WLAN firmware 服务，必须先有 RMTFS
处理 modem 的远程文件系统请求，MSS 才会发布 WLFW。

真机验证过程：

1. 新 rootfs 冷启动时 `tqftpserv` 和 `pd-mapper` 已正常运行，但
   `remoteproc3` 为 `offline`，QRTR 中没有 WLFW。
2. 手动启动 `remoteproc3` 后，MSS 为 `running`，但仍没有 WLFW。
3. 临时启动原生 arm64 `rmtfs -r -P -s` 后，QRTR 立即出现：

```text
21 Remote file system service
69 ATH10k WLAN firmware service
```

4. ath10k 随即完成 WMI 初始化，创建 `wlan0`。
5. `nmcli dev wifi list` 成功扫描到多个 2.4 GHz 和 5 GHz 接入点。

因此此前只补 `tqftpserv` 或 `pd-mapper` 都不够，`rmtfs` 和 MSS 自动启动是
让 WLFW 发布的最后一段链路。

## 最小修复

1. 安装原生 arm64 `tqftpserv`、`pd-mapper` 和 `rmtfs`。
2. `tqftpserv` 在 WCN/ath10k 探测前启动。
3. `pd-mapper` 等待 `remoteproc1` 和 `remoteproc3` 注册后再扫描。
4. `rmtfs` 等待 `/dev/qcom_rmtfs_mem1` 后启动。
5. 新增 `orbital-msm-modem.service`，自动启动 `remoteproc3`。
6. 保留已经验证过的 DTB pinctrl 修复，并做完整冷启动验证。

## 验证标准

- `systemctl is-active tqftpserv` 为 `active`。
- `tqftpserv` 日志出现 WCN 的固件读取请求。
- `iplink` 或 `nmcli dev status` 出现 `wlan0`。
- `nmcli dev wifi list` 能扫描到接入点。
- 触摸、电池、GPU、电源键和 USB 网络不回归。

## 修复实施

- 将 qrtr `v1.2` 和 tqftpserv `v1.3` 原生编译为 Ubuntu 26.04 arm64
  可执行文件，SHA-256 为
  `EDAD83F4FBD3A6EBA3712436127B223736E86A5CE4ECC612042F553DE530485B`。
- 两个 rootfs 均安装 `/usr/bin/tqftpserv` 和
  `/etc/systemd/system/tqftpserv.service`，并启用
  `multi-user.target.wants/tqftpserv.service`。
- 两个 rootfs 均安装 `/usr/bin/pd-mapper` 和
  `/etc/systemd/system/pd-mapper.service`，并启用
  `multi-user.target.wants/pd-mapper.service`。
- `pd-mapper.service` 等待 `remoteproc1` 和 `remoteproc3` 出现后再启动。
- 两个 rootfs 均安装 `/usr/bin/rmtfs` 和
  `/etc/systemd/system/rmtfs.service`，并启用
  `multi-user.target.wants/rmtfs.service`。
- `rmtfs.service` 等待 `/dev/qcom_rmtfs_mem1` 后执行
  `rmtfs -r -P -s`。
- 新增 `orbital-msm-modem.service`，在 `rmtfs`、`pd-mapper` 和
  `tqftpserv` 就绪后自动启动 `remoteproc3`。
- `build.sh` 在生成 boot image 前删除 `/wcn3990-pmu` 的
  `pinctrl-0` 与 `pinctrl-names`，并校验属性已经不存在。

## 当前验证证据

- boot image 校验通过，kernel payload 与修改后的 DTB 完全匹配。
- DTB 查询结果为 `no-pinctrl-0`、`no-pinctrl-names`。
- 两个 rootfs 中均存在 arm64 `tqftpserv`、`pd-mapper`、`rmtfs`，
  四个相关服务及启用链接一致。
- `systemd-analyze verify` 无排序环。
- 两个 raw ext4 均通过 `e2fsck -fn`。
- 两个 sparse image 均为 Android sparse、4096 字节块、10 GiB 逻辑大小。

真机运行中补齐 `rmtfs` 后已验证 `wlan0` 创建和 WiFi 扫描成功；最终冷启动
仍需用本轮镜像确认自动化启动顺序。

最终镜像 SHA-256：

```text
oneplus6-boot.img
B2712B46524F823FBB6FA7A72ED91F1046970748ADABFF10D9880842544F95FF

oneplus6-rootfs-ubuntu.img
71CAB699926CACBCB147CD34CE44CFE3A6017A834D2090EE1F224FA6D57DA3E3

oneplus6-rootfs-orbital.img
D27553C03BCBF7450B6CFA706E1E7D88C49A783B4305466875D9C15F6E5E9A12
```

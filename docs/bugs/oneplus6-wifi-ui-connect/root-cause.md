# OnePlus 6 Orbital WiFi 点击后无法连接根因报告

## 状态

根因已确认；等待用户确认后实施最小修复。

## 现象

- WiFi 扫描正常，Orbital 能看到多个 2.4 GHz 和 5 GHz 网络。
- 点击网络并输入密码后，系统没有建立连接。
- NetworkManager 日志中没有任何 WiFi 激活请求。
- `nmcli connection show` 中没有新建的无线连接配置。
- `wlan0` 一直是 `disconnected`。

## 运行时证据

Orbital journal 在用户点击网络时稳定出现：

```text
qrc:/MyDesktop/Backend/qml/WifiPage.qml:377:
ReferenceError: wifiPage is not defined
```

对应代码在 `WifiPage.qml`：

```qml
page.connectionRequested.connect(function(ssid, password) {
    wifiPage.beginConnect(ssid, password)
})
```

同一个跨组件回调还在 `onOperationStart` 中引用了 `wifiPage`：

```qml
"onOperationStart": function(ssid) {
    wifiPage.pendingSsid = ssid
}
```

## 根因

`WifiPage` 向动态创建的 `WifiConnectPage` 注册回调，但回调执行时不能解析
`WifiPage` 的根对象 id `wifiPage`。QML 抛出 `ReferenceError` 后函数立即中断，
因此：

1. `beginConnect()` 没有执行。
2. `backend.connectToWifi()` 没有执行。
3. 后端没有启动 `nmcli dev wifi connect`。
4. NetworkManager 不会创建无线 profile，也不会尝试认证或 DHCP。

这不是密码错误、驱动断开或 NetworkManager 未运行。

## 最小修复

移除跨组件的 signal/function 回调桥接：

1. `WifiConnectPage.submitConnection()` 直接调用
   `backend.connectToWifi(ssid, password)`。
2. `WifiPage` 在进入详情页前直接设置自己的 `pendingSsid`。
3. 不再向子页面传递 `onOperationStart` 或 `connectionRequested` 回调。
4. `WifiPage` 只通过现有 `Connections` 接收后端
   `wifiConnectResult`，统一清理 loading 状态并显示结果。

这样可以保持现有连接结果 Toast 和 loading 动画，不扩大行为范围。

## 验证标准

- 点击网络并提交密码后，journal 不再出现 `wifiPage is not defined`。
- NetworkManager 日志出现 WiFi activation。
- `nmcli connection show` 出现对应 SSID 的 `802-11-wireless` profile。
- `nmcli dev status` 中 `wlan0` 变为 `connected`。
- `iw dev wlan0 link` 显示已关联的 BSSID。
- Orbital 显示连接结果，不会无限停留在连接中。

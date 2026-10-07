# 官方指导与协议参考

检查日期：2026-10-07。App 使用 Apple SDK；理光 GR 相机协议并非苹果或理光官方开发接口保证。

## Apple 官方

- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)：原生导航、清楚的层级、动态字体、无障碍、自适应窗口。
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)：使用系统组件继承新系统视觉，不用截图式玻璃背景模拟导航。
- [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)：SwiftUI 原生导航与 TabView。
- [Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)：服务/特征发现、系统配对、安全访问、主队列 delegate。App 不使用私有 ATT handle 或自行实现 iOS bond。
- [NEHotspotConfiguration](https://developer.apple.com/documentation/networkextension/nehotspotconfiguration)：由系统确认加入已知 Wi‑Fi。
- [TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)：本地网络使用说明与权限。
- [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)：相机的本地 HTTP。工程不设置全局任意网络加载例外。
- [PHAssetCreationRequest.addResource](https://developer.apple.com/documentation/photos/phassetcreationrequest/addresource(with:fileurl:options:))：通过原始文件 URL 导入，不将 UIImage 转码后写入。
- [PHPhotoLibrary](https://developer.apple.com/documentation/photos/phphotolibrary)：权限和变更事务。
- [iPhone Duo](https://www.apple.com/iphone-duo/)：作为可变窗口尺寸的适配目标；没有在此设备上做实测。

## RICOH 官方

- [GR WORLD 连接步骤](https://www.ricoh-imaging.co.jp/english/products/app/gr-world/connect.html)：GR IV 配对入口、手机与相机确认、重配对说明。
- [GR IV FAQ](https://www.ricoh-imaging.co.jp/english/support/qa/gr-4/index.html)：无线连接和图像传输的使用方式。
- [GR IV 手册](https://www.ricoh-imaging.co.jp/resources/english/support/man-pdf/gr-4_en.pdf)：无线通信与存储操作。

这些页面是相机用户说明，不是公开的 iOS 相机 SDK。

## 非官方协议证据

- [dm-zharov/ricoh-gr-bluetooth-api](https://github.com/dm-zharov/ricoh-gr-bluetooth-api)：GR III / IIIx 的 WLAN 服务、SSID、Passphrase、Network Type UUID 与特征格式。
- [CursedHardware/ricoh-wireless-protocol](https://github.com/CursedHardware/ricoh-wireless-protocol)：`/v1/props`、`/v1/photos`、照片路径、`storage=in/sd1`、`size=thumb` 的协议定义。
- [aspyct/grit](https://github.com/aspyct/grit)：作者在 GR III 系列使用相机 HTTP 下载的证据。
- [GR IV BLE 实验记录](https://github.com/sky18Dragon/RICOH-GR-Live-View-Shooting/blob/main/docs/ricoh_ble_protocol.md)：GR IV 与 GR III 的配对差异、共享 UUID 和固定 handle 的观察。只参考协议事实，没有复制该项目实现。其 ESP32 固定 handle / 安全配置代码不适用于 iOS CoreBluetooth。

当前 App 用标准 CoreBluetooth 发现 UUID，并只在可读凭据与 Capture 状态下尝试写 WLAN Network Type。GR IV 是否稳定支持此路径、是否需要额外握手，需实机验证；如不兼容，应根据新证据增加专属适配，不能盲目试写未知特征。

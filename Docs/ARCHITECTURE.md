# 架构与数据流

## 代码入口

| 文件 / 目录 | 职责 |
| --- | --- |
| `GRTransfer/App/GRTransferApp.swift` | App 生命周期、两个 Tab、全局错误提示 |
| `GRTransfer/App/AppStore.swift` | MainActor UI 状态、连接、队列编排、暂停与后台收尾 |
| `GRTransfer/Core/Models.swift` | 相机/照片/任务模型、HTTP 响应校验、列表解析、日志文件 |
| `GRTransfer/Core/CameraClient.swift` | `/v1/props`、列表、缩略图、原图下载 |
| `GRTransfer/Core/OriginalFile.swift` | JPEG 检查和流式 SHA-256 |
| `GRTransfer/Core/JobStore.swift` | 加锁、原子持久化、事务式内存更新 |
| `GRTransfer/Services/CameraBluetooth.swift` | 扫描、发现服务、读取凭据、系统配对和超时 |
| `GRTransfer/Services/CameraPairing.swift` | Keychain、热点配置、已保存相机模型 |
| `GRTransfer/Services/PhotoLibrary.swift` | 图库权限、相簿、原文件导入和 asset 核对 |
| `GRTransfer/Services/ThumbnailStore.swift` | 最多两个缩略图请求、缓存、让位于原图传输 |
| `GRTransfer/Views` | 传输网格、设置、配对、相簿选择和队列 |

Core 可独立编译，但使用 ImageIO / CryptoKit / Apple Foundation，不是跨 Linux 实现。App 工程直接编译同一批 Core 源码；Swift Package 用于独立检查，不是额外安装的依赖。

## 连接

用户选中蓝牙设备 → CoreBluetooth 发现 WLAN / Camera 服务 → 读取受保护 SSID 和密码触发系统配对 → Capture 状态下尝试开启 AP → NEHotspotConfiguration 请求加入热点 → HTTP `/v1/props` 获取型号与序列号 → 确认相机身份后允许浏览。

热点配置 API 返回成功不等于相机可达。HTTP 身份以 `model|serialNo` 标识，队列固定该身份，重新下载前核对。手动入口可输入热点信息，也可探测系统已连接的相机网络。当前保存记录的“重连”主要使用已存 Wi-Fi 凭据，需要相机热点可用，不保证蓝牙自动唤醒。

GR III 和 GR IV 当前使用发现到的共享 UUID 路径；未实现经真机验证的独立 GR IV 握手适配器。蓝牙模块不可把其他平台的固定 ATT handle 或硬编码 PIN 直接移植到 iOS。

## 传输与保存

```text
选择 JPG + 保存位置
        ↓
持久化 waiting 任务（相机身份、文件、目标相簿）
        ↓
核对相机身份 → downloading → URLSession 临时文件
        ↓
HTTP 状态/长度检查 → 暂存原文件 → JPEG 校验与 SHA-256
        ↓
staged → 核对同哈希、同目标且仍存在的历史资产
        ↓
saving → 先持久化 PhotoKit placeholder ID → PhotoKit 导入原文件
        ↓
completed → 删除本机暂存副本
```

只请求无 `size` 参数的原图。缩略图通过 `size=thumb` 获取，不能作为保存源。UIImage 只用于显示，不参与原片导入。

下载以文件为单位顺序进行，URLSession 每主机最多两个连接，原图传输时暂停缩略图。HTTP 重定向、206 部分响应、非 200、长度不一致和无效 JPEG 不作为完整原片提交。网络临时失败最多额外重试两次；失败后停止本轮队列，避免对剩余所有照片重复重连。

## 持久化与恢复

App 沙盒 `Application Support/GRTransfer` 中保存：

- `cameras.json`：相机身份、SSID、可选蓝牙 peripheral ID；不含 Wi-Fi 密码。
- `transfers.json`：任务状态、文件、目标相簿、哈希、asset ID 与错误。
- `Originals/<任务 UUID>.jpg`：完整下载、等待导入的原片；导入成功后删除。

Wi-Fi 密码位于设备本地 Keychain；默认相簿 ID 存于 UserDefaults。上述 Application Support 目录设为不参与备份，Git 也不包含这些运行数据。

启动时将 downloading / saving 状态恢复为 waiting，保留哈希与 asset ID。若预留 asset ID 已在图库存在，就确认完成；否则继续处理暂存原片或重新下载。JobStore 先原子写入新日志，再替换内存快照。读取损坏日志时报告错误，不覆盖证据。

恢复不是字节级续传。没有验证过相机支持 Range 或可靠 resume data，因此不拼接部分文件。PhotoKit 保存失败保留暂存副本；原片不依赖相机再次在线也可尝试保存。

## 并发与生命周期边界

AppStore 是 MainActor。URLSession 异步下载；图像校验和哈希在 detached utility Task 执行；缩略图 actor 限流；JobStore 的锁串行化主线程及 PhotoKit 事务中的持久化变更。CoreBluetooth delegate 指定主队列。

当前 Swift language mode 为 5。完整新 SDK 构建后需检查严格并发诊断，尤其 MainActor delegate 协议隔离和 `@unchecked Sendable` 类型；不能把语法检查视为线程安全证明。

后台使用有限 `beginBackgroundTask` 收尾，系统到期取消网络任务。恢复到前台需要用户继续队列。当前没有 background URLSession、后台持续同步或系统蓝牙恢复承诺。

## 尚需验证或改进

- 真正的 PhotoKit 提交崩溃窗口、有限权限、相簿删除和磁盘写入失败。
- 同文件、不同相簿目前会重新保存资产；后续可考虑把已有资产加入另一相簿。
- 哈希去重需要先下载；不会仅凭文件名跳过，防止相机重用文件名误判。
- 完成历史持续保留；大量导入后的日志体积、启动耗时与清理策略待实测。
- 当前网格按路径自然降序，不是依据 EXIF 拍摄时间排序。
- 缩略图错误暂显示占位符，更多诊断与重试体验待补。
- 产品文案、严格无障碍和宽屏布局尚未经过运行审查。

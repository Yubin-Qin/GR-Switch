# 开发环境与换 Mac 指南

本仓库不依赖最初 MacBook 的绝对路径。源码、资源、生成器、Xcode 工程和共享 scheme 均提交到 Git；个人签名、构建产物、设备数据留在各自机器。

## 1. 新 Mac 的准备

1. 安装完整 Xcode，首次启动完成许可确认和 iOS platform 安装。需要 SDK 版本不低于应用的部署版本 26.6，并支持待测试手机的系统。
2. 配置这台 Mac 自己的 GitHub SSH key 并在 GitHub 授权，不必复制旧 Mac 的私钥。
3. 克隆仓库：

```sh
git clone git@github.com:Yubin-Qin/GR-Switch.git
cd GR-Switch
```

4. 确认工具链和脚本依赖：

```sh
xcode-select -p
xcodebuild -version
xcodebuild -showsdks
swift --version
python3 --version
```

如果工具链仍指向 `/Library/Developer/CommandLineTools`，可在 Xcode Settings → Locations 中选择 Command Line Tools。也可在当前终端临时选择完整 Xcode（按实际安装路径调整）：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

该环境变量仅影响当前终端，不会改变从 Finder 打开的 Xcode。项目脚本需要 `zsh`、Python 3 和 Apple Swift 工具链；没有 pip / npm / CocoaPods 安装步骤。

## 2. 每台 Mac 独立配置签名

```sh
cp Config/Signing.example.xcconfig Config/Signing.local.xcconfig
open GRTransfer.xcodeproj
```

编辑 `Config/Signing.local.xcconfig`，把 `YOUR_TEAM_ID` 替换为自己的 Apple Developer Team ID。在 Xcode Settings → Accounts 登录对应账号，在 target 的 Signing & Capabilities 中核对 Automatic Signing 与 Team。

`Config/App.xcconfig` 被 Debug/Release 共同引用，并可选加载同目录的 `Signing.local.xcconfig`。后者已被 Git 忽略，工程重新生成也不会覆盖。不要把真实签名配置填入示例文件。共享默认 Bundle ID 是 `com.yubin.GRTransfer`；如果需要改，用本地文件覆盖。跨 Mac 调试同一个 App 时保持相同 Team 和 Bundle ID。

Hotspot Configuration entitlement 已声明，必须确认 Team / provisioning profile 能签此 capability。不要为了通过构建直接删除它，否则加入相机热点的功能会失效。证书、私钥、provisioning profile 和 Apple ID 密码不进入仓库；在新 Mac 通过 Xcode 配置签名。

若在 Xcode Build Settings 中直接填入同名 target 设置，它可能覆盖 xcconfig。出现“配置文件改了但没生效”时，检查 Build Settings → Levels；优先保持个人配置只在本地 xcconfig。

## 3. 运行检查和构建

无需相机、可仅使用 Command Line Tools 的核心检查：

```sh
./Scripts/check_core.sh
```

它编译核心与独立检查程序，在 `127.0.0.1` 的随机端口启动模拟相机，运行 16 项检查，最后检查工程 plist。临时构建目录在退出时清理。受限运行环境可能需要允许本机端口绑定；该检查不连接真实相机或外网。

完整 Xcode 下的 Swift Package 测试：

```sh
swift test
```

`Package.swift` 只测试 `GRTransfer/Core`，不是 App 工程。它的 iOS 16 / macOS 12 声明属于可复用核心，**不是 App 的最低系统版本**。Xcode 的 GRTransfer scheme 暂无 App XCTest/UI 测试 target；不能用 App scheme 的空 TestAction 代替上述测试。

无签名模拟器构建：

```sh
xcodebuild -project GRTransfer.xcodeproj -scheme GRTransfer \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

真机运行：选择 `GRTransfer` scheme，USB 连接并信任 iPhone，按 Xcode 指引开启开发者模式，选择该设备并运行。模拟器不能验证真实 BLE、热点加入或相机吞吐。

若 `swift test` 在仅有 Command Line Tools 时提示找不到 `PlatformPath`，先运行 `check_core.sh`；完整 Xcode 配置好后再运行 Package 测试。语法解析和核心类型检查通过不代表 iOS App 编译通过。

## 4. 改代码与工程

按现有 App / Core / Services / Views 层次放置代码。`.xcodeproj` 已提交，克隆后可直接打开。新增/移除源文件，或修改共享工程配置时：

```sh
python3 Scripts/generate_project.py
git diff --stat
git diff -- GRTransfer.xcodeproj GRTransfer/Resources
```

生成器是工程配置、Info.plist、entitlements、隐私清单及代码绘制图标的来源；它会重新生成这些文件。对这些生成文件的持久修改应同步到生成器。`Config/App.xcconfig`、签名示例及本地签名文件由开发者维护，生成器只引用它们。

生成器采用稳定文件标识，Xcode 导航中按源码层和配置分组。不要为了换机器重命名代码根目录、target、scheme 或 Bundle ID。产品显示名的统一可作为单独变更处理。

完成一次改动后，运行与改动相关的检查；影响传输、PhotoKit 或 BLE 时按真机计划补充验证。记录“实际执行的命令/设备/结果”，不要只写“已测试”。

## 5. 两台 Mac 之间交接

旧 Mac 离开前：

```sh
git status
git add <本次修改的文件>
git commit -m "Describe the completed change"
git push
```

新 Mac 已有克隆时：

```sh
git status
git pull --ff-only
```

若工作区有本地改动，先提交或明确保存后再更新；发生分叉时先检查双方提交，不要强制推送覆盖。多人或并行开发使用功能分支和 PR，合并前保留验证结果。

Git 不会迁移 App 沙盒内的传输队列、相机照片、Keychain Wi‑Fi 密码、系统蓝牙配对、模拟器状态或开发证书。换开发 Mac 但继续使用同一部 iPhone 时，保持相同签名身份以减少安装标识变化；卸载 App 会清除其沙盒记录，应先完成需要保留的传输。新测试设备需重新配对。

## 6. 提交边界

提交源码、测试、文档、共享配置、资源和工程；不提交 `Signing.local.xcconfig`、`.build`、DerivedData、xcuserdata、真实相机照片/日志、密码、证书或私钥。新增测试样本使用合成数据或已获授权且去除个人信息的文件。仓库当前未指定开源许可证，不能仅因可访问就假定具备开源授权。

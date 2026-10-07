import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showPairing = false
    @State private var showAlbums = false
    @State private var removal: SavedCamera?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "camera.aperture").font(.largeTitle).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("GR Transfer").font(.title2.bold())
                            Text("专注照片，忠于原片。").font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                }
                Section {
                    if store.cameras.isEmpty { Text("还没有保存的相机").foregroundStyle(.secondary) }
                    ForEach(store.cameras) { camera in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(camera.identity.model, systemImage: "camera")
                                Spacer()
                                if store.connected?.key == camera.id { Text("已连接").font(.caption).foregroundStyle(.green) }
                            }
                            Text("序列号尾号 \(camera.identity.serialNo.suffix(4)) · \(camera.ssid)")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("连接") { Task { await store.reconnect(camera) } }.buttonStyle(.bordered)
                                Spacer()
                                Button("移除", role: .destructive) { removal = camera }.buttonStyle(.borderless)
                            }.disabled(store.locked)
                        }.padding(.vertical, 6)
                    }
                    Button("添加相机", systemImage: "plus") { showPairing = true }.disabled(store.locked)
                    if store.connected != nil { Button("断开当前连接") { store.disconnect() }.disabled(store.locked) }
                } header: { Text("我的相机") } footer: {
                    Text("支持 GR III / IIIx 与 GR IV 系列的连接流程。不同型号与固件仍需真机验证。Wi‑Fi 密码仅存储于本机钥匙串。")
                }
                Section("照片") {
                    Button { showAlbums = true } label: {
                        LabeledContent("保存到", value: store.albums.first(where: { $0.id == store.albumID })?.title ?? "照片图库")
                    }.disabled(store.transferring)
                    LabeledContent("传输格式", value: "原始 JPG")
                    LabeledContent("拍摄信息", value: "保留原始 EXIF")
                }
                Section {
                    Label("下载到磁盘，避免大图占满内存", systemImage: "internaldrive")
                    Label("失败自动重试，队列保存在本机", systemImage: "arrow.clockwise")
                    Label("校验完整性后再保存", systemImage: "checkmark.shield")
                } header: { Text("传输保障") } footer: {
                    Text("默认单张原图顺序传输，缩略图请求在传输时暂停。离开应用后，iOS 可能暂停网络任务；回到应用点“继续”即可。未完成的单张照片会重新下载。")
                }
                Section("权限与帮助") {
                    Button("打开系统设置", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    Text("首次连接需允许蓝牙与本地网络访问。浏览和创建相簿需照片图库权限。相机 Wi‑Fi 没有互联网是正常现象。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("设置")
                .sheet(isPresented: $showPairing) { PairingView(bluetooth: store.bluetooth) }
                .sheet(isPresented: $showAlbums) { AlbumPickerView() }
                .confirmationDialog("移除这台相机？", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
                    Button("移除本机连接记录", role: .destructive) { if let removal { store.forget(removal) }; removal = nil }
                } message: { Text("不会删除照片。系统蓝牙配对记录需在 iOS 或相机的蓝牙设置中单独移除。") }
        }
    }
}

struct PairingView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var bluetooth: CameraBluetooth
    @State private var ssid = ""
    @State private var password = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("让相机与手机靠近", systemImage: "camera.badge.ellipsis")
                    Text("打开相机，在无线通信设置中进入蓝牙配对。暂时退出 GR WORLD / Image Sync，避免占用连接。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    Button(bluetooth.scanning ? "停止搜索" : "搜索蓝牙相机", systemImage: "antenna.radiowaves.left.and.right") {
                        if bluetooth.scanning { bluetooth.stopScan() } else { bluetooth.scan() }
                    }.disabled(store.connecting)
                    Text(bluetooth.status).font(.footnote).foregroundStyle(.secondary)
                    ForEach(bluetooth.nearby) { camera in
                        Button {
                            Task { await store.pair(camera.id); if store.connected != nil { dismiss() } }
                        } label: { HStack { Label(camera.name, systemImage: "camera"); Spacer(); Image(systemName: "chevron.right") } }
                        .disabled(store.connecting)
                    }
                    if store.connecting { ProgressView("正在连接，请留意系统提示…") }
                } header: { Text("通过蓝牙连接") } footer: {
                    Text("配对确认由 iOS 处理。若相机无法自动开启 Wi‑Fi，请在相机上开启后，使用下方手动连接。")
                }
                Section("手动连接 Wi‑Fi") {
                    TextField("相机 Wi‑Fi 名称（SSID）", text: $ssid).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("相机 Wi‑Fi 密码", text: $password)
                    Button("加入网络并连接") {
                        Task { await store.manualConnect(ssid: ssid.trimmingCharacters(in: .whitespacesAndNewlines), password: password); if store.connected != nil { dismiss() } }
                    }.disabled(ssid.isEmpty || password.isEmpty || store.connecting)
                    Button("我已在系统设置连接相机 Wi‑Fi") {
                        Task { await store.useCurrentNetwork(); if store.connected != nil { dismiss() } }
                    }.disabled(store.connecting)
                }
                Section {
                    Text("Wi‑Fi 名称和密码可在相机的通信信息中查看。GR IV 若不显示密码，请先尝试蓝牙配对获取。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("添加相机").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { bluetooth.stopScan(); dismiss() }.disabled(store.connecting) } }
                .interactiveDismissDisabled(store.connecting)
                .onDisappear { bluetooth.stopScan() }
        }
    }
}

import SwiftUI

struct TransferView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let openSettings: () -> Void
    @State private var showQueue = false
    @State private var showAlbums = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    connectionCard
                    if let failure = store.storageFailure {
                        Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                    if store.connected != nil {
                        libraryHeader
                        if store.loading {
                            ProgressView("正在读取相机照片…").frame(maxWidth: .infinity, minHeight: 200)
                        } else if store.photos.isEmpty {
                            ContentUnavailableView("这里还没有 JPG", systemImage: "photo.on.rectangle.angled",
                                                   description: Text("试试切换存储位置，或拍摄一张 JPG 后刷新。"))
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 180 : 104, maximum: 240), spacing: 8)], spacing: 12) {
                                ForEach(store.photos) { photo in
                                    PhotoCell(photo: photo, cameraKey: store.connected!.key,
                                              selected: store.selection.contains(photo.id), thumbnails: store.thumbnails,
                                              transferring: store.transferring) {
                                        if store.selection.contains(photo.id) { store.selection.remove(photo.id) }
                                        else { store.selection.insert(photo.id) }
                                    }
                                    .disabled(store.transferring)
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: "camera.aperture").font(.system(size: 72, weight: .ultraLight)).foregroundStyle(.secondary)
                            Text("每一张，都如拍摄时。")
                                .font(.title2.weight(.semibold))
                            Text("浏览相机里的照片，将原始 JPG\n连同拍摄信息一起保存。")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("连接我的相机", action: openSettings).buttonStyle(.borderedProminent).controlSize(.large)
                        }.frame(maxWidth: .infinity, minHeight: 300)
                    }
                    if store.pendingCount > 0 || store.transferring { transferCard }
                    Label("原始 JPG · 保留 EXIF · 不压缩", systemImage: "checkmark.shield")
                        .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                .padding(20).frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("传输")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showQueue = true } label: { Image(systemName: "list.bullet.rectangle") }
                        .accessibilityLabel("传输记录")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(store.connected == nil || store.locked).accessibilityLabel("刷新相机照片")
                }
            }
            .refreshable { await store.refresh() }
            .safeAreaInset(edge: .bottom) {
                if !store.selection.isEmpty && !store.transferring {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("已选择 \(store.selection.count) 张").font(.headline)
                            Button { showAlbums = true } label: {
                                Text(store.albums.first(where: { $0.id == store.albumID })?.title ?? "存入照片图库")
                                    .font(.caption).lineLimit(1)
                            }
                        }
                        Spacer()
                        Button("传输原图", systemImage: "arrow.down") { store.enqueue() }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(store.locked || store.storageFailure != nil)
                    }
                    .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal).padding(.bottom, 8)
                }
            }
            .sheet(isPresented: $showQueue) { QueueView() }
            .sheet(isPresented: $showAlbums) { AlbumPickerView() }
        }
    }
    private var connectionCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.title2).frame(width: 52, height: 52)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text(store.connected?.model ?? "RICOH GR").font(.headline)
                Text(store.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if store.connecting { ProgressView() }
            else {
                Image(systemName: store.connected == nil ? "wifi.slash" : "wifi")
                    .foregroundStyle(store.connected == nil ? Color.secondary : Color.green)
                    .accessibilityLabel(store.connected == nil ? "未连接" : "Wi-Fi 已连接")
            }
        }.padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("相机照片").font(.title3.bold())
                Text("\(store.photos.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button(store.selection.count == store.photos.count && !store.photos.isEmpty ? "取消全选" : "全选") {
                    store.selection = store.selection.count == store.photos.count ? [] : Set(store.photos.map(\.id))
                }.disabled(store.locked || store.photos.isEmpty)
            }
            Picker("存储位置", selection: $store.storage) {
                ForEach(CameraStorage.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).disabled(store.locked)
                .onChange(of: store.storage) { _, _ in Task { await store.refresh() } }
        }
    }
    private var transferCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(store.transferring ? "正在传输原图" : "还有 \(store.pendingCount) 张待完成", systemImage: "arrow.down.circle.fill").font(.headline)
                Spacer()
                if store.transferring { Button("暂停") { store.pause() } }
                else { Button("继续") { store.startTransfers() }.disabled(store.locked) }
            }
            if store.transferring {
                if store.expected > 0 { ProgressView(value: min(1, Double(store.received) / Double(store.expected))) }
                else { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
                HStack {
                    Text(store.jobs.first(where: { $0.id == store.activeJobID })?.photo.filename ?? "准备中")
                    Spacer()
                    Text(store.speed > 0 ? "\(store.speed / 1_000_000, specifier: "%.1f") MB/s" : "连接中…").monospacedDigit()
                }.font(.caption).foregroundStyle(.secondary)
            }
            Text("传输时请保持相机开启，尽量让应用留在前台。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct PhotoCell: View {
    let photo: CameraPhoto
    let cameraKey: String
    let selected: Bool
    let thumbnails: ThumbnailStore
    let transferring: Bool
    let action: () -> Void
    @State private var image: UIImage?
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Color(uiColor: .tertiarySystemFill).aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let image { Image(uiImage: image).resizable().scaledToFill() }
                        else { Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary) }
                    }.clipped()
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title2).symbolRenderingMode(.palette)
                            .foregroundStyle(selected ? Color.accentColor : .white, .white)
                            .shadow(radius: 2).padding(8)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
                Text(photo.filename).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
        }.buttonStyle(.plain)
            .accessibilityLabel(photo.filename).accessibilityAddTraits(selected ? [.isSelected] : [])
            .task(id: "\(cameraKey)/\(photo.id)/\(transferring)") {
                if !transferring && image == nil { image = await thumbnails.image(for: photo, cameraKey: cameraKey) }
            }
    }
}

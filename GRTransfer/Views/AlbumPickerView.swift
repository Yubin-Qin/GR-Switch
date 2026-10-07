import SwiftUI
import PhotosUI

struct AlbumPickerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var creating = false
    var body: some View {
        NavigationStack {
            Form {
                Section("保存位置") {
                    albumRow("照片图库", id: "")
                    ForEach(store.albums) { album in albumRow(album.title, id: album.id) }
                }
                Section("新建相簿") {
                    TextField("相簿名称，例如：京都散步", text: $name)
                    Button("创建相簿", systemImage: "folder.badge.plus") {
                        creating = true
                        Task { await store.createAlbum(name); name = ""; creating = false }
                    }.disabled(creating || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section {
                    Text("原片始终保存到系统照片图库；选择相簿会同时将照片加入该相簿。已排队照片的保存位置不受后续修改影响。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("保存到").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .task { await store.loadAlbums() }
        }
    }
    private func albumRow(_ title: String, id: String) -> some View {
        Button { store.albumID = id } label: {
            HStack { Label(title, systemImage: id.isEmpty ? "photo.on.rectangle" : "folder"); Spacer()
                if store.albumID == id { Image(systemName: "checkmark").fontWeight(.semibold) }
            }
        }.foregroundStyle(.primary)
    }
}

struct QueueView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("已保存", value: "\(store.completedCount) 张")
                    LabeledContent("待完成", value: "\(store.pendingCount) 张")
                    if store.pendingCount > 0 {
                        if store.transferring { Button("暂停传输") { store.pause() } }
                        else { Button("继续未完成的传输") { store.startTransfers() } }
                    }
                }
                Section("最近的传输") {
                    ForEach(Array(store.jobs.suffix(200).reversed())) { job in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: job.state == .completed ? "checkmark.circle.fill" : job.state == .failed ? "exclamationmark.circle" : "clock")
                                .foregroundStyle(job.state == .completed ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(job.photo.filename).font(.headline)
                                Text("\(job.camera.model) · \(job.state.title)").font(.caption).foregroundStyle(.secondary)
                                if let error = job.error { Text(error).font(.caption).foregroundStyle(.red) }
                            }
                        }.padding(.vertical, 4)
                            .swipeActions {
                                if job.state != .completed && !store.locked {
                                    Button("移出队列", role: .destructive) { store.removePending(job.id) }
                                }
                            }
                    }
                }
                if store.jobs.isEmpty { Text("选择照片后，传输进度会显示在这里。").foregroundStyle(.secondary) }
            }.navigationTitle("传输记录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

import SwiftUI
import Photos
import UIKit

@MainActor
final class AppStore: ObservableObject {
    @Published var cameras: [SavedCamera] = []
    @Published private(set) var connected: CameraIdentity?
    @Published private(set) var photos: [CameraPhoto] = []
    @Published private(set) var jobs: [TransferJob] = []
    @Published private(set) var albums: [PhotoAlbum] = []
    @Published var selection = Set<String>()
    @Published var storage: CameraStorage = .sd1
    @Published var albumID = UserDefaults.standard.string(forKey: "destinationAlbum") ?? "" {
        didSet { UserDefaults.standard.set(albumID, forKey: "destinationAlbum") }
    }
    @Published var errorMessage: String?
    @Published private(set) var status = "连接相机，让照片回到身边。"
    @Published private(set) var connecting = false
    @Published private(set) var loading = false
    @Published private(set) var transferring = false
    @Published private(set) var activeJobID: UUID?
    @Published private(set) var received: Int64 = 0
    @Published private(set) var expected: Int64 = 0
    @Published private(set) var speed: Double = 0
    @Published private(set) var storageFailure: String?
    let bluetooth = CameraBluetooth()
    let client = CameraClient()
    let thumbnails = ThumbnailStore()
    let library = PhotoLibrary()
    private let directory: URL
    private var jobStore: JobStore?
    private var transferTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var lastProgress = Date.distantPast
    private var lastBytes: Int64 = 0
    var pendingCount: Int { jobs.filter { $0.state != .completed }.count }
    var completedCount: Int { jobs.filter { $0.state == .completed }.count }
    var locked: Bool { transferring || connecting || loading }

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GRTransfer", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var resource = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try resource.setResourceValues(values)
            jobStore = try JobStore(url: directory.appendingPathComponent("transfers.json"))
            jobs = jobStore!.snapshot()
            let saved = directory.appendingPathComponent("cameras.json")
            if FileManager.default.fileExists(atPath: saved.path) {
                cameras = try JSONDecoder().decode([SavedCamera].self, from: Data(contentsOf: saved))
            }
        } catch { storageFailure = "无法读取本地记录：\(error.localizedDescription)。请保留应用数据后检查存储空间。" }
    }
    func report(_ error: Error) {
        if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { return }
        errorMessage = error.localizedDescription
    }
    func pair(_ id: UUID) async {
        guard !locked else { return }
        connecting = true; defer { connecting = false }
        do {
            let credentials = try await bluetooth.connect(id)
            try await establish(ssid: credentials.ssid, password: credentials.password, peripheral: credentials.peripheralID, expected: nil)
        } catch { report(error); status = "未连接相机" }
    }
    func manualConnect(ssid: String, password: String) async {
        guard !locked else { return }
        connecting = true; defer { connecting = false }
        do { try await establish(ssid: ssid, password: password, peripheral: nil, expected: nil) }
        catch { report(error); status = "未连接相机" }
    }
    func reconnect(_ camera: SavedCamera) async {
        guard !locked else { return }
        connecting = true; defer { connecting = false }
        do {
            // Saved Wi-Fi credentials allow reconnection even if BLE is unavailable.
            guard let password = CredentialStore.load(camera.id), !camera.ssid.isEmpty else {
                throw BluetoothError.message("请在相机开启 Wi‑Fi，然后使用手动连接或重新蓝牙配对。")
            }
            try await establish(ssid: camera.ssid, password: password, peripheral: camera.peripheralID, expected: camera.identity)
        } catch { report(error); status = "未连接相机" }
    }
    func useCurrentNetwork() async {
        guard !locked else { return }
        connecting = true; connected = nil; photos = []; selection = []
        defer { connecting = false }
        do {
            let identity = try await client.identity()
            connected = identity; status = "\(identity.model) · 已连接"
            await refresh()
        } catch { report(error); status = "未连接相机，请检查相机 Wi‑Fi 和本地网络权限" }
    }
    private func establish(ssid: String, password: String, peripheral: UUID?, expected: CameraIdentity?) async throws {
        connected = nil; photos = []; selection = []
        await thumbnails.clear()
        status = "正在加入相机 Wi‑Fi…"
        try await CameraWiFi.join(ssid: ssid, password: password)
        // NEHotspotConfiguration success only means configuration was applied. Verify HTTP identity.
        var found: CameraIdentity?
        var lastError: Error = CameraError.invalidResponse
        for attempt in 0..<6 {
            do { found = try await client.identity(); break }
            catch {
                lastError = error
                if !CameraProtocol.shouldRetry(error) { throw error }
                if attempt < 5 { try await Task.sleep(nanoseconds: 2_000_000_000) }
            }
        }
        guard let identity = found else { throw lastError }
        if let expected, identity.key != expected.key { throw CameraError.wrongCamera }
        try CredentialStore.save(password, for: identity.key)
        let saved = SavedCamera(identity: identity, peripheralID: peripheral, ssid: ssid)
        var next = cameras.filter { $0.id != saved.id }; next.append(saved)
        try JSONEncoder().encode(next).write(to: directory.appendingPathComponent("cameras.json"), options: .atomic)
        cameras = next; connected = identity; status = "\(identity.model) · 已连接"
        await refresh()
    }
    func forget(_ camera: SavedCamera) {
        guard !locked else { return }
        do {
            let next = cameras.filter { $0.id != camera.id }
            try JSONEncoder().encode(next).write(to: directory.appendingPathComponent("cameras.json"), options: .atomic)
            cameras = next; CredentialStore.remove(camera.id); CameraWiFi.forget(ssid: camera.ssid)
            if connected?.key == camera.id { disconnect() }
        } catch { report(error) }
    }
    func disconnect() {
        guard !transferring else { return }
        connected = nil; photos = []; selection = []; bluetooth.disconnect(); status = "未连接相机"
    }
    func refresh() async {
        guard let connected, !transferring, !loading else { return }
        loading = true; defer { loading = false }
        do {
            let actual = try await client.identity()
            guard actual.key == connected.key else { throw CameraError.wrongCamera }
            photos = try await client.photos(storage: storage)
            selection.formIntersection(Set(photos.map(\.id)))
        } catch { photos = []; selection = []; report(error) }
    }
    func loadAlbums() async {
        do { try await library.authorize(); albums = library.albums() } catch { report(error) }
    }
    func createAlbum(_ name: String) async {
        do { try await library.createAlbum(title: name); albums = library.albums() } catch { report(error) }
    }
    func enqueue() {
        guard let connected, !locked, storageFailure == nil else { return }
        do {
            try change { jobs in
                for photo in photos where selection.contains(photo.id) {
                    guard !jobs.contains(where: { $0.camera.key == connected.key && $0.photo == photo && $0.state != .completed }) else { continue }
                    jobs.append(TransferJob(camera: connected, photo: photo, albumID: albumID.isEmpty ? nil : albumID))
                }
            }
            selection = []; startTransfers()
        } catch { report(error) }
    }
    func startTransfers() {
        guard !locked, pendingCount > 0, storageFailure == nil else { return }
        transferring = true
        UIApplication.shared.isIdleTimerDisabled = true
        transferTask = Task { await runTransfers() }
    }
    func pause() { transferTask?.cancel() }
    func enteredBackground() {
        guard transferring, backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish original photo") { [weak self] in
            Task { @MainActor in self?.pause(); self?.endBackgroundTime() }
        }
    }
    func enteredForeground() { endBackgroundTime() }
    private func endBackgroundTime() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    func removePending(_ id: UUID) {
        guard !locked, jobs.contains(where: { $0.id == id && $0.state != .completed }) else { return }
        do {
            try change { $0.removeAll { $0.id == id } }
            try? FileManager.default.removeItem(at: stagedURL(id))
        } catch { report(error) }
    }
    private func stagedURL(_ id: UUID) -> URL { directory.appendingPathComponent("Originals/\(id.uuidString).jpg") }
    private func change(_ body: (inout [TransferJob]) throws -> Void) throws {
        guard let jobStore else { throw BluetoothError.message("本地传输记录不可用。") }
        try jobStore.update(body); jobs = jobStore.snapshot()
    }
    private func set(_ id: UUID, _ body: (inout TransferJob) -> Void) throws {
        try change { jobs in if let index = jobs.firstIndex(where: { $0.id == id }) { body(&jobs[index]) } }
    }
    private func runTransfers() async {
        defer {
            transferring = false; activeJobID = nil; speed = 0; transferTask = nil
            UIApplication.shared.isIdleTimerDisabled = false; endBackgroundTime()
        }
        do {
            try await library.authorize()
            let ids = jobs.filter { $0.state != .completed }.map(\.id)
            await thumbnails.suspend()
            defer { Task { await thumbnails.resume() } }
            for id in ids {
                try Task.checkCancellation()
                guard let job = jobs.first(where: { $0.id == id }) else { continue }
                activeJobID = id; received = 0; expected = 0; lastBytes = 0; lastProgress = Date(); speed = 0
                // Recover the commit window without importing the same file twice.
                if let assetID = job.assetID, library.exists(assetID) {
                    try set(id) { $0.state = .completed; $0.error = nil }
                    try? FileManager.default.removeItem(at: stagedURL(id)); continue
                }
                do {
                    let file = stagedURL(id)
                    var digest = job.digest
                    if !FileManager.default.fileExists(atPath: file.path) {
                        guard let connected, connected.key == job.camera.key else { throw CameraError.wrongCamera }
                        let identity = try await client.identity()
                        guard identity.key == job.camera.key else { throw CameraError.wrongCamera }
                        try set(id) { $0.state = .downloading; $0.error = nil; $0.assetID = nil }
                        for attempt in 0..<3 {
                            do {
                                _ = try await client.download(job.photo, to: file) { [weak self] bytes, total in
                                    Task { @MainActor in self?.updateProgress(id, bytes: bytes, total: total) }
                                }
                                digest = try await Task.detached(priority: .utility) { try OriginalFile.validateAndHash(file) }.value
                                break
                            } catch {
                                try? FileManager.default.removeItem(at: file)
                                guard !Task.isCancelled, attempt < 2, CameraProtocol.shouldRetry(error) else { throw error }
                                status = "连接不稳定，正在重试（\(attempt + 1)/2）…"
                                try await Task.sleep(nanoseconds: UInt64(1 << attempt) * 1_000_000_000)
                            }
                        }
                    } else {
                        let verified: String
                        do { verified = try await Task.detached(priority: .utility) { try OriginalFile.validateAndHash(file) }.value }
                        catch { try? FileManager.default.removeItem(at: file); throw error }
                        if let digest, digest != verified { try FileManager.default.removeItem(at: file); throw CameraError.invalidJPEG }
                        digest = verified
                    }
                    guard let digest else { throw CameraError.invalidJPEG }
                    try set(id) { $0.state = .staged; $0.digest = digest; $0.error = nil }
                    try Task.checkCancellation()
                    if let previous = jobs.first(where: { $0.id != id && $0.digest == digest && $0.albumID == job.albumID && $0.state == .completed }),
                       let assetID = previous.assetID, library.exists(assetID) {
                        try set(id) { $0.state = .completed; $0.assetID = assetID }
                    } else {
                        try set(id) { $0.state = .saving }
                        let store = jobStore!
                        let assetID = try await library.save(file: file, filename: job.photo.filename, albumID: job.albumID) { assetID in
                            try store.update { records in
                                if let index = records.firstIndex(where: { $0.id == id }) { records[index].assetID = assetID }
                            }
                        }
                        try set(id) { $0.state = .completed; $0.assetID = assetID; $0.error = nil }
                    }
                    try? FileManager.default.removeItem(at: file)
                    status = "已保存 \(job.photo.filename)"
                } catch {
                    let cancelled = Task.isCancelled || error is CancellationError || (error as NSError).code == NSURLErrorCancelled
                    try set(id) { $0.state = cancelled ? .waiting : .failed; $0.error = cancelled ? nil : error.localizedDescription }
                    if cancelled { status = "传输已暂停，已完成的照片已保留。"; return }
                    throw error // A disconnected camera should not cause retries for every remaining file.
                }
            }
            status = "照片已安全存入图库。"
        } catch { report(error); status = Task.isCancelled ? "传输已暂停" : "传输已停止，可重试未完成的照片。" }
    }
    private func updateProgress(_ id: UUID, bytes: Int64, total: Int64) {
        guard activeJobID == id, transferring else { return }
        let now = Date(); let interval = now.timeIntervalSince(lastProgress)
        guard interval >= 0.2 || bytes == total else { return }
        speed = Double(max(0, bytes - lastBytes)) / max(0.001, interval)
        received = bytes; expected = total; lastBytes = bytes; lastProgress = now
    }
}

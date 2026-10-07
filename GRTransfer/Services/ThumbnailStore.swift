import UIKit

/// At most two requests; the cache is bounded and requests are cancelled before originals start.
actor ThumbnailStore {
    private let cache = NSCache<NSString, UIImage>()
    private let client = CameraClient()
    private var running: [UUID: Task<Data, Error>] = [:]
    private var paused = false
    init() { cache.totalCostLimit = 24 * 1024 * 1024; cache.countLimit = 300 }
    func image(for photo: CameraPhoto, cameraKey: String) async -> UIImage? {
        let key = "\(cameraKey)/\(photo.id)" as NSString
        if let image = cache.object(forKey: key) { return image }
        while running.count >= 2 || paused {
            do { try await Task.sleep(nanoseconds: 100_000_000); try Task.checkCancellation() }
            catch { return nil }
        }
        guard !Task.isCancelled else { return nil }
        let token = UUID()
        let task = Task { try await client.thumbnail(photo) }
        running[token] = task
        defer { running.removeValue(forKey: token) }
        let data = await withTaskCancellationHandler {
            try? await task.value
        } onCancel: { task.cancel() }
        guard !Task.isCancelled, let data, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key, cost: max(1, Int(image.size.width * image.size.height * image.scale * image.scale * 4)))
        return image
    }
    func suspend() { paused = true; running.values.forEach { $0.cancel() } }
    func resume() { paused = false }
    func clear() { running.values.forEach { $0.cancel() }; cache.removeAllObjects() }
}

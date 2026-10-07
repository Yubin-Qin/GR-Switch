import Foundation

public final class CameraClient: @unchecked Sendable {
    private let session: URLSession
    public let baseURL: URL
    public init(baseURL: URL = CameraProtocol.baseURL, configuration: URLSessionConfiguration = .ephemeral) {
        self.baseURL = baseURL
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 300
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.allowsCellularAccess = false
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration, delegate: LocalOnlyDelegate(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    public func identity() async throws -> CameraIdentity {
        let data = try await get(baseURL.appendingPathComponent("props"))
        let identity = try JSONDecoder().decode(CameraIdentity.self, from: data)
        guard identity.model.uppercased().contains("GR"), !identity.serialNo.isEmpty else { throw CameraError.invalidResponse }
        return identity
    }
    public func photos(storage: CameraStorage) async throws -> [CameraPhoto] {
        var parts = URLComponents(url: baseURL.appendingPathComponent("photos"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "storage", value: storage.rawValue)]
        return try CameraProtocol.parsePhotos(await get(parts.url!), storage: storage)
    }
    public func thumbnail(_ photo: CameraPhoto) async throws -> Data {
        try await get(CameraProtocol.photoURL(photo, thumbnail: true, base: baseURL))
    }
    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try CameraProtocol.validate(response)
        return data
    }
    /// URLSession spools to disk; original JPG bytes never pass through an image encoder.
    /// Incomplete files restart from zero. No unsafe Range append when the camera lacks validators.
    public func download(_ photo: CameraPhoto, to destination: URL,
                         progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> Int64 {
        let delegate = DownloadProgress(progress)
        let (temporary, response) = try await session.download(from: CameraProtocol.photoURL(photo, base: baseURL), delegate: delegate)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        try CameraProtocol.validate(response)
        let size = (try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw CameraError.truncatedFile }
        if response.expectedContentLength > 0, response.expectedContentLength != size { throw CameraError.truncatedFile }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The destination is unique per job and is never used to hold a partial download.
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return size
    }
}

private class LocalOnlyDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
private final class DownloadProgress: LocalOnlyDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    let report: @Sendable (Int64, Int64) -> Void
    init(_ report: @escaping @Sendable (Int64, Int64) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        report(totalBytesWritten, totalBytesExpectedToWrite)
    }
}

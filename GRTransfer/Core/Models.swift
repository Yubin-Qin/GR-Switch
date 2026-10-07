import Foundation

public enum CameraStorage: String, Codable, CaseIterable, Identifiable, Sendable {
    case sd1, internalMemory = "in"
    public var id: String { rawValue }
    public var title: String { self == .sd1 ? "SD 卡" : "内置存储" }
}

public struct CameraPhoto: Codable, Hashable, Identifiable, Sendable {
    public let folder: String
    public let filename: String
    public let storage: CameraStorage
    public var id: String { "\(storage.rawValue)/\(folder)/\(filename)" }
    public init(folder: String, filename: String, storage: CameraStorage) {
        self.folder = folder; self.filename = filename; self.storage = storage
    }
}

public struct CameraIdentity: Codable, Equatable, Sendable {
    public let model: String
    public let serialNo: String
    public let firmwareVersion: String?
    public init(model: String, serialNo: String, firmwareVersion: String? = nil) {
        self.model = model; self.serialNo = serialNo; self.firmwareVersion = firmwareVersion
    }
    public var key: String { "\(model)|\(serialNo)" }
}

public enum CameraError: LocalizedError {
    case invalidResponse, http(Int), invalidPath, wrongCamera, invalidJPEG, truncatedFile, missingAlbum, permission
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "相机返回的数据无法识别，请检查型号、固件和连接。"
        case .http(let code): return "相机暂时无法完成请求（HTTP \(code)）。"
        case .invalidPath: return "相机返回了无效的照片路径。"
        case .wrongCamera: return "当前连接的相机与任务中的相机不一致，请重新连接原相机。"
        case .invalidJPEG: return "下载的文件不是完整 JPG，未写入照片图库。"
        case .truncatedFile: return "照片没有下载完整，请重试。"
        case .missingAlbum: return "目标相簿不存在或无法访问，请重新选择相簿。"
        case .permission: return "需要照片图库权限才能保存，请在系统设置中允许访问。"
        }
    }
}

public enum CameraProtocol {
    public static let baseURL = URL(string: "http://192.168.0.1/v1")!
    public static func photoURL(_ photo: CameraPhoto, thumbnail: Bool = false, base: URL = baseURL) throws -> URL {
        for component in [photo.folder, photo.filename] {
            guard !component.isEmpty, component != ".", component != "..",
                  !component.contains("/"), !component.contains("\\"), !component.contains("\0") else {
                throw CameraError.invalidPath
            }
        }
        var parts = URLComponents(url: base.appendingPathComponent("photos").appendingPathComponent(photo.folder).appendingPathComponent(photo.filename), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "storage", value: photo.storage.rawValue)]
        if thumbnail { parts.queryItems?.append(URLQueryItem(name: "size", value: "thumb")) }
        guard let url = parts.url else { throw CameraError.invalidPath }
        return url
    }
    public static func parsePhotos(_ data: Data, storage: CameraStorage) throws -> [CameraPhoto] {
        struct Listing: Decodable {
            struct Directory: Decodable { let name: String; let files: [String] }
            let dirs: [Directory]
        }
        let listing = try JSONDecoder().decode(Listing.self, from: data)
        var result = Set<CameraPhoto>()
        for directory in listing.dirs {
            for name in directory.files where ["jpg", "jpeg"].contains((name as NSString).pathExtension.lowercased()) {
                let photo = CameraPhoto(folder: directory.name, filename: name, storage: storage)
                _ = try photoURL(photo)
                result.insert(photo)
            }
        }
        return result.sorted { $0.id.localizedStandardCompare($1.id) == .orderedDescending }
    }
    public static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw CameraError.invalidResponse }
        guard http.statusCode == 200 else { throw CameraError.http(http.statusCode) }
    }
    public static func shouldRetry(_ error: Error) -> Bool {
        if let error = error as? CameraError {
            switch error {
            case .http(let status): return status == 408 || status == 429 || (500...599).contains(status)
            case .truncatedFile, .invalidJPEG: return true
            default: return false
            }
        }
        let error = error as NSError
        return error.domain == NSURLErrorDomain && [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet, NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost].contains(error.code)
    }
}

public enum JobState: String, Codable, Sendable {
    case waiting, downloading, staged, saving, completed, failed
    public var title: String {
        switch self {
        case .waiting: return "等待传输"
        case .downloading: return "正在下载"
        case .staged: return "等待存入相册"
        case .saving: return "正在保存"
        case .completed: return "已保存"
        case .failed: return "需要重试"
        }
    }
}

public struct TransferJob: Codable, Identifiable, Sendable {
    public let id: UUID
    public let camera: CameraIdentity
    public let photo: CameraPhoto
    public let albumID: String?
    public var state: JobState
    public var digest: String?
    public var assetID: String?
    public var error: String?
    public init(camera: CameraIdentity, photo: CameraPhoto, albumID: String?) {
        id = UUID(); self.camera = camera; self.photo = photo; self.albumID = albumID; state = .waiting
    }
}

/// Atomic journal. A PhotoKit placeholder is persisted before committing its transaction,
/// so a process interruption can be reconciled against the photo library on the next run.
public struct TransferJournal {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [TransferJob] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        var jobs = try JSONDecoder().decode([TransferJob].self, from: Data(contentsOf: url))
        for index in jobs.indices where [.downloading, .saving].contains(jobs[index].state) {
            jobs[index].state = .waiting
        }
        return jobs
    }
    public func save(_ jobs: [TransferJob]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(jobs).write(to: url, options: .atomic)
    }
}

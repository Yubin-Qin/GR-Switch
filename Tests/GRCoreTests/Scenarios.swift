import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#if canImport(GRCore)
import GRCore
#endif

enum CheckFailure: Error { case failed(String) }
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw CheckFailure.failed(message) }
}
func expectThrows(_ message: String, _ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw CheckFailure.failed(message)
}
func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("GRChecks-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
func makeJPEG(at url: URL) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    let metadata: [CFString: Any] = [
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "RICOH IMAGING", kCGImagePropertyTIFFModel: "RICOH GR IV"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:07 10:11:12", kCGImagePropertyExifISOSpeedRatings: [400], kCGImagePropertyExifFNumber: 2.8] as [CFString: Any],
        kCGImagePropertyOrientation: 6
    ]
    CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
    try expect(CGImageDestinationFinalize(destination), "Fixture creation")
}

enum CoreScenarios {
    static let tests: [(String, () throws -> Void)] = [
        ("JPG filtering, deduplication and natural order", {
            let bytes = Data(#"{"dirs":[{"name":"100RICOH","files":["R10.JPG","R2.jpg","R10.JPG","R3.DNG","R4.JPEG"]}]}"#.utf8)
            let photos = try CameraProtocol.parsePhotos(bytes, storage: .sd1)
            try expect(photos.map(\.filename) == ["R10.JPG", "R4.JPEG", "R2.jpg"], "Only distinct JPEGs in newest filename order")
        }),
        ("Internal storage and original resolution URL", {
            let photo = CameraPhoto(folder: "100RICOH", filename: "R#1.JPG", storage: .internalMemory)
            let url = try CameraProtocol.photoURL(photo)
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            try expect(components.queryItems == [URLQueryItem(name: "storage", value: "in")], "No size parameter on originals")
            try expect(url.absoluteString.contains("R%231.JPG"), "Filename cannot become a URL fragment")
            let thumb = try CameraProtocol.photoURL(photo, thumbnail: true)
            try expect(thumb.absoluteString.contains("size=thumb"), "Thumbnails explicitly opt in")
        }),
        ("Reject path traversal and malformed directory response", {
            for folder in ["..", ".", "a/b", "a\\b", ""] {
                try expectThrows("Unsafe path accepted") { _ = try CameraProtocol.photoURL(CameraPhoto(folder: folder, filename: "R.JPG", storage: .sd1)) }
            }
            try expectThrows("Camera error mistaken for empty card") { _ = try CameraProtocol.parsePhotos(Data(#"{"errCode":500}"#.utf8), storage: .sd1) }
        }),
        ("Reject redirects, partial HTTP responses and camera errors", {
            for status in [206, 301, 401, 404, 500] {
                let response = HTTPURLResponse(url: CameraProtocol.baseURL, statusCode: status, httpVersion: nil, headerFields: nil)!
                try expectThrows("HTTP \(status) accepted") { try CameraProtocol.validate(response) }
            }
            try CameraProtocol.validate(HTTPURLResponse(url: CameraProtocol.baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }),
        ("Retry only transient failures", {
            try expect(CameraProtocol.shouldRetry(CameraError.http(503)), "503 is transient")
            try expect(!CameraProtocol.shouldRetry(CameraError.http(404)), "404 is permanent")
            try expect(!CameraProtocol.shouldRetry(URLError(.cancelled)), "Cancellation never retries")
            try expect(CameraProtocol.shouldRetry(URLError(.networkConnectionLost)), "Lost link retries")
            try expect(!CameraProtocol.shouldRetry(CameraError.wrongCamera), "Wrong camera never retries")
        }),
        ("Journal recovery retains staged hashes and PhotoKit reservation", {
            let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
            let journal = TransferJournal(url: dir.appendingPathComponent("jobs.json"))
            let camera = CameraIdentity(model: "RICOH GR IV", serialNo: "123")
            var job = TransferJob(camera: camera, photo: CameraPhoto(folder: "100", filename: "R.JPG", storage: .sd1), albumID: "album")
            job.state = .saving; job.digest = "hash"; job.assetID = "pending-asset"
            try journal.save([job]); let recovered = try journal.load()[0]
            try expect(recovered.state == .waiting, "Interrupted operation returns to queue")
            try expect(recovered.assetID == "pending-asset" && recovered.digest == "hash", "Commit can be reconciled")
            try expect(recovered.albumID == "album" && recovered.camera.key == camera.key, "Destination and identity persist")
        }),
        ("Corrupt journal is reported, not overwritten", {
            let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("jobs.json")
            let data = Data("broken JSON".utf8); try data.write(to: url)
            try expectThrows("Corrupt journal accepted") { _ = try JobStore(url: url) }
            try expect(Data(contentsOf: url) == data, "Evidence preserved")
        }),
        ("Journal changes are transactional", {
            let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
            let store = try JobStore(url: dir.appendingPathComponent("jobs.json"))
            try expectThrows("Throwing mutation committed") {
                try store.update { records in
                    records.append(TransferJob(camera: CameraIdentity(model: "GR IV", serialNo: "1"), photo: CameraPhoto(folder: "100", filename: "R.JPG", storage: .sd1), albumID: nil))
                    throw CheckFailure.failed("Simulated persistence failure")
                }
            }
            try expect(store.snapshot().isEmpty, "In-memory state also rolls back")
        }),
        ("Serial journal updates preserve all records", {
            let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
            let store = try JobStore(url: dir.appendingPathComponent("jobs.json"))
            DispatchQueue.concurrentPerform(iterations: 30) { index in
                try! store.update { records in
                    records.append(TransferJob(camera: CameraIdentity(model: "GR IV", serialNo: "1"), photo: CameraPhoto(folder: "100", filename: "R\(index).JPG", storage: .sd1), albumID: nil))
                }
            }
            try expect(store.snapshot().count == 30, "No lost UI/PhotoKit updates")
            try expect(TransferJournal(url: dir.appendingPathComponent("jobs.json")).load().count == 30, "Disk agrees with memory")
        }),
        ("JPEG validation preserves bytes, EXIF, TIFF and orientation", {
            let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("original.jpg"); try makeJPEG(at: file)
            let before = try Data(contentsOf: file)
            let hash1 = try OriginalFile.validateAndHash(file)
            let hash2 = try OriginalFile.validateAndHash(file)
            try expect(hash1 == hash2 && hash1.count == 64, "Stable SHA-256")
            try expect(Data(contentsOf: file) == before, "Original bytes never changed")
            let source = CGImageSourceCreateWithURL(file as CFURL, nil)!
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
            let exif = props[kCGImagePropertyExifDictionary] as! NSDictionary
            try expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:10:07 10:11:12", "Capture time preserved")
            try expect(props[kCGImagePropertyOrientation] as? Int == 6, "Orientation preserved")
        }),
        ("Reject truncated JPEG and a disguised HTML error page", {
            let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("broken.jpg")
            try makeJPEG(at: file); var bytes = try Data(contentsOf: file); bytes.removeLast(10); try bytes.write(to: file)
            try expectThrows("Truncated file accepted") { _ = try OriginalFile.validateAndHash(file) }
            try Data("<html>camera unavailable</html>".utf8).write(to: file)
            try expectThrows("HTML accepted") { _ = try OriginalFile.validateAndHash(file) }
        })
    ]
}

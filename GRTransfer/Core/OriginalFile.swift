import Foundation
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

public enum OriginalFile {
    public static func validateAndHash(_ file: URL) throws -> String {
        // Memory mapping avoids copying a large original into RAM. Validation decodes only
        // a small thumbnail and reads metadata; the source file remains byte-for-byte intact.
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let thumbnailOptions: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                 kCGImageSourceThumbnailMaxPixelSize: 32]
        guard data.count > 4, data.prefix(2) == Data([0xff, 0xd8]), data.suffix(2) == Data([0xff, 0xd9]),
              let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) != nil else { throw CameraError.invalidJPEG }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

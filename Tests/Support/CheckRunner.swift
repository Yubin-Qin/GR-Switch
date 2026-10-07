import Foundation

@main
struct CheckRunner {
    static func main() async throws {
        for (name, test) in CoreScenarios.tests { try test(); print("PASS \(name)") }
        if CommandLine.arguments.count > 1 {
            let port = CommandLine.arguments[1]
            let base = URL(string: "http://127.0.0.1:\(port)/v1")!
            let client = CameraClient(baseURL: base)
            let identity = try await client.identity()
            try expect(identity.serialNo == "TEST-0001", "Camera identity")
            let photos = try await client.photos(storage: .internalMemory)
            try expect(photos.count == 1 && photos[0].storage == .internalMemory, "Storage request")
            let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
            let target = dir.appendingPathComponent("original.jpg")
            _ = try await client.download(photos[0], to: target) { _, _ in }
            let expected = Data([0xff, 0xd8]) + Data("EXIF-preservation-fixture".utf8) + Data([0xff, 0xd9])
            try expect(Data(contentsOf: target) == expected, "Network preserves every source byte")
            print("PASS HTTP identity, internal storage, original URL and exact download bytes")
            for name in ["REDIRECT.JPG", "TRUNCATED.JPG", "ERROR.JPG"] {
                let bad = CameraPhoto(folder: "100RICOH", filename: name, storage: .sd1)
                let destination = dir.appendingPathComponent(name)
                var failed = false
                do { _ = try await client.download(bad, to: destination) { _, _ in } }
                catch { failed = true }
                try expect(failed && !FileManager.default.fileExists(atPath: destination.path), "Bad HTTP download never becomes a staged original: \(name)")
                print("PASS HTTP rejects \(name)")
            }
            let slow = CameraPhoto(folder: "100RICOH", filename: "SLOW.JPG", storage: .sd1)
            let cancelledDestination = dir.appendingPathComponent("cancelled.jpg")
            let task = Task { try await client.download(slow, to: cancelledDestination) { _, _ in } }
            try await Task.sleep(nanoseconds: 150_000_000); task.cancel()
            var cancelled = false
            do { _ = try await task.value } catch { cancelled = true }
            try expect(cancelled && !FileManager.default.fileExists(atPath: cancelledDestination.path), "Cancelled file never staged")
            print("PASS Cancellation stops in-flight network download")
        }
        print("ALL CHECKS PASSED")
    }
}

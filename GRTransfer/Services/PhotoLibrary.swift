import Foundation
import Photos
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

struct PhotoAlbum: Identifiable { let id: String; let title: String }

final class PhotoLibrary: @unchecked Sendable {
    func authorize() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { throw CameraError.permission }
    }
    func albums() -> [PhotoAlbum] {
        var result: [PhotoAlbum] = []
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil).enumerateObjects { album, _, _ in
            if album.canPerform(.addContent) { result.append(PhotoAlbum(id: album.localIdentifier, title: album.localizedTitle ?? "未命名相簿")) }
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func createAlbum(title: String) async throws {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        try await authorize()
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
        }
    }
    func exists(_ id: String) -> Bool { PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).count > 0 }
    func save(file: URL, filename: String, albumID: String?, reserve: @escaping @Sendable (String) throws -> Void) async throws -> String {
        var album: PHAssetCollection?
        if let albumID {
            album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject
            guard let album, album.canPerform(.addContent) else { throw CameraError.missingAlbum }
        }
        // PhotoKit runs this block on its own queue. The journal callback is synchronous:
        // never commit an asset whose identifier hasn't been durably recorded.
        let reservation = AssetReservation()
        let selectedAlbum = album
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            guard let placeholder = request.placeholderForCreatedAsset else { return }
            do { try reserve(placeholder.localIdentifier) }
            catch { reservation.error = error; return }
            reservation.id = placeholder.localIdentifier
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = filename
            options.uniformTypeIdentifier = UTType.jpeg.identifier
            options.shouldMoveFile = false
            request.addResource(with: .photo, fileURL: file, options: options)
            if let selectedAlbum {
                PHAssetCollectionChangeRequest(for: selectedAlbum)?.addAssets([placeholder] as NSArray)
            }
        }
        if let error = reservation.error { throw error }
        guard let id = reservation.id else { throw CameraError.invalidResponse }
        return id
    }
}
private final class AssetReservation: @unchecked Sendable { var id: String?; var error: Error? }

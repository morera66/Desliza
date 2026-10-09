import Foundation
@preconcurrency import Photos

/// Permisos, acceso a los elementos y borrado real.
@MainActor
final class PhotoLibrary: ObservableObject {
    @Published private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var hasAccess: Bool { status == .authorized || status == .limited }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func refreshStatus() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Devuelve los PHAsset en el mismo orden que los ids (los que ya no existen se omiten).
    func assets(for ids: [String]) -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        var byID: [String: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            byID[asset.localIdentifier] = asset
        }
        return ids.compactMap { byID[$0] }
    }

    /// iOS muestra su propio aviso de confirmación. Lo borrado va a "Eliminados recientemente".
    func delete(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }
}

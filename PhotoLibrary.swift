import Foundation
@preconcurrency import Photos

/// Permisos, acceso a los elementos y borrado real.
@MainActor
final class PhotoLibrary: ObservableObject {
    @Published private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    /// Texto de diagnóstico que se muestra en la pantalla de permisos.
    @Published private(set) var lastMessage: String?

    var hasAccess: Bool { status == .authorized || status == .limited }

    /// Versión con callback en vez de async, y dejando rastro en pantalla de cada paso.
    func requestAccess() {
        lastMessage = "Pidiendo acceso… (estado antes: \(Self.describe(status)))"
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { @Sendable [weak self] newStatus in
            Task { @MainActor in
                self?.applyResponse(newStatus)
            }
        }
    }

    private func applyResponse(_ newStatus: PHAuthorizationStatus) {
        status = newStatus
        lastMessage = "Respuesta de iOS: \(Self.describe(newStatus))"
    }

    static func describe(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "sin decidir"
        case .restricted: return "restringido"
        case .denied: return "denegado"
        case .authorized: return "acceso total"
        case .limited: return "acceso limitado"
        @unknown default: return "desconocido (\(status.rawValue))"
        }
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

import Foundation
import UIKit
import CoreGraphics
@preconcurrency import Photos

/// Trabajo pesado (recorrer la fototeca, tamaños, hashes) fuera del hilo principal.
/// Solo entra y sale con tipos simples (String, Int, Int64, Date) para no tener líos de concurrencia.
enum BackgroundWork {

    nonisolated static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }

    // MARK: - Listados

    /// Identificadores ordenados de más nuevo a más antiguo.
    /// mediaType: PHAssetMediaType.rawValue (1 imagen, 2 vídeo) o nil para todo.
    nonisolated static func ids(mediaType: Int?,
                                screenshotsOnly: Bool = false,
                                from: Date? = nil,
                                to: Date? = nil,
                                excluding: Set<String>) -> [String] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var predicates: [NSPredicate] = []
        if let mediaType {
            predicates.append(NSPredicate(format: "mediaType == %d", Int32(mediaType)))
        }
        if screenshotsOnly {
            predicates.append(NSPredicate(format: "(mediaSubtypes & %d) != 0",
                                          Int32(PHAssetMediaSubtype.photoScreenshot.rawValue)))
        }
        if let from {
            predicates.append(NSPredicate(format: "creationDate >= %@", from as NSDate))
        }
        if let to {
            predicates.append(NSPredicate(format: "creationDate < %@", to as NSDate))
        }
        if !predicates.isEmpty {
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        let result = PHAsset.fetchAssets(with: options)
        var ids: [String] = []
        ids.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            if !excluding.contains(asset.localIdentifier) {
                ids.append(asset.localIdentifier)
            }
        }
        return ids
    }

    /// Fotos y vídeos de tal día como hoy en años anteriores.
    nonisolated static func onThisDayIDs(excluding: Set<String>) -> [String] {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.year, .month, .day], from: Date())
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var ids: [String] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate, !excluding.contains(asset.localIdentifier) else { return }
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            if c.month == today.month && c.day == today.day && c.year != today.year {
                ids.append(asset.localIdentifier)
            }
        }
        return ids
    }

    /// Pendientes por categoría para la pantalla de inicio (una sola pasada por la fototeca).
    nonisolated static func homeCounts(excluding: Set<String>) -> [String: Int] {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.year, .month, .day], from: Date())
        var recent = 0, videos = 0, screenshots = 0, onThisDay = 0

        PHAsset.fetchAssets(with: PHFetchOptions()).enumerateObjects { asset, _, _ in
            guard !excluding.contains(asset.localIdentifier) else { return }
            recent += 1
            if asset.mediaType == .video { videos += 1 }
            if asset.mediaSubtypes.contains(.photoScreenshot) { screenshots += 1 }
            if let date = asset.creationDate {
                let c = calendar.dateComponents([.year, .month, .day], from: date)
                if c.month == today.month && c.day == today.day && c.year != today.year {
                    onThisDay += 1
                }
            }
        }
        return ["recent": recent, "videos": videos, "screenshots": screenshots, "onThisDay": onThisDay]
    }

    /// "2025-03" -> [total, pendientes]
    nonisolated static func monthCounts(excluding: Set<String>) -> [String: [Int]] {
        let calendar = Calendar.current
        var counts: [String: [Int]] = [:]
        PHAsset.fetchAssets(with: PHFetchOptions()).enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            let c = calendar.dateComponents([.year, .month], from: date)
            let key = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
            var entry = counts[key] ?? [0, 0]
            entry[0] += 1
            if !excluding.contains(asset.localIdentifier) { entry[1] += 1 }
            counts[key] = entry
        }
        return counts
    }

    // MARK: - Tamaños

    nonisolated static func sizes(for ids: [String]) -> [String: Int64] {
        guard !ids.isEmpty else { return [:] }
        var sizes: [String: Int64] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            sizes[asset.localIdentifier] = fileSize(of: asset)
        }
        return sizes
    }

    /// Suma todos los recursos del elemento (original, vídeo del Live Photo, ediciones...).
    nonisolated static func fileSize(of asset: PHAsset) -> Int64 {
        var total: Int64 = 0
        for resource in PHAssetResource.assetResources(for: asset) {
            if let size = resource.value(forKey: "fileSize") as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }

    // MARK: - Duplicados

    /// Clave por foto: dimensiones + hash perceptual (dHash 64 bits).
    /// Dos fotos con la misma clave son copias o casi idénticas.
    nonisolated static func duplicateKeys(for ids: [String]) -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false // las que solo están en iCloud se saltan

        var keys: [String: String] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            var cgImage: CGImage?
            manager.requestImage(for: asset,
                                 targetSize: CGSize(width: 64, height: 64),
                                 contentMode: .aspectFill,
                                 options: options) { image, _ in
                cgImage = image?.cgImage
            }
            if let cgImage, let hash = dHash(cgImage) {
                keys[asset.localIdentifier] = "\(asset.pixelWidth)x\(asset.pixelHeight)-\(String(hash, radix: 16))"
            }
        }
        return keys
    }

    /// Reduce a 9x8 en grises y compara cada píxel con el de su derecha.
    nonisolated static func dHash(_ image: CGImage) -> UInt64? {
        let width = 9, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)

        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var hash: UInt64 = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                hash <<= 1
                if pixels[y * width + x] > pixels[y * width + x + 1] {
                    hash |= 1
                }
            }
        }
        return hash
    }
}

import Foundation
@preconcurrency import Photos

/// Cola de elementos de una categoría y lo que se ha hecho con ellos.
@MainActor
final class SwipeSession: ObservableObject {
    let category: CleanCategory

    @Published private(set) var ids: [String] = []
    @Published private(set) var index = 0
    @Published private(set) var isLoading = true
    @Published private(set) var progress: Double?
    @Published private(set) var sizes: [String: Int64] = [:]
    @Published private(set) var sessionTrashCount = 0
    @Published private(set) var sessionTrashBytes: Int64 = 0
    @Published private(set) var history: [SwipeAction] = []

    private var hasLoaded = false
    private var assetCache: [String: PHAsset] = [:]

    init(category: CleanCategory) {
        self.category = category
    }

    var currentID: String? { index < ids.count ? ids[index] : nil }
    var nextID: String? { index + 1 < ids.count ? ids[index + 1] : nil }
    var remaining: Int { max(ids.count - index, 0) }
    var canUndo: Bool { !history.isEmpty }

    func asset(_ id: String) -> PHAsset? {
        if let cached = assetCache[id] { return cached }
        let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
        if let asset { assetCache[id] = asset }
        return asset
    }

    // MARK: - Carga

    func loadIfNeeded(store: CleanStore) async {
        guard !hasLoaded else { return }
        await load(store: store)
    }

    func load(store: CleanStore) async {
        hasLoaded = true
        isLoading = true
        let excluding = store.reviewedIDs
        let imageType = PHAssetMediaType.image.rawValue
        let videoType = PHAssetMediaType.video.rawValue
        var result: [String] = []

        switch category {
        case .recent:
            result = await BackgroundWork.run { BackgroundWork.ids(mediaType: nil, excluding: excluding) }

        case .random:
            let all = await BackgroundWork.run { BackgroundWork.ids(mediaType: nil, excluding: excluding) }
            result = Array(all.shuffled().prefix(30))

        case .onThisDay:
            result = await BackgroundWork.run { BackgroundWork.onThisDayIDs(excluding: excluding) }

        case .screenshots:
            result = await BackgroundWork.run {
                BackgroundWork.ids(mediaType: imageType, screenshotsOnly: true, excluding: excluding)
            }

        case .videos:
            result = await BackgroundWork.run { BackgroundWork.ids(mediaType: videoType, excluding: excluding) }

        case .largeVideos:
            let videoIDs = await BackgroundWork.run { BackgroundWork.ids(mediaType: videoType, excluding: excluding) }
            var all: [String: Int64] = [:]
            progress = 0
            var start = 0
            while start < videoIDs.count {
                let slice = Array(videoIDs[start..<min(start + 100, videoIDs.count)])
                let found = await BackgroundWork.run { BackgroundWork.sizes(for: slice) }
                all.merge(found) { old, _ in old }
                start += 100
                progress = Double(min(start, videoIDs.count)) / Double(videoIDs.count)
            }
            sizes.merge(all) { old, _ in old }
            result = videoIDs.sorted { (all[$0] ?? 0) > (all[$1] ?? 0) }
            progress = nil

        case .month(let year, let month):
            let calendar = Calendar.current
            if let from = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
               let to = calendar.date(byAdding: .month, value: 1, to: from) {
                result = await BackgroundWork.run {
                    BackgroundWork.ids(mediaType: nil, from: from, to: to, excluding: excluding)
                }
            }
        }

        ids = result
        index = 0
        history = []
        isLoading = false
        await prefetchSizes()
    }

    /// Calcula el tamaño de la actual y las siguientes 5.
    private func prefetchSizes() async {
        guard index < ids.count else { return }
        let window = ids[index..<min(index + 6, ids.count)].filter { sizes[$0] == nil }
        guard !window.isEmpty else { return }
        let pending = Array(window)
        let found = await BackgroundWork.run { BackgroundWork.sizes(for: pending) }
        sizes.merge(found) { old, _ in old }
    }

    // MARK: - Acciones

    func swipe(keep: Bool, store: CleanStore) {
        guard let id = currentID else { return }
        if keep {
            store.keep(id)
            history.append(.keep(id))
        } else {
            store.trash(id)
            history.append(.trash(id))
            sessionTrashCount += 1
            sessionTrashBytes += sizes[id] ?? 0
        }
        index += 1
        Task { await prefetchSizes() }
    }

    func undo(store: CleanStore) {
        guard let last = history.popLast() else { return }
        store.undo(last)
        if case .trash(let id) = last {
            sessionTrashCount -= 1
            sessionTrashBytes -= sizes[id] ?? 0
        }
        index = max(index - 1, 0)
    }

    /// Para elementos que se borraron fuera de la app mientras tanto.
    func skip() {
        index += 1
        Task { await prefetchSizes() }
    }
}

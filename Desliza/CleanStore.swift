import Foundation

/// Guarda el progreso: lo conservado no vuelve a salir, así se limpia poco a poco.
@MainActor
final class CleanStore: ObservableObject {
    @Published private(set) var keptIDs: Set<String> = []
    @Published private(set) var trashIDs: [String] = []
    @Published private(set) var freedBytes: Int64 = 0
    @Published private(set) var deletedCount = 0
    @Published private(set) var ignoredDuplicateKeys: Set<String> = []

    private var trashSet: Set<String> = []
    private var saveTask: Task<Void, Never>?

    private struct SavedState: Codable {
        var kept: [String]
        var trash: [String]
        var freedBytes: Int64
        var deletedCount: Int
        var ignoredDuplicates: [String]
    }

    private static var fileURL: URL {
        URL.documentsDirectory.appending(path: "estado-limpieza.json")
    }

    init() {
        load()
    }

    /// Todo lo ya revisado (conservado o en la papelera).
    var reviewedIDs: Set<String> { keptIDs.union(trashSet) }
    var trashIDSet: Set<String> { trashSet }

    // MARK: - Acciones

    func keep(_ id: String) {
        keptIDs.insert(id)
        scheduleSave()
    }

    func trash(_ id: String) {
        guard trashSet.insert(id).inserted else { return }
        keptIDs.remove(id)
        trashIDs.append(id)
        scheduleSave()
    }

    func undo(_ action: SwipeAction) {
        switch action {
        case .keep(let id):
            keptIDs.remove(id)
        case .trash(let id):
            trashSet.remove(id)
            trashIDs.removeAll { $0 == id }
        }
        scheduleSave()
    }

    /// Sacar de la papelera = conservar.
    func restoreFromTrash(_ id: String) {
        trashSet.remove(id)
        trashIDs.removeAll { $0 == id }
        keptIDs.insert(id)
        scheduleSave()
    }

    /// Quita de la papelera lo que ya no existe (borrado desde la app Fotos, por ejemplo).
    func pruneTrash(existing: Set<String>) {
        let before = trashIDs.count
        trashIDs.removeAll { !existing.contains($0) }
        trashSet = Set(trashIDs)
        if trashIDs.count != before { scheduleSave() }
    }

    func registerDeleted(ids: [String], bytes: Int64) {
        let deleted = Set(ids)
        trashIDs.removeAll { deleted.contains($0) }
        trashSet.subtract(deleted)
        keptIDs.subtract(deleted)
        freedBytes += bytes
        deletedCount += ids.count
        scheduleSave()
    }

    func ignoreDuplicateGroup(_ key: String) {
        ignoredDuplicateKeys.insert(key)
        scheduleSave()
    }

    func resetKept() {
        keptIDs.removeAll()
        ignoredDuplicateKeys.removeAll()
        scheduleSave()
    }

    // MARK: - Guardado

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        let state = SavedState(kept: Array(keptIDs),
                               trash: trashIDs,
                               freedBytes: freedBytes,
                               deletedCount: deletedCount,
                               ignoredDuplicates: Array(ignoredDuplicateKeys))
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("Error guardando el estado: \(error)")
        }
    }

    /// Espera 1 s para no escribir el archivo en cada deslizamiento.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        keptIDs = Set(state.kept)
        trashIDs = state.trash
        trashSet = Set(state.trash)
        freedBytes = state.freedBytes
        deletedCount = state.deletedCount
        ignoredDuplicateKeys = Set(state.ignoredDuplicates)
    }
}

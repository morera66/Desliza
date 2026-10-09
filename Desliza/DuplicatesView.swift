import SwiftUI
@preconcurrency import Photos

struct DuplicateGroup: Identifiable {
    let id: String          // clave del grupo (dimensiones + hash)
    var assetIDs: [String]  // de la más antigua a la más reciente
}

@MainActor
final class DuplicateScanner: ObservableObject {
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published private(set) var progress: Double = 0
    @Published private(set) var isScanning = false
    @Published private(set) var hasScanned = false

    func scan(excluding: Set<String>, ignored: Set<String>) async {
        guard !isScanning else { return }
        isScanning = true
        progress = 0

        let imageType = PHAssetMediaType.image.rawValue
        let allIDs = await BackgroundWork.run { BackgroundWork.ids(mediaType: imageType, excluding: excluding) }

        var position: [String: Int] = [:]
        for (i, id) in allIDs.enumerated() { position[id] = i }

        var byKey: [String: [String]] = [:]
        var start = 0
        while start < allIDs.count {
            let slice = Array(allIDs[start..<min(start + 200, allIDs.count)])
            let keys = await BackgroundWork.run { BackgroundWork.duplicateKeys(for: slice) }
            for (id, key) in keys {
                byKey[key, default: []].append(id)
            }
            start += 200
            progress = Double(min(start, allIDs.count)) / Double(allIDs.count)
        }

        // allIDs va de nueva a antigua: posición mayor = más antigua, que va primero (es la que se conserva)
        groups = byKey
            .filter { $0.value.count > 1 && !ignored.contains($0.key) }
            .map { entry in
                DuplicateGroup(id: entry.key,
                               assetIDs: entry.value.sorted { (position[$0] ?? 0) > (position[$1] ?? 0) })
            }
            .sorted { $0.assetIDs.count > $1.assetIDs.count }

        isScanning = false
        hasScanned = true
    }

    func dropGroup(_ id: String) {
        groups.removeAll { $0.id == id }
    }
}

struct DuplicatesView: View {
    @EnvironmentObject private var store: CleanStore
    @StateObject private var scanner = DuplicateScanner()
    @State private var selected: Set<String> = []

    var body: some View {
        Group {
            if scanner.isScanning {
                VStack(spacing: 16) {
                    ProgressView(value: scanner.progress)
                    Text("Analizando fotos… \(Int(scanner.progress * 100)) %")
                    Text("Con muchas fotos puede tardar unos minutos. Deja la app abierta.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
            } else if !scanner.hasScanned {
                VStack(spacing: 16) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Busca fotos repetidas o casi idénticas: copias de WhatsApp, ráfagas, capturas repetidas…")
                        .multilineTextAlignment(.center)
                    Button("Buscar duplicados") { Task { await startScan() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(32)
            } else if scanner.groups.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("No hay duplicados pendientes")
                        .font(.headline)
                    Button("Volver a buscar") { Task { await startScan() } }
                }
                .padding(32)
            } else {
                List {
                    Section {
                        Button("Mover todas las marcadas a la papelera (\(selected.count))") {
                            for group in scanner.groups { move(group) }
                        }
                        .disabled(selected.isEmpty)
                    } footer: {
                        Text("En cada grupo se conserva la más antigua (✓ verde). Toca una foto para cambiar su marca.")
                    }

                    ForEach(scanner.groups) { group in
                        Section("\(group.assetIDs.count) fotos iguales") {
                            DuplicateGroupRow(ids: group.assetIDs, selected: $selected)
                            HStack {
                                let count = group.assetIDs.filter { selected.contains($0) }.count
                                Button("Mover \(count) a la papelera") { move(group) }
                                    .disabled(count == 0)
                                Spacer()
                                Button("Ignorar") { ignore(group) }
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .navigationTitle("Duplicados")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { TrashToolbarButton() }
        }
    }

    private func startScan() async {
        await scanner.scan(excluding: store.trashIDSet, ignored: store.ignoredDuplicateKeys)
        selected = Set(scanner.groups.flatMap { $0.assetIDs.dropFirst() })
    }

    private func move(_ group: DuplicateGroup) {
        let toTrash = group.assetIDs.filter { selected.contains($0) }
        guard !toTrash.isEmpty else { return }
        toTrash.forEach { store.trash($0) }
        selected.subtract(toTrash)
        // Si quedan 2 o más es que quieres conservarlas: no volver a mostrar este grupo
        if group.assetIDs.count - toTrash.count >= 2 {
            store.ignoreDuplicateGroup(group.id)
        }
        scanner.dropGroup(group.id)
    }

    private func ignore(_ group: DuplicateGroup) {
        store.ignoreDuplicateGroup(group.id)
        selected.subtract(group.assetIDs)
        scanner.dropGroup(group.id)
    }
}

struct DuplicateGroupRow: View {
    let ids: [String]
    @Binding var selected: Set<String>
    @EnvironmentObject private var library: PhotoLibrary
    @State private var assets: [PHAsset] = []

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    let isSelected = selected.contains(asset.localIdentifier)
                    AssetImageView(asset: asset, targetSize: CGSize(width: 110, height: 110))
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .opacity(isSelected ? 0.55 : 1)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: isSelected ? "trash.circle.fill" : "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white, isSelected ? Color.red : Color.green)
                                .padding(4)
                        }
                        .onTapGesture {
                            if isSelected {
                                selected.remove(asset.localIdentifier)
                            } else {
                                selected.insert(asset.localIdentifier)
                            }
                        }
                }
            }
            .padding(.vertical, 4)
        }
        .task(id: ids) {
            assets = library.assets(for: ids)
        }
    }
}

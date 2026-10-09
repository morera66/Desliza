import SwiftUI
@preconcurrency import Photos

/// Revisión final antes del borrado real.
struct TrashView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var store: CleanStore

    @State private var assets: [PHAsset] = []
    @State private var sizes: [String: Int64] = [:]
    @State private var isLoading = true
    @State private var isDeleting = false
    @State private var showDoneAlert = false
    @State private var lastFreed: Int64 = 0
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    private var totalBytes: Int64 {
        assets.reduce(0) { $0 + (sizes[$1.localIdentifier] ?? 0) }
    }

    var body: some View {
        Group {
            if assets.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("La papelera está vacía")
                        .font(.headline)
                    Text("Desliza fotos a la izquierda para mandarlas aquí.")
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ScrollView {
                    Text("Toca una foto para sacarla de la papelera (se conserva).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(AssetImageView(asset: asset, targetSize: CGSize(width: 120, height: 120)))
                                .clipped()
                                .overlay(alignment: .bottomTrailing) {
                                    if asset.mediaType == .video {
                                        Image(systemName: "video.fill")
                                            .font(.caption)
                                            .foregroundStyle(.white)
                                            .padding(4)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { restore(asset) }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button(role: .destructive) {
                        Task { await deleteAll() }
                    } label: {
                        Text(isDeleting ? "Borrando…" : "Borrar \(assets.count) · \(formatBytes(totalBytes))")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isDeleting || assets.isEmpty)
                    .padding()
                    .background(.bar)
                }
            }
        }
        .navigationTitle("Papelera")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .alert("Espacio liberado", isPresented: $showDoneAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Has liberado aprox. \(formatBytes(lastFreed)). iOS guarda lo borrado 30 días en «Eliminados recientemente»: vacía ese álbum en la app Fotos para recuperar el espacio ya.")
        }
        .alert("No se pudo borrar", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reload() async {
        isLoading = true
        let ids = store.trashIDs
        let found = library.assets(for: ids)
        store.pruneTrash(existing: Set(found.map(\.localIdentifier)))
        assets = found
        let missing = found.map(\.localIdentifier).filter { sizes[$0] == nil }
        let result = await BackgroundWork.run { BackgroundWork.sizes(for: missing) }
        sizes.merge(result) { old, _ in old }
        isLoading = false
    }

    private func restore(_ asset: PHAsset) {
        store.restoreFromTrash(asset.localIdentifier)
        assets.removeAll { $0.localIdentifier == asset.localIdentifier }
    }

    private func deleteAll() async {
        isDeleting = true
        defer { isDeleting = false }
        let toDelete = assets
        let bytes = totalBytes
        do {
            try await library.delete(toDelete)
            store.registerDeleted(ids: toDelete.map(\.localIdentifier), bytes: bytes)
            assets = []
            lastFreed = bytes
            showDoneAlert = true
        } catch {
            // 3072 = el usuario ha pulsado "No permitir" en el aviso de iOS
            if (error as NSError).code != 3072 {
                errorMessage = error.localizedDescription
            }
        }
    }
}

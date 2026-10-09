import SwiftUI
import AVKit
@preconcurrency import Photos

/// Miniatura o imagen de un elemento de la fototeca.
struct AssetImageView: View {
    let asset: PHAsset
    let targetSize: CGSize
    var contentMode: ContentMode = .fill

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Color.gray.opacity(0.2))
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear { load() }
        .onDisappear { cancel() }
    }

    private func load() {
        guard image == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let size = CGSize(width: max(targetSize.width, 100) * displayScale,
                          height: max(targetSize.height, 100) * displayScale)
        requestID = PHImageManager.default().requestImage(for: asset,
                                                          targetSize: size,
                                                          contentMode: .aspectFill,
                                                          options: options) { result, _ in
            guard let result else { return }
            DispatchQueue.main.async { image = result }
        }
    }

    private func cancel() {
        if let requestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        requestID = nil
    }
}

/// Tarjeta que se desliza.
struct CardView: View {
    let asset: PHAsset
    let bytes: Int64?

    var body: some View {
        GeometryReader { geo in
            AssetImageView(asset: asset, targetSize: geo.size, contentMode: .fit)
                .background(Color.black)
                .overlay(alignment: .bottom) {
                    HStack(spacing: 10) {
                        if asset.mediaType == .video {
                            Label(durationText, systemImage: "play.fill")
                        }
                        if let date = asset.creationDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                        }
                        Spacer()
                        Text(bytes.map(formatBytes) ?? "…")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
    }

    private var durationText: String {
        let seconds = Int(asset.duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Vista a pantalla completa (tocar la tarjeta). Reproduce los vídeos.
struct AssetDetailView: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if asset.mediaType == .video {
                    if let player {
                        VideoPlayer(player: player)
                    } else {
                        ProgressView().tint(.white)
                    }
                } else {
                    GeometryReader { geo in
                        AssetImageView(asset: asset, targetSize: geo.size, contentMode: .fit)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .onAppear { loadVideo() }
            .onDisappear { player?.pause() }
        }
    }

    private func loadVideo() {
        guard asset.mediaType == .video, player == nil else { return }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            guard let item else { return }
            DispatchQueue.main.async {
                let newPlayer = AVPlayer(playerItem: item)
                player = newPlayer
                newPlayer.play()
            }
        }
    }
}

/// Botón de papelera con contador para la barra superior.
struct TrashToolbarButton: View {
    @EnvironmentObject private var store: CleanStore

    var body: some View {
        NavigationLink {
            TrashView()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                if !store.trashIDs.isEmpty {
                    Text("\(store.trashIDs.count)").monospacedDigit()
                }
            }
        }
    }
}

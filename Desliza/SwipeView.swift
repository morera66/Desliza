import SwiftUI
@preconcurrency import Photos

/// Pantalla principal de limpieza: izquierda borrar, derecha conservar.
struct SwipeView: View {
    @EnvironmentObject private var store: CleanStore
    @StateObject private var session: SwipeSession

    @State private var offset: CGSize = .zero
    @State private var isAnimatingOut = false
    @State private var showDetail = false

    init(category: CleanCategory) {
        _session = StateObject(wrappedValue: SwipeSession(category: category))
    }

    var body: some View {
        VStack(spacing: 16) {
            if session.isLoading {
                Spacer()
                if let progress = session.progress {
                    ProgressView(value: progress) {
                        Text("Calculando tamaños… \(Int(progress * 100)) %")
                    }
                    .padding(.horizontal, 40)
                } else {
                    ProgressView("Cargando…")
                }
                Spacer()
            } else if let id = session.currentID {
                if let asset = session.asset(id) {
                    header
                    cardStack(current: asset, id: id)
                    controls
                } else {
                    Spacer()
                    Text("Este elemento ya no existe.")
                    Button("Saltar") { session.skip() }
                    Spacer()
                }
            } else {
                finished
            }
        }
        .padding()
        .navigationTitle(session.category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { TrashToolbarButton() }
        }
        .task { await session.loadIfNeeded(store: store) }
        .sheet(isPresented: $showDetail) {
            if let id = session.currentID, let asset = session.asset(id) {
                AssetDetailView(asset: asset)
            }
        }
    }

    // MARK: - Partes

    private var header: some View {
        HStack {
            Text("\(session.remaining) pendientes")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if session.sessionTrashCount > 0 {
                Label("\(session.sessionTrashCount) · \(formatBytes(session.sessionTrashBytes))", systemImage: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    private func cardStack(current: PHAsset, id: String) -> some View {
        ZStack {
            if let nextID = session.nextID, let next = session.asset(nextID) {
                CardView(asset: next, bytes: session.sizes[nextID])
                    .id(nextID)
                    .scaleEffect(0.94)
                    .opacity(0.8)
            }
            CardView(asset: current, bytes: session.sizes[id])
                .id(id)
                .overlay(alignment: .topLeading) {
                    stamp("CONSERVAR", color: .green)
                        .opacity(Double(max(0, offset.width) / 100))
                }
                .overlay(alignment: .topTrailing) {
                    stamp("BORRAR", color: .red)
                        .opacity(Double(max(0, -offset.width) / 100))
                }
                .offset(x: offset.width, y: offset.height * 0.2)
                .rotationEffect(.degrees(Double(offset.width) / 25))
                .gesture(dragGesture)
                .onTapGesture { showDetail = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.title2.weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 3))
            .padding(24)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            roundButton("trash.fill", color: .red, size: 64) { animateOut(keep: false) }
            roundButton("arrow.uturn.backward", color: .gray, size: 48) { session.undo(store: store) }
                .disabled(!session.canUndo)
                .opacity(session.canUndo ? 1 : 0.4)
            roundButton("checkmark", color: .green, size: 64) { animateOut(keep: true) }
        }
    }

    private func roundButton(_ icon: String, color: Color, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(Circle().fill(Color(.secondarySystemBackground)))
        }
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text(session.ids.isEmpty ? "No queda nada por revisar aquí" : "¡Categoría revisada!")
                .font(.title3.bold())
            if session.sessionTrashCount > 0 {
                Text("Has mandado \(session.sessionTrashCount) a la papelera (\(formatBytes(session.sessionTrashBytes))). Bórralas desde la papelera para liberar el espacio.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            if session.category.isRandom {
                Button("Otra tanda") {
                    Task { await session.load(store: store) }
                }
                .buttonStyle(.borderedProminent)
            }
            NavigationLink {
                TrashView()
            } label: {
                Label("Ir a la papelera", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            if session.canUndo {
                Button("Deshacer la última") { session.undo(store: store) }
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Gestos

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isAnimatingOut else { return }
                offset = value.translation
            }
            .onEnded { value in
                guard !isAnimatingOut else { return }
                let width = value.translation.width
                let predicted = value.predictedEndTranslation.width
                if width > 110 || predicted > 300 {
                    animateOut(keep: true)
                } else if width < -110 || predicted < -300 {
                    animateOut(keep: false)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = .zero }
                }
            }
    }

    private func animateOut(keep: Bool) {
        guard !isAnimatingOut, session.currentID != nil else { return }
        isAnimatingOut = true
        withAnimation(.easeOut(duration: 0.2)) {
            offset = CGSize(width: keep ? 700 : -700, height: offset.height)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            session.swipe(keep: keep, store: store)
            offset = .zero
            isAnimatingOut = false
        }
    }
}

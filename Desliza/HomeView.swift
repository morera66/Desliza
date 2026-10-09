import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: CleanStore
    @State private var counts: [String: Int] = [:]
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        stat(formatBytes(store.freedBytes), "liberados")
                        Divider()
                        stat("\(store.deletedCount)", "borradas")
                        Divider()
                        stat("\(store.keptIDs.count)", "conservadas")
                    }
                    .padding(.vertical, 6)

                    if !store.trashIDs.isEmpty {
                        NavigationLink {
                            TrashView()
                        } label: {
                            Label("\(store.trashIDs.count) en la papelera esperando a borrarse", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Deslizar") {
                    row(.recent, count: counts["recent"])
                    row(.random, count: nil)
                    row(.onThisDay, count: counts["onThisDay"])
                    row(.screenshots, count: counts["screenshots"])
                    row(.videos, count: counts["videos"])
                    NavigationLink {
                        MonthsView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Por mes")
                                Text("Mes a mes, para ir terminando bloques")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "calendar")
                        }
                    }
                }

                Section("Liberar mucho espacio") {
                    row(.largeVideos, count: nil)
                    NavigationLink {
                        DuplicatesView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Duplicados y casi idénticas")
                                Text("Copias y ráfagas repetidas")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "square.on.square")
                        }
                    }
                }

                Section {
                    Button("Volver a revisar las conservadas", role: .destructive) {
                        showResetConfirm = true
                    }
                } footer: {
                    Text("Lo que conservas no vuelve a salir, así puedes limpiar poco a poco sin repetir.")
                }
            }
            .navigationTitle("Desliza")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { TrashToolbarButton() }
            }
            .task { await refreshCounts() }
            .refreshable { await refreshCounts() }
            .confirmationDialog("¿Volver a mostrar todas las fotos que marcaste para conservar?",
                                isPresented: $showResetConfirm,
                                titleVisibility: .visible) {
                Button("Sí, empezar de nuevo", role: .destructive) {
                    store.resetKept()
                    Task { await refreshCounts() }
                }
            }
        }
    }

    private func refreshCounts() async {
        let excluding = store.reviewedIDs
        counts = await BackgroundWork.run { BackgroundWork.homeCounts(excluding: excluding) }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ category: CleanCategory, count: Int?) -> some View {
        NavigationLink {
            SwipeView(category: category)
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading) {
                        Text(category.title)
                        Text(category.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: category.systemImage)
                }
                Spacer()
                if let count {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}

struct MonthsView: View {
    @EnvironmentObject private var store: CleanStore
    @State private var months: [MonthInfo] = []
    @State private var isLoading = true

    struct MonthInfo: Identifiable {
        let id: String
        let year: Int
        let month: Int
        let total: Int
        let remaining: Int
    }

    var body: some View {
        List(months) { info in
            NavigationLink {
                SwipeView(category: .month(year: info.year, month: info.month))
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(monthTitle(year: info.year, month: info.month))
                        Text("\(info.total) elementos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if info.remaining == 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("\(info.remaining) pendientes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if isLoading && months.isEmpty { ProgressView() }
        }
        .navigationTitle("Por mes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { TrashToolbarButton() }
        }
        .task { await load() }
    }

    private func load() async {
        let excluding = store.reviewedIDs
        let raw = await BackgroundWork.run { BackgroundWork.monthCounts(excluding: excluding) }
        months = raw.compactMap { entry -> MonthInfo? in
            let parts = entry.key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2, entry.value.count == 2, parts[0] > 0 else { return nil }
            return MonthInfo(id: entry.key, year: parts[0], month: parts[1],
                             total: entry.value[0], remaining: entry.value[1])
        }
        .sorted { $0.id > $1.id }
        isLoading = false
    }
}

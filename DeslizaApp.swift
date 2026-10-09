import SwiftUI

@main
struct DeslizaApp: App {
    @StateObject private var library = PhotoLibrary()
    @StateObject private var store = CleanStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(store)
        }
    }
}

/// Decide si mostrar la pantalla de permisos o la app.
struct RootView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @EnvironmentObject private var store: CleanStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if library.hasAccess {
                HomeView()
            } else {
                AccessView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                library.refreshStatus()
            } else if phase == .background {
                store.saveNow()
            }
        }
    }
}

struct AccessView: View {
    @EnvironmentObject private var library: PhotoLibrary

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text("Desliza")
                .font(.largeTitle.bold())
            Text("Revisa tus fotos deslizando: izquierda para borrar, derecha para conservar. Para eso necesito acceso a tu fototeca.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if library.status == .denied || library.status == .restricted {
                Text("El acceso está denegado. Actívalo en Ajustes > Desliza > Fotos > Acceso total.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Dar acceso a Fotos") {
                    library.requestAccess()
                }
                .buttonStyle(.borderedProminent)
            }

            // Diagnóstico: qué ha respondido iOS al pedir el permiso
            if let message = library.lastMessage {
                Text(message)
                    .font(.footnote.monospaced())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
    }
}

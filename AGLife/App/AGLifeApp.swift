import SwiftUI

@main
struct AGLifeApp: App {
    @StateObject private var store = LifeStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if store.isReady {
                    RootView()
                } else {
                    ContentUnavailableView {
                        Label("Archivio non disponibile", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("I dati originali sono conservati. Riprova ad aprirli prima di proseguire.")
                    } actions: {
                        Button("Riprova") { store.reload() }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .environmentObject(store)
            .tint(.teal)
            .safeAreaInset(edge: .top) { SaveErrorBanner().environmentObject(store) }
        }
    }
}

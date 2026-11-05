import EventKit
import SwiftUI

@main
struct AGLifeApp: App {
    @StateObject private var store = LifeStore()
    @StateObject private var notifications = NotificationService()
    @StateObject private var appleReminders = AppleReminders()
    @Environment(\.scenePhase) private var scenePhase

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
            .environmentObject(notifications)
            .environmentObject(appleReminders)
            .tint(.teal)
            .safeAreaInset(edge: .top) {
                SaveErrorBanner().environmentObject(store).environmentObject(notifications)
            }
            .onChange(of: store.data.appointments, initial: true) { _, appointments in
                if store.isReady { notifications.synchronize(appointments) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, store.isReady {
                    notifications.synchronize(store.data.appointments)
                    appleReminders.synchronize(store)
                }
            }
            .onChange(of: store.isReady, initial: true) { _, ready in
                if ready { appleReminders.synchronize(store) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged).receive(on: RunLoop.main)) { _ in
                if scenePhase == .active { appleReminders.synchronize(store) }
            }
        }
    }
}

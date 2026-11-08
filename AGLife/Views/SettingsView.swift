import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LifeStore
    @EnvironmentObject private var notifications: NotificationService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AppleListRecoveryView()
                    LifeHeading(title: "Un promemoria, al momento giusto.", subtitle: "Verifica le notifiche sul tuo iPhone.", area: .calendar, symbol: "bell.badge")
                    LifeCard(area: .calendar) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Permesso: \(notifications.authorization)").font(.headline)
                            Text(notifications.isSyncing ? "Verifica richieste in corso…" : "Promemoria in attesa confermati: \(notifications.pendingCount)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("Il test richiede il permesso iOS per mostrare avvisi locali e suoni. Non usa server o notifiche push.")
                                .font(.footnote).foregroundStyle(.secondary)
                            LifePrimaryButton(title: notifications.isTesting ? "Preparazione…" : "Invia notifica di prova",
                                symbol: "bell", area: .calendar, enabled: !notifications.isTesting) {
                                Task {
                                    await notifications.sendTest()
                                    notifications.synchronize(store.data.appointments)
                                }
                            }
                            if let message = notifications.testResult {
                                Text(message).font(.subheadline).accessibilityLabel("Esito del test: " + message)
                            }
                            Button("Ricontrolla permessi e promemoria") { notifications.synchronize(store.data.appointments) }
                                .frame(minHeight: 44)
                        }
                    }
                    LifeCard(area: .calendar) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Provalo in tre situazioni").font(.headline)
                            Text("1. Invia il test e resta in AG Life per circa 10 secondi.\n2. Ripeti il test e porta LiveContainer in background.\n3. Ripeti ancora e blocca l’iPhone.")
                            Text("L’accettazione della richiesta da iOS non garantisce la consegna. Controlla anche Full immersion, riepilogo notifiche e permessi dell’host nelle impostazioni iOS.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text("In LiveContainer, apri le impostazioni specifiche di AG Life e valuta “Fix Local Notification” (il nome può variare). Riapri l’app e ripeti il test. Se non funziona, non fare affidamento sui promemoria.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Link("Guida ufficiale LiveContainer", destination: URL(string: "https://github.com/LiveContainer/LiveContainer#fix-file-picker--local-notification")!)
                        }
                    }
                }.padding(20)
            }
            .background(LifeBackdrop(area: .calendar)).tint(LifeArea.calendar.accent)
            .navigationTitle("Impostazioni").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { SaveErrorBanner() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
            .task { notifications.synchronize(store.data.appointments) }
        }
    }
}

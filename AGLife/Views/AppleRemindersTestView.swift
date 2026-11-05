import EventKit
import SwiftUI

struct AppleRemindersTestView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization = EKEventStore.authorizationStatus(for: .reminder)
    @State private var requesting = false
    @State private var testIdentifier: String?
    @State private var result: String?

    var body: some View {
        LifeCard(area: .calendar) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Test Promemoria Apple").font(.headline)
                Text("Accesso EventKit: \(authorizationLabel)")
                Text("Il test crea «Test AG Life» nell’elenco predefinito. Lascia aperte queste impostazioni mentre passi a Promemoria Apple per completarlo.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(requesting ? "Richiesta in corso…" : "Richiedi accesso ai Promemoria") {
                    Task { await requestAccess() }
                }
                .disabled(requesting || authorization != .notDetermined)
                Button("Aggiorna stato autorizzazione", action: refreshAuthorization)
                Button("Crea e verifica «Test AG Life»", action: createTest)
                    .disabled(requesting || authorization != .fullAccess || testIdentifier != nil)
                Button("Rileggi il promemoria di prova", action: readTest)
                    .disabled(requesting || authorization != .fullAccess || testIdentifier == nil)
                if let result {
                    Text(result).font(.subheadline)
                }
            }
            .buttonStyle(.bordered)
        }
        .onChange(of: scenePhase, initial: true) { _, _ in refreshAuthorization() }
    }

    private var authorizationLabel: String {
        switch authorization {
        case .notDetermined: return "Non ancora richiesto"
        case .restricted: return "Limitato da iOS"
        case .denied: return "Negato"
        case .fullAccess: return "Accesso completo"
        case .writeOnly: return "Sola scrittura, rilettura indisponibile"
        @unknown default: return "Stato sconosciuto (\(authorization.rawValue))"
        }
    }

    private func refreshAuthorization() {
        authorization = EKEventStore.authorizationStatus(for: .reminder)
    }

    private func requestAccess() async {
        guard !requesting else { return }
        requesting = true
        defer {
            requesting = false
            refreshAuthorization()
        }
        let store = EKEventStore()
        do {
            let granted = try await store.requestFullAccessToReminders()
            let status = EKEventStore.authorizationStatus(for: .reminder)
            result = granted && status == .fullAccess
                ? "EventKit ha concesso l’accesso completo. Puoi creare il promemoria di prova."
                : "EventKit non ha confermato l’accesso completo. Controlla Privacy e sicurezza → Promemoria su iOS, anche sotto il nome LiveContainer."
        } catch {
            result = "Richiesta di accesso non riuscita. \(errorDescription(error))"
        }
    }

    private func createTest() {
        refreshAuthorization()
        guard authorization == .fullAccess, testIdentifier == nil else { return }
        let store = EKEventStore()
        guard let calendar = store.defaultCalendarForNewReminders(),
              calendar.allowsContentModifications else {
            result = "EventKit non trova un elenco Promemoria predefinito scrivibile. Verifica che Promemoria Apple abbia un elenco utilizzabile."
            return
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = "Test AG Life"
        do {
            try store.save(reminder, commit: true)
            testIdentifier = reminder.calendarItemIdentifier
            readTest(afterSave: true)
        } catch {
            result = "Salvataggio non riuscito. \(errorDescription(error))"
        }
    }

    private func readTest() {
        readTest(afterSave: false)
    }

    private func readTest(afterSave: Bool) {
        refreshAuthorization()
        guard authorization == .fullAccess, let testIdentifier else {
            result = "Rilettura indisponibile. Serve l’accesso completo e un test creato in questa sessione."
            return
        }
        let freshStore = EKEventStore()
        guard let reminder = freshStore.calendarItem(withIdentifier: testIdentifier) as? EKReminder else {
            result = afterSave
                ? "EventKit ha accettato il salvataggio, ma il promemoria non è stato ritrovato. Cerca «Test AG Life» nell’app Promemoria e riprova la rilettura."
                : "EventKit non ritrova il promemoria di questa sessione. Verifica che sia ancora presente nell’app Promemoria."
            return
        }
        let completion = reminder.isCompleted ? "completato" : "non completato"
        let dates = reminder.startDateComponents == nil && reminder.dueDateComponents == nil
            ? "senza data né scadenza" : "con data o scadenza"
        result = "\(afterSave ? "Salvataggio verificato" : "Rilettura riuscita"). «\(reminder.title ?? "Test AG Life")», \(completion), \(dates)."
    }

    private func errorDescription(_ error: Error) -> String {
        let details = error as NSError
        return "\(details.localizedDescription) (\(details.domain), codice \(details.code))"
    }
}

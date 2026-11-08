import EventKit
import SwiftUI

@MainActor
final class AppleReminders: ObservableObject {
    @Published private(set) var issues: [UUID: String] = [:]
    @Published private(set) var creating = Set<UUID>()
    @Published private(set) var diagnostics: [UUID: String] = [:]
    private let listKey = "AppleReminders.managedList"
    private lazy var eventStore = EKEventStore()

    func create(for id: UUID, in store: LifeStore) async {
        guard creating.insert(id).inserted else { return }
        defer { creating.remove(id) }
        do {
            _ = eventStore
            let events = EKEventStore()
            if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
                _ = try await events.requestFullAccessToReminders()
            }
            try requireAccess()
            guard let note = store.data.notes.first(where: { $0.id == id }), note.appleReminder == nil else { return }
            let list = try managedList(in: events)
            // Persist the attempt before writing to Apple. An interrupted save cannot auto-create a duplicate.
            guard setLink(AppleReminderLink(), for: id, in: store) else { return }
            let reminder = EKReminder(eventStore: events)
            reminder.calendar = list
            reminder.title = note.body
            reminder.url = marker(id)
            reminder.isCompleted = false
            try persist(reminder, in: events)
            let link = AppleReminderLink(identifier: reminder.calendarItemIdentifier, syncedTitle: note.body)
            if !setLink(link, for: id, in: store) {
                issues[id] = "Creato in Apple, ma il collegamento locale non è stato salvato."
            } else {
                let verified = try verify(reminder, expectedList: list.calendarIdentifier)
                record(verified, for: id)
            }
        } catch {
            issues[id] = error.localizedDescription
            store.errorMessage = "Pensiero salvato in AG Life. Promemoria Apple: \(error.localizedDescription)"
        }
    }

    func synchronize(_ store: LifeStore) {
        guard store.isReady else { return }
        let notes = store.data.notes.filter { $0.appleReminder != nil && !creating.contains($0.id) }
        guard !notes.isEmpty else { return }
        _ = eventStore // Retain an observer store for EKEventStoreChanged.
        let events = EKEventStore()
        var changes: [UUID: AppleReminderLink] = [:]
        for note in notes {
            do {
                guard var link = note.appleReminder else { continue }
                let reminder = try linkedReminder(note, in: events)
                if reminder.title != note.body && note.body != link.syncedTitle {
                    guard reminder.title == link.syncedTitle else {
                        link.isCompleted = reminder.isCompleted
                        if link != note.appleReminder { changes[note.id] = link }
                        issues[note.id] = "Titolo modificato anche in Apple. Entrambi i testi sono conservati."
                        continue
                    }
                    reminder.title = note.body
                    try persist(reminder, in: events)
                    _ = try verify(reminder, expectedList: reminder.calendar.calendarIdentifier)
                }
                if reminder.title == note.body { link.syncedTitle = note.body }
                link.isCompleted = reminder.isCompleted
                if link != note.appleReminder { changes[note.id] = link }
                issues[note.id] = reminder.title == note.body ? nil : "Il titolo in Apple è diverso dal testo locale."
                diagnostics[note.id] = description(reminder)
            } catch {
                issues[note.id] = error.localizedDescription
            }
        }
        if !changes.isEmpty {
            store.update { data in
                for index in data.notes.indices {
                    if let link = changes[data.notes[index].id] { data.notes[index].appleReminder = link }
                }
            }
        }
    }

    func setCompleted(_ completed: Bool, for id: UUID, in store: LifeStore) {
        guard let note = store.data.notes.first(where: { $0.id == id }), var link = note.appleReminder else { return }
        do {
            let events = EKEventStore()
            let reminder = try linkedReminder(note, in: events)
            if reminder.isCompleted != completed {
                reminder.isCompleted = completed
                try persist(reminder, in: events)
            }
            _ = try verify(reminder, expectedList: reminder.calendar.calendarIdentifier)
            link.isCompleted = completed
            _ = setLink(link, for: id, in: store)
            synchronize(store)
        } catch { issues[id] = error.localizedDescription }
    }

    func delete(_ id: UUID, includingApple: Bool, in store: LifeStore) {
        guard let note = store.data.notes.first(where: { $0.id == id }), !creating.contains(id) else { return }
        if includingApple, note.appleReminder != nil {
            do {
                let events = EKEventStore()
                let reminder = try linkedReminder(note, in: events)
                try events.remove(reminder, commit: true)
            } catch {
                issues[id] = error.localizedDescription
                store.errorMessage = "Pensiero conservato. Eliminazione da Apple non riuscita: \(error.localizedDescription)"
                return
            }
        }
        if store.update({ $0.notes.removeAll { $0.id == id } }) { issues[id] = nil }
    }

    func clearIssue(for id: UUID) {
        issues[id] = nil
        diagnostics[id] = nil
    }

    // Read-only search by the marker we wrote, never by the user's text.
    func recover(_ id: UUID, in store: LifeStore) async {
        guard creating.insert(id).inserted else { return }
        defer { creating.remove(id) }
        do {
            try requireAccess()
            let events = EKEventStore()
            let predicate = events.predicateForReminders(in: nil)
            let reminders: [EKReminder]? = await withCheckedContinuation { continuation in
                events.fetchReminders(matching: predicate) { continuation.resume(returning: $0) }
            }
            guard let reminders else {
                throw Problem(message: "Apple non ha restituito i promemoria. Riprova quando l’account è disponibile.")
            }
            let matches = reminders.filter { $0.url == marker(id) }
            guard matches.count == 1, let reminder = matches.first else {
                throw Problem(message: matches.isEmpty
                    ? "Nessun promemoria trovato con il collegamento originale. Il pensiero resta salvato."
                    : "Più promemoria hanno lo stesso collegamento. Serve una verifica nell’app Apple.")
            }
            guard let current = store.data.notes.first(where: { $0.id == id }), current.appleReminder != nil else { return }
            var link = current.appleReminder!
            link.identifier = reminder.calendarItemIdentifier
            link.isCompleted = reminder.isCompleted
            if link.syncedTitle == nil, reminder.title == current.body { link.syncedTitle = current.body }
            guard setLink(link, for: id, in: store) else { return }
            record(reminder, for: id)
            // Recover a lost list ID only with marker evidence and one unambiguous AG Life list.
            if reminder.calendar.title == "AG Life",
               events.calendars(for: .reminder).filter({ $0.title == "AG Life" }).count == 1,
               UserDefaults.standard.string(forKey: listKey).flatMap({ events.calendar(withIdentifier: $0) }) == nil {
                UserDefaults.standard.set(reminder.calendar.calendarIdentifier, forKey: listKey)
            }
        } catch { issues[id] = error.localizedDescription }
    }

    private func persist(_ reminder: EKReminder, in events: EKEventStore) throws {
        guard reminder.calendar.allowsContentModifications else {
            throw Problem(message: "La lista del promemoria è in sola lettura.")
        }
        do { try events.save(reminder, commit: false) }
        catch {
            events.reset()
            throw Problem(message: "Scrittura del promemoria non riuscita. " + error.localizedDescription)
        }
        do { try events.commit() }
        catch {
            events.reset()
            throw Problem(message: "Conferma del salvataggio non riuscita. Verifica o recupera il collegamento prima di riprovare. " + error.localizedDescription)
        }
    }

    private func verify(_ reminder: EKReminder, expectedList: String) throws -> EKReminder {
        let reader = EKEventStore()
        guard let saved = reader.calendarItem(withIdentifier: reminder.calendarItemIdentifier) as? EKReminder else {
            throw Problem(message: "Salvataggio accettato, ma il promemoria non è rileggibile. Usa Verifica e recupera collegamento.")
        }
        guard saved.calendar.calendarIdentifier == expectedList, saved.url == reminder.url,
              saved.title == reminder.title, saved.isCompleted == reminder.isCompleted,
              saved.startDateComponents == reminder.startDateComponents,
              saved.dueDateComponents == reminder.dueDateComponents else {
            throw Problem(message: "La rilettura mostra dati o una lista diversi. Controlla il promemoria in Apple prima di modificarlo ancora.")
        }
        return saved
    }

    private func description(_ reminder: EKReminder) -> String {
        let state = reminder.isCompleted ? "completato" : "da completare"
        let dates = reminder.dueDateComponents == nil && reminder.startDateComponents == nil
            ? "senza data" : "con data"
        return "Presente in EventKit · Lista “\(reminder.calendar.title ?? "")” · Account “\(reminder.calendar.source.title)” · \(state), \(dates). Il widget deve visualizzare questa lista."
    }

    private func record(_ reminder: EKReminder, for id: UUID) {
        diagnostics[id] = description(reminder)
        issues[id] = nil
    }

    private func setLink(_ link: AppleReminderLink?, for id: UUID, in store: LifeStore) -> Bool {
        store.update { data in
            if let index = data.notes.firstIndex(where: { $0.id == id }) {
                data.notes[index].appleReminder = link
            }
        }
    }

    private func requireAccess() throws {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            throw Problem(message: "Accesso a Promemoria indisponibile. Controlla il permesso iOS di LiveContainer.")
        }
    }

    private func linkedReminder(_ note: Note, in events: EKEventStore) throws -> EKReminder {
        try requireAccess()
        guard let identifier = note.appleReminder?.identifier else {
            throw Problem(message: "Identificativo non confermato. Usa Verifica e recupera collegamento.")
        }
        guard let reminder = events.calendarItem(withIdentifier: identifier) as? EKReminder,
              reminder.url == marker(note.id) else {
            throw Problem(message: "Identificativo non trovato o collegamento diverso. Usa Verifica e recupera collegamento.")
        }
        return reminder
    }

    private func marker(_ id: UUID) -> URL {
        URL(string: "aglife://thought/\(id.uuidString)")!
    }

    private func managedList(in events: EKEventStore) throws -> EKCalendar {
        if let identifier = UserDefaults.standard.string(forKey: listKey) {
            guard let list = events.calendar(withIdentifier: identifier) else {
                throw Problem(message: "Lista AG Life collegata non trovata. Prova il recupero su un pensiero già collegato.")
            }
            guard list.allowedEntityTypes.contains(.reminder), list.allowsContentModifications else {
                throw Problem(message: "La lista AG Life collegata non consente modifiche ai promemoria.")
            }
            return list
        }
        guard !events.calendars(for: .reminder).contains(where: { $0.title == "AG Life" }) else {
            throw Problem(message: "Esiste una lista AG Life, ma manca il suo collegamento. Recupera un pensiero già collegato per identificarla senza creare duplicati.")
        }
        guard let source = events.defaultCalendarForNewReminders()?.source else {
            throw Problem(message: "Apple non offre un account predefinito per creare l’elenco AG Life.")
        }
        let list = EKCalendar(for: .reminder, eventStore: events)
        list.title = "AG Life"
        list.source = source
        try events.saveCalendar(list, commit: true)
        UserDefaults.standard.set(list.calendarIdentifier, forKey: listKey)
        return list
    }

    private struct Problem: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}

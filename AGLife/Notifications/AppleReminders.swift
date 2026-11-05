import EventKit
import SwiftUI

@MainActor
final class AppleReminders: ObservableObject {
    @Published private(set) var issues: [UUID: String] = [:]
    @Published private(set) var creating = Set<UUID>()
    private let listKey = "AppleReminders.managedList"
    private lazy var eventStore = EKEventStore()

    func create(for id: UUID, in store: LifeStore) async {
        guard creating.insert(id).inserted else { return }
        defer { creating.remove(id) }
        do {
            let events = eventStore
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
            try events.save(reminder, commit: true)
            let link = AppleReminderLink(identifier: reminder.calendarItemIdentifier, syncedTitle: note.body)
            if !setLink(link, for: id, in: store) {
                issues[id] = "Creato in Apple, ma il collegamento locale non è stato salvato."
            } else {
                issues[id] = nil
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
        let events = eventStore
        events.reset()
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
                    try events.save(reminder, commit: true)
                }
                if reminder.title == note.body { link.syncedTitle = note.body }
                link.isCompleted = reminder.isCompleted
                if link != note.appleReminder { changes[note.id] = link }
                issues[note.id] = reminder.title == note.body ? nil : "Il titolo in Apple è diverso dal testo locale."
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
                try events.save(reminder, commit: true)
            }
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
            throw Problem(message: "Collegamento non confermato. Verifica l’elenco AG Life in Apple.")
        }
        guard let reminder = events.calendarItem(withIdentifier: identifier) as? EKReminder,
              reminder.url == marker(note.id) else {
            throw Problem(message: "Promemoria collegato non trovato. Il pensiero resta in AG Life.")
        }
        return reminder
    }

    private func marker(_ id: UUID) -> URL {
        URL(string: "aglife://thought/\(id.uuidString)")!
    }

    private func managedList(in events: EKEventStore) throws -> EKCalendar {
        if let identifier = UserDefaults.standard.string(forKey: listKey) {
            guard let list = events.calendar(withIdentifier: identifier),
                  list.allowedEntityTypes.contains(.reminder), list.allowsContentModifications else {
                throw Problem(message: "L’elenco AG Life collegato non è disponibile o è in sola lettura.")
            }
            return list
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

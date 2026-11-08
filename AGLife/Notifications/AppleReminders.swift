import EventKit
import SwiftUI

@MainActor
final class AppleReminders: ObservableObject {
    @Published private(set) var issues: [UUID: String] = [:]
    @Published private(set) var creating = Set<UUID>()
    @Published private(set) var diagnostics: [UUID: String] = [:]
    @Published private(set) var listChoices: [ListChoice] = []
    @Published private(set) var listReport = "Cerca le liste accessibili a EventKit."
    @Published private(set) var canCreateList = false
    struct ListChoice: Identifiable {
        let id: String
        let account: String
    }
    private let listKey = "AppleReminders.managedList"
    private lazy var eventStore = EKEventStore()
    private var isSynchronizing = false

    func create(for id: UUID, in store: LifeStore) async {
        guard creating.insert(id).inserted else { return }
        defer { creating.remove(id) }
        do {
            SaveTrace.record("3 · Controllo permesso Apple")
            _ = eventStore
            let events = EKEventStore()
            defer { withExtendedLifetime(events) {} }
            if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
                _ = try await events.requestFullAccessToReminders()
            }
            try requireAccess()
            guard let note = store.data.notes.first(where: { $0.id == id }), note.appleReminder == nil else { return }
            let list = try managedList(in: events)
            SaveTrace.record("4 · Lista Apple verificata")
            // Persist the attempt before writing to Apple. An interrupted save cannot auto-create a duplicate.
            guard setLink(AppleReminderLink(), for: id, in: store) else { return }
            let reminder = EKReminder(eventStore: events)
            reminder.calendar = list
            reminder.title = note.body
            reminder.url = marker(id)
            reminder.isCompleted = false
            SaveTrace.record("5 · Scrittura e commit Apple")
            try persist(reminder, in: events)
            let link = AppleReminderLink(identifier: reminder.calendarItemIdentifier, syncedTitle: note.body)
            if !setLink(link, for: id, in: store) {
                issues[id] = "Creato in Apple, ma il collegamento locale non è stato salvato."
            } else {
                let verified = try verify(reminder, expectedList: list.calendarIdentifier)
                diagnostics[id] = verified
                issues[id] = nil
                SaveTrace.record("7 · Salvataggio Apple verificato")
            }
        } catch {
            SaveTrace.record("Errore · Sincronizzazione Apple non riuscita, pensiero locale conservato")
            issues[id] = error.localizedDescription
            store.errorMessage = "Pensiero salvato in AG Life. Promemoria Apple: \(error.localizedDescription)"
        }
    }

    func synchronize(_ store: LifeStore) {
        guard store.isReady, !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        let notes = store.data.notes.filter { $0.appleReminder != nil && !creating.contains($0.id) }
        guard !notes.isEmpty else { return }
        _ = eventStore // Retain an observer store for EKEventStoreChanged.
        let events = EKEventStore()
            defer { withExtendedLifetime(events) {} }
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
                    _ = try verify(reminder, expectedList: try calendarID(reminder))
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
            defer { withExtendedLifetime(events) {} }
            let reminder = try linkedReminder(note, in: events)
            if reminder.isCompleted != completed {
                reminder.isCompleted = completed
                try persist(reminder, in: events)
            }
            _ = try verify(reminder, expectedList: try calendarID(reminder))
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
            defer { withExtendedLifetime(events) {} }
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
            defer { withExtendedLifetime(events) {} }
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
            guard var link = current.appleReminder else { return }
            link.identifier = reminder.calendarItemIdentifier
            link.isCompleted = reminder.isCompleted
            if link.syncedTitle == nil, reminder.title == current.body { link.syncedTitle = current.body }
            guard setLink(link, for: id, in: store) else { return }
            record(reminder, for: id)
            // Recover a lost list ID only with marker evidence and one unambiguous AG Life list.
            if let calendar = reminder.calendar, calendar.title == "AG Life",
               events.calendars(for: .reminder).filter({ $0.title == "AG Life" }).count == 1,
               UserDefaults.standard.string(forKey: listKey).flatMap({ events.calendar(withIdentifier: $0) }) == nil {
                UserDefaults.standard.set(calendar.calendarIdentifier, forKey: listKey)
            }
        } catch { issues[id] = error.localizedDescription }
    }

    private func persist(_ reminder: EKReminder, in events: EKEventStore) throws {
        guard let calendar = reminder.calendar, calendar.allowsContentModifications else {
            throw Problem(message: "La lista del promemoria è in sola lettura.")
        }
        // Same store owns the reminder and its calendar. Match the proven test's atomic API.
        do { try events.save(reminder, commit: true) }
        catch {
            events.reset()
            throw Problem(message: "Scrittura o commit Apple non riuscito. Verifica il collegamento prima di riprovare. " + error.localizedDescription)
        }
    }

    private func calendarID(_ reminder: EKReminder) throws -> String {
        guard let calendar = reminder.calendar else { throw Problem(message: "Lista del promemoria non disponibile.") }
        return calendar.calendarIdentifier
    }

    private func verify(_ reminder: EKReminder, expectedList: String) throws -> String {
        SaveTrace.record("6 · Rilettura Apple in corso")
        let reader = EKEventStore()
        return try withExtendedLifetime(reader) {
        guard let saved = reader.calendarItem(withIdentifier: reminder.calendarItemIdentifier) as? EKReminder else {
            throw Problem(message: "Salvataggio accettato, ma il promemoria non è rileggibile. Usa Verifica e recupera collegamento.")
        }
        guard let calendar = saved.calendar,
              calendar.calendarIdentifier == expectedList, saved.url == reminder.url,
              saved.title == reminder.title, saved.isCompleted == reminder.isCompleted,
              saved.startDateComponents == reminder.startDateComponents,
              saved.dueDateComponents == reminder.dueDateComponents else {
            throw Problem(message: "La rilettura mostra dati o una lista diversi. Controlla il promemoria in Apple prima di modificarlo ancora.")
        }
        // Return a value snapshot, never an EventKit object outliving its reader store.
        return description(saved)
        }
    }

    private func description(_ reminder: EKReminder) -> String {
        let state = reminder.isCompleted ? "completato" : "da completare"
        let dates = reminder.dueDateComponents == nil && reminder.startDateComponents == nil
            ? "senza data" : "con data"
        guard let calendar = reminder.calendar else { return "Presente in EventKit, lista non disponibile." }
        let account = calendar.source?.title ?? "Origine non disponibile"
        return "Presente in EventKit · Lista “\(calendar.title ?? "")” · Account “\(account)” · \(state), \(dates). Il widget deve visualizzare questa lista."
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
                throw Problem(message: "Lista AG Life collegata non trovata. Apri Impostazioni → Lista Promemoria Apple → Cerca liste.")
            }
            guard list.allowedEntityTypes.contains(.reminder), list.allowsContentModifications else {
                throw Problem(message: "La lista AG Life collegata non consente modifiche ai promemoria.")
            }
            return list
        }
        throw Problem(message: "Scegli la lista in Impostazioni → Lista Promemoria Apple → Cerca liste.")
    }

    func scanLists() {
        listChoices = []
        canCreateList = false
        do {
            try requireAccess()
            let events = EKEventStore()
            defer { withExtendedLifetime(events) {} }
            let lists = events.calendars(for: .reminder)
            let named = lists.filter { $0.title == "AG Life" }
            listChoices = named.filter { $0.allowsContentModifications }.map { list in
                ListChoice(id: list.calendarIdentifier, account: accountLabel(list.source, in: events))
            }
            canCreateList = listChoices.isEmpty
            let stored = UserDefaults.standard.string(forKey: listKey)
            let linked = lists.first { $0.calendarIdentifier == stored }
            let status = linked.map { $0.allowsContentModifications ? "Collegamento attuale accessibile." : "Collegamento attuale in sola lettura." }
                ?? "Identificativo salvato assente o non più visibile."
            let groups = Dictionary(grouping: lists, by: { $0.source?.sourceIdentifier ?? "unavailable" })
            let summary = events.sources.enumerated().map { index, source in
                let accountLists = groups[source.sourceIdentifier] ?? []
                let matches = accountLists.filter { $0.title == "AG Life" }
                return "Account \(index + 1) · \(sourceTypeLabel(source)): \(accountLists.count) liste, \(matches.count) chiamate AG Life, \(matches.filter { $0.allowsContentModifications }.count) modificabili."
            }.joined(separator: "\n")
            listReport = "Accesso completo confermato. \(status)\nEventKit restituisce \(lists.count) liste e \(listChoices.count) liste AG Life compatibili.\n\(summary)"
            if lists.isEmpty {
                listReport += "\nSe Apple mostra già la lista, verifica account e permesso Promemoria di LiveContainer in iOS, quindi ripeti la ricerca."
            }
        } catch { listReport = error.localizedDescription }
    }

    func selectList(_ identifier: String) {
        do {
            let events = EKEventStore()
            defer { withExtendedLifetime(events) {} }
            try requireAccess()
            guard let list = events.calendars(for: .reminder).first(where: { $0.calendarIdentifier == identifier }),
                  list.title == "AG Life", list.allowsContentModifications else {
                throw Problem(message: "La lista scelta non è più accessibile o modificabile. Ripeti Cerca liste.")
            }
            UserDefaults.standard.set(identifier, forKey: listKey)
            listReport = "Lista AG Life ricollegata · \(accountLabel(list.source, in: events)). Puoi riprovare l’invio del pensiero."
            canCreateList = false
        } catch { listReport = error.localizedDescription }
    }

    func createListExplicitly() {
        do {
            try requireAccess()
            let events = EKEventStore()
            defer { withExtendedLifetime(events) {} }
            guard !events.calendars(for: .reminder).contains(where: { $0.title == "AG Life" && $0.allowsContentModifications }) else {
                scanLists()
                return
            }
            guard let source = events.defaultCalendarForNewReminders()?.source else {
                throw Problem(message: "Account predefinito Promemoria non disponibile. Configuralo nell’app Apple e ripeti la ricerca.")
            }
            let list = EKCalendar(for: .reminder, eventStore: events)
            list.title = "AG Life"
            list.source = source
            canCreateList = false
            try events.saveCalendar(list, commit: true)
            // Keep the ID even if the independent verification fails, avoiding a blind retry.
            UserDefaults.standard.set(list.calendarIdentifier, forKey: listKey)
            canCreateList = false
            let reader = EKEventStore()
            guard reader.calendar(withIdentifier: list.calendarIdentifier) != nil else {
                throw Problem(message: "Creazione accettata, ma lista non ancora rileggibile. Ripeti Cerca liste prima di creare ancora.")
            }
            scanLists()
            listReport = "Lista creata e collegata.\n" + listReport
        } catch { listReport = error.localizedDescription }
    }

    private func accountLabel(_ source: EKSource?, in events: EKEventStore) -> String {
        guard let source else { return "Origine EventKit non disponibile" }
        let number = (events.sources.firstIndex(where: { $0.sourceIdentifier == source.sourceIdentifier }) ?? 0) + 1
        let title = source.title.contains("@") ? "Account \(number)" : source.title
        return "\(title) · account \(number), \(sourceTypeLabel(source))"
    }

    private func sourceTypeLabel(_ source: EKSource) -> String {
        switch source.sourceType {
        case .local: return "Sul dispositivo"
        case .exchange: return "Exchange"
        case .calDAV: return "CalDAV / iCloud"
        case .mobileMe: return "iCloud"
        case .subscribed: return "Abbonamento"
        case .birthdays: return "Compleanni"
        @unknown default: return "Altra origine"
        }
    }

    private struct Problem: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}

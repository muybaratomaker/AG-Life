import Foundation

@main
struct CoreTests {
    static func main() throws {
        try check(Money.parse("12,34") == Decimal(string: "12.34"), "Decimal comma")
        try check(Money.parse("12.34") == Decimal(string: "12.34"), "Decimal point")
        for invalid in ["", "0", "-1", "1.234", "1,234.56", "abc", "1e2", "NaN", "9999999999", ".", "1."] {
            try check(Money.parse(invalid) == nil, "Reject invalid amount: \(invalid)")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let february = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        var data = LifeData()
        data.movements = [
            Movement(kind: .expense, amount: Decimal(string: "0.10")!, category: .other, detail: "Test", date: january),
            Movement(kind: .expense, amount: Decimal(string: "0.20")!, category: .home, detail: "", date: january),
            Movement(kind: .income, amount: 50, category: .work, detail: "", date: january),
            Movement(kind: .expense, amount: 99, category: .other, detail: "", date: february)
        ]
        try check(data.total(.expense, in: january, calendar: calendar) == Decimal(string: "0.30"), "Exact monthly decimals")
        try check(data.total(.income, in: january, calendar: calendar) == 50, "Income separated")
        data.notes = [Note(body: "Idea è 🌿\nPrima riga\nSeconda riga")]
        data.appointments = [Appointment(title: "Impegno", date: january, detail: "Dettaglio")]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = LocalArchive(url: directory.appendingPathComponent("life.json"))
        try check(try archive.load() == LifeData(), "Missing file starts empty")
        let legacyID = UUID()
        let oldNotes = [
            LegacyNote(id: legacyID, title: "  Titolo è 🌿  ", body: "Corpo\noriginale", updatedAt: Date(timeIntervalSinceReferenceDate: 12345)),
            LegacyNote(id: UUID(), title: "Solo titolo", body: "", updatedAt: Date(timeIntervalSinceReferenceDate: 54321)),
            LegacyNote(id: UUID(), title: "", body: "Solo corpo", updatedAt: Date(timeIntervalSinceReferenceDate: 123))
        ]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Encode exactly as v1 did, without routing Decimal values through binary doubles.
        let legacyBytes = try JSONEncoder().encode(LegacyArchive(movements: data.movements,
            appointments: data.appointments, notes: oldNotes))
        try legacyBytes.write(to: archive.url)
        let migrated = try archive.load()
        try check(migrated.version == 3, "Legacy schema migrates to v3")
        try check(migrated.notes[0].id == legacyID, "Legacy identity preserved")
        try check(migrated.notes[0].updatedAt == Date(timeIntervalSinceReferenceDate: 12345), "Legacy timestamp preserved")
        try check(migrated.notes[0].body == "  Titolo è 🌿  \n\nCorpo\noriginale", "Title and body preserved verbatim")
        try check(migrated.notes[1].body == "Solo titolo", "Title-only note preserved")
        try check(migrated.notes[2].body == "Solo corpo", "Body-only note preserved")
        try check(migrated.notes.allSatisfy { !$0.isPinned }, "Legacy notes start unpinned")
        try check(migrated.appointments.allSatisfy { $0.reminder == nil }, "Legacy appointments have no reminders")
        try check(migrated.movements == data.movements && migrated.appointments == data.appointments, "Other data unchanged")
        try check(try Data(contentsOf: archive.url) == legacyBytes, "Migration reads without rewriting original")
        try archive.save(migrated)
        try check(try Data(contentsOf: archive.url.appendingPathExtension("pre-v3-backup")) == legacyBytes, "Pre-migration original backed up byte for byte")
        try check(try archive.load() == migrated, "Migration is idempotent after save and restart")
        let encodedNotes = try JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated.notes)) as! [[String: Any]]
        try check(encodedNotes.allSatisfy { $0["title"] == nil }, "New schema contains body only")

        let oldBodyNote = BodyOnlyNote(id: UUID(), body: "Testo v2\nimmutato", updatedAt: january)
        let oldAppointment = LegacyAppointment(id: UUID(), title: "Impegno v2", date: february, detail: "Dettagli")
        let v2 = LegacyV2Archive(movements: data.movements, appointments: [oldAppointment], notes: [oldBodyNote])
        let v2Bytes = try JSONEncoder().encode(v2)
        let v2Archive = LocalArchive(url: directory.appendingPathComponent("v2.json"))
        try v2Bytes.write(to: v2Archive.url)
        var migratedV2 = try v2Archive.load()
        try check(migratedV2.version == 3 && migratedV2.notes[0].body == oldBodyNote.body, "v2 body preserved")
        try check(migratedV2.notes[0].id == oldBodyNote.id && migratedV2.notes[0].updatedAt == january, "v2 identity and date preserved")
        try check(!migratedV2.notes[0].isPinned && migratedV2.appointments[0].reminder == nil, "Missing v2 properties default safely")
        try check(migratedV2.notes[0].appleReminder == nil, "Old thoughts remain unlinked")
        let appleLink = AppleReminderLink(identifier: "eventkit-test-id", syncedTitle: oldBodyNote.body, isCompleted: true)
        migratedV2.notes[0].appleReminder = appleLink
        migratedV2.notes[0].isPinned = true
        migratedV2.appointments[0].reminder = .fifteenMinutes
        try v2Archive.save(migratedV2)
        try check(try v2Archive.load() == migratedV2, "Pin and reminder persist after restart")
        try check(try v2Archive.load().notes[0].appleReminder == appleLink, "Apple identifier, synced title and completion survive restart")
        try check(try Data(contentsOf: v2Archive.url.appendingPathExtension("pre-v3-backup")) == v2Bytes, "v2 backup preserved")
        migratedV2.notes[0].isPinned = false
        migratedV2.appointments[0].reminder = nil
        try v2Archive.save(migratedV2)
        try check(try v2Archive.load() == migratedV2, "Unpin and disabled reminder persist")
        try check(try Data(contentsOf: v2Archive.url.appendingPathExtension("pre-v3-backup")) == v2Bytes, "Backup never replaced")

        var reminderItem = Appointment(title: "Test", date: february, detail: "")
        try check(reminderItem.reminderDate == nil, "Disabled reminder never scheduled")
        let identifier = reminderItem.notificationIdentifier
        for lead in ReminderLead.allCases {
            reminderItem.reminder = lead
            let expected = february.addingTimeInterval(-Double(lead.rawValue))
            try check(reminderItem.reminderDate == expected, "All reminder offsets")
            try check(reminderItem.futureReminderDate(after: expected) == nil, "Exact present time excluded")
            try check(reminderItem.futureReminderDate(after: expected.addingTimeInterval(1)) == nil, "Past trigger excluded")
            try check(reminderItem.futureReminderDate(after: expected.addingTimeInterval(-60)) == expected, "Future trigger accepted")
        }
        reminderItem.date = january
        reminderItem.title = "Modificato"
        try check(reminderItem.notificationIdentifier == identifier, "Stable identifier across edits")
        try check(Appointment(title: "Altro", date: january, detail: "").notificationIdentifier != identifier, "Distinct identifiers per appointment")

        let now = january.addingTimeInterval(12 * 3600)
        let earlier = Appointment(title: "Passato oggi", date: now.addingTimeInterval(-3600), detail: "")
        let later = Appointment(title: "Tra poco", date: now.addingTimeInterval(3600), detail: "")
        let tomorrow = Appointment(title: "Domani", date: february, detail: "")
        var agendaData = LifeData()
        agendaData.appointments = [earlier, tomorrow, later,
            Appointment(title: "Ieri", date: january.addingTimeInterval(-1), detail: ""),
            Appointment(title: "Lontano", date: february.addingTimeInterval(7 * 86400), detail: "")]
        let agenda = agendaData.agenda(at: now, calendar: calendar)
        try check(agenda.today.map(\.id) == [later.id, earlier.id], "Today includes elapsed, prioritizes next appointments")
        try check(agenda.upcoming.map(\.id) == [tomorrow.id], "Upcoming excludes today, past and outside seven days")
        agendaData.appointments += (1...10).map {
            Appointment(title: "Test", date: now.addingTimeInterval(Double($0 * 60)), detail: "")
        }
        let limited = agendaData.agenda(at: now, calendar: calendar)
        try check(limited.today.count == 3 && limited.todayCount == 12, "Agenda caps visible rows, preserves total")
        agendaData.appointments += (1...5).map {
            Appointment(title: "Test domani", date: february.addingTimeInterval(Double($0 * 60)), detail: "")
        }
        let busy = agendaData.agenda(at: now, calendar: calendar)
        try check(busy.upcoming.count == 2 && busy.upcomingCount == 6, "Upcoming preview limited to two")
        try check(busy.today.map(\.id).allSatisfy { id in !busy.upcoming.contains { $0.id == id } }, "No duplicate events between sections")
        try archive.save(data)
        try check(try archive.load() == data, "Round trip all models, dates, UUIDs, Unicode and decimals")
        data.notes[0].body = "Aggiornata"
        data.movements.removeFirst()
        try archive.save(data)
        try check(try archive.load() == data, "Atomic replacement preserves edits and deletion")
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: archive.url)
        do {
            _ = try archive.load()
            throw Failure(message: "Corrupt file must throw")
        } catch is DecodingError { }
        try check(try Data(contentsOf: archive.url) == corrupt, "Corrupt original untouched")
        do {
            try archive.save(data)
            throw Failure(message: "Corrupt archive must not be overwritten")
        } catch let error as Failure { throw error } catch { }
        try check(try Data(contentsOf: archive.url) == corrupt, "Save also preserves corrupt original")
        try FileManager.default.removeItem(at: archive.url)
        var future = LifeData()
        future.version = 99
        try archive.save(future)
        do {
            _ = try archive.load()
            throw Failure(message: "Unknown version must throw")
        } catch let error as NSError where error.domain == "AGLife" { }
        let blocker = directory.appendingPathComponent("file")
        try Data().write(to: blocker)
        do {
            try LocalArchive(url: blocker.appendingPathComponent("life.json")).save(data)
            throw Failure(message: "Write failure must throw")
        } catch let error as Failure { throw error } catch { }
        print("PASS: amounts, archive, v1/v2 migration and backup, pins, reminder dates and identifiers, agenda and failures")
    }
    struct LegacyNote: Encodable {
        let id: UUID
        let title: String
        let body: String
        let updatedAt: Date
    }
    struct LegacyArchive: Encodable {
        let version = 1
        let movements: [Movement]
        let appointments: [Appointment]
        let notes: [LegacyNote]
    }
    struct BodyOnlyNote: Encodable {
        let id: UUID
        let body: String
        let updatedAt: Date
    }
    struct LegacyAppointment: Encodable {
        let id: UUID
        let title: String
        let date: Date
        let detail: String
    }
    struct LegacyV2Archive: Encodable {
        let version = 2
        let movements: [Movement]
        let appointments: [LegacyAppointment]
        let notes: [BodyOnlyNote]
    }
    struct Failure: Error { let message: String }
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(message: message) }
    }
}

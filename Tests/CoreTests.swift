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
        data.notes = [Note(title: "Idea è 🌿", body: "Prima riga\nSeconda riga")]
        data.appointments = [Appointment(title: "Impegno", date: january, detail: "Dettaglio")]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = LocalArchive(url: directory.appendingPathComponent("life.json"))
        try check(try archive.load() == LifeData(), "Missing file starts empty")
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
        print("PASS: amounts, monthly totals, archive round trips, corruption, schema and write failures")
    }
    struct Failure: Error { let message: String }
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(message: message) }
    }
}

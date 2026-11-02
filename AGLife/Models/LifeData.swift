import Foundation

enum MovementKind: String, Codable, CaseIterable, Identifiable {
    case expense = "Uscita"
    case income = "Entrata"
    var id: String { rawValue }
}

enum Category: String, Codable, CaseIterable, Identifiable {
    case groceries = "Spesa", home = "Casa", transport = "Trasporti"
    case leisure = "Tempo libero", health = "Salute", work = "Lavoro", other = "Altro"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .groceries: return "basket"
        case .home: return "house"
        case .transport: return "tram"
        case .leisure: return "sparkles"
        case .health: return "heart"
        case .work: return "briefcase"
        case .other: return "ellipsis.circle"
        }
    }
}

struct Movement: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: MovementKind
    var amount: Decimal
    var category: Category
    var detail: String
    var date: Date
}

struct Appointment: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var date: Date
    var detail: String
    var reminder: ReminderLead?

    init(id: UUID = UUID(), title: String, date: Date, detail: String, reminder: ReminderLead? = nil) {
        self.id = id
        self.title = title
        self.date = date
        self.detail = detail
        self.reminder = reminder
    }

    private enum CodingKeys: String, CodingKey { case id, title, date, detail, reminder }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        date = try values.decode(Date.self, forKey: .date)
        detail = try values.decode(String.self, forKey: .detail)
        reminder = try values.decodeIfPresent(ReminderLead.self, forKey: .reminder)
    }

    var notificationIdentifier: String { "com.aglife.personal.reminder." + id.uuidString }
    var reminderDate: Date? { reminder.map { date.addingTimeInterval(-Double($0.rawValue)) } }
    func futureReminderDate(after now: Date) -> Date? {
        guard let fireDate = reminderDate, fireDate > now else { return nil }
        return fireDate
    }
}

enum ReminderLead: Int, Codable, CaseIterable, Identifiable {
    case atTime = 0, fiveMinutes = 300, fifteenMinutes = 900, oneHour = 3600, oneDay = 86400
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .atTime: return "All’ora dell’impegno"
        case .fiveMinutes: return "5 minuti prima"
        case .fifteenMinutes: return "15 minuti prima"
        case .oneHour: return "1 ora prima"
        case .oneDay: return "1 giorno prima"
        }
    }
}

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var body: String
    var updatedAt = Date()
    var isPinned = false

    init(id: UUID = UUID(), body: String, updatedAt: Date = .now, isPinned: Bool = false) {
        self.id = id
        self.body = body
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey { case id, title, body, updatedAt, isPinned }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        body = try values.decode(String.self, forKey: .body)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        // Legacy titles become editable text. Preserve even whitespace and identical titles.
        if let title = try values.decodeIfPresent(String.self, forKey: .title), !title.isEmpty {
            body = title + (body.isEmpty ? "" : "\n\n" + body)
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(body, forKey: .body)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(isPinned, forKey: .isPinned)
    }
}

struct LifeData: Codable, Equatable {
    var version = 3
    var movements: [Movement] = []
    var appointments: [Appointment] = []
    var notes: [Note] = []

    func agenda(at now: Date, calendar: Calendar = .current) -> AgendaSummary {
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let horizon = calendar.date(byAdding: .day, value: 7, to: todayEnd) ?? todayEnd
        let today = appointments.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let remaining = today.filter { $0.date >= now }.sorted { $0.date < $1.date }
        let elapsed = today.filter { $0.date < now }.sorted { $0.date > $1.date }
        let upcoming = appointments.filter { $0.date >= todayEnd && $0.date < horizon }
            .sorted { $0.date < $1.date }
        return AgendaSummary(today: Array((remaining + elapsed).prefix(3)),
            upcoming: Array(upcoming.prefix(2)), todayCount: today.count, upcomingCount: upcoming.count)
    }

    func total(_ kind: MovementKind, in month: Date, calendar: Calendar = .current) -> Decimal {
        movements.filter { $0.kind == kind && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }
}

struct AgendaSummary {
    let today: [Appointment]
    let upcoming: [Appointment]
    let todayCount: Int
    let upcomingCount: Int
}

enum Money {
    // Accept either Italian decimal comma or decimal point, without ambiguous grouping.
    static func parse(_ text: String) -> Decimal? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !parts[0].isEmpty,
              parts.allSatisfy({ $0.allSatisfy { "0123456789".contains($0) } }),
              parts.count == 1 || (1...2).contains(parts[1].count),
              let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              amount > 0, amount <= Decimal(999_999_999) else { return nil }
        return amount
    }

    static func display(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.locale = Locale(identifier: "it_IT")
        return formatter.string(from: value as NSDecimalNumber) ?? "€ 0,00"
    }
}

import SwiftUI

struct SaveErrorBanner: View {
    @EnvironmentObject private var store: LifeStore
    var body: some View {
        if let message = store.errorMessage {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.footnote)
                Button { store.errorMessage = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Chiudi messaggio")
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
            .accessibilityElement(children: .contain)
        }
    }
}

enum EditorRoute: String, Identifiable {
    case movement, appointment, note
    var id: String { rawValue }
}

struct RootView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Home", systemImage: "square.grid.2x2.fill") }
            ExpensesView().tabItem { Label("Spese", systemImage: "creditcard.fill") }
            CalendarView().tabItem { Label("Calendario", systemImage: "calendar") }
            NotesView().tabItem { Label("Note", systemImage: "note.text") }
        }
    }
}

struct SummaryCard: View {
    let title: String
    let amount: Decimal
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(Money.display(amount)).font(.title2.bold()).minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct MovementRow: View {
    let movement: Movement
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: movement.category.symbol)
                .font(.title3).foregroundStyle(.teal)
                .frame(width: 44, height: 44).background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text(movement.detail.isEmpty ? movement.category.rawValue : movement.detail).lineLimit(2)
                Text("\(movement.category.rawValue) · \(movement.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text("\(movement.kind == .income ? "+" : "−")\(Money.display(movement.amount))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(movement.kind == .income ? Color.teal : Color.primary)
        }.padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct AppointmentRow: View {
    let appointment: Appointment
    var body: some View {
        HStack(spacing: 14) {
            Text(appointment.date, format: .dateTime.hour().minute())
                .font(.subheadline.bold()).foregroundStyle(.teal).monospacedDigit()
            VStack(alignment: .leading, spacing: 4) {
                Text(appointment.title).font(.headline)
                Text(appointment.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption).foregroundStyle(.secondary)
                if !appointment.detail.isEmpty {
                    Text(appointment.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}

struct AddBar: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        .padding(.horizontal).padding(.vertical, 8).background(.bar)
    }
}

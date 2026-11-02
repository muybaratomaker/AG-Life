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
    @EnvironmentObject private var store: LifeStore
    @State private var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            HomeView(onOpenCalendar: { selection = 2 })
                .tabItem { Label("Home", systemImage: "square.grid.2x2.fill") }.tag(0)
            ExpensesView().tabItem { Label("Spese", systemImage: "creditcard.fill") }.tag(1)
            CalendarView().tabItem { Label("Calendario", systemImage: "calendar") }.tag(2)
            NotesView().tabItem { Label("Pensieri", systemImage: "note.text") }.tag(3)
        }
        .sensoryFeedback(.success, trigger: store.feedbackRevision)
    }
}

struct GentlePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    var wide = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if wide {
                    HStack(spacing: 16) {
                        icon
                        labels
                        Spacer(minLength: 0)
                        Image(systemName: "plus").font(.title3.weight(.semibold))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) { icon; labels }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: wide ? 100 : 148, alignment: .leading)
            .foregroundStyle(.primary)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(GentlePressStyle())
        .accessibilityLabel(title + ", " + subtitle)
    }

    private var icon: some View {
        Image(systemName: symbol).font(.title2.weight(.semibold)).foregroundStyle(color)
            .frame(width: 44, height: 44).background(color.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
    private var labels: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ThoughtRow: View {
    let note: Note
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.body).font(.body).foregroundStyle(.primary).lineLimit(3)
            Text(note.updatedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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

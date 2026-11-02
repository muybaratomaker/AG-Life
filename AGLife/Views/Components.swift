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
        .tint(selection == 2 ? LifeArea.calendar.accent : selection == 3 ? LifeArea.thoughts.accent : LifeArea.spending.accent)
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
                        Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(color)
                            .accessibilityHidden(true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) { icon; labels }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: wide ? 108 : 158, alignment: .leading)
            .foregroundStyle(.primary)
            .background(LinearGradient(colors: [color.opacity(0.18), color.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(color.opacity(0.2), lineWidth: 1) }
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
            Text(title).font(.system(.headline, design: .rounded))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ThoughtRow: View {
    let note: Note
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "quote.opening").font(.title3.weight(.bold))
                .foregroundStyle(LifeArea.thoughts.accent).accessibilityHidden(true)
            Text(note.body).font(.body).foregroundStyle(.primary).lineLimit(3)
            Text(note.updatedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [LifeArea.thoughts.accent.opacity(0.13), LifePalette.surface],
            startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

struct SummaryCard: View {
    let title: String
    let amount: Decimal
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.medium)).foregroundStyle(LifeArea.spending.accent)
            Text(Money.display(amount)).font(.system(.title2, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(LifeArea.spending.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct MovementRow: View {
    let movement: Movement
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 14))
        layout {
            Image(systemName: movement.category.symbol)
                .font(.title3).foregroundStyle(LifeArea.spending.accent)
                .frame(width: 44, height: 44).background(LifeArea.spending.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(movement.detail.isEmpty ? movement.category.rawValue : movement.detail).lineLimit(2)
                Text("\(movement.category.rawValue) · \(movement.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text("\(movement.kind == .income ? "+" : "−")\(Money.display(movement.amount))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(movement.kind == .income ? LifeArea.spending.accent : Color.primary)
        }.padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct AppointmentRow: View {
    let appointment: Appointment
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        layout {
            Text(appointment.date, format: .dateTime.hour().minute())
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(LifeArea.calendar.accent).monospacedDigit().padding(10)
                .background(LifeArea.calendar.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
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
    var area: LifeArea = .spending
    let action: () -> Void
    var body: some View {
        LifePrimaryButton(title: title, symbol: "plus", area: area, action: action)
            .padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
    }
}

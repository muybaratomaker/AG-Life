import SwiftUI

struct HomeView: View {
    var onOpenCalendar: () -> Void = {}
    @EnvironmentObject private var store: LifeStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editor: EditorRoute?
    @State private var selectedNote: Note?

    private var cardLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(context.date, format: .dateTime.month(.wide).year())
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("Il tuo spazio, ogni giorno.").font(.largeTitle.bold())
                            Text("Spese, progetti e pensieri. Tutto qui.").foregroundStyle(.secondary)
                        }.padding(.vertical, 10)
                        cardLayout {
                            SummaryCard(title: "Uscite", amount: store.data.total(.expense, in: context.date), symbol: "arrow.up.right")
                            SummaryCard(title: "Entrate", amount: store.data.total(.income, in: context.date), symbol: "arrow.down.left")
                        }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        HStack {
                            Text("Saldo del mese")
                            Spacer()
                            Text(Money.display(store.data.total(.income, in: context.date) - store.data.total(.expense, in: context.date)))
                                .fontWeight(.semibold)
                        }
                    }
                    Section("Aggiungi al volo") {
                        VStack(spacing: 12) {
                            cardLayout {
                                QuickActionCard(title: "Spese", subtitle: "Entrate e uscite", symbol: "creditcard", color: .teal) {
                                    editor = .movement
                                }
                                QuickActionCard(title: "Impegni", subtitle: "Nuovo evento", symbol: "calendar.badge.plus", color: .indigo) {
                                    editor = .appointment
                                }
                            }
                            QuickActionCard(title: "Un pensiero", subtitle: "Scrivi quello che hai in mente",
                                symbol: "square.and.pencil", color: .orange, wide: true) { editor = .note }
                        }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    }
                    let agenda = store.data.agenda(at: context.date)
                    Section("Oggi · \(agenda.todayCount) impegni") {
                        if agenda.today.isEmpty { Text("Nessun impegno oggi. Spazio per te.").foregroundStyle(.secondary) }
                        ForEach(agenda.today) { appointment in
                            VStack(alignment: .leading, spacing: 2) {
                                AppointmentRow(appointment: appointment)
                                if appointment.date < context.date {
                                    Text("Già iniziato").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if agenda.todayCount > agenda.today.count {
                            Text("Altri \(agenda.todayCount - agenda.today.count) impegni nel calendario")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("Nei prossimi 7 giorni") {
                        if agenda.upcoming.isEmpty { Text("Nessun impegno imminente.").foregroundStyle(.secondary) }
                        ForEach(agenda.upcoming) { AppointmentRow(appointment: $0) }
                        Button(action: onOpenCalendar) { Label("Apri il calendario", systemImage: "arrow.right.circle") }
                            .frame(minHeight: 44)
                    }
                    Section("Pensieri recenti") {
                        if store.data.notes.isEmpty { Text("Fai spazio alla prossima idea.").foregroundStyle(.secondary) }
                        ForEach(Array(store.data.notes.sorted { $0.updatedAt > $1.updatedAt }.prefix(3))) { note in
                            Button { selectedNote = note } label: {
                                ThoughtRow(note: note)
                            }
                        }
                    }
                }
            }
            .navigationTitle("AG Life")
            .sensoryFeedback(.selection, trigger: editor) { _, newValue in newValue != nil }
            .sheet(item: $editor) { route in
                switch route {
                case .movement: MovementEditor()
                case .appointment: AppointmentEditor()
                case .note: NoteEditor()
                }
            }
            .sheet(item: $selectedNote) { NoteEditor(note: $0) }
        }
    }
}

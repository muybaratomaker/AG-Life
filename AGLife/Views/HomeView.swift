import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: LifeStore
    @State private var editor: EditorRoute?
    @State private var selectedNote: Note?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Date.now, format: .dateTime.month(.wide).year())
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Il tuo spazio, ogni giorno.").font(.largeTitle.bold())
                        Text("Spese, progetti e pensieri. Tutto qui.").foregroundStyle(.secondary)
                    }.padding(.vertical, 10)
                    HStack {
                        SummaryCard(title: "Uscite", amount: store.data.total(.expense, in: .now), symbol: "arrow.up.right")
                        SummaryCard(title: "Entrate", amount: store.data.total(.income, in: .now), symbol: "arrow.down.left")
                    }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    HStack {
                        Text("Saldo del mese")
                        Spacer()
                        Text(Money.display(store.data.total(.income, in: .now) - store.data.total(.expense, in: .now)))
                            .fontWeight(.semibold)
                    }
                }
                Section("Aggiungi al volo") {
                    Button { editor = .movement } label: { Label("Un movimento", systemImage: "plus.circle.fill") }
                    Button { editor = .appointment } label: { Label("Un impegno", systemImage: "calendar.badge.plus") }
                    Button { editor = .note } label: { Label("Un pensiero", systemImage: "square.and.pencil") }
                }
                Section("Prossimi impegni") {
                    let upcoming = store.data.appointments.filter { $0.date >= .now }.sorted { $0.date < $1.date }
                    if upcoming.isEmpty { Text("Nessun impegno in programma.").foregroundStyle(.secondary) }
                    ForEach(Array(upcoming.prefix(3))) { AppointmentRow(appointment: $0) }
                }
                Section("Note recenti") {
                    if store.data.notes.isEmpty { Text("Fai spazio alla prossima idea.").foregroundStyle(.secondary) }
                    ForEach(Array(store.data.notes.sorted { $0.updatedAt > $1.updatedAt }.prefix(3))) { note in
                        Button { selectedNote = note } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(note.title).font(.headline).foregroundStyle(.primary)
                                Text(note.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("AG Life")
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

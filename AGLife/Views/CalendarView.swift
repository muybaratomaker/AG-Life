import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var store: LifeStore
    @State private var selectedDate = Date.now
    @State private var adding = false
    @State private var editing: Appointment?
    @State private var deleting: Appointment?

    private var appointments: [Appointment] {
        store.data.appointments.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                LifeHeading(title: "Il tempo per ciò che conta.", subtitle: "Trova il tuo ritmo, un giorno alla volta.", area: .calendar, symbol: "calendar")
                    .lifeFloatingRow()
                Section {
                    DatePicker("Giorno", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                Section(selectedDate.formatted(date: .complete, time: .omitted)) {
                    if appointments.isEmpty {
                        LifeEmptyState(title: "Spazio per te", message: "Questo giorno è una pagina aperta. Scegli come viverlo.", symbol: "sun.horizon", area: .calendar)
                    }
                    ForEach(appointments) { appointment in
                        Button { editing = appointment } label: { LifeCard(area: .calendar) { AppointmentRow(appointment: appointment) } }
                            .buttonStyle(GentlePressStyle()).lifeFloatingRow()
                            .swipeActions {
                                Button("Elimina", role: .destructive) { deleting = appointment }
                            }
                    }
                }
            }
            .lifeList(area: .calendar)
            .navigationTitle("Calendario")
            .safeAreaInset(edge: .bottom) { AddBar(title: "Nuovo impegno", area: .calendar) { adding = true } }
            .sheet(isPresented: $adding) { AppointmentEditor(date: selectedDate) }
            .sheet(item: $editing) { AppointmentEditor(appointment: $0) }
            .confirmationDialog("Eliminare questo impegno?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    if let item = deleting { store.update { $0.appointments.removeAll { $0.id == item.id } } }
                    deleting = nil
                }
            }
        }
    }
}

struct AppointmentEditor: View {
    @EnvironmentObject private var store: LifeStore
    @Environment(\.dismiss) private var dismiss
    private let original: Appointment?
    @State private var title: String
    @State private var date: Date
    @State private var detail: String

    init(appointment: Appointment? = nil, date: Date = .now) {
        original = appointment
        _title = State(initialValue: appointment?.title ?? "")
        _date = State(initialValue: appointment?.date ?? date)
        _detail = State(initialValue: appointment?.detail ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LifeHeading(title: "Fai spazio a un impegno.", subtitle: "Un momento da segnare, un passo da fare.", area: .calendar, symbol: "calendar.badge.plus")
                    LifeField(title: "Il tuo impegno", symbol: "pencil.line", area: .calendar) {
                        TextField("Che cosa hai in programma?", text: $title, axis: .vertical)
                            .font(.system(.title3, design: .rounded, weight: .semibold)).lineLimit(1...3)
                            .accessibilityLabel("Titolo dell’impegno")
                    }
                    LifeField(title: "Data e ora", symbol: "clock", area: .calendar) {
                        DatePicker("Quando", selection: $date).datePickerStyle(.compact)
                    }
                    LifeField(title: "I dettagli", symbol: "text.alignleft", area: .calendar) {
                        TextField("Un luogo, un appunto, qualcosa da ricordare…", text: $detail, axis: .vertical)
                            .lineLimit(3...6).accessibilityLabel("Dettagli dell’impegno")
                    }
                    Text("Gli impegni restano in AG Life. Questa versione non invia notifiche e non accede al calendario di sistema.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }
            .scrollDismissesKeyboard(.interactively).background(LifeBackdrop(area: .calendar)).tint(LifeArea.calendar.accent)
            .navigationTitle(original == nil ? "Nuovo impegno" : "Modifica impegno")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { SaveErrorBanner() }
            .safeAreaInset(edge: .bottom) {
                LifeSaveBar(area: .calendar, enabled: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: save)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
        }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let item = Appointment(id: original?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), date: date,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines))
        if store.update({ data in
            data.appointments.removeAll { $0.id == item.id }
            data.appointments.append(item)
        }) { dismiss() }
    }
}

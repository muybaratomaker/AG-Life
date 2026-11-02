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
                Section {
                    DatePicker("Giorno", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                Section(selectedDate.formatted(date: .complete, time: .omitted)) {
                    if appointments.isEmpty {
                        ContentUnavailableView("Spazio per te", systemImage: "calendar",
                            description: Text("Nessun impegno per questo giorno."))
                    }
                    ForEach(appointments) { appointment in
                        Button { editing = appointment } label: { AppointmentRow(appointment: appointment) }
                            .tint(.primary)
                            .swipeActions {
                                Button("Elimina", role: .destructive) { deleting = appointment }
                            }
                    }
                }
            }
            .navigationTitle("Calendario")
            .safeAreaInset(edge: .bottom) { AddBar(title: "Nuovo impegno") { adding = true } }
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
            Form {
                TextField("Titolo dell’impegno", text: $title)
                DatePicker("Quando", selection: $date)
                Section("Dettagli") {
                    TextField("Luogo, promemoria o altri dettagli", text: $detail, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    Text("Gli impegni restano in AG Life. Questa versione non invia notifiche e non accede al calendario di sistema.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(original == nil ? "Nuovo impegno" : "Modifica impegno")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { SaveErrorBanner() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let item = Appointment(id: original?.id ?? UUID(),
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines), date: date,
                            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines))
                        if store.update({ data in
                            data.appointments.removeAll { $0.id == item.id }
                            data.appointments.append(item)
                        }) { dismiss() }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

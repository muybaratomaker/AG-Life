import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var store: LifeStore
    @EnvironmentObject private var notifications: NotificationService
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
                        Button { editing = appointment } label: {
                            LifeCard(area: .calendar) {
                                VStack(alignment: .leading, spacing: 10) {
                                    AppointmentRow(appointment: appointment)
                                    if let lead = appointment.reminder {
                                        Label(lead.label, systemImage: "bell").font(.caption).foregroundStyle(LifeArea.calendar.accent)
                                        Text(notifications.isSyncing ? "Verifica promemoria in corso…" :
                                            notifications.statuses[appointment.id] ?? "Stato da verificare nelle impostazioni")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
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
    @EnvironmentObject private var notifications: NotificationService
    @Environment(\.dismiss) private var dismiss
    private let original: Appointment?
    @State private var title: String
    @State private var date: Date
    @State private var detail: String
    @State private var reminderEnabled: Bool
    @State private var lead: ReminderLead
    @State private var explainingPermission = false

    init(appointment: Appointment? = nil, date: Date = .now) {
        original = appointment
        _title = State(initialValue: appointment?.title ?? "")
        _date = State(initialValue: appointment?.date ?? date)
        _detail = State(initialValue: appointment?.detail ?? "")
        _reminderEnabled = State(initialValue: appointment?.reminder != nil)
        _lead = State(initialValue: appointment?.reminder ?? .atTime)
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
                    LifeField(title: "Promemoria", symbol: "bell.badge", area: .calendar) {
                        Toggle("Avvisami", isOn: $reminderEnabled)
                        Text("AG Life usa notifiche locali per ricordarti questo impegno. Il permesso è facoltativo; puoi salvare l’impegno anche senza autorizzarlo.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if reminderEnabled {
                            Picker("Quando avvisarti", selection: $lead) {
                                ForEach(ReminderLead.allCases) { Text($0.label).tag($0) }
                            }.pickerStyle(.menu)
                            if date.addingTimeInterval(-Double(lead.rawValue)) <= .now {
                                Text("L’orario dell’avviso è già trascorso: l’impegno sarà salvato senza programmare una notifica.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Text("Permesso: \(notifications.authorization). La consegna in LiveContainer va verificata con il test nelle Impostazioni.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Text("Gli impegni restano in AG Life e non accedono al calendario di sistema.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }
            .scrollDismissesKeyboard(.interactively).background(LifeBackdrop(area: .calendar)).tint(LifeArea.calendar.accent)
            .navigationTitle(original == nil ? "Nuovo impegno" : "Modifica impegno")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { SaveErrorBanner() }
            .onChange(of: reminderEnabled) { _, enabled in
                guard enabled else { return }
                Task {
                    if await notifications.needsPermission() { explainingPermission = true }
                    else { await notifications.requestPermission() }
                }
            }
            .alert("Un promemoria per i tuoi impegni", isPresented: $explainingPermission) {
                Button("Non ora", role: .cancel) { reminderEnabled = false }
                Button("Continua") { Task { await notifications.requestPermission() } }
            } message: {
                Text("AG Life chiederà a iOS il permesso di mostrare avvisi locali e riprodurre un suono. Se neghi il permesso, l’impegno resta salvabile senza un avviso programmato.")
            }
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
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines), reminder: reminderEnabled ? lead : nil)
        if store.update({ data in
            data.appointments.removeAll { $0.id == item.id }
            data.appointments.append(item)
        }) { dismiss() }
    }
}

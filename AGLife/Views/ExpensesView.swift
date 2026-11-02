import SwiftUI

struct ExpensesView: View {
    @EnvironmentObject private var store: LifeStore
    @State private var month = Date.now
    @State private var adding = false
    @State private var editing: Movement?
    @State private var deleting: Movement?

    private var movements: [Movement] {
        store.data.movements.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").padding(8) }
                            .accessibilityLabel("Mese precedente")
                        Spacer()
                        Text(month, format: .dateTime.month(.wide).year()).font(.headline)
                        Spacer()
                        Button { moveMonth(1) } label: { Image(systemName: "chevron.right").padding(8) }
                            .accessibilityLabel("Mese successivo")
                    }.buttonStyle(.borderless)
                    LabeledContent("Uscite", value: Money.display(store.data.total(.expense, in: month)))
                    LabeledContent("Entrate", value: Money.display(store.data.total(.income, in: month)))
                }
                Section("Movimenti") {
                    if movements.isEmpty {
                        ContentUnavailableView("Un mese da scrivere", systemImage: "creditcard",
                            description: Text("Aggiungi la tua prima entrata o uscita."))
                    }
                    ForEach(movements) { movement in
                        Button { editing = movement } label: { MovementRow(movement: movement) }.tint(.primary)
                            .swipeActions {
                                Button("Elimina", role: .destructive) { deleting = movement }
                            }
                    }
                }
            }
            .navigationTitle("Spese")
            .safeAreaInset(edge: .bottom) { AddBar(title: "Nuovo movimento") { adding = true } }
            .sheet(isPresented: $adding) { MovementEditor() }
            .sheet(item: $editing) { MovementEditor(movement: $0) }
            .confirmationDialog("Eliminare questo movimento?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    if let item = deleting { store.update { $0.movements.removeAll { $0.id == item.id } } }
                    deleting = nil
                }
            }
        }
    }

    private func moveMonth(_ value: Int) {
        // Normalize before adding a month (e.g. January 31 -> February, not March).
        let start = Calendar.current.dateInterval(of: .month, for: month)?.start ?? month
        month = Calendar.current.date(byAdding: .month, value: value, to: start) ?? start
    }
}

struct MovementEditor: View {
    @EnvironmentObject private var store: LifeStore
    @Environment(\.dismiss) private var dismiss
    private let original: Movement?
    @State private var kind: MovementKind
    @State private var amount: String
    @State private var category: Category
    @State private var detail: String
    @State private var date: Date

    init(movement: Movement? = nil) {
        original = movement
        _kind = State(initialValue: movement?.kind ?? .expense)
        _amount = State(initialValue: movement.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "")
        _category = State(initialValue: movement?.category ?? .other)
        _detail = State(initialValue: movement?.detail ?? "")
        _date = State(initialValue: movement?.date ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $kind) {
                        ForEach(MovementKind.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    TextField("Importo in euro", text: $amount).keyboardType(.decimalPad)
                    if !amount.isEmpty && Money.parse(amount) == nil {
                        Text("Inserisci un importo positivo con massimo due decimali, senza separatori delle migliaia.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Categoria", selection: $category) {
                        ForEach(Category.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Descrizione", text: $detail, axis: .vertical).lineLimit(2...4)
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle(original == nil ? "Nuovo movimento" : "Modifica movimento")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { SaveErrorBanner() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }.disabled(Money.parse(amount) == nil)
                }
            }
        }
    }

    private func save() {
        guard let value = Money.parse(amount) else { return }
        let item = Movement(id: original?.id ?? UUID(), kind: kind, amount: value, category: category,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines), date: date)
        if store.update({ data in
            data.movements.removeAll { $0.id == item.id }
            data.movements.append(item)
        }) { dismiss() }
    }
}

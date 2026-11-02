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
                LifeHeading(title: "Ogni scelta conta.", subtitle: "Una visione chiara del tuo mese.", symbol: "creditcard.fill")
                .lifeFloatingRow()
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
                    SummaryCard(title: "Uscite del mese", amount: store.data.total(.expense, in: month), symbol: "arrow.up.right")
                    SummaryCard(title: "Entrate del mese", amount: store.data.total(.income, in: month), symbol: "arrow.down.left")
                }
                Section("Movimenti") {
                    if movements.isEmpty {
                        LifeEmptyState(title: "Un mese da scrivere", message: "Ogni piccolo movimento racconta la tua giornata.", symbol: "creditcard")
                    }
                    ForEach(movements) { movement in
                        Button { editing = movement } label: {
                            LifeCard { MovementRow(movement: movement) }
                        }.buttonStyle(GentlePressStyle()).lifeFloatingRow()
                        .swipeActions {
                            Button("Elimina", role: .destructive) { deleting = movement }
                        }
                    }
                }
            }
            .lifeList(area: .spending)
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
    @FocusState private var amountFocused: Bool

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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LifeHeading(title: "Dai valore alle tue scelte.", subtitle: "Un movimento, tutto sotto controllo.", symbol: "creditcard.fill")
                    LifeField(title: "Movimento", symbol: "arrow.left.arrow.right") {
                        Picker("Tipo", selection: $kind) {
                            ForEach(MovementKind.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    LifeField(title: "Importo in euro", symbol: "eurosign.circle") {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("€").font(.title).foregroundStyle(LifeArea.spending.accent).accessibilityHidden(true)
                            TextField("0,00", text: $amount).keyboardType(.decimalPad).focused($amountFocused)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .accessibilityLabel("Importo in euro")
                        }
                        if !amount.isEmpty && Money.parse(amount) == nil {
                            Text("Inserisci un importo positivo con massimo due decimali, senza separatori delle migliaia.")
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LifeField(title: "Categoria", symbol: category.symbol) {
                        Picker("Categoria", selection: $category) {
                            ForEach(Category.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                        }.pickerStyle(.menu)
                    }
                    LifeField(title: "Descrizione", symbol: "text.alignleft") {
                        TextField("A cosa si riferisce?", text: $detail, axis: .vertical).lineLimit(2...4)
                        .accessibilityLabel("Descrizione")
                    }
                    LifeField(title: "Quando", symbol: "calendar") {
                        DatePicker("Data", selection: $date, displayedComponents: .date).datePickerStyle(.compact)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively).background(LifeBackdrop()).tint(LifeArea.spending.accent)
            .navigationTitle(original == nil ? "Nuovo movimento" : "Modifica movimento")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { SaveErrorBanner() }
            .safeAreaInset(edge: .bottom) { LifeSaveBar(area: .spending, enabled: Money.parse(amount) != nil, action: save) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    if amountFocused {
                        Spacer()
                        Button("Fine") { amountFocused = false }
                    }
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

import SwiftUI

struct HomeView: View {
    var onOpenCalendar: () -> Void = {}
    @EnvironmentObject private var store: LifeStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editor: EditorRoute?
    @State private var selectedNote: Note?
    @State private var showingSettings = false

    private var cardLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header(at: context.date)
                        balance(at: context.date)
                        quickActions
                        agenda(at: context.date)
                        thoughts
                    }.padding(20).padding(.bottom, 12)
                }.background(LifeBackdrop())
            }
            .navigationTitle("AG Life").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Impostazioni")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
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

    private func header(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(date.formatted(.dateTime.weekday(.wide).day().month(.wide)), systemImage: "sun.max.fill")
                .font(.subheadline.weight(.medium)).foregroundStyle(LifeArea.spending.accent)
            Text("La vita,\na modo tuo.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-0.8)
            Text("Un po’ di ordine. Più spazio per te.").font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func balance(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("IL TUO MESE").font(.caption.weight(.bold)).tracking(2)
                        Text(date, format: .dateTime.month(.wide).year()).font(.subheadline)
                    }
                    Spacer()
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.title2).accessibilityHidden(true)
                }.foregroundStyle(.white.opacity(0.85))
                Text(Money.display(store.data.total(.income, in: date) - store.data.total(.expense, in: date)))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(.white)
                Text("Saldo del mese").font(.subheadline).foregroundStyle(.white.opacity(0.9))
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [LifeArea.spending.ink, Color(red: 0.10, green: 0.30, blue: 0.46)],
                startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 30))
            cardLayout {
                SummaryCard(title: "Uscite", amount: store.data.total(.expense, in: date), symbol: "arrow.up.right")
                SummaryCard(title: "Entrate", amount: store.data.total(.income, in: date), symbol: "arrow.down.left")
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Fai spazio alla giornata", caption: "AGGIUNGI AL VOLO")
            cardLayout {
                QuickActionCard(title: "Spese", subtitle: "Entrate e uscite", symbol: "creditcard.fill", color: LifeArea.spending.accent) {
                    editor = .movement
                }
                QuickActionCard(title: "Impegni", subtitle: "Il tuo prossimo passo", symbol: "calendar", color: LifeArea.calendar.accent) {
                    editor = .appointment
                }
            }
            QuickActionCard(title: "Un pensiero", subtitle: "Le idee belle iniziano qui",
                symbol: "square.and.pencil", color: LifeArea.thoughts.accent, wide: true) { editor = .note }
        }
    }

    private func agenda(at date: Date) -> some View {
        let summary = store.data.agenda(at: date)
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Il ritmo di oggi", caption: "LA TUA AGENDA")
            LifeCard(area: .calendar) {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Oggi · \(summary.todayCount) impegni", systemImage: "sun.horizon")
                        .font(.headline).foregroundStyle(LifeArea.calendar.accent)
                    if summary.today.isEmpty {
                        Text("Nessun impegno oggi. Respira, c’è spazio per te.").foregroundStyle(.secondary).font(.subheadline)
                    }
                    ForEach(summary.today) { appointment in
                        VStack(alignment: .leading, spacing: 4) {
                            AppointmentRow(appointment: appointment)
                            if appointment.date < date {
                                Text("Già iniziato").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if summary.todayCount > summary.today.count {
                        Text("Altri \(summary.todayCount - summary.today.count) impegni nel calendario")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider().overlay(LifeArea.calendar.accent.opacity(0.1))
                    Text("Nei prossimi 7 giorni").font(.subheadline.weight(.semibold))
                    if summary.upcoming.isEmpty { Text("Nessun impegno imminente.").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(summary.upcoming) { AppointmentRow(appointment: $0) }
                    Button(action: onOpenCalendar) {
                        Label("Tutta la tua agenda", systemImage: "arrow.right.circle.fill")
                            .font(.headline).frame(minHeight: 44)
                    }.tint(LifeArea.calendar.accent)
                }
            }
        }
    }

    private var thoughts: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Da tenere con te", caption: "PENSIERI RECENTI")
            if store.data.notes.isEmpty {
                LifeCard(area: .thoughts) {
                    LifeEmptyState(title: "Una pagina tutta tua", message: "Idee, parole, piccoli momenti. Inizia da un pensiero.",
                        symbol: "sparkles", area: .thoughts)
                }
            }
            if store.data.notes.contains(where: \.isPinned) {
                Label("Fissati in alto", systemImage: "pin.fill").font(.headline).foregroundStyle(LifeArea.thoughts.accent)
                ForEach(Array(store.data.notes.filter(\.isPinned).sorted { $0.updatedAt > $1.updatedAt }.prefix(3))) { note in
                    Button { selectedNote = note } label: { ThoughtRow(note: note) }
                        .buttonStyle(GentlePressStyle()).contextMenu { ThoughtActions(note: note) }
                }
                Text("Tutti i pensieri fissati sono nella scheda Pensieri.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(store.data.notes.filter { !$0.isPinned }.sorted { $0.updatedAt > $1.updatedAt }.prefix(3))) { note in
                Button { selectedNote = note } label: { ThoughtRow(note: note) }
                    .buttonStyle(GentlePressStyle()).contextMenu { ThoughtActions(note: note) }
            }
        }
    }

    private func sectionTitle(_ title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption).font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.secondary)
            Text(title).font(.system(.title3, design: .rounded, weight: .bold))
        }
    }
}

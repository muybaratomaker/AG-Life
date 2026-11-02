import SwiftUI

struct NotesView: View {
    @EnvironmentObject private var store: LifeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var adding = false
    @State private var editing: Note?
    @State private var deleting: Note?
    @State private var search = ""

    private var notes: [Note] {
        store.data.notes.filter {
            search.isEmpty || $0.body.localizedCaseInsensitiveContains(search)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                LifeHeading(title: "Le parole, il tuo spazio.", subtitle: "Tieni vicine le idee che ti somigliano.", area: .thoughts, symbol: "quote.bubble.fill")
                .lifeFloatingRow()
                if notes.isEmpty {
                    LifeEmptyState(title: search.isEmpty ? "Raccogli le tue idee" : "Nessun pensiero trovato",
                    message: search.isEmpty ? "Non serve un titolo. Solo un momento per te." : "Prova con un’altra parola.",
                    symbol: "sparkles", area: .thoughts).lifeFloatingRow()
                }
                ForEach(notes) { note in
                    Button { editing = note } label: {
                        ThoughtRow(note: note)
                    }.buttonStyle(GentlePressStyle()).lifeFloatingRow()
                    .swipeActions { Button("Elimina", role: .destructive) { deleting = note } }
                }
            }
            .lifeList(area: .thoughts)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: notes)
            .navigationTitle("Pensieri")
            .searchable(text: $search, prompt: "Cerca nei tuoi pensieri")
            .safeAreaInset(edge: .bottom) { AddBar(title: "Nuovo pensiero", area: .thoughts) { adding = true } }
            .sensoryFeedback(.selection, trigger: adding) { _, newValue in newValue }
            .sheet(isPresented: $adding) { NoteEditor() }
            .sheet(item: $editing) { NoteEditor(note: $0) }
            .confirmationDialog("Eliminare questo pensiero?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    if let item = deleting { store.update { $0.notes.removeAll { $0.id == item.id } } }
                    deleting = nil
                }
            }
        }
    }
}

struct NoteEditor: View {
    @EnvironmentObject private var store: LifeStore
    @Environment(\.dismiss) private var dismiss
    private let original: Note?
    @State private var bodyText: String
    @FocusState private var textFocused: Bool

    init(note: Note? = nil) {
        original = note
        _bodyText = State(initialValue: note?.body ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LifeHeading(title: "Lascia scorrere le idee.", subtitle: "Uno spazio tutto tuo, senza fretta.", area: .thoughts, symbol: "square.and.pencil")
                    LifeField(title: "Il tuo pensiero", symbol: "quote.opening", area: .thoughts) {
                        ZStack(alignment: .topLeading) {
                            if bodyText.isEmpty {
                                Text("Cosa hai in mente?").foregroundStyle(.secondary)
                                .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                                .accessibilityHidden(true)
                            }
                            TextEditor(text: $bodyText).scrollContentBackground(.hidden)
                            .font(.system(.body, design: .rounded)).lineSpacing(6)
                            .frame(minHeight: 300).focused($textFocused)
                            .accessibilityLabel("Testo del pensiero")
                        }
                    }
                    if let original {
                        Text("Ultima modifica: \(original.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively).background(LifeBackdrop(area: .thoughts)).tint(LifeArea.thoughts.accent)
            .navigationTitle(original == nil ? "Nuovo pensiero" : "Modifica pensiero")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { SaveErrorBanner() }
            .safeAreaInset(edge: .bottom) {
                LifeSaveBar(area: .thoughts, enabled: !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: save)
            }
            .task {
                guard original == nil else { return }
                // Wait for the sheet presentation before requesting the keyboard.
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                textFocused = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
        }
    }

    private func save() {
        guard !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let item = Note(id: original?.id ?? UUID(), body: bodyText, updatedAt: .now)
        if store.update({ data in
            data.notes.removeAll { $0.id == item.id }
            data.notes.append(item)
        }) { dismiss() }
    }
}

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
                if notes.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "Raccogli le tue idee" : "Nessun pensiero trovato",
                        systemImage: "note.text", description: Text("Un pensiero oggi, un’idea per domani."))
                }
                ForEach(notes) { note in
                    Button { editing = note } label: {
                        ThoughtRow(note: note)
                    }
                    .swipeActions { Button("Elimina", role: .destructive) { deleting = note } }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: notes)
            .navigationTitle("Pensieri")
            .searchable(text: $search, prompt: "Cerca nei tuoi pensieri")
            .safeAreaInset(edge: .bottom) { AddBar(title: "Nuovo pensiero") { adding = true } }
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
            Form {
                Section("Il tuo pensiero") {
                    ZStack(alignment: .topLeading) {
                        if bodyText.isEmpty {
                            Text("Cosa hai in mente?").foregroundStyle(.secondary)
                                .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        TextEditor(text: $bodyText).scrollContentBackground(.hidden)
                            .frame(minHeight: 280).focused($textFocused)
                            .accessibilityLabel("Testo del pensiero")
                    }
                }
            }
            .navigationTitle(original == nil ? "Nuovo pensiero" : "Modifica pensiero")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { SaveErrorBanner() }
            .task {
                guard original == nil else { return }
                // Wait for the sheet presentation before requesting the keyboard.
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                textFocused = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let item = Note(id: original?.id ?? UUID(),
                            body: bodyText, updatedAt: .now)
                        if store.update({ data in
                            data.notes.removeAll { $0.id == item.id }
                            data.notes.append(item)
                        }) { dismiss() }
                    }.disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

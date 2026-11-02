import SwiftUI

struct NotesView: View {
    @EnvironmentObject private var store: LifeStore
    @State private var adding = false
    @State private var editing: Note?
    @State private var deleting: Note?
    @State private var search = ""

    private var notes: [Note] {
        store.data.notes.filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                if notes.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "Raccogli le tue idee" : "Nessuna nota trovata",
                        systemImage: "note.text", description: Text("Un pensiero oggi, un’idea per domani."))
                }
                ForEach(notes) { note in
                    Button { editing = note } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(note.title).font(.headline).foregroundStyle(.primary)
                            if !note.body.isEmpty {
                                Text(note.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                            }
                            Text(note.updatedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                                .font(.caption).foregroundStyle(.tertiary)
                        }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .swipeActions { Button("Elimina", role: .destructive) { deleting = note } }
                }
            }
            .navigationTitle("Note")
            .searchable(text: $search, prompt: "Cerca nei tuoi pensieri")
            .safeAreaInset(edge: .bottom) { AddBar(title: "Nuova nota") { adding = true } }
            .sheet(isPresented: $adding) { NoteEditor() }
            .sheet(item: $editing) { NoteEditor(note: $0) }
            .confirmationDialog("Eliminare questa nota?", isPresented: Binding(
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
    @State private var title: String
    @State private var bodyText: String

    init(note: Note? = nil) {
        original = note
        _title = State(initialValue: note?.title ?? "")
        _bodyText = State(initialValue: note?.body ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titolo", text: $title).font(.title3.bold())
                Section("La tua nota") {
                    TextEditor(text: $bodyText).frame(minHeight: 260).accessibilityLabel("Testo della nota")
                }
            }
            .navigationTitle(original == nil ? "Nuova nota" : "Modifica nota")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { SaveErrorBanner() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let item = Note(id: original?.id ?? UUID(),
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines), updatedAt: .now)
                        if store.update({ data in
                            data.notes.removeAll { $0.id == item.id }
                            data.notes.append(item)
                        }) { dismiss() }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

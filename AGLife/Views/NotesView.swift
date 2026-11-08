import SwiftUI

struct NotesView: View {
    @EnvironmentObject private var store: LifeStore
    @EnvironmentObject private var appleReminders: AppleReminders
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
                if notes.contains(where: \.isPinned) {
                    Section { ForEach(notes.filter(\.isPinned)) { thought($0) } } header: {
                        Label("Fissati in alto", systemImage: "pin.fill").foregroundStyle(LifeArea.thoughts.accent)
                    }
                }
                if notes.contains(where: { !$0.isPinned }) {
                    Section("I tuoi pensieri") { ForEach(notes.filter { !$0.isPinned }) { thought($0) } }
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
            ), titleVisibility: .visible, presenting: deleting) { item in
                if item.appleReminder != nil {
                    Button("Elimina anche da Promemoria Apple", role: .destructive) {
                        appleReminders.delete(item.id, includingApple: true, in: store)
                    }
                    .disabled(item.appleReminder?.identifier == nil)
                    Button("Elimina il pensiero e conserva il promemoria", role: .destructive) {
                        appleReminders.delete(item.id, includingApple: false, in: store)
                    }
                } else {
                    Button("Elimina", role: .destructive) {
                        appleReminders.delete(item.id, includingApple: false, in: store)
                    }
                }
                Button("Annulla", role: .cancel) {}
            }
        }
    }

    private func thought(_ note: Note) -> some View {
        Button { editing = note } label: { ThoughtRow(note: note) }
            .buttonStyle(GentlePressStyle()).lifeFloatingRow()
            .contextMenu { ThoughtActions(note: note) }
            .accessibilityAction(named: note.isPinned ? "Rimuovi dai fissati" : "Fissa in alto") {
                store.update { data in
                    if let index = data.notes.firstIndex(where: { $0.id == note.id }) { data.notes[index].isPinned.toggle() }
                }
            }
            .swipeActions(allowsFullSwipe: false) {
                Button("Elimina", role: .destructive) { deleting = note }
                    .disabled(appleReminders.creating.contains(note.id))
            }
    }
}

struct NoteEditor: View {
    @EnvironmentObject private var store: LifeStore
    @EnvironmentObject private var appleReminders: AppleReminders
    @Environment(\.dismiss) private var dismiss
    private let original: Note?
    @State private var bodyText: String
    @State private var addToApple = false
    @State private var isSaving = false
    @State private var keepAppleLink: Bool
    @FocusState private var textFocused: Bool

    init(note: Note? = nil) {
        original = note
        _bodyText = State(initialValue: note?.body ?? "")
        _keepAppleLink = State(initialValue: note?.appleReminder != nil)
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
                    if original == nil {
                        LifeField(title: "Promemoria Apple", symbol: "checklist", area: .thoughts) {
                            Toggle("Aggiungi a Promemoria Apple", isOn: $addToApple)
                        }
                    } else if original?.appleReminder != nil {
                        LifeField(title: "Promemoria Apple", symbol: "checklist", area: .thoughts) {
                            Toggle("Mantieni il collegamento", isOn: $keepAppleLink)
                            Text("Disattivando il collegamento, il promemoria resta nell’app Apple.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively).background(LifeBackdrop(area: .thoughts)).tint(LifeArea.thoughts.accent)
            .navigationTitle(original == nil ? "Nuovo pensiero" : "Modifica pensiero")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { SaveErrorBanner() }
            .safeAreaInset(edge: .bottom) {
                LifeSaveBar(area: .thoughts, enabled: !isSaving && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: save)
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
        guard !isSaving, !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSaving = true
        SaveTrace.record("1 · Inizio salvataggio locale")
        let current = store.data.notes.first(where: { $0.id == original?.id })
        if let original, current?.body != original.body {
            store.errorMessage = "Il pensiero è cambiato mentre era aperto. Riaprilo per modificare il testo più recente."
            isSaving = false
            return
        }
        var item = Note(id: original?.id ?? UUID(), body: bodyText, updatedAt: .now, isPinned: current?.isPinned ?? false)
        item.appleReminder = keepAppleLink ? current?.appleReminder : nil
        if store.update({ data in
            data.notes.removeAll { $0.id == item.id }
            data.notes.append(item)
        }) {
            SaveTrace.record("2 · Pensiero salvato localmente")
            let service = appleReminders
            let localStore = store
            let id = item.id
            let shouldCreate = addToApple
            let shouldSync = item.appleReminder != nil
            let shouldClear = !keepAppleLink && current?.appleReminder != nil
            textFocused = false
            dismiss()
            // Run Apple work after committing local data and leaving the editor's save callback.
            Task { @MainActor in
                await Task.yield()
                if shouldCreate {
                    await service.create(for: id, in: localStore)
                } else if shouldClear {
                    service.clearIssue(for: id)
                } else if shouldSync {
                    service.synchronize(localStore)
                }
            }
        } else {
            SaveTrace.record("Errore · Salvataggio locale non riuscito")
            isSaving = false
        }
    }
}

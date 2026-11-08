import SwiftUI

struct AppleListRecoveryView: View {
    @EnvironmentObject private var appleReminders: AppleReminders
    @State private var selection: String?
    @State private var confirmingCreation = false

    var body: some View {
        LifeCard(area: .thoughts) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Lista Promemoria Apple").font(.headline)
                Text("Cerca la lista AG Life e conferma l’account da utilizzare per i nuovi pensieri.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Cerca liste") {
                    selection = nil
                    appleReminders.scanLists()
                }.buttonStyle(.bordered)
                Text(appleReminders.listReport).font(.footnote).foregroundStyle(.secondary)
                ForEach(appleReminders.listChoices) { list in
                    Button {
                        selection = list.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("AG Life").font(.headline)
                                Text(list.account).font(.caption)
                            }
                            Spacer()
                            Image(systemName: selection == list.id ? "checkmark.circle.fill" : "circle")
                        }.padding(.vertical, 8)
                    }.buttonStyle(.plain)
                    .accessibilityLabel("Seleziona AG Life, " + list.account)
                }
                if let selection {
                    LifePrimaryButton(title: "Ricollega la lista selezionata", area: .thoughts) {
                        appleReminders.selectList(selection)
                        self.selection = nil
                    }
                }
                if appleReminders.canCreateList {
                    Button("Crea una nuova lista AG Life") { confirmingCreation = true }
                        .buttonStyle(.bordered)
                }
            }
        }
        .confirmationDialog("Creare una nuova lista AG Life nell’account predefinito?", isPresented: $confirmingCreation, titleVisibility: .visible) {
            Button("Crea lista") { appleReminders.createListExplicitly() }
            Button("Annulla", role: .cancel) {}
        }
    }
}

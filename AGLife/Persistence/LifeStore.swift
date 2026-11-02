import SwiftUI

@MainActor
final class LifeStore: ObservableObject {
    @Published private(set) var data = LifeData()
    @Published private(set) var isReady = false
    @Published var errorMessage: String?
    private var archive: LocalArchive?

    init() { reload() }

    func reload() {
        do {
            let storage = try LocalArchive.applicationArchive()
            data = try storage.load()
            archive = storage
            isReady = true
            errorMessage = nil
        } catch {
            isReady = false
            errorMessage = "Impossibile aprire i dati. L’archivio esistente è stato conservato. \(error.localizedDescription)"
        }
    }

    // Publish only after a successful atomic write, so a failed save never looks successful.
    @discardableResult
    func update(_ change: (inout LifeData) -> Void) -> Bool {
        guard isReady, let archive else { return false }
        var next = data
        change(&next)
        do {
            try archive.save(next)
            data = next
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Salvataggio non riuscito. Riprova: le modifiche non sono state applicate. \(error.localizedDescription)"
            return false
        }
    }
}

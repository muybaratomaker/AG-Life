import Foundation

// Temporary diagnostic: fixed phase labels only, never thought text, account names or IDs.
enum SaveTrace {
    static let key = "Diagnostics.lastSavePhase"
    static func record(_ phase: String) {
        UserDefaults.standard.set(phase, forKey: key)
    }
}

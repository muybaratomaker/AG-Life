import SwiftUI
import UserNotifications

// One owner and one serial reconciliation worker. No push registration or background service.
@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var authorization = "Da verificare"
    @Published private(set) var statuses: [UUID: String] = [:]
    @Published private(set) var isSyncing = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var isTesting = false
    @Published var notice: String?
    @Published private(set) var testResult: String?
    private let center = UNUserNotificationCenter.current()
    private let prefix = "com.aglife.personal.reminder."
    private let testIdentifier = "com.aglife.personal.notification-test"
    private var desired: [Appointment]?
    private var worker: Task<Void, Never>?
    private var permissionTask: Task<Bool, Never>?

    override init() {
        super.init()
        center.delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    @discardableResult
    func needsPermission() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .notDetermined
    }

    @discardableResult
    func requestPermission() async -> Bool {
        if let permissionTask { return await permissionTask.value }
        let task = Task { @MainActor in
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
                catch { notice = "Richiesta permesso non riuscita: \(error.localizedDescription)" }
            }
            let updated = await center.notificationSettings()
            updateAuthorization(updated)
            let allowed = permitsNotifications(updated)
            if !allowed {
                notice = "Notifiche non autorizzate. L’impegno può essere salvato; il promemoria non è programmato. Controlla i permessi iOS e LiveContainer."
            }
            return allowed
        }
        permissionTask = task
        let allowed = await task.value
        permissionTask = nil
        return allowed
    }

    func synchronize(_ appointments: [Appointment]) {
        desired = appointments
        notice = nil
        // Clear previously confirmed states immediately when a newer snapshot is requested.
        statuses = [:]
        isSyncing = true
        guard worker == nil else { return }
        worker = Task {
            while let snapshot = desired {
                desired = nil
                await reconcile(snapshot)
            }
            isSyncing = false
            worker = nil
        }
    }

    private func reconcile(_ appointments: [Appointment]) async {
        let settings = await center.notificationSettings()
        updateAuthorization(settings)
        let allowed = permitsNotifications(settings)
        let pending = await center.pendingNotificationRequests()
        let future = appointments.filter { $0.futureReminderDate(after: .now) != nil }
            .sorted { $0.reminderDate! < $1.reminderDate! }
        // Leave room for the test and any unrelated requests; never remove host/other-app requests.
        let foreignCount = pending.filter { !$0.identifier.hasPrefix(prefix) }.count
        let capacity = max(0, min(60, 63 - foreignCount))
        let selected = allowed ? Array(future.prefix(capacity)) : []
        let wanted = Set(selected.map(\.notificationIdentifier))
        let obsolete = pending.filter { $0.identifier.hasPrefix(prefix) && !wanted.contains($0.identifier) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        var result: [UUID: String] = [:]
        for item in appointments where item.reminder != nil {
            if item.futureReminderDate(after: .now) == nil {
                result[item.id] = "Non programmato: orario dell’avviso già trascorso"
            } else if !allowed {
                result[item.id] = "Non programmato: notifiche non autorizzate"
            } else if !wanted.contains(item.notificationIdentifier) {
                result[item.id] = "Non programmato: limite di notifiche raggiunto"
            }
        }
        for item in selected {
            if desired != nil { return }
            guard let fireDate = item.futureReminderDate(after: .now) else {
                center.removePendingNotificationRequests(withIdentifiers: [item.notificationIdentifier])
                result[item.id] = "Non programmato: orario dell’avviso già trascorso"
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = "AG Life · Un impegno per te"
            content.body = item.title
            content.sound = .default
            let interval = fireDate.timeIntervalSinceNow
            guard interval >= 1 else {
                center.removePendingNotificationRequests(withIdentifiers: [item.notificationIdentifier])
                result[item.id] = "Non programmato: orario dell’avviso troppo vicino o trascorso"
                continue
            }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            do {
                // Reusing the stable identifier replaces an earlier request instead of duplicating it.
                try await center.add(UNNotificationRequest(identifier: item.notificationIdentifier, content: content, trigger: trigger))
                result[item.id] = "In verifica"
            } catch {
                center.removePendingNotificationRequests(withIdentifiers: [item.notificationIdentifier])
                result[item.id] = "Non programmato: \(error.localizedDescription)"
            }
        }
        let verified = await center.pendingNotificationRequests()
        let verifiedIDs = Set(verified.map(\.identifier))
        for item in selected where result[item.id] == "In verifica" {
            result[item.id] = verifiedIDs.contains(item.notificationIdentifier)
                ? "Richiesta accettata da iOS" : "Non confermato tra le notifiche in attesa"
        }
        // A queued edit/delete will be reconciled before exposing any final status.
        if desired == nil {
            statuses = result
            pendingCount = verified.filter { $0.identifier.hasPrefix(prefix) }.count
            if result.values.contains(where: { $0 != "Richiesta accettata da iOS" }) {
                notice = "Alcuni promemoria non sono programmati o confermati. Gli impegni sono salvati: controlla il loro stato nel Calendario."
            }
        }
    }

    func sendTest() async {
        guard !isTesting else { return }
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        guard await requestPermission() else {
            testResult = "Test non programmato: permesso non disponibile."
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "AG Life · Prova notifiche"
        content.body = "Se leggi questo messaggio, la notifica di prova è arrivata."
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: testIdentifier, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)))
            let pending = await center.pendingNotificationRequests()
            testResult = pending.contains { $0.identifier == testIdentifier }
                ? "Richiesta di prova accettata: attesa circa 10 secondi. La ricezione va verificata sul dispositivo."
                : "Test non confermato tra le notifiche in attesa. Controlla LiveContainer."
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: [testIdentifier])
            testResult = "Test non programmato: \(error.localizedDescription)"
        }
    }

    private func permitsNotifications(_ settings: UNNotificationSettings) -> Bool {
        [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
    }

    private func updateAuthorization(_ settings: UNNotificationSettings) {
        switch settings.authorizationStatus {
        case .notDetermined: authorization = "Non ancora richiesto"
        case .denied: authorization = "Non autorizzate"
        case .authorized: authorization = "Autorizzate"
        case .provisional: authorization = "Autorizzazione provvisoria"
        case .ephemeral: authorization = "Autorizzazione temporanea"
        @unknown default: authorization = "Stato non riconosciuto"
        }
        if permitsNotifications(settings), settings.alertSetting == .disabled {
            authorization += " · avvisi disattivati"
        }
    }
}

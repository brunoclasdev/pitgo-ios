//
//  GuinchoIncomingAlertNotifier.swift
//  pitgo
//
//  Notificação local genérica para ofertas pagas quando a sessão iOS ainda recebe atualizações em
//  background (normalmente pelo tracking de localização já autorizado). O servidor continua sendo
//  a autoridade; tocar na notificação apenas abre o app, que recupera o snapshot vigente.
//

import UIKit
import UserNotifications

@MainActor
final class GuinchoIncomingAlertNotifier {
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let deliveredDeadlinesKey = "pitgo.guincho.incoming-notification-deadlines"

    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func notifyIfNeeded(providerID: UUID, appointmentID: UUID, deadline: Date?) async {
        guard UIApplication.shared.applicationState == .background else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        var posted = storedDeadlines()
        posted = posted.filter { $0.value > Date().timeIntervalSince1970 }
        let key = "\(providerID.uuidString).\(appointmentID.uuidString)"
        guard posted[key] == nil else { return }

        let content = UNMutableNotificationContent()
        content.title = "Nova solicitação de guincho"
        content.body = "Abra o PitGo para consultar e responder."
        content.sound = .default
        content.userInfo = ["provider_id": providerID.uuidString, "appointment_id": appointmentID.uuidString]

        let identifier = notificationID(providerID: providerID, appointmentID: appointmentID)
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            posted[key] = (deadline ?? Date().addingTimeInterval(60)).timeIntervalSince1970
            defaults.set(posted, forKey: deliveredDeadlinesKey)
        } catch {
            // A card in foreground remains the primary alert; notification failure must not affect
            // dispatch or persist a marker that would suppress a later retry.
        }
    }

    func clear(providerID: UUID, appointmentID: UUID) async {
        let id = notificationID(providerID: providerID, appointmentID: appointmentID)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
        var posted = storedDeadlines()
        posted.removeValue(forKey: "\(providerID.uuidString).\(appointmentID.uuidString)")
        defaults.set(posted, forKey: deliveredDeadlinesKey)
    }

    func removeVisibleNotifications(providerID: UUID) async {
        let prefix = "pitgo.guincho.\(providerID.uuidString)."
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    private func notificationID(providerID: UUID, appointmentID: UUID) -> String {
        "pitgo.guincho.\(providerID.uuidString).\(appointmentID.uuidString)"
    }

    private func storedDeadlines() -> [String: Double] {
        defaults.dictionary(forKey: deliveredDeadlinesKey) as? [String: Double] ?? [:]
    }
}

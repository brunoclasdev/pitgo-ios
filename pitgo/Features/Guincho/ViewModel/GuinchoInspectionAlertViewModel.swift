import Combine
import Foundation

@MainActor
final class GuinchoInspectionAlertViewModel: ObservableObject {
    enum ReviewResult { case pending(GuinchoInspectionApprovalAlert), resolved(UUID) }
    @Published private(set) var presentedAlert: GuinchoInspectionApprovalAlert?
    @Published private(set) var isOpening = false
    @Published private(set) var openFailure: String?

    private let repository: GuinchoInspectionAlertRepository
    private var accountID: UUID?
    private var environmentID: String?
    private var pollTask: Task<Void, Never>?
    private var isForeground = false
    private var isRefreshing = false
    private var generation = UUID()

    init(repository: GuinchoInspectionAlertRepository) { self.repository = repository }

    func start(accountID: UUID) {
        guard self.accountID != accountID || environmentID != Self.environmentID else { return }
        stop()
        self.accountID = accountID
        environmentID = Self.environmentID
        if isForeground { beginPolling() }
    }

    func setForeground(_ foreground: Bool) {
        isForeground = foreground
        if foreground { beginPolling() }
        else { pollTask?.cancel(); pollTask = nil }
    }

    func stop() {
        generation = UUID()
        pollTask?.cancel(); pollTask = nil
        accountID = nil
        environmentID = nil
        presentedAlert = nil
        openFailure = nil
    }

    func dismiss(_ alert: GuinchoInspectionApprovalAlert) {
        guard let accountID, let environmentID else { return }
        UserDefaults.standard.set(true, forKey: dismissalKey(alert, accountID: accountID, environmentID: environmentID))
        presentedAlert = nil
        openFailure = nil
        Task { await refresh() }
    }

    func review(_ alert: GuinchoInspectionApprovalAlert) async -> ReviewResult? {
        guard !isOpening, let environmentID, alert.environmentID == environmentID else { return nil }
        isOpening = true
        openFailure = nil
        defer { isOpening = false }
        do {
            let result = try await repository.resolve(alertID: alert.alertID, environmentID: environmentID)
            guard self.accountID != nil else { return nil }
            presentedAlert = nil
            if result.outcome == "PENDING", let current = result.alert,
               current.appointmentID == alert.appointmentID, current.versionID == alert.versionID {
                return .pending(current)
            }
            return .resolved(alert.appointmentID)
        } catch {
            openFailure = "Não foi possível conferir a situação agora. Verifique sua conexão e tente novamente."
            return nil
        }
    }

    private func beginPolling() {
        guard isForeground, accountID != nil, pollTask == nil else { return }
        let token = generation
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.generation == token, self.isForeground {
                await self.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            self.pollTask = nil
        }
    }

    private func refresh() async {
        guard !isRefreshing, let accountID, let environmentID else { return }
        let token = generation
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var alerts: [GuinchoInspectionApprovalAlert] = []
            var cursor: GuinchoInspectionAlertPage.Cursor?
            repeat {
                let page = try await repository.list(environmentID: environmentID, after: cursor)
                alerts.append(contentsOf: page.items)
                cursor = page.nextCursor
            } while cursor != nil
            guard generation == token, self.accountID == accountID,
                  self.environmentID == environmentID, isForeground else { return }
            if let current = presentedAlert,
               !alerts.contains(where: { $0.alertID == current.alertID }) {
                presentedAlert = nil
            }
            guard presentedAlert == nil else { return }
            presentedAlert = alerts.first(where: {
                $0.environmentID == environmentID && !UserDefaults.standard.bool(forKey: dismissalKey($0, accountID: accountID, environmentID: environmentID))
            })
        } catch {
            // Falha de leitura não altera estado nem significa que a pendência foi aprovada.
        }
    }

    private func dismissalKey(_ alert: GuinchoInspectionApprovalAlert, accountID: UUID, environmentID: String) -> String {
        "pitgo.guincho-inspection-alert.dismissed.\(accountID.uuidString).\(environmentID).\(alert.appointmentID.uuidString).\(alert.versionID.uuidString)"
    }

    private static var environmentID: String { EnvironmentConfig.current.id.rawValue.lowercased() }
}

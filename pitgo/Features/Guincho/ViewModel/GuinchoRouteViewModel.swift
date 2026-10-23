import Combine
import CoreLocation
import Foundation

@MainActor
final class GuinchoRouteViewModel: ObservableObject {
    @Published private(set) var state: GuinchoRouteUIState = .closed
    @Published private(set) var latestFix: DeviceLocationFix?
    private let repository: GuinchoRouteRepository
    private let tracker: ProviderDiscoveryTracker
    private var fixSubscription: AnyCancellable?
    private var currentFixes: [DeviceLocationFix] = []
    private var appointmentID: UUID?
    private var destination: GuinchoRouteSnapshot.Point?
    private var route: GuinchoRouteSnapshot?
    private var refreshTask: Task<Void, Never>?
    private var generation = UUID()
    private var requestedInitial = false
    private var retryTask: Task<Void, Never>?

    init(repository: GuinchoRouteRepository, tracker: ProviderDiscoveryTracker) {
        self.repository = repository
        self.tracker = tracker
        fixSubscription = tracker.$lastFix.compactMap { $0 }.sink { [weak self] fix in
            Task { @MainActor in self?.receive(fix) }
        }
    }

    func activate(appointmentID: UUID, destination: CLLocationCoordinate2D) {
        guard self.appointmentID != appointmentID else { return }
        stop()
        self.appointmentID = appointmentID
        self.destination = .init(latitude: destination.latitude, longitude: destination.longitude)
        state = .loading(nil)
        let token = generation
        Task { [weak self, repository] in
            guard let self else { return }
            do {
                let saved = try await repository.snapshot(appointmentID: appointmentID)
                guard self.generation == token else { return }
                if let route = saved.snapshot(), route.isValid(for: appointmentID, expectedDestination: self.destination) {
                    self.route = route
                    self.state = .ready(route)
                }
                self.refresh(reason: self.route == nil ? .initial : .resume)
            } catch {
                guard self.generation == token else { return }
                self.refresh(reason: .initial)
            }
        }
        if let fix = tracker.lastFix { receive(fix) }
    }

    func retry() { refresh(reason: .retry) }

    func stop() {
        generation = UUID()
        refreshTask?.cancel(); refreshTask = nil
        retryTask?.cancel(); retryTask = nil
        appointmentID = nil
        destination = nil
        route = nil
        currentFixes = []
        requestedInitial = false
        state = .closed
    }

    private func receive(_ fix: DeviceLocationFix) {
        latestFix = fix
        guard appointmentID != nil, fix.horizontalAccuracy > 0,
              Date().timeIntervalSince(fix.timestamp) <= 10, fix.timestamp.timeIntervalSinceNow <= 5 else { return }
        if currentFixes.last?.timestamp != fix.timestamp { currentFixes.append(fix) }
        currentFixes = Array(currentFixes.suffix(5))
        guard let route, currentFixes.count >= 3, let first = currentFixes.first,
              let last = currentFixes.last, last.timestamp.timeIntervalSince(first.timestamp) >= 4,
              currentFixes.allSatisfy({ $0.horizontalAccuracy <= 35 && Date().timeIntervalSince($0.timestamp) <= 10 }) else { return }
        let path = route.coordinates
        let check = Task.detached(priority: .utility) { Self.distance(fix: last, to: path) > max(50, 2 * last.horizontalAccuracy) }
        Task { [weak self] in
            guard await check.value, let self, self.route?.routeVersion == route.routeVersion else { return }
            self.refresh(reason: .deviation)
        }
    }

    private func refresh(reason: GuinchoRouteReason) {
        guard let appointmentID, refreshTask == nil else { return }
        if reason == .initial && requestedInitial { return }
        requestedInitial = true
        let token = generation
        let knownVersion = route?.routeVersion ?? 0
        state = .loading(route)
        refreshTask = Task { [weak self, repository] in
            guard let self else { return }
            defer { self.refreshTask = nil }
            do {
                let payload = try await repository.refresh(appointmentID: appointmentID, reason: reason, knownVersion: knownVersion)
                guard self.generation == token, self.appointmentID == appointmentID else { return }
                if let updated = payload.snapshot(), updated.isValid(for: appointmentID, expectedDestination: self.destination),
                   updated.routeVersion >= (self.route?.routeVersion ?? 0) {
                    self.route = updated
                    self.state = .ready(updated)
                    if reason == .deviation { self.currentFixes.removeAll() }
                } else if payload.status == "PENDING" {
                    self.state = .waiting(self.route, "Atualização do percurso em andamento…")
                    self.scheduleRetry(after: Double(min(max(payload.retryAfterMs ?? 750, 500), 1_000)) / 1_000)
                } else {
                    let message = payload.code == "LOCATION_NOT_READY" || payload.code == "LOCATION_UNCERTAIN"
                        ? "Aguardando uma localização precisa para traçar o percurso."
                        : "Não foi possível atualizar o percurso. A última rota continua disponível."
                    self.state = .unavailable(self.route, message)
                    self.scheduleRetry(after: Double(min(max(payload.retryAfterMs ?? 5_000, 1_000), 30_000)) / 1_000)
                }
            } catch let failure as GuinchoRouteFailure {
                guard self.generation == token else { return }
                guard failure.retryable else {
                    self.stop()
                    return
                }
                self.state = .unavailable(self.route, "Não foi possível atualizar o percurso (\(failure.code)). A última rota continua disponível.")
                self.scheduleRetry(after: Double(min(max(failure.retryAfterMs ?? 5_000, 1_000), 30_000)) / 1_000)
            } catch {
                guard self.generation == token else { return }
                self.state = .unavailable(self.route, "Não foi possível atualizar o percurso. Tente novamente.")
                self.scheduleRetry(after: 5)
            }
        }
    }

    private func scheduleRetry(after delay: TimeInterval) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            self.refresh(reason: .retry)
        }
    }

    nonisolated private static func distance(fix: DeviceLocationFix, to path: [CLLocationCoordinate2D]) -> Double {
        guard path.count >= 2 else { return .infinity }
        let latScale = 111_320.0
        let lonScale = latScale * cos(fix.latitude * .pi / 180)
        let px = fix.longitude * lonScale, py = fix.latitude * latScale
        return zip(path, path.dropFirst()).map { a, b in
            func normalizedDelta(_ longitude: Double) -> Double {
                let delta = (longitude - fix.longitude + 540).truncatingRemainder(dividingBy: 360) - 180
                return delta * lonScale
            }
            let ax = normalizedDelta(a.longitude), ay = a.latitude * latScale
            let bx = normalizedDelta(b.longitude), by = b.latitude * latScale
            let dx = bx - ax, dy = by - ay
            let t = min(max(((px - ax) * dx + (py - ay) * dy) / max(dx * dx + dy * dy, 1), 0), 1)
            return hypot(px - (ax + t * dx), py - (ay + t * dy))
        }.min() ?? .infinity
    }
}

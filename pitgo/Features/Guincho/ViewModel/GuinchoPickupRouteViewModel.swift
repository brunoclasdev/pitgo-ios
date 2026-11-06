import Combine
import CoreLocation
import MapKit

@MainActor
final class GuinchoPickupRouteViewModel: ObservableObject {
    @Published private(set) var coordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var fitTrigger = 0
    @Published private(set) var message: String?
    private let tracker: ProviderDiscoveryTracker
    private var subscription: AnyCancellable?
    private var appointmentID: UUID?
    private var pickup: CLLocationCoordinate2D?
    private var origin: CLLocationCoordinate2D?
    private var fullCoordinates: [CLLocationCoordinate2D] = []
    private var latestFix: DeviceLocationFix?
    private var progress = GuinchoRouteProgress()
    private var lastRequest = Date.distantPast
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var directions: MKDirections?
    private let calculateRoute: (@MainActor (CLLocationCoordinate2D, CLLocationCoordinate2D) async throws -> [CLLocationCoordinate2D])?

    init(tracker: ProviderDiscoveryTracker,
         calculateRoute: (@MainActor (CLLocationCoordinate2D, CLLocationCoordinate2D) async throws -> [CLLocationCoordinate2D])? = nil) {
        self.tracker = tracker
        self.calculateRoute = calculateRoute
        subscription = tracker.$lastFix.compactMap { $0 }.sink { [weak self] fix in
            Task { @MainActor in self?.receive(fix) }
        }
    }

    func activate(appointmentID: UUID, pickup: CLLocationCoordinate2D, fallbackFix: DeviceLocationFix?) {
        if self.appointmentID != appointmentID || self.pickup?.latitude != pickup.latitude || self.pickup?.longitude != pickup.longitude {
            stop()
            self.appointmentID = appointmentID
            self.pickup = pickup
            message = "Aguardando localização para traçar o percurso até a retirada…"
        }
        if let fix = tracker.lastFix ?? fallbackFix { receive(fix) }
    }

    private func receive(_ fix: DeviceLocationFix) {
        latestFix = fix
        coordinates = progress.update(path: fullCoordinates, fix: fix)
        let point = CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
        guard let pickup, task == nil, CLLocationCoordinate2DIsValid(point), CLLocationCoordinate2DIsValid(pickup),
              fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= 100,
              Date().timeIntervalSince(fix.timestamp) <= 30, fix.timestamp.timeIntervalSinceNow <= 5 else { return }
        let moved = origin.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude)) >= 50
        } ?? true
        guard (fullCoordinates.isEmpty || moved), Date().timeIntervalSince(lastRequest) >= 30 else { return }
        lastRequest = Date()
        let token = generation
        message = coordinates.isEmpty ? "Traçando percurso até a retirada…" : nil
        task = Task { [weak self] in
            guard let self else { return }
            defer { if generation == token { task = nil; directions = nil } }
            do {
                let points: [CLLocationCoordinate2D]
                if let calculateRoute {
                    points = try await calculateRoute(point, pickup)
                } else {
                    let request = MKDirections.Request()
                    request.source = MKMapItem(placemark: MKPlacemark(coordinate: point))
                    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: pickup))
                    request.transportType = .automobile
                    let calculation = MKDirections(request: request)
                    directions = calculation
                    let response = try await calculation.calculate()
                    guard let path = response.routes.first?.polyline else {
                        throw URLError(.cannotParseResponse)
                    }
                    var result = [CLLocationCoordinate2D](repeating: .init(), count: path.pointCount)
                    path.getCoordinates(&result, range: NSRange(location: 0, length: path.pointCount))
                    points = result
                }
                guard !Task.isCancelled, generation == token, points.count >= 2,
                      points.allSatisfy({ CLLocationCoordinate2DIsValid($0) }) else { return }
                let firstRoute = fullCoordinates.isEmpty
                fullCoordinates = points
                coordinates = progress.update(path: points, fix: latestFix)
                origin = point
                message = nil
                if firstRoute { fitTrigger += 1 }
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                message = "Não foi possível atualizar o percurso até a retirada. Tentaremos novamente."
            }
        }
    }

    func stop() {
        generation = UUID()
        task?.cancel(); task = nil
        directions?.cancel(); directions = nil
        appointmentID = nil; pickup = nil; origin = nil
        lastRequest = .distantPast
        coordinates = []
        fullCoordinates = []
        latestFix = nil
        progress = GuinchoRouteProgress()
        message = nil
    }
}

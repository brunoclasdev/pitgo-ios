import Combine
import CoreLocation
import MapKit
import Foundation

@MainActor
final class GuinchoClientRouteMapModel: ObservableObject {
    @Published private(set) var provider: CLLocationCoordinate2D?
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    @Published private(set) var fitTrigger = 0
    @Published private(set) var routeVersion: Int64 = 0
    @Published private(set) var message: String?
    private var directions: MKDirections?
    private var routeTask: Task<Void, Never>?
    private var generation = UUID()
    private var routeUnavailable = false
    private var fullRoute: [CLLocationCoordinate2D] = []
    private var latestFix: DeviceLocationFix?
    private var progress = GuinchoRouteProgress()
    private let calculateRoute: (@MainActor (CLLocationCoordinate2D, CLLocationCoordinate2D) async throws -> [CLLocationCoordinate2D])?
    private let pollInterval: UInt64

    init(pollInterval: UInt64 = 5_000_000_000,
         calculateRoute: (@MainActor (CLLocationCoordinate2D, CLLocationCoordinate2D) async throws -> [CLLocationCoordinate2D])? = nil) {
        self.pollInterval = pollInterval
        self.calculateRoute = calculateRoute
    }

    func fitCoordinates(trip: GuinchoTripSummary, phase: GuinchoClientRoutePhase) -> [CLLocationCoordinate2D] {
        // Focus on the truck and the client/pickup, then the destination during transport.
        [provider ?? trip.pickup, phase.target(trip)]
    }

    func observe(appointmentID: UUID, trip: GuinchoTripSummary, phase: GuinchoClientRoutePhase,
                 repository: AppointmentTrackingRepository) async {
        stop()
        let token = generation
        provider = nil
        route = []
        routeUnavailable = false
        routeVersion += 1
        message = "Carregando percurso do guincho…"
        var lastOrigin: CLLocationCoordinate2D?
        var lastCalculation = Date.distantPast
        defer { if generation == token { stop() } }
        while !Task.isCancelled, generation == token {
            let location = await repository.fetchSnapshot(appointmentID: appointmentID)
            guard !Task.isCancelled, generation == token else { return }
            if location?.isEnded == true {
                provider = nil
                route = []
                routeVersion += 1
                message = "Acompanhamento encerrado."
                return
            }
            if let latitude = location?.latitude, let longitude = location?.longitude {
                let point = CLLocationCoordinate2D(latitude: NSDecimalNumber(decimal: latitude).doubleValue,
                                                   longitude: NSDecimalNumber(decimal: longitude).doubleValue)
                if CLLocationCoordinate2DIsValid(point) {
                    let firstFix = provider == nil
                    provider = point
                    if let accuracy = location?.accuracyM,
                       let capturedAt = location?.capturedAt ?? location?.publishedAt {
                        latestFix = DeviceLocationFix(latitude: point.latitude, longitude: point.longitude,
                            horizontalAccuracy: NSDecimalNumber(decimal: accuracy).doubleValue, timestamp: capturedAt)
                        updateRemainingRoute()
                    }
                    // Do not wait for MKDirections before bringing the truck into view.
                    if firstFix { fitTrigger += 1 }
                    message = location?.fresh == false ? "Exibindo a última localização do guincho."
                        : routeUnavailable ? "Não foi possível atualizar o percurso. Tentaremos novamente." : nil
                }
            }
            // No transporte, mostra inicialmente todo o trecho retirada → destino.
            let origin = phase == .transporting ? (lastOrigin == nil ? trip.pickup : provider ?? trip.pickup) : provider
            if let origin {
                let moved = lastOrigin.map {
                    CLLocation(latitude: origin.latitude, longitude: origin.longitude)
                        .distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) > 50
                } ?? true
                if routeTask == nil, (fullRoute.isEmpty || moved), Date().timeIntervalSince(lastCalculation) >= 30 {
                    lastCalculation = Date()
                    routeTask = Task { [weak self] in
                        guard let self else { return }
                        defer { if generation == token { routeTask = nil; directions = nil } }
                        do {
                            let coordinates: [CLLocationCoordinate2D]
                            if let calculateRoute {
                                coordinates = try await calculateRoute(origin, phase.target(trip))
                            } else {
                                let request = MKDirections.Request()
                                request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
                                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: phase.target(trip)))
                                request.transportType = .automobile
                                let calculation = MKDirections(request: request)
                                directions = calculation
                                let response = try await calculation.calculate()
                                guard let path = response.routes.first?.polyline else { return }
                                var points = [CLLocationCoordinate2D](repeating: .init(), count: path.pointCount)
                                path.getCoordinates(&points, range: NSRange(location: 0, length: path.pointCount))
                                coordinates = points
                            }
                            guard !Task.isCancelled, generation == token, coordinates.count >= 2 else { return }
                            let firstRoute = fullRoute.isEmpty
                            fullRoute = coordinates
                            updateRemainingRoute()
                            routeUnavailable = false
                            lastOrigin = origin
                            if firstRoute { fitTrigger += 1 }
                        } catch {
                            guard !Task.isCancelled, generation == token else { return }
                            routeUnavailable = true
                            message = "Não foi possível atualizar o percurso. Tentaremos novamente."
                        }
                    }
                }
            } else {
                message = "Aguardando a localização do guincho para traçar o percurso até você."
            }
            do { try await Task.sleep(nanoseconds: pollInterval) }
            catch { return }
        }
    }

    func recenter() { fitTrigger += 1 }

    private func updateRemainingRoute() {
        let remaining = progress.update(path: fullRoute, fix: latestFix)
        guard route.count != remaining.count || !zip(route, remaining).allSatisfy({
            $0.latitude == $1.latitude && $0.longitude == $1.longitude
        }) else { return }
        route = remaining
        routeVersion += 1
    }

    func stop() {
        generation = UUID()
        routeTask?.cancel()
        routeTask = nil
        directions?.cancel()
        directions = nil
        fullRoute = []
        latestFix = nil
        progress = GuinchoRouteProgress()
        route = []
        routeVersion += 1
    }
}

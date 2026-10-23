import Combine
import CoreLocation
import MapKit
import SwiftUI

@MainActor
final class GuinchoClientRouteMapModel: ObservableObject {
    @Published private(set) var provider: CLLocationCoordinate2D?
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    @Published private(set) var fitTrigger = 0
    @Published private(set) var routeVersion: Int64 = 0
    @Published private(set) var message: String?
    private var directions: MKDirections?

    func observe(appointmentID: UUID, trip: GuinchoTripSummary, phase: GuinchoClientRoutePhase,
                 repository: AppointmentTrackingRepository) async {
        provider = nil
        route = []
        routeVersion += 1
        message = "Carregando percurso do guincho…"
        var lastOrigin: CLLocationCoordinate2D?
        var lastCalculation = Date.distantPast
        while !Task.isCancelled {
            let location = await repository.fetchSnapshot(appointmentID: appointmentID)
            guard !Task.isCancelled else { return }
            if let latitude = location?.latitude, let longitude = location?.longitude {
                let point = CLLocationCoordinate2D(latitude: NSDecimalNumber(decimal: latitude).doubleValue,
                                                   longitude: NSDecimalNumber(decimal: longitude).doubleValue)
                if CLLocationCoordinate2DIsValid(point) { provider = point }
            }
            // No transporte, mostra inicialmente todo o trecho retirada → destino.
            let origin = phase == .transporting ? (lastOrigin == nil ? trip.pickup : provider ?? trip.pickup) : provider
            if let origin {
                let moved = lastOrigin.map {
                    CLLocation(latitude: origin.latitude, longitude: origin.longitude)
                        .distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) > 50
                } ?? true
                if route.isEmpty || (moved && Date().timeIntervalSince(lastCalculation) >= 30) {
                    lastCalculation = Date()
                    let request = MKDirections.Request()
                    request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
                    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: phase.target(trip)))
                    request.transportType = .automobile
                    let calculation = MKDirections(request: request)
                    directions = calculation
                    do {
                        let response = try await calculation.calculate()
                        guard !Task.isCancelled, let path = response.routes.first?.polyline else { return }
                        var coordinates = [CLLocationCoordinate2D](repeating: .init(), count: path.pointCount)
                        path.getCoordinates(&coordinates, range: NSRange(location: 0, length: path.pointCount))
                        let firstRoute = route.isEmpty
                        route = coordinates
                        routeVersion += 1
                        lastOrigin = origin
                        if firstRoute { fitTrigger += 1 }
                        message = location?.fresh == false ? "Exibindo a última localização do guincho." : nil
                    } catch {
                        guard !Task.isCancelled else { return }
                        message = "Não foi possível atualizar o percurso. Tentaremos novamente."
                    }
                    directions = nil
                }
            } else {
                message = "Aguardando a localização do guincho para traçar o percurso até você."
            }
            do { try await Task.sleep(nanoseconds: 5_000_000_000) }
            catch { return }
        }
    }

    func recenter() { fitTrigger += 1 }
    func stop() { directions?.cancel(); directions = nil }
}

struct GuinchoClientRouteMap: View {
    @StateObject private var model = GuinchoClientRouteMapModel()
    let appointmentID: UUID
    let trip: GuinchoTripSummary
    let phase: GuinchoClientRoutePhase
    let repository: AppointmentTrackingRepository

    var body: some View {
        let target = phase.target(trip)
        let annotations = [PitGoMapAnnotationItem(id: "target", coordinate: target,
            title: phase == .approaching ? "Local de retirada" : "Destino")]
            + (model.provider.map { [PitGoMapAnnotationItem(id: "provider", coordinate: $0,
                title: "Guincho", symbolName: "truck.box.fill")] } ?? [])
        PitGoMapView(annotations: annotations, centerCoordinate: target,
            fitCoordinates: model.route.count >= 2 ? model.route : nil, fitTrigger: model.fitTrigger,
            routeLine: model.route, routeVersion: model.routeVersion, routeIsEstimated: false)
            .overlay(alignment: .topTrailing) {
                Button { model.recenter() } label: {
                    Image(systemName: "scope").padding(12).background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Centralizar percurso do guincho")
                .padding(12)
            }
            .overlay(alignment: .topLeading) {
                if let message = model.message {
                    Text(message).font(.caption).padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.leading, 12).padding(.trailing, 64).padding(.top, 12)
                }
            }
            .overlay(alignment: .bottomLeading) { MapAttributionView() }
            .task(id: "\(appointmentID):\(phase.rawValue)") {
                await model.observe(appointmentID: appointmentID, trip: trip, phase: phase, repository: repository)
            }
            .onDisappear { model.stop() }
    }
}

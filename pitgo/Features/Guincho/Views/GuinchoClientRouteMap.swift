import Combine
import CoreLocation
import MapKit
import SwiftUI

struct GuinchoClientRouteMap: View {
    @StateObject private var model = GuinchoClientRouteMapModel()
    let appointmentID: UUID
    let trip: GuinchoTripSummary
    let phase: GuinchoClientRoutePhase
    let repository: AppointmentTrackingRepository
    var fitBottomPadding: CGFloat = 320

    var body: some View {
        let target = phase.target(trip)
        let annotations = [PitGoMapAnnotationItem(id: "target", coordinate: target,
            title: phase == .approaching ? "Local de retirada" : "Destino")]
            + (model.provider.map { [PitGoMapAnnotationItem(id: "provider", coordinate: $0,
                title: "Guincho", symbolName: "truck.box.fill")] } ?? [])
        PitGoMapView(annotations: annotations, centerCoordinate: target,
            fitCoordinates: model.fitCoordinates(trip: trip, phase: phase), fitTrigger: model.fitTrigger,
            followsFitCoordinates: true,
            fitBottomPadding: fitBottomPadding,
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
            .overlay(alignment: .topLeading) { MapAttributionView().padding(.top, 72).padding(.leading, 12) }
            .task(id: "\(appointmentID):\(phase.rawValue)") {
                await model.observe(appointmentID: appointmentID, trip: trip, phase: phase, repository: repository)
            }
            .onDisappear { model.stop() }
    }
}

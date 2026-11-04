import CoreLocation
import Foundation

struct GuinchoSearchResume: Decodable {
    enum Outcome: String, Decodable { case none = "NONE", active = "ACTIVE_DISPATCH", search = "RESUMABLE_SEARCH" }
    struct Draft: Decodable {
        let id: UUID
        let revision: Int64
        let vehicle_id: UUID
        let pickup_address: String
        let pickup_latitude: Double
        let pickup_longitude: Double
        let destination_address: String
        let destination_latitude: Double
        let destination_longitude: Double
        var input: GuinchoTripInput {
            GuinchoTripInput(vehicleID: vehicle_id, pickupAddress: pickup_address,
                pickup: CLLocationCoordinate2D(latitude: pickup_latitude, longitude: pickup_longitude),
                destinationAddress: destination_address,
                destination: CLLocationCoordinate2D(latitude: destination_latitude, longitude: destination_longitude))
        }
    }
    let outcome: Outcome
    let context_id: UUID?
    let generation: Int64?
    let rejected_appointment_id: UUID?
    let draft: Draft?
    let snapshot: MobileDispatchSnapshot?
    var isResumable: Bool {
        outcome == .search && context_id != nil && (generation ?? 0) > 0
            && (draft?.revision ?? 0) > 0 && draft?.input.isValid == true
    }
}

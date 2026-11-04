import CoreLocation
import Foundation
import Supabase

/// Foreground location sharing for client appointments. Guincho uses its fixed pickup instead.
@MainActor
final class ClientAppointmentLocationPublisher {
    private let repository: AppointmentTrackingRepository
    private let location = DeviceLocationRepository()

    init(repository: AppointmentTrackingRepository) { self.repository = repository }

    func run(appointmentID: UUID) async {
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
        defer { location.cancelOneShotFix() }
        while !Task.isCancelled {
            switch location.authorizationStatus {
            case .denied, .restricted: return
            case .notDetermined: break
            case .authorizedAlways, .authorizedWhenInUse:
                if case let .success(fix) = await location.requestOneShotFix(timeout: 20) {
                    guard !Task.isCancelled else { return }
                    let age = Date().timeIntervalSince(fix.timestamp)
                    if CLLocationCoordinate2DIsValid(.init(latitude: fix.latitude, longitude: fix.longitude)),
                       fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= 5000, age >= -10, age <= 30 {
                        do { try await repository.publishClientLocation(appointmentID: appointmentID, fix: fix) }
                        catch let error as PostgrestError where ["42501", "P0002"].contains(error.code ?? "") { return }
                        catch { /* A failed publish is retried with the next fresh GPS fix. */ }
                    }
                }
            }
            do { try await Task.sleep(nanoseconds: 5_000_000_000) }
            catch { return }
        }
    }
}

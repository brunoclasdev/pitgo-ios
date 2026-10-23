import Foundation

@main struct GuinchoReservationRegression {
    static func main() async throws {
        // Contract from create_guincho_request_before_payment/private.guincho_snapshot.
        let snapshot: [String: Any] = [
            "search_id": UUID().uuidString, "service_id": UUID().uuidString,
            "service_name": "Guincho", "dispatch_kind": "GUINCHO_DIRECT",
            "status": "AWAITING_PROVIDER", "radius_meters": 25000, "revision": 2,
            "server_now": "2026-10-23T15:30:00.123456+00:00", "allowed_actions": ["CANCEL"],
            "tracking_authorized": false,
            "trip": ["client_name": "Cliente", "vehicle": ["brand": "Fiat", "model": "Uno", "plate": "ABC1234"],
                     "pickup_address": "Origem", "destination_address": "Destino",
                     "pickup_latitude": -23.5, "pickup_longitude": -46.6,
                     "destination_latitude": -23.6, "destination_longitude": -46.7],
            "appointment": ["appointment_id": UUID().uuidString, "status": "PENDING", "revision": 1,
                            "quote_version": 1, "response_deadline": "2026-10-23T15:31:00+00:00",
                            "quote": ["customer_total_amount": "123.45", "currency": "BRL"]]
        ]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)!
        }
        for outcome in ["CREATED", "EXISTING", "APPLIED", "ACCEPTED", "COMPLETED", "DISPUTED"] {
            let data = try JSONSerialization.data(withJSONObject: ["outcome": outcome, "snapshot": snapshot])
            let result = try decoder.decode(DispatchFlowResult.self, from: data)
            precondition(result.snapshot?.appointment?.quotedPrice == Decimal(string: "123.45")!)
            precondition(result.snapshot?.status == .awaitingProvider)
        }
        var accepted = snapshot
        accepted["allowed_actions"] = ["OPEN_PAYMENT", "OPEN_TRACKING", "CANCEL"]
        let data = try JSONSerialization.data(withJSONObject: accepted)
        let result = try decoder.decode(DispatchFlowResult.self, from: data)
        precondition(result.snapshot?.allowedActions.contains(.openPayment) == true)
        precondition(result.snapshot?.allowedActions.contains(.openTracking) == true)
        let backgroundData = try JSONSerialization.data(withJSONObject: ["outcome": "ACTIVE", "snapshot": snapshot])
        let backgroundResult = try await Task.detached {
            let backgroundDecoder = JSONDecoder()
            backgroundDecoder.dateDecodingStrategy = decoder.dateDecodingStrategy
            return try backgroundDecoder.decode(DispatchFlowResult.self, from: backgroundData)
        }.value
        precondition(backgroundResult.snapshot?.guinchoTrip?.vehicle == "Fiat · Uno · ABC1234")
        let trip = backgroundResult.snapshot!.guinchoTrip!
        let approaching = GuinchoClientRoutePhase.approaching.target(trip)
        let transporting = GuinchoClientRoutePhase.transporting.target(trip)
        precondition(approaching.latitude == trip.pickup.latitude && approaching.longitude == trip.pickup.longitude)
        precondition(transporting.latitude == trip.destination.latitude && transporting.longitude == trip.destination.longitude)
        var cancelled = snapshot
        cancelled["status"] = "CANCELLED"
        cancelled["allowed_actions"] = [] as [String]
        var appointment = snapshot["appointment"] as! [String: Any]
        appointment["status"] = "CANCELLED"
        appointment["cancelled_by"] = "SYSTEM"
        cancelled["appointment"] = appointment
        let cancellationData = try JSONSerialization.data(withJSONObject: ["outcome": "CANCELLED", "snapshot": cancelled])
        let cancellation = try decoder.decode(DispatchFlowResult.self, from: cancellationData)
        precondition(cancellation.snapshot?.status == .cancelled)
        precondition(cancellation.snapshot?.appointment?.cancelledBy == .system)
        print("PASS: reservation, idempotent retry and follow-up responses decode with text amounts and navigation actions")
    }
}

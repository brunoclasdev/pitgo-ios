import Foundation

@main struct GuinchoSearchResumeRegression {
    static func main() throws {
        let decoder = JSONDecoder()
        let draft: [String: Any] = [
            "id": UUID().uuidString, "revision": 3, "vehicle_id": UUID().uuidString,
            "pickup_address": "Rua Origem, 10", "pickup_latitude": -23.5, "pickup_longitude": -46.6,
            "destination_address": "Rua Destino, 25, Centro", "destination_latitude": -23.6, "destination_longitude": -46.7
        ]
        var search: [String: Any] = [
            "outcome": "RESUMABLE_SEARCH", "context_id": UUID().uuidString, "generation": 2,
            "rejected_appointment_id": UUID().uuidString, "excluded_provider_ids": [UUID().uuidString], "draft": draft
        ]
        func decode(_ value: [String: Any]) throws -> GuinchoSearchResume {
            try decoder.decode(GuinchoSearchResume.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let resumed = try decode(search)
        precondition(resumed.isResumable)
        precondition(resumed.draft?.input.destinationAddress == "Rua Destino, 25, Centro")
        precondition(resumed.draft?.input.pickupAddress == "Rua Origem, 10")
        precondition(resumed.draft?.input.vehicleID.uuidString == draft["vehicle_id"] as? String)
        search["generation"] = 0
        let invalidGeneration = try decode(search)
        precondition(!invalidGeneration.isResumable)
        search["generation"] = 2
        search.removeValue(forKey: "context_id")
        let invalidContext = try decode(search)
        precondition(!invalidContext.isResumable)
        let none = try decode(["outcome": "NONE"])
        precondition(!none.isResumable)
        let active = try decode(["outcome": "ACTIVE_DISPATCH"])
        precondition(!active.isResumable)
        print("PASS: refusal recovery preserves trip; invalid contexts and active dispatch do not resume a search")
    }
}

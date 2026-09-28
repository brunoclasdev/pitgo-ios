import Foundation

// Compile with the production PitTecModels.swift and MobileDispatchModels.swift.
// Fixture follows private.pittec_dispatch_snapshot after arrive_pittec_appointment.
@main
struct PitTecArrivalRegression {
    static func main() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func snapshot(status: String, action: String, arrived: Bool) throws -> PitTecDispatchSnapshot {
            let arrivedAt = arrived ? "\"2026-09-28T19:00:00Z\"" : "null"
            let json = """
            {"outcome":"ARRIVED","snapshot":{
              "search_id":"11111111-1111-1111-1111-111111111111",
              "service_id":"22222222-2222-2222-2222-222222222222",
              "service_name":"PitTec","status":"\(status)","radius_meters":5000,
              "revision":8,"server_now":"2026-09-28T19:00:00Z",
              "allowed_actions":["OPEN_TRACKING","\(action)","CANCEL"],
              "payment":{"status":"APPROVED"},
              "appointment":{
                "appointment_id":"33333333-3333-3333-3333-333333333333",
                "status":"\(status)","revision":6,"arrived_at":\(arrivedAt),
                "quote":{"provider_amount":25,"currency":"BRL","version":1}
              }
            }}
            """
            return try decoder.decode(PitTecFlowResult.self, from: Data(json.utf8)).snapshot!
        }
        let enRoute = try snapshot(status: "ACCEPTED", action: "ARRIVE", arrived: false)
        precondition(!enRoute.hasArrived && enRoute.allowedActions.contains(.arrive))
        let arrived = try snapshot(status: "ACCEPTED", action: "START", arrived: true)
        precondition(arrived.hasArrived && arrived.allowedActions.contains(.start))
        precondition(arrived.appointment?.status == .accepted)
        precondition(!arrived.allowedActions.contains(.complete))
        let inProgress = try snapshot(status: "IN_PROGRESS", action: "COMPLETE", arrived: true)
        precondition(inProgress.hasArrived && inProgress.allowedActions.contains(.complete))
        let legacy = try snapshot(status: "IN_PROGRESS", action: "COMPLETE", arrived: false)
        precondition(legacy.hasArrived)
        print("PASS: en route → arrived (ACCEPTED + START) → in progress; legacy arrival")
    }
}

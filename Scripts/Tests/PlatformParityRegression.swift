import Foundation

@main struct PlatformParityRegression {
    static func main() throws {
        let decoder = JSONDecoder()
        for (state, expected) in [("LIVE", true), ("STALE", false)] {
            let data = Data("{\"state\":\"\(state)\",\"version\":3}".utf8)
            let snapshot = try decoder.decode(AppointmentProviderLocationSnapshot.self, from: data)
            precondition(snapshot.fresh == expected && !snapshot.isEnded)
        }
        let ended = try decoder.decode(AppointmentProviderLocationSnapshot.self, from: Data(#"{"state":"ENDED","status":"COMPLETED"}"#.utf8))
        precondition(ended.isEnded)
        let empty = try decoder.decode(AppointmentProviderLocationSnapshot.self, from: Data(#"{"state":"EMPTY"}"#.utf8))
        precondition(empty.latitude == nil && !empty.isEnded)
        for text in ["0", "-1", "1.234", "10000000000", "12abc", "1,2,3", ""] {
            precondition(!StorePrice.isValid(text), "Invalid price accepted: \(text)")
        }
        for text in ["0,01", "1", "9999999999.99", "12.50"] {
            precondition(StorePrice.isValid(text), "Valid price rejected: \(text)")
        }
        let base = #"{"payment_id":"11111111-1111-1111-1111-111111111111","status":"REFUND_PENDING","method":"PIX","amount":"1.50","created_at":"2026-11-03T12:00:00.123456Z","cancel_requested":true}"#
        let history = try decoder.decode(PaymentHistoryRecord.self, from: Data(base.utf8))
        precondition(history.amount == Decimal(string: "1.50") && history.createdAt != nil)
        precondition(history.statusLabel == "Estorno em andamento")
        let numeric = base.replacingOccurrences(of: #""amount":"1.50""#, with: #""amount":1.50"#)
        let numericHistory = try decoder.decode(PaymentHistoryRecord.self, from: Data(numeric.utf8))
        precondition(numericHistory.amount == history.amount)
        print("PASS: tracking state contract, product price limits and payment history numeric/text amounts")
    }
}

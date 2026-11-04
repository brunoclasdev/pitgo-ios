import Foundation

// Compile with GuinchoDTOs.swift, GuinchoModels.swift and ServiceRatingModels.swift.
@main struct GuinchoQuoteRegression {
    static func main() throws {
        func payload(amount: String, date: String) -> Data {
            Data("""
            {"quote_id":"11111111-1111-1111-1111-111111111111","version":1,
             "provider_id":"22222222-2222-2222-2222-222222222222","provider_name":"Guincho",
             "customer_total_amount":\(amount),"currency":"BRL","expires_at":"\(date)"}
            """.utf8)
        }
        let decoder = JSONDecoder() // Same default used by FunctionsClient.invoke.
        for date in ["2026-10-23T15:30:00Z", "2026-10-23T15:30:00.123Z",
                     "2026-10-23T12:30:00.123456-03:00"] {
            for amount in ["123.45", "\"123.45\""] {
                let dto = try decoder.decode(GuinchoQuoteDTO.self, from: payload(amount: amount, date: date))
                let quote = dto.domain()
                precondition(quote.total == Decimal(string: "123.45")!)
                precondition(quote.providerName == "Guincho" && quote.durationMinutes == nil)
                precondition(abs(quote.expiresAt.timeIntervalSince1970 - 1792769400) < 1)
            }
        }
        var sized = try JSONSerialization.jsonObject(with: payload(amount: "\"123.45\"", date: "2026-11-03T15:30:00Z")) as! [String: Any]
        let vehicleID = UUID(), sizeID = UUID()
        sized["dispatch_vehicle_id"] = vehicleID.uuidString
        sized["size_id"] = sizeID.uuidString
        sized["size_name"] = "Micro-ônibus"
        sized["size_price_version"] = 7
        let sizedQuote = try decoder.decode(GuinchoQuoteDTO.self, from: JSONSerialization.data(withJSONObject: sized)).domain()
        precondition(sizedQuote.dispatchVehicleID == vehicleID && sizedQuote.sizeID == sizeID)
        precondition(sizedQuote.sizeName == "Micro-ônibus" && sizedQuote.sizePriceVersion == 7)
        precondition(sizedQuote.total == Decimal(string: "123.45")!)
        for (amount, date) in [("\"123x\"", "2026-10-23T15:30:00Z"), ("123.45", "invalid")] {
            do {
                _ = try decoder.decode(GuinchoQuoteDTO.self, from: payload(amount: amount, date: date))
                preconditionFailure("Invalid quote accepted")
            } catch is DecodingError { }
        }
        print("PASS: quote decodes ISO8601 timestamps and numeric/text amounts; rejects malformed values")
    }
}

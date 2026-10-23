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
        for (amount, date) in [("\"123x\"", "2026-10-23T15:30:00Z"), ("123.45", "invalid")] {
            do {
                _ = try decoder.decode(GuinchoQuoteDTO.self, from: payload(amount: amount, date: date))
                preconditionFailure("Invalid quote accepted")
            } catch is DecodingError { }
        }
        print("PASS: quote decodes ISO8601 timestamps and numeric/text amounts; rejects malformed values")
    }
}

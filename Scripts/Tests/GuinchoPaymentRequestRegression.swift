import Foundation

@main struct GuinchoPaymentRequestRegression {
    static func main() throws {
        let serviceID = UUID(), appointmentID = UUID(), requestID = UUID()
        let body = CreatePaymentRequestBody(request_id: requestID, dispatch_kind: "GUINCHO_DIRECT",
            service_id: serviceID, checkout_environment: "homol", amount: Decimal(string: "1.25"),
            method: "PIX", saved_card_id: nil, card_security_code_token: nil,
            appointment_id: appointmentID, quote_version: 1)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as! [String: Any]
        precondition(json["service_id"] as? String == serviceID.uuidString)
        precondition(json["checkout_environment"] as? String == "homol")
        precondition(json["method"] as? String == "PIX")
        precondition(json["appointment_id"] as? String == appointmentID.uuidString)
        precondition(json["quote_version"] as? Int == 1)
        precondition((json["amount"] as? NSNumber)?.decimalValue == Decimal(string: "1.25")!)
        print("PASS: Guincho Pix includes service, checkout environment, test amount and appointment context")
    }
}

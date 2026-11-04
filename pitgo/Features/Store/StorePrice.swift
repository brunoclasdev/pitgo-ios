import Foundation

/// Same limits as Android's BigDecimal validation and numeric(12,2) storage.
enum StorePrice {
    static func isValid(_ text: String) -> Bool {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: #"^\+?[0-9]+(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { return false }
        return amount > 0 && amount < 10_000_000_000
    }
}

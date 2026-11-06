import Foundation

// Compile alongside InternationalPhoneInput.swift with the PhoneNumberKit package.
@main
struct InternationalPhoneRegression {
    @MainActor
    static func main() {
        let input = InternationalPhoneInput()
        precondition(Set(input.countries.map(\.id)).count == input.countries.count)
        precondition(input.countries.allSatisfy { $0.id.count == 2 })
        func country(_ id: String) -> PhoneCountry { input.countries.first { $0.id == id }! }
        let brazil = country("BR")
        let us = country("US")
        let portugal = country("PT")
        let uk = country("GB")

        for (region, raw, expected) in [
            (brazil, "11987654321", "+5511987654321"),
            (brazil, "1131234567", "+551131234567"),
            (us, "2025550123", "+12025550123"),
            (portugal, "912345678", "+351912345678"),
            (uk, "07911123456", "+447911123456")
        ] {
            let formatted = input.format(raw, country: region)
            precondition(formatted != raw, "Expected a country-specific mask for \(region.id)")
            precondition(input.e164(formatted, country: region) == expected, "Invalid E.164 output for \(region.id)")
        }
        precondition(input.e164("123", country: brazil) == nil)
        precondition(input.e164("", country: us) == nil)
        precondition(input.e164("11987654321", country: portugal) == nil)
        precondition(input.format("", country: brazil).isEmpty)
        let pasted = input.internationalInput("+44 7911 123456")
        precondition(pasted != nil)
        precondition(input.e164(pasted!.number, country: pasted!.country) == "+447911123456")
        precondition(input.internationalInput("2025550123") == nil)
        let usMask = input.format("2025550123", country: us)
        let brazilMask = input.format(usMask, country: brazil)
        precondition(brazilMask != usMask, "Country changes must update the mask")
        precondition(brazilMask.filter(\.isNumber) == "2025550123", "Country changes must preserve digits")
        let partial = input.format("11987", country: brazil)
        precondition(partial.filter(\.isNumber) == "11987")
        precondition(input.format(String(partial.dropLast()), country: brazil).filter(\.isNumber) == "1198")
        print("International phone regression checks passed")
    }
}

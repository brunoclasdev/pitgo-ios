import Foundation
import PhoneNumberKit

struct PhoneCountry: Identifiable, Hashable {
    let id: String
    let name: String
    let callingCode: String

    var flag: String {
        String(String.UnicodeScalarView(id.unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value)
        }))
    }
}

/// Shares one metadata parser across formatting, country selection and validation.
final class InternationalPhoneInput {
    private let utility = PhoneNumberUtility()
    let countries: [PhoneCountry]

    init() {
        let locale = Locale.current
        let utility = self.utility
        countries = utility.allCountries().compactMap { region in
            guard region.count == 2, let code = utility.countryCode(for: region) else { return nil }
            return PhoneCountry(id: region, name: locale.localizedString(forRegionCode: region) ?? region, callingCode: "+\(code)")
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func format(_ input: String, country: PhoneCountry) -> String {
        let digits = input.filter { $0.isASCII && $0.isNumber }
        return PartialFormatter(utility: utility, defaultRegion: country.id, withPrefix: false, maxDigits: 15)
            .formatPartial(digits)
    }

    func e164(_ input: String, country: PhoneCountry) -> String? {
        guard let number = try? utility.parse(input, withRegion: country.id),
              "+\(number.countryCode)" == country.callingCode else { return nil }
        return utility.format(number, toType: .e164)
    }

    /// Pasting a complete international number selects its country without duplicating the DDI.
    func internationalInput(_ input: String) -> (country: PhoneCountry, number: String)? {
        guard input.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+"),
              let number = try? utility.parse(input),
              let region = utility.getRegionCode(of: number),
              let country = countries.first(where: { $0.id == region }) else { return nil }
        return (country, utility.format(number, toType: .national))
    }
}

import SwiftUI

struct ProviderRatingSummaryLabel: View {
    let summary: ProviderRatingSummary?

    var body: some View {
        Group {
            if let summary, summary.isValid {
                if summary.count == 0 {
                    Text("Ainda não há avaliações")
                } else {
                    Label("\(formattedAverage) · \(summary.count) avaliações", systemImage: "star.fill")
                        .accessibilityLabel("Média \(formattedAverage) de 5, \(summary.count) avaliações")
                }
            }
        }
        .font(PitGoTypography.caption)
        .foregroundStyle(.secondary)
    }

    private var formattedAverage: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: summary?.average ?? 0)) ?? "0,0"
    }
}

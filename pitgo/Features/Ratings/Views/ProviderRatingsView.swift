import SwiftUI

struct ProviderRatingsView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: ProviderRatingsViewModel
    let onClose: () -> Void

    init(providerID: UUID, repository: ServiceRatingRepository, onClose: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: ProviderRatingsViewModel(providerID: providerID, repository: repository))
        self.onClose = onClose
    }

    var body: some View {
        List {
            Section("Sua reputação") {
                if viewModel.isLoadingSummary && viewModel.summary == nil {
                    ProgressView()
                } else if viewModel.summaryFailed {
                    Button("Não foi possível carregar a média. Tentar novamente") { viewModel.loadSummary() }
                } else {
                    ProviderRatingSummaryLabel(summary: viewModel.summary)
                    if let summary = viewModel.summary, summary.count > 0 {
                        Text("\(summary.count) avaliações recebidas")
                            .font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                    }
                }
            }
            Section("Comentários recebidos") {
                if viewModel.isLoadingRatings && viewModel.ratings.isEmpty {
                    ProgressView()
                } else if viewModel.ratingsFailed && viewModel.ratings.isEmpty {
                    Button("Não foi possível carregar os comentários. Tentar novamente") { viewModel.loadRatings(reset: true) }
                } else if viewModel.ratings.isEmpty {
                    Text("Você ainda não recebeu comentários.").foregroundStyle(tokens.textSecondary)
                }
                ForEach(viewModel.ratings) { rating in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("\(rating.rating) de 5", systemImage: "star.fill").foregroundStyle(.orange)
                            Spacer()
                            Text(rating.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                        }
                        if let comment = rating.comment, !comment.isEmpty {
                            Text(comment).font(PitGoTypography.body)
                        } else {
                            Text("Sem comentário").font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                        }
                    }
                    .padding(.vertical, 5)
                }
                if viewModel.ratingsFailed && !viewModel.ratings.isEmpty {
                    Button("Não foi possível carregar mais. Tentar novamente") { viewModel.loadRatings() }
                } else if viewModel.hasMore {
                    Button("Carregar mais") { viewModel.loadRatings() }.disabled(viewModel.isLoadingRatings)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(tokens.background)
        .navigationTitle("Avaliações recebidas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onClose) { Image(systemName: "chevron.left") }.accessibilityLabel("Voltar")
            }
        }
        .task { viewModel.loadSummary(); viewModel.loadRatings() }
    }
}

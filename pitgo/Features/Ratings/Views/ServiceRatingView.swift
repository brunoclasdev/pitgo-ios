import SwiftUI

struct ServiceRatingView: View {
    @StateObject private var viewModel: ServiceRatingViewModel
    @State private var didNotifySaved = false
    let onClose: () -> Void
    let onSaved: () -> Void

    init(
        appointmentID: UUID,
        repository: ServiceRatingRepository,
        onClose: @escaping () -> Void = {},
        onSaved: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: ServiceRatingViewModel(appointmentID: appointmentID, repository: repository))
        self.onClose = onClose
        self.onSaved = onSaved
    }

    var body: some View {
        ScrollView {
            viewContent
                .padding(20)
        }
        .navigationTitle("Avaliar atendimento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onClose) { Image(systemName: "xmark") }.accessibilityLabel("Fechar avaliação")
            }
        }
        .task { viewModel.load() }
        .onChange(of: viewModel.phase) { phase in
            if case .saved = phase, !didNotifySaved {
                didNotifySaved = true
                onSaved()
            }
        }
    }

    @ViewBuilder
    private var viewContent: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView("Carregando avaliação…").frame(maxWidth: .infinity, minHeight: 220)
        case .loadFailure:
            VStack(spacing: 12) {
                Text("Não foi possível carregar a avaliação.")
                Button("Tentar novamente") { viewModel.load() }
                Button("Fechar", action: onClose)
            }.frame(maxWidth: .infinity, minHeight: 220)
        case .ineligible:
            VStack(spacing: 12) {
                Text("Este atendimento não pode receber uma avaliação.")
                Button("Fechar", action: onClose)
            }.frame(maxWidth: .infinity, minHeight: 220)
        case let .saved(rating):
            SavedServiceRatingContent(rating: rating, onClose: onClose)
        case .ready, .submitting, .submitFailure:
            ServiceRatingForm(
                providerName: viewModel.providerName,
                selectedRating: viewModel.selectedRating,
                comment: viewModel.comment,
                phase: viewModel.phase,
                onSelect: viewModel.select,
                onComment: viewModel.setComment,
                onSubmit: viewModel.submit,
                onClose: onClose
            )
        }
    }
}

private struct ServiceRatingForm: View {
    @Environment(\.pitGoTokens) private var tokens
    let providerName: String
    let selectedRating: Int?
    let comment: String
    let phase: ServiceRatingPhase
    let onSelect: (Int) -> Void
    let onComment: (String) -> Void
    let onSubmit: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Como foi o atendimento de \(providerName)?")
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            ServiceRatingStars(selectedRating: selectedRating, isEnabled: phase == .ready || phase == .submitFailure, onSelect: onSelect)
            Text("Comentário opcional").font(PitGoTypography.body)
            ServiceRatingComment(comment: comment, isEnabled: phase == .ready || phase == .submitFailure, onChange: onComment)
            Text("\(comment.unicodeScalars.count)/500")
                .font(PitGoTypography.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if phase == .submitFailure {
                Text("Não foi possível confirmar o envio. Sua avaliação continua aqui; tente novamente.")
                    .foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently)
            }
            Button(action: onSubmit) {
                if phase == .submitting {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 50)
                } else if phase == .submitFailure {
                    Text("Tentar novamente").frame(maxWidth: .infinity, minHeight: 50)
                } else {
                    Text("Enviar avaliação").frame(maxWidth: .infinity, minHeight: 50)
                }
            }
            .foregroundStyle(.white).background(tokens.accent).clipShape(Capsule())
            .disabled((phase != .ready && phase != .submitFailure) || selectedRating == nil)
            Button("Agora não", action: onClose)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(phase == .submitting)
        }
    }
}

private struct ServiceRatingStars: View {
    let selectedRating: Int?
    let isEnabled: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { value in
                Button(action: { onSelect(value) }) {
                    Image(systemName: value <= (selectedRating ?? 0) ? "star.fill" : "star")
                        .font(.system(size: 34))
                        .foregroundStyle(value <= (selectedRating ?? 0) ? Color.orange : Color.gray)
                        .frame(minWidth: 44, minHeight: 48)
                }
                .disabled(!isEnabled)
                .accessibilityLabel(value == 1 ? "1 estrela" : "\(value) estrelas")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ServiceRatingComment: View {
    let comment: String
    let isEnabled: Bool
    let onChange: (String) -> Void

    var body: some View {
        TextEditor(text: Binding(get: { comment }, set: onChange))
            .frame(minHeight: 130)
            .padding(8)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(!isEnabled)
            .accessibilityLabel("Comentário sobre o atendimento, até 500 caracteres")
    }
}

private struct SavedServiceRatingContent: View {
    let rating: ServiceRating
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 42)).foregroundStyle(.green)
            Text("Avaliação registrada").font(PitGoTypography.sectionTitle)
            Text("\(rating.rating) de 5 estrelas").font(PitGoTypography.body)
            if let comment = rating.comment, !comment.isEmpty {
                Text(comment).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Text("Esta avaliação é definitiva e não pode ser editada.")
                .font(PitGoTypography.caption).foregroundStyle(.secondary)
            Button("Concluir", action: onClose).frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

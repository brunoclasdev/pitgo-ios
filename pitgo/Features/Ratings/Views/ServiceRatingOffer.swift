import SwiftUI

/// Consulta a elegibilidade autoritativa antes de oferecer o formulário numa tela de acompanhamento.
struct ServiceRatingOffer: View {
    let appointmentID: UUID
    let repository: ServiceRatingRepository

    @State private var context: ServiceRatingContext?
    @State private var didFail = false
    @State private var isLoading = false
    @State private var showRating = false

    var body: some View {
        Group {
            if let context, context.canRate && !context.submitted {
                Button("Avaliar atendimento") { showRating = true }
                    .frame(minHeight: 44)
            } else if context?.submitted == true {
                Label("Avaliação registrada · definitiva", systemImage: "checkmark.seal.fill")
                    .font(PitGoTypography.caption)
            } else if didFail {
                Button("Tentar novamente") { load() }.frame(minHeight: 44)
            } else if isLoading {
                ProgressView("Verificando avaliação…").font(PitGoTypography.caption)
            }
        }
        .task(id: appointmentID) { load() }
        .sheet(isPresented: $showRating) {
            NavigationStack {
                ServiceRatingView(appointmentID: appointmentID, repository: repository) {
                    showRating = false
                    load()
                }
            }
        }
    }

    private func load() {
        guard !isLoading else { return }
        isLoading = true
        didFail = false
        Task {
            do { context = try await repository.get(appointmentID: appointmentID) }
            catch { didFail = true }
            isLoading = false
        }
    }
}

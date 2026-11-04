import SwiftUI

struct GuinchoHistoryView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: GuinchoHistoryViewModel
    @State private var ratingAppointmentID: UUID?
    let inspectionRepository: GuinchoInspectionRepository
    let ratingRepository: ServiceRatingRepository
    let onBack: () -> Void
    let showsBackButton: Bool

    init(repository: GuinchoHistoryRepository, inspectionRepository: GuinchoInspectionRepository, ratingRepository: ServiceRatingRepository, showsBackButton: Bool = true, onBack: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: GuinchoHistoryViewModel(repository: repository))
        self.inspectionRepository = inspectionRepository
        self.ratingRepository = ratingRepository
        self.onBack = onBack
        self.showsBackButton = showsBackButton
    }

    var body: some View {
        List {
            if viewModel.hasFailed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Não foi possível carregar o histórico.")
                    Button("Tentar novamente") { viewModel.loadMore(reset: viewModel.rows.isEmpty) }
                }
            }
            if viewModel.rows.isEmpty && !viewModel.isLoading && !viewModel.hasFailed {
                Text("Nenhum atendimento no histórico.")
                    .foregroundStyle(tokens.textSecondary)
            }
            ForEach(Array(viewModel.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.providerName ?? row.serviceName)
                        .font(PitGoTypography.categoryTitle)
                        .foregroundStyle(tokens.textPrimary)
                    Text(row.serviceName).font(PitGoTypography.body)
                    if let trip = row.guinchoTrip {
                        Text("\(trip.pickupAddress) → \(trip.destinationAddress)")
                            .font(PitGoTypography.caption)
                    }
                    Text(historyStatus(row))
                        .font(PitGoTypography.caption)
                        .foregroundStyle(tokens.textSecondary)
                    if let createdAt = row.createdAt {
                        Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(PitGoTypography.caption)
                            .foregroundStyle(tokens.textSecondary)
                    }
                    if row.ratingState?.canRate == true, let appointmentID = row.appointment?.appointmentID {
                        Button("Avaliar atendimento") { ratingAppointmentID = appointmentID }
                            .frame(minHeight: 44)
                    } else if row.ratingState?.submitted == true {
                        Label("Avaliação registrada · definitiva", systemImage: "checkmark.seal.fill")
                            .font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                    }
                    if row.dispatchKind == .guinchoDirect, let appointmentID = row.appointment?.appointmentID {
                        NavigationLink("Ver vistoria") {
                            GuinchoInspectionView(appointmentID: appointmentID, repository: inspectionRepository)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            if viewModel.isLoading { ProgressView().frame(maxWidth: .infinity) }
            if viewModel.hasMore {
                Button("Carregar mais") { viewModel.loadMore() }
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.isLoading)
            }
        }
        .navigationTitle("Histórico de atendimentos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsBackButton {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onBack) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Voltar")
                }
            }
        }
        .task { if viewModel.rows.isEmpty { viewModel.loadMore(reset: true) } }
        .sheet(isPresented: Binding(
            get: { ratingAppointmentID != nil },
            set: { if !$0 { ratingAppointmentID = nil } }
        ), onDismiss: { viewModel.loadMore(reset: true) }) {
            if let appointmentID = ratingAppointmentID {
                NavigationStack {
                    ServiceRatingView(appointmentID: appointmentID, repository: ratingRepository) {
                        ratingAppointmentID = nil
                    }
                }
            }
        }
    }

    private func historyStatus(_ row: MobileDispatchSnapshot) -> String {
        if row.guinchoDispute?.status == .open { return "Em contestação" }
        switch row.appointment?.status {
        case .completed: return "Concluído"
        case .cancelled: return "Cancelado"
        default: return "Em andamento"
        }
    }
}

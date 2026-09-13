//
//  RequestServiceView.swift
//  pitgo
//
//  Destino do CTA "SOLICITAR ATENDIMENTO" do mapa de descoberta (contracts/map-ui-navigation.md
//  "Provider summary and request"). Mostra somente dados públicos do serviço — nenhum `serviceID`/
//  `providerID` aparece na interface. Pagamento é um mock textual: a integração real de pagamento é
//  uma feature futura fora deste escopo.
//

import SwiftUI

struct RequestServiceView: View {
    @Environment(\.pitGoTokens) private var tokens
    @State private var viewModel: RequestServiceViewModel

    let onBack: () -> Void

    init(serviceID: UUID, providerID: UUID, catalogRepository: ServiceCatalogRepository, onBack: @escaping () -> Void) {
        _viewModel = State(initialValue: RequestServiceViewModel(
            serviceID: serviceID,
            providerID: providerID,
            catalogRepository: catalogRepository
        ))
        self.onBack = onBack
    }

    var body: some View {
        content
            .background(tokens.background)
            .navigationTitle("Solicitar atendimento")
            .navigationBarTitleDisplayMode(.inline)
            .task { viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Carregando…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .content(details):
            detailView(details)
        case .invalid:
            messageState(
                symbol: "questionmark.circle",
                message: "Este serviço não está mais disponível.",
                showRetry: false
            )
        case .failure:
            messageState(
                symbol: "exclamationmark.triangle",
                message: "Não foi possível carregar este serviço. Tente novamente.",
                showRetry: true
            )
        case let .confirmed(details):
            confirmationView(details)
        }
    }

    private func detailView(_ details: RequestServiceContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(details.categoryName)
                        .font(PitGoTypography.caption)
                        .foregroundStyle(tokens.textSecondary)
                    Text(details.serviceName)
                        .font(PitGoTypography.sectionTitle)
                        .accessibilityAddTraits(.isHeader)
                    if let description = details.description, !description.isEmpty {
                        Text(description)
                            .font(PitGoTypography.body)
                            .foregroundStyle(tokens.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Valor estimado")
                        .font(PitGoTypography.categoryTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text(priceText(details.minimumPrice))
                        .font(PitGoTypography.body)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Forma de pagamento")
                        .font(PitGoTypography.categoryTitle)
                        .accessibilityAddTraits(.isHeader)
                    Label("A definir na confirmação do atendimento", systemImage: "creditcard")
                        .font(PitGoTypography.body)
                        .foregroundStyle(tokens.textSecondary)
                }

                Spacer(minLength: 24)

                Button(action: { viewModel.confirm() }) {
                    Text("SOLICITAR ATENDIMENTO")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .foregroundStyle(.white)
                .background(tokens.accent)
                .clipShape(Capsule())
                .frame(minHeight: 56)
            }
            .padding(16)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Voltar")
            }
        }
    }

    private func confirmationView(_ details: RequestServiceContent) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Solicitação enviada!")
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Text("Você será avisado quando o prestador responder ao pedido de \(details.serviceName).")
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textSecondary)
                .multilineTextAlignment(.center)
            Button("Voltar", action: onBack)
                .frame(minHeight: 56)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
    }

    private func messageState(symbol: String, message: String, showRetry: Bool) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(tokens.textSecondary)
            Text(message)
                .font(PitGoTypography.body)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.updatesFrequently)
            if showRetry {
                Button("Tentar novamente") { viewModel.retry() }
                    .frame(minHeight: 44)
            }
            Button("Voltar", action: onBack)
                .frame(minHeight: 44)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
    }

    private func priceText(_ price: Decimal?) -> String {
        guard let price else { return "Sob consulta" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        let formatted = formatter.string(from: price as NSDecimalNumber) ?? "R$ \(price)"
        return "A partir de \(formatted)"
    }
}

//
//  PaymentCheckoutView.swift
//  pitgo
//
//  Apresentada como `.sheet` a partir de `ClientMobileDispatchView`/`PitTecClientView` (`018`) — não
//  como uma nova `PitGoRoute`, ao contrário do que `contracts/payment-realtime-ui.md` descreve. A
//  troca evita alterar os dois `switch` exaustivos de `PitGoRootView` para uma tela inteiramente
//  transitória, e usa o mesmo idioma já existente de `DispatchCancellationSheet` (`013`). Em
//  `.approved`, `onApproved(requestID)` deixa a tela que apresentou o sheet chamar sua própria RPC
//  de despacho (`request_mobile_dispatch_candidate` já reservado, ou `start_pittec_dispatch`) — este
//  checkout nunca despacha nada sozinho.
//

import SwiftUI

struct PaymentCheckoutView: View {
    @Environment(\.pitGoTokens) private var tokens
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PaymentCheckoutViewModel
    @State private var copiedFeedback = false

    let onApproved: (UUID) -> Void
    let onSessionExpired: () -> Void

    init(
        serviceID: UUID,
        dispatchKind: PaymentDispatchKind,
        catalogRepository: ServiceCatalogRepository,
        paymentRepository: PaymentRepository,
        savedCardRepository: SavedCardRepository,
        pittecContext: PitTecPaymentContext? = nil,
        onApproved: @escaping (UUID) -> Void,
        onSessionExpired: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: PaymentCheckoutViewModel(
            serviceID: serviceID,
            dispatchKind: dispatchKind,
            catalogRepository: catalogRepository,
            paymentRepository: paymentRepository,
            savedCardRepository: savedCardRepository,
            pittecContext: pittecContext
        ))
        self.onApproved = onApproved
        self.onSessionExpired = onSessionExpired
    }

    var body: some View {
        NavigationStack {
            content
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tokens.background)
                .navigationTitle("Pagamento")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar", action: { dismiss() })
                            .disabled(isBusy)
                    }
                }
        }
        .interactiveDismissDisabled(isBusy)
        .task { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onChange(of: viewModel.state) { _, state in
            if case .approved = state {
                onApproved(viewModel.requestID)
            }
            if case .sessionExpired = state {
                onSessionExpired()
            }
        }
    }

    private var isBusy: Bool {
        switch viewModel.state {
        case .creatingPayment, .awaitingPix, .awaitingCardConfirmation: true
        default: false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loadingAmount, .creatingPayment:
            ProgressView()
        case .invalidService:
            messageState(
                symbol: "exclamationmark.triangle",
                message: "Este serviço não está disponível para pagamento no momento.",
                primaryAction: nil
            )
        case let .selectingMethod(amount, savedCards):
            selectingMethodState(amount: amount, savedCards: savedCards)
        case let .awaitingPix(pix):
            awaitingPixState(pix)
        case .awaitingCardConfirmation:
            VStack(spacing: 16) {
                ProgressView()
                Text("Confirmando pagamento…")
                    .font(PitGoTypography.body)
            }
        case .approved:
            messageState(symbol: "checkmark.circle.fill", message: "Pagamento aprovado.", primaryAction: nil)
        case .declined:
            messageState(
                symbol: "xmark.circle",
                message: "Pagamento recusado.",
                primaryAction: ("Tentar outro método", viewModel.chooseAnotherMethod)
            )
        case .expired:
            messageState(
                symbol: "clock.badge.exclamationmark",
                message: "O prazo do Pix expirou.",
                primaryAction: ("Gerar novo código", viewModel.retryPix),
                secondaryAction: ("Trocar forma de pagamento", viewModel.chooseAnotherMethod)
            )
        case .payerDocumentRequired:
            messageState(
                symbol: "person.text.rectangle",
                message: "Cadastre seu CPF no Perfil para pagar com Pix.",
                primaryAction: nil
            )
        case .sessionExpired:
            Color.clear
        case .failure:
            messageState(
                symbol: "wifi.exclamationmark",
                message: "Não foi possível concluir agora. Tente novamente.",
                primaryAction: ("Trocar forma de pagamento", viewModel.chooseAnotherMethod)
            )
        }
    }

    // MARK: - Seleção de método

    private func selectingMethodState(amount: Decimal, savedCards: [SavedCard]) -> some View {
        VStack(spacing: 20) {
            Text(formattedAmount(amount))
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            Button(action: viewModel.payWithPix) {
                Label("Pagar com Pix", systemImage: "qrcode")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .foregroundStyle(.white)
            .background(tokens.accent)
            .clipShape(Capsule())
            .frame(minHeight: 56)

            if !savedCards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cartões salvos").font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                    ForEach(savedCards) { card in
                        Button(action: { viewModel.payWithSavedCard(card) }) {
                            HStack {
                                Image(systemName: "creditcard").accessibilityHidden(true)
                                Text("\(card.brand.capitalized) •••• \(card.lastFourDigits)")
                                Spacer()
                            }
                            .padding()
                        }
                        .foregroundStyle(tokens.textPrimary)
                        .background(tokens.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(tokens.outline, lineWidth: 1))
                        .frame(minHeight: 44)
                    }
                }
            }

            // FR-019: nenhum atalho de cadastro de cartão aqui — só em Perfil → Formas de pagamento.
            Spacer()
        }
    }

    // MARK: - Pix

    private func awaitingPixState(_ pix: PaymentPixDetails) -> some View {
        VStack(spacing: 16) {
            if let image = decodeQRCode(pix.qrCodeBase64) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .accessibilityLabel("QR Code do Pix")
            }
            if let expiresAt = pix.expiresAt, expiresAt > Date() {
                Text(timerInterval: Date() ... expiresAt, countsDown: true)
                    .font(PitGoTypography.caption)
                    .foregroundStyle(tokens.textSecondary)
                    .monospacedDigit()
            }
            Button(action: { copyPixCode(pix.qrCode) }) {
                Label(copiedFeedback ? "Copiado!" : "Copiar código Pix", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .frame(minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(tokens.outline, lineWidth: 1))
            Text("Assim que o pagamento for aprovado, o atendimento é despachado automaticamente.")
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Trocar forma de pagamento", action: viewModel.chooseAnotherMethod)
                .frame(minHeight: 44)
        }
    }

    private func copyPixCode(_ code: String) {
        UIPasteboard.general.string = code
        copiedFeedback = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copiedFeedback = false
        }
    }

    private func decodeQRCode(_ base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Genérico

    private func messageState(
        symbol: String,
        message: String,
        primaryAction: (String, () -> Void)?,
        secondaryAction: (String, () -> Void)? = nil
    ) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(tokens.textSecondary)
            Text(message)
                .font(PitGoTypography.body)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.updatesFrequently)
            if let primaryAction {
                Button(primaryAction.0, action: primaryAction.1)
                    .frame(minHeight: 44)
            }
            if let secondaryAction {
                Button(secondaryAction.0, action: secondaryAction.1)
                    .frame(minHeight: 44)
            }
            Spacer()
        }
    }

    private func formattedAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: amount as NSDecimalNumber) ?? "R$ \(amount)"
    }
}

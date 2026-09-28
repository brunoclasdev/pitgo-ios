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

import CoreMethods
import os
import SwiftUI

struct PaymentCheckoutView: View {
    private static let logger = Logger(subsystem: "com.trustarx.pitgo", category: "PaymentCheckout")
    @Environment(\.pitGoTokens) private var tokens
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PaymentCheckoutViewModel
    @State private var copiedFeedback = false
    @State private var securityCodeField: SecurityCodeTextField?
    @State private var cardTokenError: String?
    @State private var tokenizingCard = false
    @State private var presentedCardContext: SavedCardTokenizationContext?

    let onApproved: (UUID) -> Void
    let onCancelled: () -> Void
    let onSessionExpired: () -> Void

    init(
        serviceID: UUID,
        dispatchKind: PaymentDispatchKind,
        catalogRepository: ServiceCatalogRepository,
        paymentRepository: PaymentRepository,
        savedCardRepository: SavedCardRepository,
        pittecContext: PitTecPaymentContext? = nil,
        onApproved: @escaping (UUID) -> Void,
        onCancelled: @escaping () -> Void = {},
        onSessionExpired: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: PaymentCheckoutViewModel(
            serviceID: serviceID,
            dispatchKind: dispatchKind,
            catalogRepository: catalogRepository,
            paymentRepository: paymentRepository,
            savedCardRepository: savedCardRepository,
            pittecContext: pittecContext
        ))
        self.onApproved = onApproved
        self.onCancelled = onCancelled
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
                        Button("Cancelar", action: cancelCheckout)
                            .disabled(isBusy)
                    }
                }
        }
        .interactiveDismissDisabled(isBusy)
        .task { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onChange(of: viewModel.state) { state in
            if case .approved = state {
                onApproved(viewModel.requestID)
            }
            if case .sessionExpired = state {
                onSessionExpired()
            }
            if case let .confirmingCard(context) = state {
                presentedCardContext = context
            } else {
                presentedCardContext = nil
            }
        }
        .sheet(item: $presentedCardContext) { context in
            savedCardSecurityCodeSheet(context)
        }
    }

    private var isBusy: Bool {
        switch viewModel.state {
        case .loadingCardContext, .confirmingCard, .creatingPayment, .awaitingPix, .awaitingCardConfirmation: true
        default: false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loadingAmount, .loadingCardContext, .creatingPayment:
            ProgressView()
        case .invalidService:
            messageState(
                symbol: "exclamationmark.triangle",
                message: "Este serviço não está disponível para pagamento no momento.",
                primaryAction: nil
            )
        case let .selectingMethod(amount, savedCards):
            selectingMethodState(amount: amount, savedCards: savedCards)
        case .confirmingCard:
            ProgressView()
        case let .awaitingPix(pix):
            awaitingPixState(pix)
        case .awaitingCardConfirmation:
            VStack(spacing: 16) {
                ProgressView()
                Text("Confirmando pagamento…")
                    .font(PitGoTypography.body)
                Text("Estamos aguardando a confirmação do Mercado Pago.")
                    .font(PitGoTypography.caption)
                    .foregroundStyle(tokens.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Cancelar pagamento", role: .cancel, action: cancelCheckout)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        case .approved:
            messageState(symbol: "checkmark.circle.fill", message: "Pagamento aprovado.", primaryAction: nil)
        case .declined:
            messageState(
                symbol: "xmark.circle",
                message: "Pagamento recusado. Escolha outro cartão ou pague com Pix.",
                primaryAction: ("Trocar forma de pagamento", viewModel.chooseAnotherMethod),
                secondaryAction: ("Cancelar pagamento", cancelCheckout)
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

    private func savedCardSecurityCodeSheet(_ context: SavedCardTokenizationContext) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Digite o CVV do cartão para confirmar o pagamento.")
                    .font(PitGoTypography.body)
                SecurityCodeTextFieldView(textField: $securityCodeField, placeholder: "CVV")
                    .maxLength(4)
                    .frame(height: 44)
                if let cardTokenError {
                    Text(cardTokenError).foregroundStyle(.red).font(PitGoTypography.caption)
                }
                Button("Confirmar pagamento") { tokenizeSavedCard(context) }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white)
                    .background(tokens.accent)
                    .clipShape(Capsule())
                    .disabled(securityCodeField == nil || tokenizingCard)
                if tokenizingCard { ProgressView().frame(maxWidth: .infinity) }
                Button("Cancelar pagamento", role: .cancel, action: cancelCheckout)
                    .frame(maxWidth: .infinity, minHeight: 44)
                Spacer()
            }
            .padding(24)
            .navigationTitle("Confirmar cartão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", action: cancelCheckout)
                        .disabled(tokenizingCard)
                }
            }
        }
        .interactiveDismissDisabled(tokenizingCard)
        .onAppear {
            securityCodeField = nil
            cardTokenError = nil
        }
    }

    private func tokenizeSavedCard(_ context: SavedCardTokenizationContext) {
        guard let securityCodeField else { return }
        tokenizingCard = true
        cardTokenError = nil
        Task {
            do {
                let token = try await CoreMethods().createToken(cardID: context.cardID, securityCode: securityCodeField)
                tokenizingCard = false
                viewModel.confirmSavedCard(token: token.token, context: context)
            } catch {
                Self.logger.error("Falha ao gerar token do cartão salvo: \(String(describing: error), privacy: .public)")
                tokenizingCard = false
                cardTokenError = "Não foi possível validar o cartão. Confira o CVV e tente novamente."
            }
        }
    }

    private func cancelCheckout() {
        onCancelled()
        dismiss()
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
            Button("Cancelar pagamento", role: .cancel, action: cancelCheckout)
                .frame(maxWidth: .infinity, minHeight: 44)
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
            Button("Cancelar pagamento", role: .cancel, action: cancelCheckout)
                .frame(maxWidth: .infinity, minHeight: 44)
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

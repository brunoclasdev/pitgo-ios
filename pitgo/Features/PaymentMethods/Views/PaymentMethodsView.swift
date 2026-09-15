//
//  PaymentMethodsView.swift
//  pitgo
//
//  "Formas de pagamento" (`018`) — única tela onde um cartão pode ser cadastrado (FR-019: nunca
//  inline no checkout). Campos seguros do SDK nativo do Mercado Pago (módulo `CoreMethods`,
//  confirmados nesta sessão lendo o código-fonte real do pacote resolvido via SPM — ver
//  research.md §1): `CardNumberTextFieldView`/`ExpirationDateTextFieldView`/
//  `SecurityCodeTextFieldView`, cada um com seu próprio `Binding<...TextField?>` preenchido pelo
//  próprio SDK; o app nunca lê PAN/CVV em texto claro.
//

import CoreMethods
import SwiftUI

struct PaymentMethodsView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: PaymentMethodsViewModel
    @State private var isPresentingForm = false

    init(repository: SavedCardRepository) {
        _viewModel = StateObject(wrappedValue: PaymentMethodsViewModel(repository: repository))
    }

    var body: some View {
        content
            .background(tokens.background)
            .navigationTitle("Formas de pagamento")
            .navigationBarTitleDisplayMode(.inline)
            .task { viewModel.start() }
            .sheet(isPresented: $isPresentingForm) {
                CardRegistrationForm(viewModel: viewModel, isPresented: $isPresentingForm)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure:
            VStack(spacing: 16) {
                Text("Não foi possível carregar seus cartões.")
                    .font(PitGoTypography.body)
                    .multilineTextAlignment(.center)
                Button("Tentar novamente") { viewModel.reload() }
                    .frame(minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .content(cards):
            listState(cards)
        }
    }

    private func listState(_ cards: [SavedCard]) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if cards.isEmpty {
                    VStack(spacing: 8) {
                        Text("Nenhum cartão cadastrado.")
                            .font(PitGoTypography.body)
                            .foregroundStyle(tokens.textSecondary)
                        Text("O cadastro é totalmente opcional — Pix continua disponível sem ele.")
                            .font(PitGoTypography.caption)
                            .foregroundStyle(tokens.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                } else {
                    ForEach(cards) { card in
                        cardRow(card)
                    }
                }
                registerButton
            }
            .padding(16)
        }
    }

    private func cardRow(_ card: SavedCard) -> some View {
        HStack {
            Image(systemName: "creditcard").foregroundStyle(tokens.accent).accessibilityHidden(true)
            Text("\(card.brand.capitalized) •••• \(card.lastFourDigits)")
            Spacer()
            if viewModel.removingID == card.id {
                ProgressView()
            } else {
                Button(role: .destructive, action: { viewModel.remove(card) }) {
                    Image(systemName: "trash")
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Remover cartão")
            }
        }
        .padding()
        .background(tokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(tokens.outline, lineWidth: 1))
    }

    @ViewBuilder
    private var registerButton: some View {
        if ManagedMercadoPagoConfiguration.current != nil {
            Button(action: { isPresentingForm = true }) {
                Label("Cadastrar cartão", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .foregroundStyle(.white)
            .background(tokens.accent)
            .clipShape(Capsule())
            .frame(minHeight: 56)
        } else {
            Text("Cadastro de cartão indisponível no momento.")
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textSecondary)
        }
    }
}

/// Formulário de tokenização — vive num `.sheet` próprio para que os campos seguros do SDK sejam
/// recriados a cada tentativa (o SDK não oferece um "limpar" explícito).
private struct CardRegistrationForm: View {
    @Environment(\.pitGoTokens) private var tokens
    @ObservedObject var viewModel: PaymentMethodsViewModel
    @Binding var isPresented: Bool

    @State private var cardNumberField: CardNumberTextField?
    @State private var expirationField: ExpirationDateTextfield?
    @State private var securityCodeField: SecurityCodeTextField?
    @State private var cardHolderName = ""
    @State private var formError: String?
    @State private var isTokenizing = false
    /// Cópia manual do valor anterior de `isSubmitting` — `onChange(of:)` de um único parâmetro
    /// (compatível com iOS 16) não entrega o valor antigo como a variante de dois parâmetros. Seguro
    /// iniciar em `false`: este formulário é recriado do zero a cada abertura do `.sheet`, sempre com
    /// `viewModel.isSubmitting == false` no primeiro corpo renderizado.
    @State private var wasSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Número do cartão").font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                    CardNumberTextFieldView(
                        textField: $cardNumberField,
                        placeholder: "0000 0000 0000 0000",
                        onBinChanged: { _ in },
                        onLastFourDigitsFilled: { _ in },
                        onFocusChanged: { _ in },
                        onError: { _ in formError = "Número de cartão inválido." }
                    )
                    .frame(height: 44)

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Validade").font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                            ExpirationDateTextFieldView(textField: $expirationField, placeholder: "MM/AA")
                                .frame(height: 44)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CVV").font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                            SecurityCodeTextFieldView(textField: $securityCodeField, placeholder: "CVV")
                                .frame(height: 44)
                        }
                    }

                    Text("Nome impresso no cartão").font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                    TextField("Nome no cartão", text: $cardHolderName)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.words)

                    if let formError {
                        Text(formError)
                            .font(PitGoTypography.caption)
                            .foregroundStyle(.red)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    if let submitError = viewModel.submitError {
                        Text(submitError)
                            .font(PitGoTypography.caption)
                            .foregroundStyle(.red)
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    Button(action: submit) {
                        ZStack {
                            if isTokenizing || viewModel.isSubmitting { ProgressView() }
                            Text("Salvar cartão").opacity(isTokenizing || viewModel.isSubmitting ? 0 : 1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .foregroundStyle(.white)
                    .background(tokens.accent)
                    .clipShape(Capsule())
                    .frame(minHeight: 56)
                    .disabled(isTokenizing || viewModel.isSubmitting || !canSubmit)
                }
                .padding(16)
            }
            .background(tokens.background)
            .navigationTitle("Cadastrar cartão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { isPresented = false }
                }
            }
        }
        .onChange(of: viewModel.isSubmitting) { isSubmitting in
            // Cadastro concluído sem erro — fecha o formulário sozinho; um erro mantém a tela aberta
            // para nova tentativa (US2 cenário 2).
            if wasSubmitting, !isSubmitting, viewModel.submitError == nil {
                isPresented = false
            }
            wasSubmitting = isSubmitting
        }
    }

    private var canSubmit: Bool {
        cardNumberField != nil && expirationField != nil && securityCodeField != nil
    }

    private func submit() {
        guard let cardNumberField, let expirationField, let securityCodeField else { return }
        formError = nil
        isTokenizing = true
        Task {
            do {
                let token = try await CoreMethods().createToken(
                    cardNumber: cardNumberField,
                    expirationDate: expirationField,
                    securityCode: securityCodeField,
                    cardHolderName: cardHolderName.isEmpty ? nil : cardHolderName
                )
                isTokenizing = false
                viewModel.registerCard(token: token.token)
            } catch {
                isTokenizing = false
                formError = "Não foi possível processar o cartão. Confira os dados e tente novamente."
            }
        }
    }
}

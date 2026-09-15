//
//  PaymentMethodsViewModel.swift
//  pitgo
//
//  Formas de pagamento (`018`) — área dedicada do Perfil; cadastro de cartão é sempre opcional e
//  nunca acontece a partir do checkout (FR-005/FR-019).
//

import Combine
import Foundation

enum PaymentMethodsUiState: Equatable {
    case loading
    case content([SavedCard])
    case failure
}

@MainActor
final class PaymentMethodsViewModel: ObservableObject {
    @Published private(set) var state: PaymentMethodsUiState = .loading
    @Published private(set) var isSubmitting = false
    @Published private(set) var submitError: String?
    @Published private(set) var removingID: SavedCard.ID?

    private let repository: SavedCardRepository
    private var isStarted = false

    init(repository: SavedCardRepository) {
        self.repository = repository
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        reload()
    }

    func reload() {
        state = .loading
        Task { [weak self] in
            guard let self else { return }
            switch await self.repository.list() {
            case let .success(cards):
                self.state = .content(cards)
            case .failure:
                self.state = .failure
            }
        }
    }

    /// `token` vem do SDK nativo (`CoreMethods.createToken`) — o PAN/CVV nunca chegam aqui (FR-006).
    func registerCard(token: String) {
        guard !isSubmitting else { return }
        isSubmitting = true
        submitError = nil
        Task { [weak self] in
            guard let self else { return }
            switch await self.repository.save(cardToken: token) {
            case .success:
                self.isSubmitting = false
                self.reload()
            case let .failure(reason):
                self.isSubmitting = false
                self.submitError = self.message(for: reason)
            }
        }
    }

    func dismissSubmitError() {
        submitError = nil
    }

    func remove(_ card: SavedCard) {
        guard removingID == nil else { return }
        removingID = card.id
        Task { [weak self] in
            guard let self else { return }
            _ = await self.repository.remove(id: card.id)
            self.removingID = nil
            self.reload()
        }
    }

    private func message(for reason: SavedCardFailureReason) -> String {
        switch reason {
        case .cardRejected: "Cartão recusado. Confira os dados e tente novamente, ou tente outro cartão."
        case .offline: "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .timeout, .serviceUnavailable: "Não foi possível concluir agora. Tente novamente em instantes."
        case .sessionExpired: "Sua sessão expirou. Entre novamente."
        case .notFound: "Cartão não encontrado."
        case .unknown: "Não foi possível cadastrar o cartão. Tente novamente."
        }
    }
}

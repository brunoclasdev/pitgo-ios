//
//  DispatchResumeCoordinator.swift
//  pitgo
//
//  Decide o destino inicial de despacho ao autenticar/reabrir o app (`013`,
//  contracts/mobile-dispatch-ui-navigation.md "Retomada e back stack"). Reaproveita
//  `get_my_active_mobile_dispatch()` — o mesmo endpoint já retorna o contexto certo pelo papel da
//  sessão; o coordinator só traduz o snapshot no destino tipado da rota. Não decide papel sozinho —
//  quem chama já sabe se está no lado cliente ou provider (`AppSessionState`).
//

import Foundation

enum DispatchResumeDestination: Equatable {
    case none
    case clientSearch(searchID: UUID)
    case clientTracking(appointmentID: UUID)
    case providerIncoming(appointmentID: UUID)
    case providerTracking(appointmentID: UUID)
}

@MainActor
final class DispatchResumeCoordinator {
    private let repository: MobileDispatchRepository

    init(repository: MobileDispatchRepository) {
        self.repository = repository
    }

    func resolveForClient() async -> DispatchResumeDestination {
        switch await repository.getActiveDispatch() {
        case let .snapshot(snapshot):
            // `028`: Guincho nunca usa a tela genérica de tracking — o acompanhamento inteiro
            // (chegada, transporte, conclusão, contestação) vive em `ClientMobileDispatchView`
            // (ver `guinchoAcceptedState`), então sempre retoma por `.clientSearch`.
            if snapshot.dispatchKind != .guinchoDirect,
               let appointment = snapshot.appointment, appointment.status == .accepted || appointment.status == .inProgress {
                return .clientTracking(appointmentID: appointment.appointmentID)
            }
            return snapshot.status.isTerminal ? .none : .clientSearch(searchID: snapshot.searchID)
        case .noActiveFlow, .failure:
            return .none
        }
    }

    func resolveForProvider() async -> DispatchResumeDestination {
        switch await repository.getActiveDispatch() {
        case let .snapshot(snapshot):
            guard let appointment = snapshot.appointment else { return .none }
            // `028`: Guincho fica inteiramente em `ProviderIncomingRequestView` (ver
            // `guinchoReservedState`) — nunca em `ProviderTrackingView` (publicação de localização
            // do guincho móvel clássico, fora do escopo deste porte).
            if snapshot.dispatchKind == .guinchoDirect {
                switch appointment.status {
                case .pending, .accepted, .inProgress, .awaitingClientCompletionConfirmation, .disputed:
                    return .providerIncoming(appointmentID: appointment.appointmentID)
                default:
                    return .none
                }
            }
            switch appointment.status {
            case .pending: return .providerIncoming(appointmentID: appointment.appointmentID)
            case .accepted, .inProgress: return .providerTracking(appointmentID: appointment.appointmentID)
            default: return .none
            }
        case .noActiveFlow, .failure:
            return .none
        }
    }
}

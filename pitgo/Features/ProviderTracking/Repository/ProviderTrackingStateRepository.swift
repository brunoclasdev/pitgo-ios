//
//  ProviderTrackingStateRepository.swift
//  pitgo
//
//  Controller `@Observable` de escopo de processo (mesmo padrão de `ProviderMigrationCoordinator`)
//  que possui o `ProviderLocationTracker` e decide `ProviderTrackingState`. Construído uma vez em
//  `PitGoRootView`. `SessionStore` sinaliza `stop()` antes de limpar uma sessão autenticada (ver
//  contracts/navigation-session.md "Tracking cleanup").
//

import CoreLocation
import Foundation

@Observable
@MainActor
final class ProviderTrackingStateRepository {
    private(set) var state: ProviderTrackingState = .stopped

    private let locationRepository: DeviceLocationRepository
    private let publishRepository: ProviderLocationRepository
    private var tracker: ProviderLocationTracker?
    private var currentAppointmentID: UUID?

    init(locationRepository: DeviceLocationRepository, publishRepository: ProviderLocationRepository) {
        self.locationRepository = locationRepository
        self.publishRepository = publishRepository
    }

    /// Solicitada somente nesse momento (ação visível na tela de atendimento aceito), nunca no
    /// cadastro (ver research.md §8).
    func requestAlwaysAuthorizationIfNeeded() {
        switch locationRepository.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            locationRepository.requestAlwaysAuthorization()
        case .authorizedAlways, .denied, .restricted:
            break
        }
    }

    /// Pré-condições (ver contracts/location-realtime.md): iniciado por ação visível, provider
    /// MOBILE/ativo/disponível e atendimento ACCEPTED/IN_PROGRESS pertencente ao provider — a
    /// verificação dessas condições é do chamador (`ProviderTrackingViewModel`); aqui só checamos
    /// permissão/serviço de localização.
    func start(appointmentID: UUID) {
        guard state == .stopped else { return }
        guard DeviceLocationServiceStatus.isEnabled else {
            state = .degraded(reason: .locationServicesDisabled)
            return
        }
        switch locationRepository.authorizationStatus {
        case .denied, .restricted:
            state = .degraded(reason: .permissionDenied)
            return
        case .notDetermined, .authorizedWhenInUse, .authorizedAlways:
            break
        }

        state = .starting
        currentAppointmentID = appointmentID
        let tracker = ProviderLocationTracker(locationRepository: locationRepository, publishRepository: publishRepository)
        tracker.onOutcome = { [weak self] result in
            self?.apply(result)
        }
        self.tracker = tracker
        tracker.start(appointmentID: appointmentID)
        state = .active(lastPublishedAt: Date())
    }

    /// Chamada em toda condição terminal (conclusão/cancelamento do atendimento, provider
    /// fixo/inativo/indisponível, perda de sessão/permissão, saída/troca de conta, parada explícita).
    func stop() {
        guard state != .stopped else { return }
        state = .stopping
        tracker?.stop(appointmentID: currentAppointmentID)
        tracker = nil
        currentAppointmentID = nil
        state = .stopped
    }

    private func apply(_ result: PublishLocationResult) {
        switch result {
        case let .published(_, publishedAt):
            state = .active(lastPublishedAt: publishedAt)
        case .ignoredOlder:
            break // fix mais antigo — não é uma condição de parada
        case .publisherConflict:
            stop()
            state = .degraded(reason: .publisherConflict)
        case .sessionExpired:
            stop()
            state = .degraded(reason: .sessionExpired)
        case .offline:
            state = .degraded(reason: .offline)
        case .service, .unknown:
            state = .degraded(reason: .service)
        }
    }
}

/// `CLLocationManager.locationServicesEnabled()` é uma chamada síncrona custosa/bloqueante em
/// algumas versões do sistema — isolada aqui para não acoplar `ProviderTrackingStateRepository`
/// diretamente ao `CoreLocation` além do necessário.
enum DeviceLocationServiceStatus {
    static var isEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }
}

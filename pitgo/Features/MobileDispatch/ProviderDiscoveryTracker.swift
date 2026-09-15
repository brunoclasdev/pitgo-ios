//
//  ProviderDiscoveryTracker.swift
//  pitgo
//
//  Motor de publicação de posição enquanto o provider móvel está "Disponível", ANTES de qualquer
//  atendimento (`013`). Mesmo desenho de `ProviderLocationTracker` (`009`, inalterado por esta
//  feature) — mas para `publish_mobile_provider_location`/`stop_mobile_provider_location`, que não
//  recebem `appointmentID`: o servidor decide sozinho se a posição vai para a discovery pública ou
//  para o tracking privado de um atendimento reservado (confirmado nesta sessão via inspeção direta
//  da função — `target: DISCOVERY|APPOINTMENT` na resposta). Por isso este tracker não precisa saber
//  qual é o alvo: publica continuamente enquanto "Disponível" estiver ligado, e o próprio backend
//  redireciona quando um atendimento é aceito.
//

import Combine
import Foundation

@MainActor
final class ProviderDiscoveryTracker: ObservableObject {
    @Published private(set) var state: ProviderTrackingState = .stopped
    /// `022` — último fix recebido pelo mesmo stream já consumido para publicar a localização de
    /// despacho; exposto só para exibição (ex.: centralizar o mapa da home do PitTec), sem criar uma
    /// segunda fonte de localização.
    @Published private(set) var lastFix: DeviceLocationFix?

    private let locationRepository: DeviceLocationRepository
    private let dispatchRepository: MobileDispatchRepository
    private let trackerInstanceID = UUID()
    private var updatesTask: Task<Void, Never>?
    private var lastPublishAttempt: Date?
    private var sequence: Int64 = 0
    private let publishInterval: TimeInterval = 10

    init(locationRepository: DeviceLocationRepository, dispatchRepository: MobileDispatchRepository) {
        self.locationRepository = locationRepository
        self.dispatchRepository = dispatchRepository
    }

    func start() {
        guard state == .stopped else { return }
        guard DeviceLocationServiceStatus.isEnabled else {
            state = .degraded(reason: .locationServicesDisabled)
            return
        }
        switch locationRepository.authorizationStatus {
        case .denied, .restricted:
            state = .degraded(reason: .permissionDenied)
            return
        case .notDetermined:
            break
        case .authorizedWhenInUse:
            // Publicar enquanto "Disponível" precisa sobreviver ao segundo plano (FR-005) —
            // solicitada só neste momento (ação visível), nunca no cadastro (research.md §3/§8).
            locationRepository.requestAlwaysAuthorization()
        case .authorizedAlways:
            break
        }

        state = .starting
        let stream = locationRepository.startHighPrecisionUpdates()
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await fix in stream {
                if Task.isCancelled { break }
                await self.handle(fix: fix)
            }
        }
        state = .active(lastPublishedAt: Date())
    }

    func stop() {
        guard state != .stopped else { return }
        state = .stopping
        updatesTask?.cancel()
        updatesTask = nil
        locationRepository.stopHighPrecisionUpdates()
        let repository = dispatchRepository
        let trackerInstanceID = trackerInstanceID
        Task { await repository.stopDiscoveryLocation(trackerInstanceID: trackerInstanceID) }
        state = .stopped
    }

    private func handle(fix: DeviceLocationFix) async {
        lastFix = fix
        let now = Date()
        if let last = lastPublishAttempt, now.timeIntervalSince(last) < publishInterval { return }
        lastPublishAttempt = now
        sequence += 1
        let result = await dispatchRepository.publishDiscoveryLocation(fix: fix, trackerInstanceID: trackerInstanceID, sequence: sequence)
        apply(result)
    }

    private func apply(_ result: DiscoveryPublishOutcome) {
        switch result {
        case let .published(_, publishedAt):
            state = .active(lastPublishedAt: publishedAt)
        case .ignored:
            break
        case .publisherConflict:
            stop()
            state = .degraded(reason: .publisherConflict)
        case let .failure(reason):
            switch reason {
            case .sessionExpired:
                stop()
                state = .degraded(reason: .sessionExpired)
            case .offline:
                state = .degraded(reason: .offline)
            default:
                state = .degraded(reason: .service)
            }
        }
    }
}

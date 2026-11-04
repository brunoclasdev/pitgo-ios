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
    @Published private(set) var isWaitingForPublisherRecovery = false
    private let leaseStore: ProviderPublisherLeaseStore
    private let scope: String
    private let conflictRetryDelay: TimeInterval
    private var ownerID = UUID()
    private var generation = UUID()
    private var updatesTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var lastPublishAttempt: Date?
    private var conflictRecoveries = 0
    private let publishInterval: TimeInterval = 10

    init(locationRepository: DeviceLocationRepository, dispatchRepository: MobileDispatchRepository,
         accountID: UUID, environment: String = EnvironmentConfig.current.fingerprint,
         leaseStore: ProviderPublisherLeaseStore? = nil, conflictRetryDelay: TimeInterval = 31) {
        let leaseStore = leaseStore ?? .shared
        self.locationRepository = locationRepository
        self.dispatchRepository = dispatchRepository
        self.leaseStore = leaseStore
        self.scope = leaseStore.scope(accountID: accountID, environment: environment)
        self.conflictRetryDelay = conflictRetryDelay
    }

    func start() { start(recoveringConflict: false) }

    func restart() {
        stop()
        start()
    }

    private func start(recoveringConflict: Bool) {
        guard startupTask == nil, updatesTask == nil else { return }
        guard DeviceLocationServiceStatus.isEnabled else {
            state = .degraded(reason: .locationServicesDisabled)
            return
        }
        switch locationRepository.authorizationStatus {
        case .denied, .restricted:
            state = .degraded(reason: .permissionDenied)
            return
        case .authorizedWhenInUse: locationRepository.requestAlwaysAuthorization()
        case .notDetermined: locationRepository.requestWhenInUseAuthorization()
        case .authorizedAlways: break
        }
        if !recoveringConflict { conflictRecoveries = 0 }
        recoveryTask?.cancel()
        recoveryTask = nil
        isWaitingForPublisherRecovery = false
        lastPublishAttempt = nil
        generation = UUID()
        ownerID = UUID()
        let token = generation
        let ownerID = ownerID
        let previousCleanup = leaseStore.claim(scope: scope, ownerID: ownerID) { [weak self] in
            guard let self, self.ownerID == ownerID else { return }
            self.stop()
        }
        state = .starting
        startupTask = Task { [weak self] in
            await previousCleanup?.value
            guard let self, !Task.isCancelled, generation == token,
                  leaseStore.isOwner(scope: scope, ownerID: ownerID) else { return }
            let stream = locationRepository.startHighPrecisionUpdates()
            updatesTask = Task { [weak self] in
                guard let self else { return }
                for await fix in stream {
                    guard !Task.isCancelled, generation == token else { break }
                    await handle(fix: fix, generation: token, ownerID: ownerID)
                }
            }
            startupTask = nil
        }
    }

    func stop() {
        generation = UUID()
        recoveryTask?.cancel()
        recoveryTask = nil
        isWaitingForPublisherRecovery = false
        let previousStartup = startupTask
        startupTask?.cancel()
        startupTask = nil
        let previousUpdates = updatesTask
        updatesTask?.cancel()
        updatesTask = nil
        let ownerID = ownerID
        let ownsPublisher = leaseStore.isOwner(scope: scope, ownerID: ownerID)
        if ownsPublisher { locationRepository.stopHighPrecisionUpdates() }
        if ownsPublisher && !leaseStore.hasCleanup(scope: scope, ownerID: ownerID) {
            let trackerID = leaseStore.lease(scope: scope).trackerID
            let scope = scope
            let cleanup = Task { [leaseStore, dispatchRepository] in
                // An older publish must finish before releasing its row or starting its successor.
                await previousStartup?.value
                await previousUpdates?.value
                guard leaseStore.isOwner(scope: scope, ownerID: ownerID) else { return }
                await dispatchRepository.stopDiscoveryLocation(trackerInstanceID: trackerID)
                leaseStore.release(scope: scope, ownerID: ownerID)
            }
            leaseStore.setCleanup(cleanup, scope: scope, ownerID: ownerID)
        }
        state = .stopped
    }

    private func handle(fix: DeviceLocationFix, generation token: UUID, ownerID: UUID) async {
        lastFix = fix
        guard (-90...90).contains(fix.latitude), (-180...180).contains(fix.longitude),
              fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= 100,
              Date().timeIntervalSince(fix.timestamp) <= 30, fix.timestamp.timeIntervalSinceNow <= 10 else { return }
        let now = Date()
        if let last = lastPublishAttempt, now.timeIntervalSince(last) < publishInterval { return }
        guard let sequence = leaseStore.nextSequence(scope: scope, ownerID: ownerID) else { return }
        lastPublishAttempt = now
        let trackerID = leaseStore.lease(scope: scope).trackerID
        let result = await dispatchRepository.publishDiscoveryLocation(fix: fix, trackerInstanceID: trackerID, sequence: sequence)
        guard !Task.isCancelled, generation == token, leaseStore.isOwner(scope: scope, ownerID: ownerID) else { return }
        switch result {
        case let .published(_, publishedAt): state = .active(lastPublishedAt: publishedAt)
        case .ignored: break
        case .publisherConflict:
            stop()
            state = .degraded(reason: .publisherConflict)
            // A one-time migration/relaunch can leave the previous random ID leased for 30s.
            // Wait for server expiry once; never forcibly replace another active publisher.
            if conflictRecoveries == 0 {
                conflictRecoveries += 1
                let token = generation
                isWaitingForPublisherRecovery = true
                recoveryTask = Task { [weak self] in
                    guard let self else { return }
                    do { try await Task.sleep(nanoseconds: UInt64(conflictRetryDelay * 1_000_000_000)) }
                    catch { return }
                    guard generation == token, !Task.isCancelled else { return }
                    isWaitingForPublisherRecovery = false
                    recoveryTask = nil
                    start(recoveringConflict: true)
                }
            }
        case let .failure(reason):
            switch reason {
            case .sessionExpired:
                stop()
                state = .degraded(reason: .sessionExpired)
            case .offline: state = .degraded(reason: .offline)
            default: state = .degraded(reason: .service)
            }
        }
    }
}

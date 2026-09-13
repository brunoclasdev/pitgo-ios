//
//  ProviderLocationTracker.swift
//  pitgo
//
//  Motor do tracking: consome o `AsyncStream` de fixes de alta precisão de `DeviceLocationRepository`
//  e publica no máximo a cada ~10s via `ProviderLocationRepository` (ver contracts/
//  location-realtime.md "Aquisição/publicação de posição móvel" de `009`). `trackerInstanceID`/
//  `sequence` satisfazem o contrato de monotonicidade já implementado no servidor. Não decide
//  elegibilidade nem possui estado de UI — isso é `ProviderTrackingStateRepository`.
//

import Foundation

@MainActor
final class ProviderLocationTracker {
    let trackerInstanceID = UUID()

    private let locationRepository: DeviceLocationRepository
    private let publishRepository: ProviderLocationRepository
    private var updatesTask: Task<Void, Never>?
    private var lastPublishAttempt: Date?
    private var sequence: Int64 = 0
    private let publishInterval: TimeInterval = 10

    /// Chamado a cada tentativa de publicação — `ProviderTrackingStateRepository` decide o que fazer
    /// com o resultado (inclusive parar em condições terminais).
    var onOutcome: ((PublishLocationResult) -> Void)?

    init(locationRepository: DeviceLocationRepository, publishRepository: ProviderLocationRepository) {
        self.locationRepository = locationRepository
        self.publishRepository = publishRepository
    }

    func start(appointmentID: UUID) {
        stopUpdatesOnly()
        let stream = locationRepository.startHighPrecisionUpdates()
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await fix in stream {
                if Task.isCancelled { break }
                await self.handle(fix: fix, appointmentID: appointmentID)
            }
        }
    }

    /// `appointmentID` presente dispara uma tentativa best-effort de `stop_provider_location`.
    func stop(appointmentID: UUID?) {
        stopUpdatesOnly()
        guard let appointmentID else { return }
        let trackerInstanceID = trackerInstanceID
        Task { [publishRepository] in
            await publishRepository.stop(appointmentID: appointmentID, trackerInstanceID: trackerInstanceID)
        }
    }

    private func stopUpdatesOnly() {
        updatesTask?.cancel()
        updatesTask = nil
        locationRepository.stopHighPrecisionUpdates()
    }

    private func handle(fix: DeviceLocationFix, appointmentID: UUID) async {
        let now = Date()
        if let last = lastPublishAttempt, now.timeIntervalSince(last) < publishInterval {
            return
        }
        lastPublishAttempt = now
        sequence += 1
        let result = await publishRepository.publish(
            appointmentID: appointmentID,
            fix: fix,
            trackerInstanceID: trackerInstanceID,
            sequence: sequence
        )
        onOutcome?(result)
    }
}

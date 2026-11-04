//
//  AppointmentTrackingViewModel.swift
//  pitgo
//
//  Mescla snapshot/broadcast somente quando a `version` recebida é mais nova (ver contracts/
//  location-realtime.md "Ordem de consumo"). Um `Task` local marca `.stale` em `publishedAt + 30s`
//  mesmo sem novo evento. Conecta em `.onAppear`/some, desconecta em `.onDisappear`/troca de sessão.
//

import Combine
import CoreLocation
import Foundation

@MainActor
final class AppointmentTrackingViewModel: ObservableObject {
    @Published private(set) var marker: AppointmentMarkerState = .unavailable

    private let repository: AppointmentTrackingRepository
    private var currentVersion: Int64 = -1
    private var staleTask: Task<Void, Never>?
    private var isConnected = false
    private var connectionTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var generation = UUID()

    init(repository: AppointmentTrackingRepository) {
        self.repository = repository
    }

    func connect(appointmentID: UUID) {
        guard !isConnected else { return }
        isConnected = true
        let publisher = ClientAppointmentLocationPublisher(repository: repository)
        locationTask = Task { await publisher.run(appointmentID: appointmentID) }
        currentVersion = -1
        marker = .unavailable
        let generation = UUID()
        self.generation = generation
        connectionTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await repository.connect(appointmentID: appointmentID) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == generation, self.isConnected else { return }
                    await self.refresh(appointmentID: appointmentID, generation: generation)
                }
            }
            guard !Task.isCancelled, self.generation == generation, isConnected else { return }
            if let snapshot { apply(snapshot) }
        }
        // Keep updating even if Realtime is unavailable or reconnects without a broadcast.
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.generation == generation, isConnected {
                await refresh(appointmentID: appointmentID, generation: generation)
                do { try await Task.sleep(nanoseconds: 5_000_000_000) }
                catch { return }
            }
        }
    }

    func disconnect() {
        guard isConnected else { return }
        isConnected = false
        locationTask?.cancel()
        locationTask = nil
        generation = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        pollTask?.cancel()
        pollTask = nil
        staleTask?.cancel()
        staleTask = nil
        Task { [repository] in await repository.disconnect() }
    }

    private var refreshing = false
    private func refresh(appointmentID: UUID, generation: UUID) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let snapshot = await repository.fetchSnapshot(appointmentID: appointmentID)
        guard !Task.isCancelled, self.generation == generation, isConnected else { return }
        if let snapshot { apply(snapshot) }
    }

    private func apply(_ snapshot: AppointmentProviderLocationSnapshot) {
        if snapshot.isEnded {
            marker = .ended
            locationTask?.cancel()
            staleTask?.cancel()
            pollTask?.cancel()
            return
        }
        if case .ended = marker { return }
        applyPosition(snapshot)
    }

    private func applyPosition(_ snapshot: AppointmentProviderLocationSnapshot) {
        if snapshot.state == "EMPTY" {
            // Like Android, an empty snapshot must not erase a known position on reconnect.
            if currentVersion < 0 { marker = .unavailable }
            return
        }
        guard let version = snapshot.version, version >= currentVersion else { return }
        guard let latitude = snapshot.latitude, let longitude = snapshot.longitude, let publishedAt = snapshot.publishedAt else {
            marker = .unavailable
            return
        }
        currentVersion = version
        let location = CLLocationCoordinate2D(latitude: NSDecimalNumber(decimal: latitude).doubleValue, longitude: NSDecimalNumber(decimal: longitude).doubleValue)
        guard CLLocationCoordinate2DIsValid(location) else { return }
        staleTask?.cancel()
        if snapshot.fresh == false {
            marker = .stale(location: location, updatedAt: publishedAt)
        } else {
            marker = .live(location: location, updatedAt: publishedAt)
            scheduleStale(after: publishedAt)
        }
    }

    /// Transiciona para `.stale` em `publishedAt + 30s` mesmo sem outro evento (SC-006).
    private func scheduleStale(after publishedAt: Date) {
        staleTask?.cancel()
        let delay = publishedAt.addingTimeInterval(30).timeIntervalSinceNow
        guard delay > 0 else {
            if case let .live(location, updatedAt) = marker {
                marker = .stale(location: location, updatedAt: updatedAt)
            }
            return
        }
        staleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if case let .live(location, updatedAt) = marker {
                marker = .stale(location: location, updatedAt: updatedAt)
            }
        }
    }
}

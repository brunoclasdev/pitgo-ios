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

    init(repository: AppointmentTrackingRepository) {
        self.repository = repository
    }

    func connect(appointmentID: UUID) {
        guard !isConnected else { return }
        isConnected = true
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await repository.connect(appointmentID: appointmentID) { [weak self] payload in
                Task { @MainActor in
                    self?.apply(payload)
                }
            }
            if let snapshot {
                apply(snapshot)
            }
        }
    }

    func disconnect() {
        guard isConnected else { return }
        isConnected = false
        staleTask?.cancel()
        staleTask = nil
        Task { [repository] in
            await repository.disconnect()
        }
    }

    private func apply(_ snapshot: AppointmentProviderLocationSnapshot) {
        guard let version = snapshot.version, version >= currentVersion else { return }
        guard let latitude = snapshot.latitude, let longitude = snapshot.longitude, let publishedAt = snapshot.publishedAt else {
            marker = .unavailable
            return
        }
        currentVersion = version
        let location = CLLocationCoordinate2D(latitude: NSDecimalNumber(decimal: latitude).doubleValue, longitude: NSDecimalNumber(decimal: longitude).doubleValue)
        if snapshot.fresh == false {
            marker = .stale(location: location, updatedAt: publishedAt)
        } else {
            marker = .live(location: location, updatedAt: publishedAt)
            scheduleStale(after: publishedAt)
        }
    }

    private func apply(_ payload: BroadcastLocationPayload) {
        guard let version = payload.version, version > currentVersion else { return }
        currentVersion = version

        if payload.event == "CLEARED" {
            marker = .ended
            staleTask?.cancel()
            return
        }

        guard let latitude = payload.latitude, let longitude = payload.longitude, let publishedAt = payload.publishedAt else { return }
        let location = CLLocationCoordinate2D(latitude: NSDecimalNumber(decimal: latitude).doubleValue, longitude: NSDecimalNumber(decimal: longitude).doubleValue)
        marker = .live(location: location, updatedAt: publishedAt)
        scheduleStale(after: publishedAt)
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

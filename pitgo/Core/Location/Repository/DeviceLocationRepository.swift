//
//  DeviceLocationRepository.swift
//  pitgo
//
//  Wrapper único de `CLLocationManager` (ver contracts/location-realtime.md e research.md §6/§9 de
//  `009`). Expõe um fix one-shot cancelável (cadastro/verificação de endereço) e um `AsyncStream` de
//  fixes de alta precisão (tracking de provider móvel). Nenhum conhecimento de sessão, provider ou
//  atendimento; nenhuma persistência em disco.
//

import CoreLocation
import Foundation

@MainActor
final class DeviceLocationRepository: NSObject {
    private let manager = CLLocationManager()
    private var oneShotID = UUID()
    private var oneShotContinuation: CheckedContinuation<DeviceLocationOneShotResult, Never>?
    private var updateContinuation: AsyncStream<DeviceLocationFix>.Continuation?
    private var updateStreamID = UUID()
    private var authorizationContinuation: AsyncStream<DeviceLocationAuthorization>.Continuation?

    override init() {
        super.init()
        manager.delegate = self
    }

    var authorizationStatus: DeviceLocationAuthorization {
        map(manager.authorizationStatus)
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Solicitada somente no início do tracking de provider móvel (nunca no cadastro/verificação de
    /// endereço — ver research.md §8).
    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// Notifica mudanças de autorização (ex.: revogada nas Configurações com a tela aberta).
    func authorizationChanges() -> AsyncStream<DeviceLocationAuthorization> {
        AsyncStream { continuation in
            authorizationContinuation = continuation
        }
    }

    /// Fix único de alta precisão com timeout de 15s implementado aqui — `CLLocationManager` não tem
    /// timeout nativo (ver research.md §6). Cancelável: chamadas concorrentes substituem a pendente.
    func requestOneShotFix(timeout: TimeInterval = 15) async -> DeviceLocationOneShotResult {
        guard CLLocationManager.locationServicesEnabled() else { return .serviceDisabled }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return .permissionDenied
        default:
            break
        }

        manager.desiredAccuracy = kCLLocationAccuracyBest

        return await withCheckedContinuation { continuation in
            resumeOneShot(with: .timeout) // cancela qualquer requisição anterior pendente
            oneShotContinuation = continuation
            let requestID = UUID()
            oneShotID = requestID
            manager.requestLocation()

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let self, self.oneShotID == requestID else { return }
                self.resumeOneShot(with: .timeout)
            }
        }
    }

    /// Cancela um fix one-shot pendente sem produzir resultado visível (troca de tela/sessão).
    func cancelOneShotFix() {
        resumeOneShot(with: .failure)
    }

    private func resumeOneShot(with result: DeviceLocationOneShotResult) {
        guard let continuation = oneShotContinuation else { return }
        oneShotContinuation = nil
        continuation.resume(returning: result)
    }

    /// Stream de fixes de alta precisão para tracking do provider (US3) — sem batching, sem
    /// distância mínima (`distanceFilter = kCLDistanceFilterNone`), com atualização em background
    /// (ver contracts/location-realtime.md "Atualização em background").
    func startHighPrecisionUpdates() -> AsyncStream<DeviceLocationFix> {
        let streamID = UUID()
        updateStreamID = streamID
        updateContinuation?.finish()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.allowsBackgroundLocationUpdates = manager.authorizationStatus == .authorizedAlways
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        return AsyncStream { continuation in
            updateContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.updateStreamID == streamID else { return }
                    self.manager.stopUpdatingLocation()
                    self.updateContinuation = nil
                }
            }
        }
    }

    func stopHighPrecisionUpdates() {
        updateStreamID = UUID()
        manager.stopUpdatingLocation()
        updateContinuation?.finish()
        updateContinuation = nil
    }

    private func map(_ status: CLAuthorizationStatus) -> DeviceLocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedWhenInUse: .authorizedWhenInUse
        case .authorizedAlways: .authorizedAlways
        @unknown default: .denied
        }
    }
}

extension DeviceLocationRepository: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = DeviceLocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
        Task { @MainActor in
            self.resumeOneShot(with: .success(fix))
            self.updateContinuation?.yield(fix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.resumeOneShot(with: .failure)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationContinuation?.yield(self.map(status))
        }
    }
}

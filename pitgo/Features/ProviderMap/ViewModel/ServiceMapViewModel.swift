//
//  ServiceMapViewModel.swift
//  pitgo
//
//  Localização do cliente é um fix one-shot mantido em memória (sem permissão, cai para uma região
//  manual — ver research.md §12 de `009`). Cada busca tem uma geração incremental; respostas de um
//  serviço/viewport antigo são descartadas (ver data-model.md "ServiceMapResult").
//

import Combine
import CoreLocation
import Foundation

@MainActor
final class ServiceMapViewModel: ObservableObject {
    @Published private(set) var state: ServiceMapUiState = .loading

    private let serviceID: UUID
    private let repository: ServiceMapRepository
    private let locationRepository: DeviceLocationRepository
    private let connectivityObserver: ConnectivityObserver
    private var generation: UInt64 = 0

    private let defaultRadiusMeters = 5_000
    /// São Paulo — centro manual quando a permissão é negada e nenhum pan do usuário ainda ocorreu.
    private let fallbackCenter = CLLocationCoordinate2D(latitude: -23.5505, longitude: -46.6333)

    init(
        serviceID: UUID,
        repository: ServiceMapRepository,
        locationRepository: DeviceLocationRepository,
        connectivityObserver: ConnectivityObserver = ConnectivityObserver()
    ) {
        self.serviceID = serviceID
        self.repository = repository
        self.locationRepository = locationRepository
        self.connectivityObserver = connectivityObserver
    }

    func load() {
        Task { [weak self] in
            guard let self else { return }
            let locationMode = await resolveClientLocation()
            let (latitude, longitude) = coordinate(for: locationMode)
            await search(centerLatitude: latitude, centerLongitude: longitude, radiusMeters: defaultRadiusMeters, locationMode: locationMode)
        }
    }

    func retry() {
        load()
    }

    /// "Buscar nesta área" — busca pelo centro atual do mapa, sem depender de nova permissão.
    func searchThisArea(center: CLLocationCoordinate2D) {
        let mode: ClientLocationMode = if case let .authorized(lat, lon) = currentLocationMode, lat == center.latitude, lon == center.longitude {
            currentLocationMode
        } else {
            .manual(latitude: center.latitude, longitude: center.longitude)
        }
        Task { [weak self] in
            guard let self else { return }
            await search(centerLatitude: center.latitude, centerLongitude: center.longitude, radiusMeters: defaultRadiusMeters, locationMode: mode)
        }
    }

    private var currentLocationMode: ClientLocationMode {
        if case let .content(_, _, mode) = state { return mode }
        return .unavailable
    }

    private func coordinate(for mode: ClientLocationMode) -> (Double, Double) {
        switch mode {
        case let .authorized(lat, lon), let .manual(lat, lon):
            (lat, lon)
        case .unavailable:
            (fallbackCenter.latitude, fallbackCenter.longitude)
        }
    }

    private func resolveClientLocation() async -> ClientLocationMode {
        switch locationRepository.authorizationStatus {
        case .denied, .restricted:
            return .unavailable
        case .notDetermined:
            locationRepository.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            break
        }

        switch await locationRepository.requestOneShotFix(timeout: 15) {
        case let .success(fix):
            return .authorized(latitude: fix.latitude, longitude: fix.longitude)
        default:
            return .unavailable
        }
    }

    private func search(centerLatitude: Double, centerLongitude: Double, radiusMeters: Int, locationMode: ClientLocationMode) async {
        generation += 1
        let requestGeneration = generation
        state = .loading

        // Domina proativamente sobre a falha de rede da RPC (contracts/maplibre-style-runtime.md
        // "Resource state" — ausência de conectividade domina como `.offline`).
        if connectivityObserver.status == .offline {
            state = .offline
            return
        }

        let result = await repository.discover(
            serviceID: serviceID,
            centerLatitude: centerLatitude,
            centerLongitude: centerLongitude,
            radiusMeters: radiusMeters
        )
        guard requestGeneration == generation else { return } // resposta de uma busca antiga

        let viewport = MapViewport(centerLatitude: centerLatitude, centerLongitude: centerLongitude, radiusMeters: radiusMeters)
        switch result {
        case let .success(results):
            state = results.isEmpty ? .empty : .content(results: results, viewport: viewport, locationMode: locationMode)
        case .sessionExpired:
            state = .failure(reason: .sessionExpired)
        case .offline:
            state = .offline
        case .service, .unknown:
            state = .failure(reason: .service)
        }
    }
}

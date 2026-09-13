//
//  ServiceMapModels.swift
//  pitgo
//
//  Estados do mapa de descoberta por serviço (ver data-model.md "ServiceMapUiState" de `009`).
//

import Foundation

struct MapViewport: Equatable {
    let centerLatitude: Double
    let centerLongitude: Double
    let radiusMeters: Int
}

enum ClientLocationMode: Equatable {
    case authorized(latitude: Double, longitude: Double)
    case manual(latitude: Double, longitude: Double)
    case unavailable
}

enum ServiceMapFailureReason: Hashable {
    case service
    case sessionExpired
    case unknown
}

enum ServiceMapUiState {
    case loading
    case content(results: [ServiceMapResult], viewport: MapViewport, locationMode: ClientLocationMode)
    case empty
    case offline
    case failure(reason: ServiceMapFailureReason)
}

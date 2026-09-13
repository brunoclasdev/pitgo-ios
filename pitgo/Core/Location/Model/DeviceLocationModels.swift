//
//  DeviceLocationModels.swift
//  pitgo
//
//  Tipos sem UI usados por `DeviceLocationRepository` (ver contracts/location-realtime.md). Nenhum
//  conhecimento de sessão, provider ou atendimento; nenhuma persistência em disco.
//

import Foundation

/// Fix validado — sem histórico. `timestamp` é a hora do próprio fix (`CLLocation.timestamp`), não
/// a hora de recebimento.
struct DeviceLocationFix: Equatable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date
}

enum DeviceLocationAuthorization {
    case notDetermined
    case restricted
    case denied
    case authorizedWhenInUse
    case authorizedAlways
}

enum DeviceLocationOneShotResult {
    case success(DeviceLocationFix)
    case permissionDenied
    case timeout
    case serviceDisabled
    case failure
}

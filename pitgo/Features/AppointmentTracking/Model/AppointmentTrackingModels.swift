//
//  AppointmentTrackingModels.swift
//  pitgo
//
//  Estado do marcador privado de acompanhamento (ver data-model.md "AppointmentMarkerState" de
//  `009`). Broadcast e snapshot mesclam por `version`; um timer local transiciona `.live` para
//  `.stale` em 30s mesmo sem outro evento de rede — nenhuma tabela mantém histórico.
//

import CoreLocation
import Foundation

enum AppointmentMarkerState {
    case unavailable
    case live(location: CLLocationCoordinate2D, updatedAt: Date)
    case stale(location: CLLocationCoordinate2D, updatedAt: Date)
    case ended
}

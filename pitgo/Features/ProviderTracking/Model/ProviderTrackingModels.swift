//
//  ProviderTrackingModels.swift
//  pitgo
//
//  Estados de tracking do provider móvel (ver data-model.md "ProviderTrackingState" de `009`).
//

import Foundation

enum ProviderTrackingState: Equatable {
    case stopped
    case starting
    case active(lastPublishedAt: Date)
    case degraded(reason: TrackingDegradedReason)
    case stopping
}

enum TrackingDegradedReason: Hashable {
    case permissionDenied
    case locationServicesDisabled
    case publisherConflict
    case offline
    case service
    case sessionExpired
    case notEligible
    case appointmentTerminal
}

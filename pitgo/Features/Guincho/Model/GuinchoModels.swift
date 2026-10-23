//
//  GuinchoModels.swift
//  pitgo
//
//  `028` (porte do app Android — `features/guincho/model/GuinchoModels.kt`): domínio da etapa
//  pré-pagamento do Guincho — escolha de retirada/destino/veículo no mapa, descoberta de guincheiros
//  elegíveis e cotação. O que acontece DEPOIS de "Contratar" (aceite, chegada, transporte, conclusão,
//  contestação) é só uma extensão do `MobileDispatchSnapshot` já existente (`013`) — ver
//  `MobileDispatchModels.swift`, nunca duplicado aqui.
//

import CoreLocation
import Foundation

struct GuinchoTripInput {
    let vehicleID: UUID
    let pickupAddress: String
    let pickup: CLLocationCoordinate2D
    let destinationAddress: String
    let destination: CLLocationCoordinate2D

    var isValid: Bool {
        let pickupTrimmed = pickupAddress.trimmingCharacters(in: .whitespaces)
        let destinationTrimmed = destinationAddress.trimmingCharacters(in: .whitespaces)
        return (1 ... 500).contains(pickupTrimmed.count) && (1 ... 500).contains(destinationTrimmed.count)
            && CLLocationCoordinate2DIsValid(pickup) && CLLocationCoordinate2DIsValid(destination)
    }
}

struct GuinchoDraft: Equatable {
    let id: UUID
    let revision: Int64
}

struct GuinchoProvider: Identifiable, Equatable {
    let id: UUID
    let offerID: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    let ratingSummary: ProviderRatingSummary?

    static func == (lhs: GuinchoProvider, rhs: GuinchoProvider) -> Bool {
        lhs.id == rhs.id && lhs.offerID == rhs.offerID && lhs.name == rhs.name
            && lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.distanceMeters == rhs.distanceMeters
            && lhs.ratingSummary == rhs.ratingSummary
    }
}

struct GuinchoQuote: Equatable {
    let id: UUID
    let version: Int64
    let providerID: UUID
    let providerName: String
    /// Total final do cliente — nunca o detalhamento (preço-base/km/10%/taxas), que fica só no
    /// backend (FR-007).
    let total: Decimal
    let expiresAt: Date
    let durationMinutes: Int?

    var isExpired: Bool { expiresAt <= Date() }
}

struct GuinchoAddressSuggestion: Identifiable, Equatable {
    let id: String
    let label: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: GuinchoAddressSuggestion, rhs: GuinchoAddressSuggestion) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label
            && lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

enum GuinchoFailureReason {
    case invalidInput
    case sessionExpired
    case offline
    case timeout
    case routeUnavailable
    case providerUnavailable
    case quoteExpired
    case quoteConflict
    case pricingUnavailable
    case serviceUnavailable
    case contract
    case unknown
}

enum GuinchoOutcome<Value> {
    case success(Value)
    case failure(GuinchoFailureReason)
}

/// `028`: contexto do checkout de um atendimento Guincho já aceito pelo guincheiro, aguardando só o
/// pagamento (`AWAITING_PAYMENT`) — mesmo papel de `PitTecPaymentContext` (`021`), com o valor
/// vindo do orçamento do atendimento, nunca recalculado no checkout.
struct GuinchoPaymentContext: Equatable, Identifiable {
    let searchID: UUID
    let appointmentID: UUID
    let quoteVersion: Int64
    let amount: Decimal

    var id: UUID { appointmentID }
}

/// A etapa do atendimento define o destino; o GPS do cliente nunca é usado como origem do guincho.
enum GuinchoClientRoutePhase: String {
    case approaching, transporting
    func target(_ trip: GuinchoTripSummary) -> CLLocationCoordinate2D {
        self == .approaching ? trip.pickup : trip.destination
    }
}

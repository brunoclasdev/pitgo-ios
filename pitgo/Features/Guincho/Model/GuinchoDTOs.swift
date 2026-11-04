//
//  GuinchoDTOs.swift
//  pitgo
//
//  `028`: payload/resposta das RPCs e da Edge Function dedicadas à etapa pré-pagamento do Guincho
//  (`save_guincho_trip_draft`, `discover_guincho_providers`, Edge Function `guincho-quote`).
//  `GuinchoTripDto`/`GuinchoDisputeDto` também são usados por `MobileDispatchModels.swift` — o
//  mesmo envelope `trip`/`dispute` aparece no snapshot compartilhado assim que o pagamento aprova.
//

import CoreLocation
import Foundation

struct GuinchoDraftDTO: Decodable {
    let draftID: UUID
    let revision: Int64

    enum CodingKeys: String, CodingKey {
        case draftID = "draft_id"
        case revision
    }

    func domain() -> GuinchoDraft { GuinchoDraft(id: draftID, revision: revision) }
}

struct GuinchoProviderDTO: Decodable {
    let providerID: UUID
    let providerServiceID: UUID
    let displayName: String
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double
    let ratingSummary: ProviderRatingSummary?
    let dispatchVehicleID: UUID?
    let sizeID: UUID?
    let sizeName: String?

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case providerServiceID = "provider_service_id"
        case displayName = "display_name"
        case latitude, longitude
        case distanceMeters = "distance_meters"
        case ratingSummary = "rating_summary"
        case dispatchVehicleID = "dispatch_vehicle_id"
        case sizeID = "size_id"
        case sizeName = "size_name"
    }

    func domain() -> GuinchoProvider {
        GuinchoProvider(
            id: providerID,
            offerID: providerServiceID,
            name: displayName,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            distanceMeters: distanceMeters,
            ratingSummary: ratingSummary?.isValid == true ? ratingSummary : nil,
            dispatchVehicleID: dispatchVehicleID, sizeID: sizeID, sizeName: sizeName
        )
    }
}

struct GuinchoQuoteDTO: Decodable {
    let quoteID: UUID
    let version: Int64
    let providerID: UUID
    let providerName: String
    let customerTotalAmount: Decimal
    let currency: String
    let expiresAt: Date
    let durationMinutes: Int?
    let dispatchVehicleID: UUID?
    let sizeID: UUID?
    let sizeName: String?
    let sizePriceVersion: Int64?

    enum CodingKeys: String, CodingKey {
        case quoteID = "quote_id"
        case version
        case providerID = "provider_id"
        case providerName = "provider_name"
        case customerTotalAmount = "customer_total_amount"
        case currency
        case expiresAt = "expires_at"
        case durationMinutes = "duration_minutes"
        case dispatchVehicleID = "dispatch_vehicle_id"
        case sizeID = "size_id"
        case sizeName = "size_name"
        case sizePriceVersion = "size_price_version"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quoteID = try container.decode(UUID.self, forKey: .quoteID)
        version = try container.decode(Int64.self, forKey: .version)
        providerID = try container.decode(UUID.self, forKey: .providerID)
        providerName = try container.decode(String.self, forKey: .providerName)
        currency = try container.decode(String.self, forKey: .currency)
        dispatchVehicleID = try container.decodeIfPresent(UUID.self, forKey: .dispatchVehicleID)
        sizeID = try container.decodeIfPresent(UUID.self, forKey: .sizeID)
        sizeName = try container.decodeIfPresent(String.self, forKey: .sizeName)
        sizePriceVersion = try container.decodeIfPresent(Int64.self, forKey: .sizePriceVersion)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)

        // O backend pode serializar numeric como número ou texto decimal.
        if let amount = try? container.decode(Decimal.self, forKey: .customerTotalAmount) {
            customerTotalAmount = amount
        } else {
            let raw = try container.decode(String.self, forKey: .customerTotalAmount)
            guard let amount = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
                  raw.range(of: #"^-?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else {
                throw DecodingError.dataCorruptedError(forKey: .customerTotalAmount, in: container,
                    debugDescription: "Valor de orçamento inválido")
            }
            customerTotalAmount = amount
        }

        // FunctionsClient usa JSONDecoder() por padrão, que espera Date numérica.
        // A Edge Function devolve timestamps ISO8601 do Postgres, inclusive com frações.
        let timestamp = try container.decode(String.self, forKey: .expiresAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractionalDate = formatter.date(from: timestamp)
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = fractionalDate ?? formatter.date(from: timestamp) else {
            throw DecodingError.dataCorruptedError(forKey: .expiresAt, in: container,
                debugDescription: "Validade de orçamento inválida")
        }
        expiresAt = date
    }

    func domain() -> GuinchoQuote {
        GuinchoQuote(
            id: quoteID,
            version: version,
            providerID: providerID,
            providerName: providerName,
            total: customerTotalAmount,
            expiresAt: expiresAt,
            durationMinutes: durationMinutes,
            dispatchVehicleID: dispatchVehicleID, sizeID: sizeID, sizeName: sizeName, sizePriceVersion: sizePriceVersion
        )
    }
}

// MARK: - Trip/veículo/contestação — reaproveitados pelo snapshot de despacho compartilhado

struct GuinchoVehicleDTO: Decodable {
    let brand: String
    let model: String
    let plate: String?
    let color: String?
}

struct GuinchoTripDTO: Decodable {
    let clientName: String
    let vehicle: GuinchoVehicleDTO
    let pickupAddress: String
    let destinationAddress: String
    let pickupLatitude: Double
    let pickupLongitude: Double
    let destinationLatitude: Double
    let destinationLongitude: Double

    enum CodingKeys: String, CodingKey {
        case clientName = "client_name"
        case vehicle
        case pickupAddress = "pickup_address"
        case destinationAddress = "destination_address"
        case pickupLatitude = "pickup_latitude"
        case pickupLongitude = "pickup_longitude"
        case destinationLatitude = "destination_latitude"
        case destinationLongitude = "destination_longitude"
    }
}

struct GuinchoTripSummary: Equatable {
    let clientName: String
    let vehicle: String
    let pickupAddress: String
    let destinationAddress: String
    let pickup: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D

    static func == (lhs: GuinchoTripSummary, rhs: GuinchoTripSummary) -> Bool {
        lhs.clientName == rhs.clientName && lhs.vehicle == rhs.vehicle
            && lhs.pickupAddress == rhs.pickupAddress && lhs.destinationAddress == rhs.destinationAddress
            && lhs.pickup.latitude == rhs.pickup.latitude && lhs.pickup.longitude == rhs.pickup.longitude
            && lhs.destination.latitude == rhs.destination.latitude && lhs.destination.longitude == rhs.destination.longitude
    }
}

extension GuinchoTripDTO {
    nonisolated func summary() -> GuinchoTripSummary {
        GuinchoTripSummary(
            clientName: clientName,
            vehicle: [vehicle.brand, vehicle.model, vehicle.plate, vehicle.color].compactMap { $0 }.joined(separator: " · "),
            pickupAddress: pickupAddress,
            destinationAddress: destinationAddress,
            pickup: CLLocationCoordinate2D(latitude: pickupLatitude, longitude: pickupLongitude),
            destination: CLLocationCoordinate2D(latitude: destinationLatitude, longitude: destinationLongitude)
        )
    }
}

enum GuinchoDisputeStatus: String, Decodable {
    case open = "OPEN"
    case resolved = "RESOLVED"
}

enum GuinchoDisputeResolution: String, Decodable {
    case complete = "COMPLETE"
    case cancelFullRefund = "CANCEL_FULL_REFUND"
}

struct GuinchoDisputeDTO: Decodable {
    let id: UUID
    let reason: String
    let status: GuinchoDisputeStatus
    let resolution: GuinchoDisputeResolution?
    let justification: String?
}

struct GuinchoDispute: Equatable {
    let id: UUID
    let reason: String
    let status: GuinchoDisputeStatus
    let resolution: GuinchoDisputeResolution?
    let justification: String?
}

extension GuinchoDisputeDTO {
    func domain() -> GuinchoDispute {
        GuinchoDispute(id: id, reason: reason, status: status, resolution: resolution, justification: justification)
    }
}

// MARK: - Edge Function `guincho-address-search`

struct GuinchoAddressSearchRequestBody: Encodable {
    let query: String
    let latitude: Double
    let longitude: Double
    let reverse: Bool
    let number: String?
}

struct GuinchoAddressSuggestionDTO: Decodable {
    let id: String
    let label: String
    let latitude: Double
    let longitude: Double
}

struct GuinchoAddressSuggestionsResponse: Decodable {
    let suggestions: [GuinchoAddressSuggestionDTO]
}

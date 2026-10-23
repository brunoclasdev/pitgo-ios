//
//  GuinchoAddressRepository.swift
//  pitgo
//
//  `028` (porte do app Android — `GuinchoAddressRepository.kt`, que usa `android.location.Geocoder`;
//  aqui o equivalente nativo é `CLGeocoder`). Busca/sugestão de endereço roda na Edge Function
//  `guincho-address-search` (já implantada, compartilhada com o Android); o reverse-geocode do ponto
//  de retirada (texto amigável a partir de uma coordenada) e o "endereço + número" de melhor esforço
//  usam o geocoder do sistema como complemento, nunca como fonte principal de coordenadas.
//

import Contacts
import CoreLocation
import Foundation
import Supabase

final class GuinchoAddressRepository {
    private let client: SupabaseClient
    private let geocoder = CLGeocoder()

    init(client: SupabaseClient) {
        self.client = client
    }

    func suggestions(query: String, proximity: CLLocationCoordinate2D) async -> GuinchoOutcome<[GuinchoAddressSuggestion]> {
        await search(query: query, coordinate: proximity, reverse: false, number: nil)
    }

    /// Tenta a Edge Function com "endereço, número"; se não houver resultado, cai para o geocoder
    /// nativo como melhor esforço (mesmo fallback do Android — nunca bloqueia a confirmação por um
    /// serviço de geocodificação indisponível).
    func resolveDestination(address: String, number: String, proximity: CLLocationCoordinate2D) async -> GuinchoOutcome<[GuinchoAddressSuggestion]> {
        let result = await search(query: address, coordinate: proximity, reverse: false, number: number)
        if case let .success(suggestions) = result, !suggestions.isEmpty { return result }
        if case .failure(.sessionExpired) = result { return result }
        if let fallback = await addressWithNumber(query: address, number: number) {
            return .success([fallback])
        }
        return result
    }

    func pickupAddress(_ coordinate: CLLocationCoordinate2D) async -> String {
        await addressAtCoordinate(coordinate, fallbackFormat: "Retirada em %@")
    }

    func destinationAddress(_ coordinate: CLLocationCoordinate2D) async -> String {
        let result = await search(query: "", coordinate: coordinate, reverse: true, number: nil)
        if case let .success(suggestions) = result, let first = suggestions.first { return first.label }
        return await addressAtCoordinate(coordinate, fallbackFormat: "Destino em %@")
    }

    // MARK: - Edge Function

    private func search(query: String, coordinate: CLLocationCoordinate2D, reverse: Bool, number: String?) async -> GuinchoOutcome<[GuinchoAddressSuggestion]> {
        do {
            let response: GuinchoAddressSuggestionsResponse = try await client.functions.invoke(
                "guincho-address-search",
                options: FunctionInvokeOptions(body: GuinchoAddressSearchRequestBody(
                    query: query, latitude: coordinate.latitude, longitude: coordinate.longitude,
                    reverse: reverse, number: number
                ))
            )
            let suggestions = response.suggestions.compactMap { dto -> GuinchoAddressSuggestion? in
                guard !dto.label.isEmpty, dto.label.count <= 500,
                      CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: dto.latitude, longitude: dto.longitude))
                else { return nil }
                return GuinchoAddressSuggestion(id: dto.id, label: dto.label, coordinate: CLLocationCoordinate2D(latitude: dto.latitude, longitude: dto.longitude))
            }
            return .success(suggestions)
        } catch let functionsError as FunctionsError {
            if case let .httpError(statusCode, _) = functionsError, statusCode == 401 {
                return .failure(.sessionExpired)
            }
            return .failure(.serviceUnavailable)
        } catch {
            return .failure(.serviceUnavailable)
        }
    }

    // MARK: - CLGeocoder (melhor esforço — nunca a fonte principal de coordenadas)

    private func addressAtCoordinate(_ coordinate: CLLocationCoordinate2D, fallbackFormat: String) async -> String {
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            return String(format: fallbackFormat, coordinateText(coordinate))
        }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let placemark = try? await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "pt_BR")).first,
           let line = placemark.formattedAddressLine, !line.isEmpty {
            return String(line.prefix(500))
        }
        return String(format: fallbackFormat, coordinateText(coordinate))
    }

    private func addressWithNumber(query: String, number: String) async -> GuinchoAddressSuggestion? {
        let expectedNumber = normalizedNumber(number)
        guard !expectedNumber.isEmpty else { return nil }
        guard let placemarks = try? await geocoder.geocodeAddressString(query, in: nil, preferredLocale: Locale(identifier: "pt_BR")) else { return nil }
        guard let match = placemarks.first(where: { placemark in
            guard let coordinate = placemark.location?.coordinate, CLLocationCoordinate2DIsValid(coordinate),
                  let thoroughfare = placemark.thoroughfare, !thoroughfare.isEmpty else { return false }
            return normalizedNumber(placemark.subThoroughfare ?? "") == expectedNumber
        }), let coordinate = match.location?.coordinate else { return nil }
        return GuinchoAddressSuggestion(id: "ios-address", label: query, coordinate: coordinate)
    }

    private func normalizedNumber(_ value: String) -> String {
        value.folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
            .filter(\.isLetter).isEmpty
            ? value.filter(\.isNumber)
            : value.folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR")).filter { $0.isLetter || $0.isNumber }.lowercased()
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }
}

private extension CLPlacemark {
    /// Equivalente a `Address.getAddressLine(0)` do Android — uma linha única e amigável.
    var formattedAddressLine: String? {
        guard let postalAddress else { return name }
        return CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
            .replacingOccurrences(of: "\n", with: ", ")
    }
}

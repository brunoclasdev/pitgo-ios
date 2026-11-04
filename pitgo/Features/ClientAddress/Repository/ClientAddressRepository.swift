//
//  ClientAddressRepository.swift
//  pitgo
//
//  Única fronteira com `get_my_client_address`/`upsert_my_client_address` (já existentes,
//  confirmadas via `pg_get_functiondef` nesta sessão). Nenhum `userID` é enviado pelo client —
//  owner sempre `auth.uid()` no servidor.
//

import Foundation
import Supabase

enum ClientAddressFetchResult {
    case found(ClientAddress)
    case notFound
    case failure
}

enum ClientAddressSaveResult {
    case success(ClientAddress)
    case invalidInput
    case sessionExpired
    case offline
    case service
    case unknown
}

final class ClientAddressRepository {
    let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetch() async -> ClientAddressFetchResult {
        struct Envelope: Decodable {
            let outcome: String
            let address: ClientAddress?
        }
        do {
            let result: Envelope = try await client.rpc("get_my_client_address").execute().value
            switch result.outcome {
            case "FOUND":
                guard let address = result.address else { return .failure }
                return .found(address)
            default:
                return .notFound
            }
        } catch {
            return .failure
        }
    }

    func save(_ draft: ClientAddressDraft, latitude: Double, longitude: Double) async -> ClientAddressSaveResult {
        struct Params: Encodable {
            let p_street: String
            let p_number: String
            let p_neighborhood: String
            let p_zip_code: String
            let p_city: String
            let p_state: String
            let p_complement: String
            let p_latitude: Double
            let p_longitude: Double
        }
        struct Envelope: Decodable {
            let outcome: String
            let address: ClientAddress?
        }
        let params = Params(
            p_street: draft.street,
            p_number: draft.number,
            p_neighborhood: draft.neighborhood,
            p_zip_code: draft.postalCode,
            p_city: draft.city,
            p_state: draft.state?.rawValue ?? "",
            p_complement: draft.complement,
            p_latitude: latitude,
            p_longitude: longitude
        )
        do {
            let result: Envelope = try await client.rpc("upsert_my_client_address", params: params).execute().value
            guard let address = result.address else { return .unknown }
            return .success(address)
        } catch {
            return classify(error)
        }
    }

    private func classify(_ error: Error) -> ClientAddressSaveResult {
        if let postgrestError = error as? PostgrestError {
            switch postgrestError.code {
            case "42501": return .sessionExpired
            case "22023": return .invalidInput
            default: return .unknown
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return .offline
            default: return .service
            }
        }
        return .unknown
    }
}

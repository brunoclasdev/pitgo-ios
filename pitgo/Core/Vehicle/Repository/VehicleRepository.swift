//
//  VehicleRepository.swift
//  pitgo
//
//  Lista veículos ativos próprios e invoca somente as RPCs transacionais `create_vehicle`/
//  `set_primary_vehicle` já existentes e compartilhadas (ver contracts/supabase.md). Nenhum
//  parâmetro de owner/status é enviado pelo client.
//

import Foundation
import Supabase

private struct CreateVehicleParams: Encodable {
    let p_brand: String
    let p_model: String
    let p_version: String?
    let p_manufacture_year: Int?
    let p_model_year: Int?
    let p_plate: String?
    let p_renavam: String?
    let p_chassis: String?
    let p_color: String?
    let p_fuel_type: String?
    let p_transmission: String?
    let p_engine: String?
    let p_mileage: Int?
    let p_make_primary: Bool
}

private struct SetPrimaryVehicleParams: Encodable {
    let p_vehicle_id: String
}

final class VehicleRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Veículos ativos do usuário atual, principal primeiro (ver contracts/supabase.md "Read list").
    func listActiveVehicles(userID: UUID) async -> [Vehicle]? {
        try? await client
            .from("vehicles")
            .select()
            .eq("user_id", value: userID.uuidString)
            .eq("active", value: true)
            .order("is_primary", ascending: false)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func createVehicle(_ draft: VehicleDraft) async -> VehicleFormResult {
        let params = CreateVehicleParams(
            p_brand: draft.brand,
            p_model: draft.model,
            p_version: draft.version,
            p_manufacture_year: draft.manufactureYear,
            p_model_year: draft.modelYear,
            p_plate: draft.plate,
            p_renavam: draft.renavam,
            p_chassis: draft.chassis,
            p_color: draft.color,
            p_fuel_type: draft.fuelType,
            p_transmission: draft.transmission,
            p_engine: draft.engine,
            p_mileage: draft.mileage,
            p_make_primary: draft.makePrimary
        )
        do {
            let rows: [Vehicle] = try await client
                .rpc("create_vehicle", params: params)
                .execute()
                .value
            guard let vehicle = rows.first else { return .failure(.contract) }
            return .success(vehicle)
        } catch {
            return classify(error)
        }
    }

    func setPrimary(vehicleID: UUID) async -> VehicleFormResult {
        let params = SetPrimaryVehicleParams(p_vehicle_id: vehicleID.uuidString)
        do {
            let rows: [Vehicle] = try await client
                .rpc("set_primary_vehicle", params: params)
                .execute()
                .value
            guard let vehicle = rows.first else { return .failure(.vehicleUnavailable) }
            return .success(vehicle)
        } catch {
            return classify(error)
        }
    }

    /// Mapeia exclusivamente os SQLSTATEs allowlisted por `create_vehicle`/`set_primary_vehicle`
    /// (ver contracts/vehicle-rpcs.md "Contrato de erros sanitizados") — nunca interpreta
    /// `message`/`details`/`hint`, e nunca encaminha o `Error` bruto ao ViewModel/log.
    private func classify(_ error: Error) -> VehicleFormResult {
        if let postgrestError = error as? PostgrestError {
            switch postgrestError.code {
            case "P2001": return .fieldFailure(.brand, .required)
            case "P2002": return .fieldFailure(.model, .required)
            case "P2003": return .fieldFailure(.plate, .invalidFormat)
            case "P2004": return .fieldFailure(.renavam, .invalidFormat)
            case "P2005": return .fieldFailure(.chassis, .invalidFormat)
            case "P2006": return .fieldFailure(.manufactureYear, .outOfRange)
            case "P2007": return .fieldFailure(.modelYear, .outOfRange)
            case "P2008": return .fieldFailure(.mileage, .outOfRange)
            case "P2011": return .fieldFailure(.plate, .unavailable)
            case "P2012": return .fieldFailure(.renavam, .unavailable)
            case "P2013": return .fieldFailure(.chassis, .unavailable)
            case "P0002": return .failure(.vehicleUnavailable)
            case "42501": return .failure(.sessionExpired)
            case "PGRST202", "PGRST203", "42883": return .failure(.rpcUnavailable)
            default: return .failure(.unknown) // inclui 23505 não traduzido pela RPC
            }
        }
        if let httpError = error as? HTTPError {
            switch httpError.response.statusCode {
            case 401, 403: return .failure(.sessionExpired)
            case 404: return .failure(.rpcUnavailable)
            case 500...599: return .failure(.serviceUnavailable)
            default: return .failure(.unknown)
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .failure(.offline)
            case .timedOut:
                return .failure(.timeout)
            default:
                return .failure(.serviceUnavailable)
            }
        }
        return .failure(.unknown)
    }
}

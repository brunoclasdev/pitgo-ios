//
//  AppointmentTrackingRepository.swift
//  pitgo
//
//  Assina o canal privado `appointment-location:<id>` e busca o snapshot via RPC já existente (ver
//  contracts/location-realtime.md "Ordem de consumo" de `009`). O callback de broadcast é
//  deliberadamente `nonisolated`/`@Sendable` (mesma cautela de `PitGoRootView`/`SignUpView` — ver
//  `006`/`007` — contra o crash real do compilador ao sintetizar um thunk de isolamento para um
//  parâmetro `@Sendable` não-isolado); quem consome o evento faz o próprio hop para `@MainActor`.
//

import Foundation
import Supabase

nonisolated struct BroadcastLocationPayload: Decodable, Sendable {
    let event: String // "UPSERT" | "CLEARED"
    let latitude: Decimal?
    let longitude: Decimal?
    let accuracyM: Decimal?
    let capturedAt: Date?
    let publishedAt: Date?
    let version: Int64?

    enum CodingKeys: String, CodingKey {
        case event, latitude, longitude, version
        case accuracyM = "accuracy_m"
        case capturedAt = "captured_at"
        case publishedAt = "published_at"
    }
}

final class AppointmentTrackingRepository {
    private let client: SupabaseClient
    private var channel: RealtimeChannelV2?
    private var subscription: RealtimeSubscription?

    init(client: SupabaseClient) {
        self.client = client
    }

    /// 1) `setAuth()`; 2) cria e assina o canal privado; 3) busca o snapshot **depois** da
    /// assinatura confirmada — ordem exigida pelo contrato.
    func connect(
        appointmentID: UUID,
        onEvent: @escaping @Sendable (BroadcastLocationPayload) -> Void
    ) async -> AppointmentProviderLocationSnapshot? {
        await client.realtimeV2.setAuth()

        let channel = client.realtimeV2.channel("appointment-location:\(appointmentID)") { config in
            config.isPrivate = true
        }
        self.channel = channel

        subscription = channel.onBroadcast(event: "*") { payload in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data = try? JSONEncoder().encode(payload),
                  let decoded = try? decoder.decode(BroadcastLocationPayload.self, from: data) else { return }
            onEvent(decoded)
        }

        try? await channel.subscribeWithError()

        return await fetchSnapshot(appointmentID: appointmentID)
    }

    /// Buscado de novo ao reconectar (ver contracts/location-realtime.md "Ordem de consumo").
    func fetchSnapshot(appointmentID: UUID) async -> AppointmentProviderLocationSnapshot? {
        try? await client
            .rpc("get_appointment_provider_location", params: GetAppointmentProviderLocationParams(p_appointment_id: appointmentID))
            .execute()
            .value
    }

    func disconnect() async {
        subscription = nil
        if let channel {
            await client.realtimeV2.removeChannel(channel)
        }
        channel = nil
    }
}

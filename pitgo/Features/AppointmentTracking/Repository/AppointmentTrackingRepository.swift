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
    private var connectionID = UUID()

    init(client: SupabaseClient) {
        self.client = client
    }

    /// 1) `setAuth()`; 2) cria e assina o canal privado; 3) busca o snapshot **depois** da
    /// assinatura confirmada — ordem exigida pelo contrato.
    func connect(
        appointmentID: UUID,
        onEvent: @escaping @Sendable (BroadcastLocationPayload) -> Void
    ) async -> AppointmentProviderLocationSnapshot? {
        let connectionID = UUID()
        self.connectionID = connectionID
        await client.realtimeV2.setAuth()
        guard self.connectionID == connectionID, !Task.isCancelled else { return nil }

        let channel = client.realtimeV2.channel("appointment-location:\(appointmentID)") { config in
            config.isPrivate = true
        }
        self.channel = channel

        subscription = channel.onBroadcast(event: "*") { payload in
            // Broadcasts are wake-up signals: current INSERT/UPDATE/DELETE/ENDED payloads
            // have different row shapes. Always read the authoritative RPC snapshot.
            onEvent(BroadcastLocationPayload(event: "REFRESH", latitude: nil, longitude: nil,
                accuracyM: nil, capturedAt: nil, publishedAt: nil, version: nil))
        }

        try? await channel.subscribeWithError()

        guard self.connectionID == connectionID, !Task.isCancelled else { return nil }
        return await fetchSnapshot(appointmentID: appointmentID)
    }

    /// Buscado de novo ao reconectar (ver contracts/location-realtime.md "Ordem de consumo").
    func fetchSnapshot(appointmentID: UUID) async -> AppointmentProviderLocationSnapshot? {
        try? await client
            .rpc("get_appointment_provider_location", params: GetAppointmentProviderLocationParams(p_appointment_id: appointmentID))
            .execute()
            .value
    }

    func publishClientLocation(appointmentID: UUID, fix: DeviceLocationFix) async throws {
        struct Params: Encodable {
            let p_appointment_id: UUID
            let p_latitude: Double
            let p_longitude: Double
            let p_accuracy_m: Double
            let p_captured_at: Date
        }
        try await client.rpc("publish_client_location", params: Params(p_appointment_id: appointmentID,
            p_latitude: fix.latitude, p_longitude: fix.longitude,
            p_accuracy_m: fix.horizontalAccuracy, p_captured_at: fix.timestamp)).execute()
    }

    func disconnect() async {
        connectionID = UUID()
        subscription = nil
        let previousChannel = channel
        channel = nil
        if let previousChannel {
            await client.realtimeV2.removeChannel(previousChannel)
        }
    }
}

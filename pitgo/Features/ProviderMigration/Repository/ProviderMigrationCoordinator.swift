//
//  ProviderMigrationCoordinator.swift
//  pitgo
//
//  Único lugar onde o desafio de migração em texto plano existe — escopo de processo, construído
//  uma vez em `PitGoRootView` (mesmo padrão de `VehicleOnboardingStore`, mas sem persistência: ver
//  research.md §3 — "encerramento do processo descarta o desafio e exige reiniciar o fluxo"). Nunca
//  em `UserDefaults`/`Keychain`/rota/log.
//

import Foundation
import Security

@Observable
@MainActor
final class ProviderMigrationCoordinator {
    private(set) var token: String?
    private(set) var expiresAt: Date?

    /// Gera 32 bytes aleatórios e os mantém como o desafio pendente (research.md §3).
    func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let generated = Data(bytes).base64EncodedString()
        token = generated
        expiresAt = nil
        return generated
    }

    func markPending(expiresAt: Date) {
        self.expiresAt = expiresAt
    }

    /// `nil` quando não há desafio pendente válido — nunca reutilizado após `clear()`.
    var activeToken: String? {
        guard let token, let expiresAt, expiresAt > Date() else { return nil }
        return token
    }

    func clear() {
        token = nil
        expiresAt = nil
    }
}

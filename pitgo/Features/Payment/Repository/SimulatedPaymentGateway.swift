//
//  SimulatedPaymentGateway.swift
//  pitgo
//
//  `027` US2 (porte do app Android — `SimulatedPaymentGateway.kt`): usado só quando
//  `EnvironmentConfig.current.simulated` (Dev). Reproduz os mesmos estados que `PaymentRepository`
//  produziria (PENDING → APPROVED/REJECTED/EXPIRED/CANCELLED), mas inteiramente em memória para
//  `MOBILE_SEQUENTIAL`/`PITTEC_AUTO_SEQUENTIAL` — nunca chama `mp-create-payment`/`mp-refund-payment`
//  nem cria nenhuma preferência/cobrança real no Mercado Pago (FR-004/SC-002).
//
//  `028`: `GUINCHO_DIRECT` é a ÚNICA exceção — o pagamento precisa existir de verdade em
//  `public.payments` (o restante do fluxo de aceite/acompanhamento consulta essa linha
//  independentemente do ambiente), então delega para o backend real via a RPC dedicada
//  `simulate_guincho_payment` (migration `20260930145000_guincho_dev_simulation.sql`, mesma do
//  Android) em vez de simular em memória — a mesma composição `persisted = client.map(PaymentRepository
//  .init)` do Android. Essa RPC exige `private.guincho_runtime_settings.simulation_enabled = true`
//  no projeto Dev (configuração manual via service role, fora do escopo do app) — sem ela, falha com
//  `SIMULATION_DISABLED`, nunca com um sucesso inventado.
//
//  Um `actor` (em vez do `Mutex`+`MutableStateFlow` do Android) porque Swift já serializa o acesso ao
//  estado mutável por isolamento, sem precisar de um lock manual nem de um tipo de observação
//  separado — `subscribe`/`notify` bastam para o único consumidor real (`PaymentCheckoutViewModel`
//  faz polling a cada 3s de qualquer forma; o canal aqui só acelera, nunca é a única fonte).
//

import Foundation
import Supabase

actor SimulatedPaymentGateway: SimulatablePaymentGateway {
    nonisolated let simulated = true

    private struct SimulatedPayment {
        let id: UUID
        let requestID: UUID
        var status: PaymentStatus
        let method: PaymentMethodKind
        let pix: PaymentPixDetails?
    }

    /// QR code de exemplo sem valor real — mesma string/base64 "SIMULACAO-SEM-VALOR" usada pelo
    /// gateway simulado do Android, para que uma captura de tela nunca seja confundida com um Pix
    /// cobrável de verdade.
    private nonisolated static let simulatedPixBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="

    private var payments: [UUID: SimulatedPayment] = [:]
    private var subscriptions: [UUID: @Sendable () -> Void] = [:]
    /// `028` — `nil` só em contextos sem `SupabaseClient` disponível (não deveria acontecer em
    /// produção; `createPayment` para `GUINCHO_DIRECT` falha explicitamente nesse caso).
    private let client: SupabaseClient?
    private let persisted: PaymentRepository?

    init(client: SupabaseClient? = nil) {
        self.client = client
        self.persisted = client.map(PaymentRepository.init(client:))
    }

    func createPayment(
        requestID: UUID,
        dispatchKind: PaymentDispatchKind,
        serviceID: UUID,
        amount: Decimal,
        method: PaymentMethodKind,
        savedCardID: UUID?,
        cardSecurityCodeToken: String?,
        appointmentID: UUID?,
        quoteVersion: Int64?
    ) async -> PaymentCreationOutcome {
        if dispatchKind == .guinchoDirect {
            return await createGuinchoPayment(requestID: requestID, method: method)
        }

        if let existing = payments[requestID] {
            return .created(PaymentCreationResult(paymentID: existing.id, status: existing.status, pix: existing.pix))
        }
        guard amount > 0 else { return .failure(.unknown) }

        let pix: PaymentPixDetails? = method == .pix
            ? PaymentPixDetails(qrCode: "SIMULACAO-SEM-VALOR", qrCodeBase64: Self.simulatedPixBase64, expiresAt: Date().addingTimeInterval(300))
            : nil
        let payment = SimulatedPayment(id: UUID(), requestID: requestID, status: .pending, method: method, pix: pix)
        payments[requestID] = payment
        return .created(PaymentCreationResult(paymentID: payment.id, status: .pending, pix: pix))
    }

    func status(requestID: UUID) async -> PaymentStatusResult {
        if let payment = payments[requestID] {
            return .found(paymentID: payment.id, status: payment.status, method: payment.method)
        }
        // `028`: pode ser um pagamento Guincho real criado por `createGuinchoPayment` — consulta o
        // backend de verdade em vez de reportar `.notFound` por engano.
        guard let persisted else { return .notFound }
        return await persisted.status(requestID: requestID)
    }

    /// Cancelamento/estorno — Guincho delega ao `PaymentRepository` real (o pagamento existe de
    /// verdade); os demais continuam locais: aprovado vira `.refunded`, qualquer outro estado
    /// não-terminal vira `.cancelled` (mesma regra do Android).
    func refund(paymentID: UUID) async -> PaymentRefundOutcome {
        guard let requestID = payments.first(where: { $0.value.id == paymentID })?.key,
              var payment = payments[requestID] else {
            guard let persisted else { return .failure(.notFound) }
            return await persisted.refund(paymentID: paymentID)
        }
        payment.status = payment.status == .approved ? .refunded : .cancelled
        payments[requestID] = payment
        notify(requestID)
        return .resolved(payment.status)
    }

    func subscribe(requestID: UUID, onChanged: @escaping @Sendable () -> Void) async {
        subscriptions[requestID] = onChanged
        // `028`: um pagamento Guincho é real — observa o canal Realtime real também, para que
        // aprovar/rejeitar pelos botões de simulação (que chamam a RPC real) reflita sem precisar
        // esperar o polling de 3s do `PaymentCheckoutViewModel`.
        if payments[requestID] == nil, let persisted {
            await persisted.subscribe(requestID: requestID, onChanged: onChanged)
        }
    }

    func unsubscribe() async {
        subscriptions.removeAll()
        await persisted?.unsubscribe()
    }

    nonisolated func disconnect() {
        Task { await self.unsubscribe() }
    }

    /// Só aplica a transição a partir de `PENDING`, igual ao Android — um pagamento já terminal não
    /// pode ser "re-simulado" para outro estado. Para Guincho, delega para a mesma RPC real.
    func simulate(requestID: UUID, status: PaymentStatus) async -> PaymentStatusResult {
        guard [.approved, .rejected, .expired, .cancelled].contains(status) else {
            return await self.status(requestID: requestID)
        }
        if let payment = payments[requestID] {
            guard payment.status == .pending else { return await self.status(requestID: requestID) }
            var updated = payment
            updated.status = status
            payments[requestID] = updated
            notify(requestID)
            return .found(paymentID: updated.id, status: status, method: updated.method)
        }
        return await simulateGuinchoPayment(requestID: requestID, status: status, method: .pix)
    }

    private func notify(_ requestID: UUID) {
        subscriptions[requestID]?()
    }

    // MARK: - `028` — Guincho (delega ao backend real)

    private func createGuinchoPayment(requestID: UUID, method: PaymentMethodKind) async -> PaymentCreationOutcome {
        let result = await simulateGuinchoPayment(requestID: requestID, status: .pending, method: method)
        switch result {
        case let .found(paymentID, status, _):
            return .created(PaymentCreationResult(paymentID: paymentID, status: status, pix: lastGuinchoPix))
        case .notFound:
            return .failure(.unknown)
        case let .failure(reason):
            return .failure(reason)
        }
    }

    /// Guardado só para repassar o Pix recém-criado a `createGuinchoPayment` — `simulate_guincho_payment`
    /// devolve o `pix` no mesmo retorno, mas `PaymentStatusResult` (compartilhado com o fluxo real)
    /// não carrega esse campo.
    private var lastGuinchoPix: PaymentPixDetails?

    private func simulateGuinchoPayment(requestID: UUID, status: PaymentStatus, method: PaymentMethodKind) async -> PaymentStatusResult {
        guard let client else { return .failure(.unknown) }
        do {
            let snapshot: GuinchoSimulatedPaymentSnapshot = try await client
                .rpc("simulate_guincho_payment", params: SimulateGuinchoPaymentParams(
                    p_request_id: requestID, p_status: status.rawValue, p_method: method.rawValue
                ))
                .execute()
                .value
            lastGuinchoPix = snapshot.pix
            return .found(paymentID: snapshot.paymentID, status: snapshot.status, method: snapshot.method ?? method)
        } catch let postgrestError as PostgrestError {
            if postgrestError.code == "42501" { return .failure(.sessionExpired) }
            return .failure(.unknown)
        } catch {
            return .failure(.unknown)
        }
    }
}

/// `nonisolated`: sem isso, o projeto define `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` e o tipo
/// (logo sua conformância `Encodable`/`Decodable` sintetizada) herdaria isolamento `@MainActor` por
/// padrão — inutilizável de dentro do `actor SimulatedPaymentGateway` (mesmo achado de `026`/`027`
/// com `static let` dentro de `actor`, aqui aplicado ao tipo inteiro).
private nonisolated struct SimulateGuinchoPaymentParams: Encodable {
    let p_request_id: UUID
    let p_status: String
    let p_method: String
}

/// Mesmo formato de `private.payment_snapshot(p)` já usado por `get_payment_status`
/// (`PaymentStatusEnvelope`), com o `pix` adicional que só importa na criação.
private nonisolated struct GuinchoSimulatedPaymentSnapshot: Decodable {
    let paymentID: UUID
    let status: PaymentStatus
    let method: PaymentMethodKind?
    let pix: PaymentPixDetails?

    enum CodingKeys: String, CodingKey {
        case paymentID = "payment_id"
        case status, method, pix
    }
}

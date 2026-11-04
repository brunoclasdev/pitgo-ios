//
//  PaymentGateway.swift
//  pitgo
//
//  `027`: fronteira que `PaymentCheckoutViewModel` e os fluxos de despacho (MobileDispatch/PitTec)
//  enxergam no lugar de `PaymentRepository` concreto — permite trocar por `SimulatedPaymentGateway`
//  em `EnvironmentConfig.current.simulated` (Dev) sem o resto do app saber a diferença. Mesma
//  superfície já usada por esses chamadores antes deste porte; `PaymentRepository` passa a conformar
//  sem mudar nenhuma assinatura.
//

import Foundation

protocol PaymentGateway: AnyObject {
    var simulated: Bool { get }

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
    ) async -> PaymentCreationOutcome

    func recoverable() async -> PaymentStatusResult
    func status(requestID: UUID) async -> PaymentStatusResult
    func cancel(paymentID: UUID) async -> PaymentRefundOutcome
    func cancelUnpaidGuincho(requestID: UUID) async -> Bool
    func refund(paymentID: UUID) async -> PaymentRefundOutcome
    func subscribe(requestID: UUID, onChanged: @escaping @Sendable () -> Void) async
    func unsubscribe() async
    func disconnect()
}

extension PaymentRepository: PaymentGateway {
    var simulated: Bool { false }
}

/// `027` US2: só o gateway simulado de Dev implementa isto — exposto à UI do checkout
/// (`PaymentCheckoutView`) como os botões "Aprovar"/"Rejeitar"/"Expirar"/"Cancelar" para testar
/// estados sem cobrança real (mesmo contrato de `PaymentGateway.simulate`/`PaymentCheckoutScreen` no
/// Android).
protocol SimulatablePaymentGateway: PaymentGateway {
    func simulate(requestID: UUID, status: PaymentStatus) async -> PaymentStatusResult
}

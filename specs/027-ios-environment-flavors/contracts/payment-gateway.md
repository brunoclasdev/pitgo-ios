# Contract: PaymentGateway (Dev simulado vs. integrado)

## Protocolo

```swift
protocol PaymentGateway: AnyObject {
    var simulated: Bool { get }
    func createPayment(requestID:dispatchKind:amount:method:savedCardID:cardSecurityCodeToken:appointmentID:quoteVersion:) async -> PaymentCreationOutcome
    func status(requestID:) async -> PaymentStatusResult
    func refund(paymentID:) async -> PaymentRefundOutcome
    func subscribe(requestID:onChanged:) async
    func unsubscribe() async
    func disconnect()
}

protocol SimulatablePaymentGateway: PaymentGateway {
    func simulate(requestID:status:) async -> PaymentStatusResult
}
```

`PaymentRepository` (já existente) conforma a `PaymentGateway` sem mudar nenhuma assinatura —
`simulated` é sempre `false`. `SimulatedPaymentGateway` (novo, `actor`) conforma a
`SimulatablePaymentGateway`.

## Seleção

`PitGoRootView.init` escolhe o gateway uma única vez, a partir de `EnvironmentConfig.current.simulated`
(derivado de `ENVIRONMENT_ID`, nunca de um toggle em runtime):

```swift
paymentRepository = EnvironmentConfig.current.simulated
    ? SimulatedPaymentGateway()
    : PaymentRepository(client: client)
```

## Comportamento simulado

- `createPayment`: cria um `Payment` local `PENDING` (com `PixCharge` fake quando `method == .pix`);
  uma segunda chamada com o mesmo `requestID` retorna o mesmo pagamento (idempotência, igual ao
  backend real).
- `status`/`subscribe`: refletem só o estado local — nenhuma chamada de rede.
- `simulate(requestID:status:)`: só transiciona a partir de `PENDING` para
  `APPROVED`/`REJECTED`/`EXPIRED`/`CANCELLED`; chamado pelos botões de
  `PaymentCheckoutView.simulationBanner`, visível só quando `viewModel.simulated`.
- `refund`: `APPROVED` → `REFUNDED`; qualquer outro estado não-terminal → `CANCELLED`.
- `disconnect`: limpa as inscrições locais (equivalente a encerrar o canal Realtime real).

## Checkout UI (Dev)

`PaymentCheckoutView` mostra, enquanto aguarda confirmação (`loadingAmount`/`awaitingPix`/
`awaitingCardConfirmation`), um aviso "Ambiente de desenvolvimento — pagamento simulado" e os
botões Aprovar/Rejeitar/Expirar + "Simular falha" (este último não chama o gateway — só força o
estado `.failure` localmente, igual ao `simulateFailure()` do Android).

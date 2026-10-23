# Validation: 028-refinamento-guincho (iOS)

## Build (xcodebuild, iOS Simulator destination, 2026-10-22)

- `-scheme pitgo` (Dev): `** BUILD SUCCEEDED **`, após 8 rodadas de correção de compilação:
  1. Isolamento de ator: o projeto define `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — structs
     `Encodable`/`Decodable` privadas usadas de dentro do `actor SimulatedPaymentGateway` precisaram
     de `nonisolated` explícito (mesmo achado já registrado em `027`).
  2. `T: Sendable` ausente nos genéricos de `GuinchoRepository` (cruzam fronteira de concorrência).
  3. `CoreLocation` não importado em `GuinchoRepository.swift`.
  4. `withThrowingTaskGroup` próprio para timeout era incompatível com Swift 6 estrito — removido;
     `GuinchoRepository` passou a seguir o mesmo padrão sem timeout próprio de
     `MobileDispatchRepository`/`PaymentRepository` (confia em `URLError.timedOut`).
  5. `try` mal posicionado numa expressão `??` em `MobileDispatchModels.swift`.
  6. `.map(String.init)` ambíguo em `GuinchoMapViewModel.swift` (removido, desnecessário).
  7. Switches exaustivos sobre `ServiceSearchStatus`/`AppointmentStatus`/`PitGoRoute` quebrados pelos
     novos casos — corrigidos em `PitTecClientView`, `PitTecHomeView`, `ProfileView`,
     `ProviderDashboardView` (fallback seguro ou novo case, nunca travando a tela).
- `-scheme pitgo-Prod`: `** BUILD SUCCEEDED **`.
- `-scheme pitgo-Homol`: `** BUILD SUCCEEDED **`.

## Funcional (manual) — pendente

T020: fluxo completo cliente+prestador (duas contas) não executado nesta sessão — pendente de
validação manual do usuário:
- Regressão reportada: no iPhone, digitar o endereço de destino e aguardar sugestões; sem pan/zoom
  manual nem tocar em "Minha localização", confirmar que um callback programático do mapa não troca
  o texto digitado pelo endereço do centro atual. A correção está instalada em Homol; reteste manual
  pendente.
- Escolha de retirada (GPS/manual)/destino (busca de endereço)/veículo → seleção de guincheiro no
  mapa → cotação → "Contratar".
- Lado prestador: aceitar/recusar dentro do prazo, remuneração (sem os 10%/taxas do cliente).
- Pagamento pós-aceite (Pix/cartão salvo), liberação de nome/veículo/endereço após aprovação.
- Chegada → início do transporte → conclusão pelo prestador → confirmação ou contestação pelo
  cliente.
- Retomada do app em cada estágio (fechar/reabrir) — confirmar que nunca cai na tela genérica de
  tracking (`AppointmentTrackingView`/`ProviderTrackingView`).

## Gaps conhecidos (documentados, não acidentais)

Ver "Ajustes de escopo" em `spec.md`: resolução de contestação (dashboard web), GPS ao vivo do
guincheiro, vistoria fotográfica e avaliação ficam para specs futuras (029-034 do Android, ainda não
portadas).

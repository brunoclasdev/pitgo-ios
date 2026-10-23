# Validation: 027-ios-environment-flavors

## Build (xcodebuild, iOS Simulator destination, 2026-10-22)

- `-scheme pitgo` (Dev, `Debug`/`Dev.xcconfig`): `** BUILD SUCCEEDED **` — Run Script "Validate
  Supabase Config" passou (supabaseUrl/Key/ProjectRef/mapStyle válidos; isolamento Dev≠Prod
  confirmado: `ljnqlaiiwreuczbdghxn` ≠ `eetbrkznuqbdrnybnyhf`).
- `-scheme pitgo-Homol` (`Debug-Homol`/`Homol.xcconfig`): `** BUILD SUCCEEDED **`.
- `-scheme pitgo-Prod` (`Debug-Prod`/`Prod.xcconfig`): `** BUILD SUCCEEDED **` (primeira tentativa
  colidiu com o build de Homol rodando em paralelo na mesma DerivedData — "database is locked",
  não é um erro de código; a segunda tentativa isolada passou).

Um erro real foi encontrado e corrigido durante a validação: `SimulatedPaymentGateway
.simulatedPixBase64` precisou de `nonisolated` explícito — o projeto define
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` globalmente, então um `static let` dentro de um `actor`
herdava isolamento `@MainActor` por padrão e não era acessível de dentro do próprio `actor` sem
`await`.

## Funcional (manual) — pendente

- T019: validar no Perfil que os três schemes mostram o rótulo de ambiente certo; validar no
  checkout de Dev que o banner/botões de simulação aparecem e que nenhuma chamada de rede `mp-*`
  acontece (inspecionável via Instruments/proxy, não verificado nesta sessão); validar que Homol/
  Prod seguem o fluxo de pagamento integrado normal (já coberto indiretamente pela spec 018/022,
  reaproveitado sem mudança de comportamento).

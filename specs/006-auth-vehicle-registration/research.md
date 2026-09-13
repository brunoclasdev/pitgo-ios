# Phase 0 Research: Sessão autenticada e cadastro de veículos (iOS)

## 0. Backend compartilhado — nenhuma migration nova

**Decision**: reutilizar integralmente `public.profiles`, `public.vehicles`, os triggers, RPCs
(`create_vehicle`, `set_primary_vehicle`), grants e RLS já criados e conciliados pela migration
Android (`supabase/migrations/20260819010000_auth_session_vehicles.sql`) no mesmo projeto Supabase.
Nenhuma migration é criada neste repositório; o contrato exato está em
[contracts/supabase.md](contracts/supabase.md).

**Rationale**: mesmo racional de `005-create-user-account` — um único schema compartilhado entre
Android e iOS. Duplicar a migration arriscaria divergência de RPCs/constraints entre plataformas
para a mesma tabela.

## 1. Estado central de sessão

**Decision**: criar um `SessionStore` (`@Observable final class`, `@MainActor`) instanciado uma
única vez em `pitgoApp.swift` e injetado via `.environment(sessionStore)` — o equivalente iOS ao
`PitGoApplication`/`PitGoAppContainer` do Android, sem framework de DI. O estado raiz é um `enum`
selado e mutuamente exclusivo, com os mesmos seis casos do Android:

```swift
enum AppSessionState {
    case initializing
    case verifying
    case unauthenticated(reason: UnauthenticatedReason?)
    case offlineVerification
    case profileBlocked(ProfileBlockedReason)   // .missing, .inactive, .inconsistent
    case authenticated(AccountSnapshot)
}
```

Somente `.authenticated` carrega dados renderizáveis. `SessionStore` é a única fronteira que chama
`SupabaseClientProvider.client.auth` para inicialização, login, validação, renovação e logout;
Login, cadastro e destinos privados o recebem via `Environment`.

**Rationale**: mesma exigência de centralização da constitution iOS (herdada do Android — proíbe
verificações independentes por tela). `@Observable` + `enum` exclusivo reproduz a garantia de
"nenhuma combinação de estados contraditórios" sem exigir `StateFlow`. `supabase-swift` expõe
`client.auth.session` e um `AsyncStream` de eventos de autenticação (`client.auth.authStateChanges`),
suficientes para essa fronteira. Fontes: [Auth Swift session](https://supabase.com/docs/reference/swift/auth-getsession),
[auth state changes](https://supabase.com/docs/reference/swift/auth-onauthstatechange).

**Alternatives considered**: mesmas do Android — verificar sessão em cada View/ViewModel (rejeitado,
duplica regra); rota inicial estática Welcome sem gate (rejeitado, produz flash do fluxo não
autenticado); um framework de DI externo (rejeitado, `@Observable` + `Environment` nativos já
resolvem).

## 2. Restauração, validação remota e logout

**Decision**: idêntico ao Android em termos de sequência — aguardar carregamento local do Auth,
validar remotamente havendo sessão, então carregar perfil e veículo principal. Falha de rede leva a
`.offlineVerification` (sessão local preservada, retry disponível); ausência/invalidez de sessão
leva a `.unauthenticated`; perfil ausente/inativo/inconsistente leva a `.profileBlocked` com retry e
logout, sem correção automática. Observar o `AsyncStream` de `authStateChanges` para reagir a
`signedOut`/`tokenRefreshed` a qualquer momento, limpando o snapshot imediatamente ao perder
autorização. Logout usa escopo local explícito (`client.auth.signOut(scope: .local)`), garantindo
limpeza mesmo sem rede.

**Rationale**: mesmas clarificações do spec, válidas para qualquer client. `supabase-swift` também
persiste/renova a sessão automaticamente; a validação de perfil continua sendo regra do app, não do
SDK.

**Alternatives considered**: idênticas ao Android — abrir Home com cache offline (rejeitado pela
clarificação); logout automático em falha de rede (rejeitado, destrói sessão possivelmente válida);
recriar perfil via metadata (rejeitado, metadata não é autoritativa).

## 3. Bootstrap da conta e Home

**Decision**: `AccountRepository` (Swift, `PostgREST` via `SupabaseClientProvider.client.from(...)`)
consulta o perfil exato do `id` autenticado e o único veículo ativo principal, em paralelo via
`async let`. `HomeUiState` vira `enum { case loading, content(AccountSnapshot), noVehicle(Profile),
failure(RegistrationResult-like reason) }`, sem modelos demonstrativos. Retornar à Home a partir da
Garagem dispara um novo `async let` de bootstrap (sem Realtime nesta entrega).

**Rationale**: `async let` é o equivalente direto ao paralelismo estruturado que o Android obtém com
coroutines lançadas em paralelo — sem operador adicional. Mesmo racional de defesa em profundidade
(filtro explícito + RLS) do Android.

**Alternatives considered**: idênticas ao Android — manter modelos demonstrativos (rejeitado, risco
de dado falso); Realtime (rejeitado, sem necessidade de sincronização contínua nesta entrega); cache
local (rejeitado, experiência offline foi descartada pela clarificação).

## 4. Convite pós-cadastro persistente

**Decision**: usar `UserDefaults.standard` (não `SwiftData`) para um `VehicleOnboardingStore` que
mantém um `Set<String>` de UUIDs pendentes, sob uma chave própria (`"pitgo.pendingVehicleOnboarding"`).
Operações `markPending(_ userID: UUID)`, `isPending(_ userID: UUID) -> Bool`,
`resolve(_ userID: UUID)`. O cadastro só conclui depois de `markPending` ter sido persistido.
Escolher qualquer ação do convite chama `resolve` antes de navegar. O convite é um destino de raiz
dedicado (sem `TabView`), inserido entre `.authenticated` e a exibição da Home quando
`isPending(userID)` é verdadeiro — o `PitGoRootView` verifica essa pendência a cada bootstrap
autenticado, antes de montar a `TabView`.

**Rationale**: `UserDefaults` é a ferramenta constitucional para preferência simples não sensível,
sobrevivendo a reinícios do processo sem exigir `SwiftData`/Core Data para um único `Set` de
strings. Mesmo racional do Android (DataStore escolhido pela mesma razão, `SwiftData`/Core Data
seriam desproporcionais para este dado). Um `Set`, não um único UUID, preserva decisões pendentes de
contas diferentes no mesmo aparelho.

**Alternatives considered**: idênticas ao Android — inferir pendência pela ausência de veículos
(rejeitado, penalizaria contas antigas); coluna nova em `profiles` (rejeitada, a clarificação exige
persistência local, não sincronizada); estado apenas em memória do `SessionStore` (rejeitado, não
sobrevive ao encerramento do processo, exigido pela clarificação de "reapresentar após reabrir").

## 5. Operações atômicas de veículo

**Decision**: nenhuma mudança de schema/RPC — `VehicleRepository` chama exatamente os mesmos RPCs
`create_vehicle`/`set_primary_vehicle` já implementados e documentados em
[contracts/supabase.md](contracts/supabase.md), via `client.rpc("create_vehicle", params:)` /
`client.rpc("set_primary_vehicle", params:)` do `supabase-swift`. A serialização por usuário
(`pg_advisory_xact_lock`) e a atomicidade da troca de principal são garantidas pelo Postgres,
independentemente da plataforma cliente.

**Rationale**: a atomicidade é uma propriedade de backend; o iOS herda a mesma garantia sem
reimplementar lock ou transação client-side.

**Alternatives considered**: idênticas ao Android, sem variação por plataforma (duas chamadas
PostgREST sem RPC, INSERT/UPDATE direto com RLS, Edge Function — todas já rejeitadas).

## 6. Contrato e validação dos veículos

**Decision**: manter no `VehicleFormViewModel` somente texto digitado em memória (`@Observable`,
nenhum `@AppStorage`/`SwiftData`). No submit, produzir um `VehicleDraft` normalizado (Swift `struct`)
com as mesmas regras do Android: marca/modelo com `trim()`; opcionais vazios viram `nil`; placa e
chassi em caixa alta; placa sem separador visual; Renavam apenas dígitos preservando zeros;
anos/quilometragem convertidos com segurança (`Int(String)` falha vira erro de campo, não crash).
Validação local replica exatamente as mesmas regras Kotlin, portadas para Swift: placa legado/
Mercosul, Renavam 11 dígitos, chassi VIN 17 caracteres sem I/O/Q, anos 1900–próximo ano civil,
quilometragem ≥ 0. O RPC repete as invariantes decisivas (backend inalterado); conflitos `23505` só
são classificados pelos nomes allowlisted `vehicles_plate_unique`, `vehicles_renavam_unique` e
`vehicles_chassis_unique`.

**Rationale**: mesmo racional do Android — estado normalizado evita diferença entre colagem e
máscara; validação dupla trata o client como não confiável, mesma allowlist de erro.

**Alternatives considered**: idênticas ao Android — máscara persistida (rejeitado); validação
somente client-side (rejeitado); persistir rascunho para recuperação (rejeitado pela clarificação de
descarte total na expiração de sessão).

## 7. Navegação e superfícies SwiftUI

**Decision**: estender `UnauthenticatedRoute` (criado em `005`) com `.login`, mantendo `.signUp`.
Login é uma `Form`/`ScrollView` com e-mail/senha, loading e falhas tipadas, empurrada na
`NavigationStack` não autenticada a partir da Welcome (`onEnter` passa a empurrar `.login` em vez de
ser no-op, como `onCreateAccount` passou a empurrar `.signUp` em `005`). O convite pós-cadastro e a
Garagem/formulário de veículo/Perfil vivem dentro da área autenticada: `Garagem` e `Perfil` já
existem como abas placeholder da `TabView` desde `002-initial-layouts` — esta feature as torna
funcionais. O formulário de veículo é uma `View` compartilhada com um parâmetro `origin: VehicleFormOrigin`
(`.onboarding` ou `.garage`, único argumento não sensível — `userID` sempre vem de `SessionStore`,
nunca de rota).

O convite pós-cadastro (`VehicleOnboardingView`) é renderizado pelo `PitGoRootView` como uma tela
cheia **fora** da `TabView` enquanto `isPending(userID)` é verdadeiro, mesmo estando
`.authenticated` — Home só é montada depois de `resolve(userID)`.

**Rationale**: preserva o design system e as abas já reservadas em `002`; evita passar identidade
pela rota; um destino de raiz dedicado para o convite (fora da `TabView`) impede que Back o
dispense silenciosamente, mesmo racional do Android (destino sem bottom nav, sem fechamento
implícito).

**Alternatives considered**: idênticas ao Android — logout em menu oculto no avatar (rejeitado, baixa
descoberta); duplicar a `TabView` por tela (rejeitado, já existe uma única `PitGoBottomTabs`
compartilhada desde `002`); passar `userID` como argumento de rota (rejeitado, identidade só vem da
sessão).

## 8. Avatar remoto

**Decision**: usar `AsyncImage(url:)`, nativo do SwiftUI, quando `avatarURL` não for vazio, com
`.frame` limitado, `ProgressView` como placeholder e fallback imediato para iniciais em qualquer
estado de erro/URL inválida — sem adicionar nenhuma biblioteca de terceiros.

**Rationale**: diferente do Android (Compose não tem carregador de imagem assíncrono nativo e
precisou adicionar Coil), o SwiftUI já resolve download assíncrono, cache em memória e ciclo de vida
via `AsyncImage` nativo — uma vantagem estrutural real da plataforma que elimina uma dependência
inteira presente no lado Android. Fonte: [AsyncImage](https://developer.apple.com/documentation/swiftui/asyncimage).

**Alternatives considered**: ignorar `avatarURL` (rejeitado por FR-008); adicionar Kingfisher/Nuke
para cache em disco mais agressivo (rejeitado por YAGNI — `AsyncImage` já atende ao requisito de
placeholder + fallback + carregamento assíncrono sem dependência nova); baixar `Data` manualmente
com `URLSession` (rejeitado, duplica pipeline que `AsyncImage` já entrega).

## 9. Persistência e proteção da sessão

**Decision**: usar o armazenamento padrão de sessão do `supabase-swift` (baseado em Keychain, mais
restritivo por padrão que o `SharedPreferences` do Android). Como tarefa explícita desta feature,
**verificar** a configuração de acessibilidade do item de Keychain usado pelo SDK e, se necessária,
ajustar para `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (impede que o item participe de
iCloud Keychain sync entre dispositivos) — o equivalente iOS à exclusão explícita de
`SharedPreferences` do backup Android (`backup_rules.xml`/`data_extraction_rules.xml`, que não têm
análogo direto no iOS porque o Keychain, ao contrário de `UserDefaults`, não é incluído em backups
não criptografados do Finder/iCloud por padrão). `UserDefaults` do onboarding não contém token,
senha, documento ou rascunho. Nenhum `Error` do SDK é enviado a log/crash reporting; somente
categorias de domínio e códigos allowlisted podem ser registrados em debug.

**Rationale**: o SDK já implementa rotação e restauração de sessão; a tarefa desta feature é
confirmar/reforçar a configuração de proteção do item, não reimplementar armazenamento de sessão.

**Alternatives considered**: aceitar a configuração padrão sem verificar (rejeitado — mesmo cuidado
do Android com backup, adaptado ao mecanismo real do iOS); implementar Keychain próprio substituindo
o `AuthLocalStorage` do SDK (rejeitado, amplia o escopo sem necessidade); persistir senha para
reautenticação (rejeitado, senha existe só na memória do formulário).

## 10. Verificação operacional (sem migration nova)

**Decision**: mesma postura de `005` — usar `supabase db diff` (leitura) para confirmar que o schema
de `public.vehicles`/RPCs documentado em [contracts/supabase.md](contracts/supabase.md) já está
aplicado no projeto compartilhado. Nenhum `supabase db reset`/`db push` faz parte desta feature iOS;
qualquer divergência de schema é corrigida na migration do repositório Android, fonte única de
verdade.

**Rationale**: idêntico a `005-create-user-account §0`.

## Primary sources

- Supabase Swift Auth (sessão, `authStateChanges`): https://supabase.com/docs/reference/swift/auth-getsession,
  https://supabase.com/docs/reference/swift/auth-onauthstatechange
- Supabase Swift RPC: https://supabase.com/docs/reference/swift/rpc
- Supabase Database Functions e segurança: https://supabase.com/docs/guides/database/functions
- Supabase RLS e grants: https://supabase.com/docs/guides/database/postgres/row-level-security
- PostgreSQL locks transacionais: https://www.postgresql.org/docs/current/explicit-locking.html
- `AsyncImage` (SwiftUI): https://developer.apple.com/documentation/swiftui/asyncimage
- Keychain accessibility constants: https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly
- `UserDefaults`: https://developer.apple.com/documentation/foundation/userdefaults

## Resolution status

Todas as decisões do Technical Context foram resolvidas; não restam pendências.

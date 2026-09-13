# Research: Criar conta de usuário (iOS)

## 0. Backend compartilhado — nenhuma migration nova

**Decision**: reutilizar integralmente o schema `public.profiles`, a função/trigger `AFTER INSERT ON
auth.users`, os grants e as RLS policies já criados pela migration Android
(`supabase/migrations/<timestamp>_create_profiles.sql`) no mesmo projeto Supabase (`eetbrkznuqbdrnybnyhf`).
Esta feature iOS **não cria uma nova migration** e não altera o schema — ela apenas consome o
contrato já ativo, documentado em [profiles-schema.md](contracts/profiles-schema.md).

**Rationale**: Android e iOS compartilham o mesmo backend Supabase (mesmo projeto, mesmo `supabaseUrl`,
mesma tabela). Recriar ou duplicar a migration arriscaria divergência de schema entre plataformas e
viola diretamente a decisão de arquitetura registrada na constitution iOS (mesmo backend). A
validação desta feature no iOS é de responsabilidade puramente client-side: consumir Auth/PostgREST
com o mesmo contrato que o Android já validou em produção/desenvolvimento.

**Alternatives considered**: gerar uma segunda migration idêntica dentro de um diretório
`supabase/` do repositório iOS, rejeitado porque os dois repositórios (Android e iOS) apontam para o
mesmo projeto remoto — aplicar a mesma migration duas vezes é redundante e arrisca conflito de
histórico de migrations caso os dois repositórios usem CLIs Supabase distintos e desalinhados;
criar uma tabela paralela específica para iOS, rejeitado por quebrar a unicidade de perfil por
usuário exigida pelo FR-011/FR-012 do spec (uma identidade, um perfil, independente da plataforma
de origem do cadastro).

## 1. SDK, versões e módulos

**Decision**: estender o `supabase-swift` já configurado em `004` com os produtos `Auth` e
`PostgREST` (Swift Package Manager, mesmo pacote, produtos adicionais — não pacotes separados).
Não adicionar `Storage`, `Realtime`, `Functions`, `GoTrue` isolado ou qualquer biblioteca de
formulário/máscara de terceiros.

**Rationale**: `supabase-swift` expõe `Auth`/`PostgREST` como productos do mesmo pacote SPM já
resolvido em `004-configure-supabase`; adicioná-los ao target não introduz uma nova dependência
externa, apenas amplia o que já é linkado. `Codable` nativo do Swift substitui a necessidade do
plugin Kotlin Serialization do Android — não há dependência equivalente a declarar. Fontes:
[supabase-swift products](https://github.com/supabase/supabase-swift), [Auth Swift](https://supabase.com/docs/reference/swift/auth-signup),
[PostgREST Swift](https://supabase.com/docs/reference/swift/select).

**Alternatives considered**: mesma lista do Android — usar somente Auth e confiar no trigger sem
conferir o perfil, rejeitado pela mesma necessidade de recuperação idempotente; parsing manual de
JSON com `JSONSerialization`, rejeitado porque `Codable` já resolve tipagem sem custo adicional.

## 2. Cadastro, sessão imediata e metadata

**Decision**: após aguardar a inicialização do cliente (`SupabaseClientProvider.client.auth.session`
observado ou `try? await client.auth.session` com tratamento de ausência), chamar
`client.auth.signUp(email:password:data:)` com e-mail normalizado, senha e `data` contendo somente
`name`, `phone` e exatamente um entre `cpf`/`cnpj`, como `[String: AnyJSON]`. O retorno do `signUp`
não decide sucesso sozinho: ler `client.auth.session` (ou `currentSession`) logo em seguida e exigir
`id`/`email` não nulos. O ambiente Supabase (compartilhado com Android) já mantém **Confirm email**
desabilitado; se o signup não produzir sessão imediata, retornar `.environmentMisconfigured` e não
navegar para Home.

**Rationale**: a API Swift do `Auth` aceita metadata (`data`) no mesmo formato conceitual do
`raw_user_meta_data` usado pelo Kotlin SDK — ambos chegam ao mesmo trigger Postgres. Como o ambiente
de Auth já está configurado (sem confirmação de e-mail, senha mínima 8) pelo trabalho da feature
Android, o iOS herda o mesmo comportamento sem reconfiguração. Fontes: [signUp Swift](https://supabase.com/docs/reference/swift/auth-signup),
[sessão atual](https://supabase.com/docs/reference/swift/auth-getsession).

**Alternatives considered**: mesmas do Android — confirmar e-mail antes da Home contradiz a
clarificação já registrada no spec; enviar e-mail também como metadata duplica fonte de verdade.

## 3. Criação atômica e recuperação idempotente

**Decision**: como o trigger/função já existe no backend compartilhado (ver seção 0), o
`SignUpRepository` iOS implementa exatamente a mesma sequência client-side do Android: signup →
exigir sessão → `select` em `profiles` pelo próprio `id` → se ausente, `insert`/`upsert` idempotente
(`onConflict: "id"`, ignorando duplicidade) sem enviar `active` → `select` novamente para confirmar.
Numa resposta de rede ambígua sem sessão local, tentar um único `signIn(email:password:)` com as
mesmas credenciais antes de tratar como recuperação.

**Rationale**: a lógica de orquestração é uma decisão de client, não de schema — o comportamento do
trigger transacional (falha propagada, rollback do signup em caso de CHECK inválido) já está
garantido pelo backend compartilhado; o iOS só precisa replicar a mesma sequência de chamadas que o
Android usa para lidar com o mesmo contrato. Fonte: [gerenciamento de dados de usuário](https://supabase.com/docs/guides/auth/managing-user-data)
(mesma referência do Android, válida para qualquer cliente Supabase).

**Alternatives considered**: idênticas às do Android (Edge Function com service-role, exclusão via
privilégio administrativo, navegação otimista antes da confirmação) — todas rejeitadas pelos mesmos
motivos, sem diferença por plataforma.

## 4. Schema e invariantes de `profiles`

**Decision**: nenhuma mudança. O schema documentado em [profiles-schema.md](contracts/profiles-schema.md)
é herdado sem alteração — mesmas colunas, mesmos checks nomeados, mesma relação 1:1 com
`auth.users`, mesmo texto para CPF/CNPJ (preservando zeros e caracteres alfanuméricos).

**Rationale**: ver seção 0 — reuso de backend compartilhado.

## 5. CPF e CNPJ vigentes — porte para Swift

**Decision**: portar a mesma regra de validação (não a mesma implementação Kotlin, mas o mesmo
algoritmo) para Swift: CPF exige exatamente 11 dígitos, rejeita sequências repetidas e valida os
dois DVs por módulo 11; CNPJ aceita tanto o formato legado numérico quanto o alfanumérico vigente
(12 caracteres `[0-9A-Z]` + 2 DVs numéricos), usando `ASCII - 48` e os pesos oficiais para os DVs,
implementado em `SignUpValidation.swift` como funções puras (`static func isValidCPF(_ digits:
String) -> Bool`, `static func isValidCNPJ(_ value: String) -> Bool`). A UI aplica máscara
`##.###.###/####-##`, teclado numérico apenas para CPF; CNPJ aceita letras maiúsculas e números.

**Rationale**: mesma exigência regulatória do Android (CNPJ alfanumérico vigente desde julho de
2026); a validação client-side é apenas feedback imediato — a autoridade final continua sendo as
funções SQL já aplicadas no banco compartilhado (`profiles_cpf_valid`/`profiles_cnpj_valid`), que
não mudam entre plataformas. Fontes: mesmas do Android — [CNPJ alfanumérico](https://www.gov.br/receitafederal/pt-br/acesso-a-informacao/acoes-e-programas/programas-e-atividades/cnpj-alfanumerico)
e [manual oficial de DVs](https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/publicacoes/documentos-tecnicos/cnpj/manual-dv-cnpj.pdf/@@download/file).

**Alternatives considered**: mesmas do Android, sem variação por plataforma.

## 6. RLS, grants e funções do banco

**Decision**: nenhuma mudança. As policies de SELECT/INSERT `(select auth.uid()) = id` e os grants
mínimos a `authenticated` (documentados em [profiles-schema.md](contracts/profiles-schema.md)) já
protegem qualquer cliente que use a chave publishable/anon — Android ou iOS — de forma idêntica,
porque RLS é aplicada pelo Postgres à identidade JWT autenticada, independente da plataforma que fez
a requisição.

**Rationale**: RLS é uma garantia de backend; nenhuma configuração adicional client-side é necessária
para o iOS herdar a mesma proteção. Fonte: [RLS Supabase](https://supabase.com/docs/guides/database/postgres/row-level-security).

## 7. Repository, resultados e tratamento de falhas

**Decision**: `SignUpRepository` (`final class`, `@MainActor` não exigido — é um serviço de rede
puro, não uma entidade de UI) recebe o `SupabaseClient` por `init` e expõe uma única função
`async func register(_:) async -> RegistrationResult` e `async func retryProfile(_:) async ->
RegistrationResult`, ambas **sem `throws`** — todo erro do SDK (`AuthError`, `PostgrestError`,
`URLError`) é capturado internamente com `do/catch` e mapeado para um `enum RegistrationResult`
tipado, nunca propagado como `Error` para o ViewModel. `Task.isCancelled`/`CancellationError` é
respeitado (a função retorna cedo sem mapear como falha de domínio quando a `Task` pai foi
cancelada).

**Rationale**: manter o resultado como um valor de retorno tipado (em vez de `throws`) espelha
deliberadamente o design do Android (`sealed class RegistrationResult`, nunca uma exceção
atravessando a fronteira do Repository) — o ViewModel faz apenas um `switch` exaustivo sobre casos
conhecidos, sem `try/catch` espalhado pela camada de apresentação. Fonte: [error handling Swift Concurrency](https://developer.apple.com/documentation/swift/concurrency).

**Alternatives considered**: função `throws` com um `enum SignUpError: Error`, rejeitada porque
obrigaria o ViewModel a um `do/catch` para cada chamada e reintroduziria o risco de um `Error` não
mapeado escapar sem sanitização; Combine/`AnyPublisher`, rejeitado por YAGNI — `async/await` já
resolve a orquestração sequencial sem operadores adicionais.

**Security note**: idêntica ao Android — mensagens de `AuthError`/`PostgrestError` do
`supabase-swift` podem conter URL, headers (inclusive `Authorization`) e o valor de uma constraint
violada. Nunca logar o `Error` bruto, sua `localizedDescription` completa, headers ou `details`;
mapear somente `AuthError.ErrorCode` estável, status HTTP e nomes de constraints em allowlist
(idênticos aos do Android, ver [profiles-schema.md](contracts/profiles-schema.md)) para um
`RegistrationResult` sanitizado.

## 8. Estado MVVM e ciclo do formulário

**Decision**: `SignUpViewModel` é uma classe `@Observable @MainActor` com uma propriedade
`private(set) var state: SignUpUiState`, contendo `PersonType?`, `name`, `email`, `phone`, um único
`document`, senha/confirmação apenas em memória, erros tipados, `FocusRequest` e um
`SignUpSubmissionState` (`enum` com `.editing`, `.submitting(SignUpStage)`, `.failure(reason:
SignUpFailureReason, profilePending: Bool)`, `.success`). O ViewModel normaliza entrada, valida
todos os campos numa única passada, foca o primeiro erro, bloqueia disparos concorrentes com uma
guarda síncrona (`guard case .editing = state.submission else { return }` antes de lançar a `Task`)
e chama o Repository dentro de uma `Task { @MainActor in ... }` própria, cancelada automaticamente
se a View for descartada (`.task` modifier) — sem precisar de `viewModelScope` explícito, que não
existe em Swift. `Success` permanece no estado; a View observa e a navegação raiz reage via
`.onChange(of:)`. Após falha remota, `password`/`passwordConfirmation` são limpos e nunca fazem parte
de um tipo `Codable`/persistido (nenhum `@AppStorage`, `SwiftData` ou `UserDefaults` os toca).

**Rationale**: `@Observable` + `enum` exclusivo reproduz exatamente a garantia do Android (estados
contraditórios impossíveis de representar) sem exigir `StateFlow`; `Task` própria por submissão
substitui `viewModelScope.launch` porque o Swift Concurrency associa o ciclo de vida da `Task`
diretamente à View via `.task`, sem exigir um escopo de coroutine dedicado à classe. Fonte: [Swift
Observation](https://developer.apple.com/documentation/observation), [managing tasks in SwiftUI](https://developer.apple.com/documentation/swiftui/task).

**Alternatives considered**: mesmas do Android — dois campos ocultos, eventos de navegação via
Combine `PassthroughSubject` (equivalente a Channel, mesmo risco de perda), reducer/MVI, persistir
senha para restauração de estado — todas rejeitadas pelos mesmos motivos.

## 9. UI, teclado e acessibilidade

**Decision**: `SignUpView` stateless usa `NavigationStack`-friendly toolbar (título + botão voltar
nativo do próprio `NavigationStack`, sem TopAppBar manual), uma única `ScrollView`/`Form` com
`.scrollDismissesKeyboard(.interactively)`, sem `TabView` (o cadastro fica fora da área autenticada,
mesmo racional do Android sem bottom navigation). Tipo de pessoa é um grupo de seleção acessível
(`Picker` com `.pickerStyle(.segmented)` ou dois `Button`s customizados anunciando
`.accessibilityAddTraits(.isSelected)`, empilhando em `Dynamic Type` grande via `ViewThatFits`).
Campos: nome dinâmico (`TextField` com label computado), e-mail (`.keyboardType(.emailAddress)`,
`.textContentType(.emailAddress)`, `.autocorrectionDisabled()`), telefone/documento com
formatação-ao-editar (ver nota abaixo), senha/confirmação (`SecureField`/`TextField` alternável por
toggle de visibilidade com `.textContentType(.newPassword)` para habilitar sugestão de senha forte
do iOS). CTA usa `Button` com altura mínima 56pt e `ProgressView` sobreposta durante submissão.
Erros ficam junto ao campo (`Text` vermelho abaixo, `.accessibilityLabel` combinando rótulo + erro);
banner remoto usa `.accessibilityAddTraits(.updatesFrequently)` (Live Region). Foco vai ao primeiro
erro via `@FocusState` enum de campo. Back e o botão de navegação usam `.confirmationDialog` para
descarte quando há rascunho, e ficam desabilitados durante uma submissão potencialmente já
commitada no servidor.

**Rationale**: reaproveita os padrões já definidos em `001`–`003` (tema, `ViewThatFits`, alvos de
44pt); `@FocusState` é o mecanismo nativo do SwiftUI para "focar o primeiro campo inválido",
equivalente direto ao `BringIntoView`/foco do Compose. Fontes: [text input SwiftUI](https://developer.apple.com/documentation/swiftui/text-input-and-output),
[FocusState](https://developer.apple.com/documentation/swiftui/focusstate), [textContentType](https://developer.apple.com/documentation/uikit/uitextcontenttype).

**Mask/formatting note**: SwiftUI não possui um equivalente direto ao par
`VisualTransformation`/`OffsetMapping` do Compose (que reescreve o texto exibido preservando a
posição exata do cursor). A decisão é aplicar formatação **no `onChange` do valor bruto** (dígitos
puros armazenados no estado; a versão mascarada é recomputada e reatribuída ao `TextField` a cada
alteração). Isso é aceitável porque: (a) o iOS já reposiciona razoavelmente o cursor ao final do
texto reformatado em edições incrementais (digitação normal, o caso majoritário); (b) colar um valor
já mascarado continua produzindo o valor canônico correto, pois a normalização ocorre antes da
validação, independente de onde o cursor ficou. A única regressão real frente ao Android é a edição
manual no **meio** de um valor já mascarado, onde o cursor pode saltar para o fim — um trade-off de
UX documentado e aceito, não um bloqueio funcional.

**Alternatives considered**: implementar um `UITextField` customizado via `UIViewRepresentable` com
mapeamento de cursor equivalente ao Android, rejeitado por YAGNI/complexidade desproporcional ao
risco (aumenta superfície de manutenção para um ganho de UX marginal em edição no meio do texto);
`TextField(_:value:format:)` com um `ParseableFormatStyle` customizado, considerado mas não adotado
como decisão principal porque `FormatStyle` foi desenhado para exibição/parse completos, não para
mascaramento incremental caractere-a-caractere — pode ser revisitado numa iteração futura se a
regressão de cursor se mostrar um problema real em uso.

## 10. Navegação e "back stack"

**Decision**: estender `PitGoRootView` (hoje um `@State private var showHome: Bool` alternando
Welcome/Home, ver `002-initial-layouts`) para um pequeno estado raiz explícito:

```swift
enum RootPhase: Hashable {
    case unauthenticated
    case home
}
```

com uma `NavigationStack` interna cobrindo o fluxo não autenticado (`path: [UnauthenticatedRoute]`,
`enum UnauthenticatedRoute: Hashable { case signUp }`), montada apenas enquanto `phase ==
.unauthenticated`. `WelcomeView.onCreateAccount` passa a empurrar `.signUp` nesse path (era um
no-op em `002`). Ao receber `SignUpUiState.submission == .success`, o `PitGoRootView` faz
`phase = .home` — o que descarta inteiramente a `NavigationStack` não autenticada (Welcome + SignUp
saem da memória junto com qualquer senha residual em estado), equivalente ao
`popUpTo(Welcome){inclusive=true}` + `launchSingleTop` do Android. Voltar do `SignUpView` usa o
`path.removeLast()` padrão do `NavigationStack` (ou o botão nativo), retornando à Welcome.

**Rationale**: um `enum RootPhase` de dois casos é a forma mais simples de representar "há sessão
válida ou não" sem introduzir um framework de navegação/DI; descartar a `NavigationStack` inteira ao
trocar de `phase` é uma vantagem estrutural do SwiftUI sobre o back stack do Android — não é preciso
chamar `popUpTo` explicitamente, a troca de `view identity` já libera toda a subárvore anterior
(incluindo o estado do `SignUpViewModel`, que é recriado do zero se o usuário deslogar e cadastrar
de novo no futuro).

**Alternatives considered**: manter `showHome: Bool` e adicionar um terceiro `Bool` para SignUp,
rejeitado porque combinações booleanas conflitantes (`showHome && showSignUp`) voltam a ser
representáveis — exatamente o problema que motivou trocar por um `enum`; usar `NavigationPath` única
para todo o app (autenticado + não autenticado), rejeitado porque misturaria rotas com
responsabilidades de acesso completamente diferentes numa única pilha.

## 11. Verificação operacional (sem migration nova)

**Decision**: a validação backend desta feature no iOS é de **verificação**, não de aplicação: usar
`supabase db diff`/consultas de leitura contra o projeto já configurado para confirmar que o schema
documentado em [profiles-schema.md](contracts/profiles-schema.md) já existe e está inalterado, e
que as configurações de Auth (Confirm email desabilitado, senha mínima 8) seguem ativas — as mesmas
já garantidas pela feature Android equivalente. Nenhum `supabase db reset`/`db push` faz parte desta
feature iOS.

**Rationale**: como não há migration nova (seção 0), não há schema a resetar/aplicar; o trabalho é
inteiramente client-side (`xcodebuild`) mais os cenários manuais de `quickstart.md`.

**Alternatives considered**: reaplicar a migration Android a partir do repositório iOS "por
segurança", rejeitado por criar um segundo ponto de verdade para o mesmo schema, contrariando a
premissa de backend único e compartilhado registrada na constitution iOS.

## Resolution status

Todas as decisões do Technical Context foram resolvidas; não restam decisões pendentes.

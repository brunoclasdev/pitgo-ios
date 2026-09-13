# Research: Cadastro de empresa prestadora (iOS)

## 0. Backend compartilhado — nenhuma migration nova

**Decision**: reutilizar integralmente `public.providers`, `public.addresses`,
`public.service_categories`, `public.services`, `public.provider_services`, a RPC
`create_provider_registration` e as policies RLS já criadas pela migration Android
(`supabase/migrations/20260820000000_provider_registration.sql`) no mesmo projeto compartilhado.
Nenhuma migration é criada neste repositório; o contrato exato está em
[contracts/supabase-provider-registration.md](contracts/supabase-provider-registration.md).

**Rationale**: mesmo racional de `005`/`006` — schema único compartilhado entre Android e iOS.

## 1. Stack e fronteiras existentes

**Decision**: reutilizar SwiftUI/`@Observable`/MVVM, `SessionStore` e os produtos `Auth`/`PostgREST`
do `supabase-swift` já configurados. Criar um único `ProviderRegistrationRepository`, sem
dependência nova, camada de Use Case ou cache.

**Rationale**: mesmo desenho já usado por `VehicleRepository` em `006`: DTO `Codable`, chamada RPC,
resultado de domínio tipado e erro sanitizado. Camadas adicionais apenas repassariam chamadas.

**Alternatives considered**: idênticas ao Android — acesso Supabase na View (rejeitado, viola
MVVM); Edge Function (rejeitada, introduz backend/credencial sem melhorar a transação PostgreSQL já
existente).

## 2. Entrada autenticada e continuidade do CTA público

**Decision**: a entrada autenticada principal é "Área da empresa" na aba Perfil (empurra
`PitGoRoute.providerRegistration` na `NavigationStack` daquela aba). O CTA público da Welcome
"Cadastrar empresa" empurra `UnauthenticatedRoute.signUp(origin: .provider)` — `SignUpOrigin` vira
um `enum` com associated value que o `UnauthenticatedRoute.signUp` carrega (`case signUp(origin:
SignUpOrigin)`), em vez de um argumento de string livre. Depois que `SessionStore` emitir
`.authenticated`, o `PitGoRootView` consome esse valor **uma única vez, em memória** (não persistido
em `UserDefaults`, diferente da pendência de veículo de `006` — a intenção de "acabei de pedir para
virar prestador" não precisa sobreviver ao encerramento do processo) e mostra
`ProviderRegistrationView` antes da `TabView`, em vez de ir direto para Home.

**Rationale**: mesmo racional do Android — usuários autenticados não voltam à Welcome, então
precisam de uma entrada dentro da área da conta; o CTA público não pode abrir diretamente uma tela
protegida. Um `enum` com associated value é mais idiomático em Swift que uma string de origem/rota
livre, e mantém a mesma garantia de "nenhum destino arbitrário" do Android (só `.default`/`.provider`
existem).

**Alternatives considered**: idênticas ao Android — abrir o formulário direto pela Welcome
(rejeitado por FR-001); passar `providerID` (rejeitado, owner vem da sessão); persistir a intenção
em `UserDefaults` como a pendência de veículo (rejeitado — diferente do onboarding de veículo, que
precisa sobreviver ao fechamento do app antes de qualquer escolha, aqui o cadastro de conta e a
abertura do formulário de empresa acontecem na mesma sessão de app contínua, sem uma etapa
intermediária que sobreviva a um "fechar e reabrir").

## 3. Destino único para formulário e consulta

**Decision**: `ProviderRegistrationView` tem estados exclusivos para carregamento, falha inicial,
formulário, empresa existente, sucesso e sessão expirada — mesmo `enum
ProviderRegistrationUiState` do Android, traduzido para Swift. Se já existir um provider completo, a
própria View mostra o resumo da empresa, endereço e ofertas. Após criação, mostra confirmação e o
mesmo resumo; a ação final retorna à aba Perfil, removendo a rota do `NavigationPath`.

**Rationale**: idêntico ao Android — evita um segundo destino quase idêntico e resolve perda de
resposta (um retry que encontra o agregado completo é sucesso reconhecido, não uma segunda criação).

**Alternatives considered**: idênticas ao Android (tela de detalhes separada, sobrescrever provider
existente) — ambas rejeitadas pelos mesmos motivos.

## 4. UI longa, responsiva e acessível

**Decision**: usar uma única `List` SwiftUI (nativamente lazy, equivalente direto ao `LazyColumn`
do Android) com seções `Section("Dados da empresa")`, `Section("Endereço")` e
`Section("Serviços oferecidos")`, sem `TabView`, largura de leitura limitada em telas largas
(`.frame(maxWidth: 600)` centralizado) e `.scrollDismissesKeyboard(.interactively)`. Coordenadas
opcionais ficam num `DisclosureGroup` recolhível. Cada oferta é uma linha da `List` com `id`
estável (`OfferDraft.localID`, um `UUID` gerado uma vez por rascunho de oferta — nunca reindexado),
usando `ForEach(offers) { ... }.onDelete` para remoção acessível. `@FocusState` leva ao primeiro
campo inválido.

**Rationale**: `List` já entrega lazy loading, separadores, swipe-to-delete acessível e reflow
correto em Dynamic Type — o mesmo padrão de `001`–`006`. Mesmo racional do Android para rejeitar
wizard/duas colunas/accordion (ver research Android §4).

**Alternatives considered**: idênticas ao Android — wizard multi-etapas (rejeitado, dificulta o
"foco no primeiro erro global"); duas colunas fixas (rejeitado, corta labels em Dynamic Type
grande); accordion por oferta (rejeitado, esconde erros sem necessidade).

## 5. Catálogo e seletores dependentes

**Decision**: `ProviderRegistrationRepository` consulta categorias ordenadas e carrega serviços por
categoria sob demanda, paginando com `.range(from:to:)` do PostgREST até uma página curta. O
ViewModel mantém `LoadState<T>` (`enum { loading, empty, content(T), failure(reason) }`) e um cache
`[CategoryID: LoadState<[CatalogService]>]` enquanto a View existir. Trocar de categoria numa oferta
limpa o `serviceID` daquela oferta. Serviços já escolhidos por outra oferta ficam indisponíveis no
`Picker`; a validação definitiva permanece no submit e no UNIQUE do banco.

**Rationale**: idêntico ao Android — o app não cria/altera catálogo nem impõe limite total de
ofertas; cache por categoria evita chamadas repetidas; paginação evita truncamento silencioso.

**Alternatives considered**: idênticas ao Android — carregar um limite fixo (rejeitado, trunca
dados); copiar a lista de serviços para cada oferta (rejeitado, custo/divergência); enviar
`categoryID` à RPC (rejeitado, é derivável e poderia contradizer o serviço).

## 6. Schema canônico (contexto, sem ação nesta feature)

Nenhuma ação — o schema, a reconciliação singular/plural, a grafia física `neighbornhood` e todas as
constraints já foram resolvidas e aplicadas pela migration Android. Ver
[contracts/supabase-provider-registration.md](contracts/supabase-provider-registration.md) para o
contrato exato herdado; o modelo Swift expõe `neighborhood` (grafia correta) e mapeia via
`CodingKeys` para `neighbornhood` (grafia física), mesma estratégia do `Profile.isActive`/`active`
em `005`/`006`.

## 7. Operação PostgreSQL atômica

**Decision**: nenhuma mudança de schema/RPC — `ProviderRegistrationRepository` chama exatamente
`create_provider_registration(p_provider:, p_address:, p_offers:)` já implementada, via
`client.rpc("create_provider_registration", params: payload).execute()` do `supabase-swift`,
decodificando a resposta JSON fechada (`outcome`, `offer_count`).

**Rationale**: a atomicidade é uma propriedade de backend; o iOS herda a mesma garantia sem
reimplementar lock ou transação client-side, idêntico a `006 §5`.

**Alternatives considered**: idênticas ao Android, sem variação por plataforma.

## 8. RLS e privilégio mínimo

**Decision**: nenhuma mudança — RLS e grants já aplicados (SELECT-only em `authenticated`, EXECUTE
apenas na RPC) protegem qualquer cliente que use a chave publishable/anon, Android ou iOS, de forma
idêntica.

**Rationale**: RLS é aplicada pelo Postgres à identidade JWT autenticada, independente da plataforma
de origem da requisição — mesmo racional de `005 §6`/`006 §6`.

## 9. Normalização e validação em duas fronteiras

**Decision**: estender `BrazilianInputValidation` (extraída em `005`/portada para
`Core/Common/Validation/BrazilianInputValidation.swift`) com CEP (8 dígitos) e as 27 UFs
brasileiras. `ProviderRegistrationViewModel` mantém entradas editáveis em `String`; uma função pura
de validação produz um `ProviderRegistrationCommand` normalizado: nome/endereço com `trim()`, e-mail
em minúsculas, telefone/CEP só dígitos, CNPJ maiúsculo alfanumérico, UF maiúscula, país fixo `"BR"`,
preço como `Decimal` (nunca `Double`, para não perder centavos), duração como `Int` e coordenadas
como `Decimal?` pareadas. Máscaras seguem a mesma abordagem "formatação-ao-editar" já decidida em
`005 §9` (sem `OffsetMapping`, dígitos puros no estado, máscara recomputada no `onChange`).

CNPJ aceita 12 caracteres alfanuméricos + 2 DVs numéricos, mesmo algoritmo oficial já portado para
Swift em `005`. Preço não gratuito deve ser maior que zero com até duas casas decimais; gratuito
envia `isFree = true` e preço zero. Coordenadas são ambas `nil` ou ambas válidas.

**Rationale**: idêntico ao Android — validação local dá orientação e foco; o banco é a autoridade
definitiva. `Decimal` é o tipo Swift correto para valores monetários, equivalente direto ao
`BigDecimal` do Android (evita o erro de arredondamento binário de `Double`).

**Alternatives considered**: idênticas ao Android — persistir máscara (rejeitado); aceitar somente
CNPJ numérico (rejeitado, obsoleto); usar `Double` para preço (rejeitado, arredondamento); validar
somente no client (rejeitado, cliente não confiável).

## 10. Estado, retry e privacidade

**Decision**: `ProviderRegistrationViewModel` captura o `userID` esperado no bootstrap (a partir de
`SessionStore.state`), observa mudanças de sessão e descarta rascunho/cache/resultados tardios se a
sessão sair de `.authenticated` ou trocar de usuário — mesmo mecanismo de "captura e compara" descrito
em `006` para o formulário de veículo. `ProviderRegistrationUiState` é um `enum` exclusivo
(`.loading`, `.startupFailure`, `.editing`, `.alreadyRegistered`, `.success`, `.sessionExpired`). Um
único `Task` de submissão e uma guarda síncrona bloqueiam toques duplicados. Falhas temporárias
preservam o rascunho somente em memória; conflito de e-mail/CNPJ/serviço marca o campo
correspondente; sessão expirada zera tudo.

O Repository mapeia somente classes/status/códigos e nomes de constraint allowlisted — nunca
propaga o `Error` bruto do SDK, mensagem PostgREST, headers, payload, IDs ou CNPJ completo. A UI
mostra CNPJ mascarado no resumo.

**Rationale**: idêntico ao racional do Android — a sessão central já cobre refresh/expiração;
estado em memória preserva o trabalho durante falha transitória sem persistir documento/endereço.

**Alternatives considered**: idênticas ao Android — `UserDefaults`/`SwiftData` para o rascunho
(rejeitado, persistiria PII sem necessidade); `AsyncStream`/`Combine` para eventos de navegação
(rejeitado, mesmo risco de perda de evento que um `Channel` Kotlin).

## Resolution status

Todas as decisões do Technical Context foram resolvidas; não restam pendências.

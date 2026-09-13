# Implementation Plan: Cadastro de empresa prestadora (iOS)

**Branch**: `007-provider-registration` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/007-provider-registration/spec.md`

## Summary

Implementar um destino autenticado de cadastro e consulta da empresa prestadora em SwiftUI/MVVM. O
formulário reúne dados da empresa, um endereço brasileiro e uma lista dinâmica de ofertas escolhidas
do catálogo existente. O client valida e mantém o rascunho apenas em memória; um único
`ProviderRegistrationRepository` carrega o catálogo e chama a função PostgreSQL
`create_provider_registration` **já existente e compartilhada com o Android**, que deriva o
proprietário de `auth.uid()`, revalida todo o agregado, serializa concorrência por conta e cria
`providers`, `addresses` e todas as linhas de `provider_services` na mesma transação. Uma empresa já
existente é carregada como resumo em vez de ser sobrescrita. Nenhuma migration nova é criada nesta
feature iOS.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: `supabase-swift` (produtos `Auth`/`PostgREST`, já resolvidos em
`004`–`006`); SwiftUI, Foundation. Nenhuma dependência nova.

**Storage**: Supabase Auth e PostgreSQL (`profiles`, `providers`, `addresses`,
`service_categories`, `services`, `provider_services` — schema e RPC já existentes e compartilhados
com o Android); nenhum rascunho persistido localmente

**Testing**: build via `xcodebuild`, verificação (não aplicação) do schema compartilhado e roteiro
manual em `quickstart.md`; nenhum teste automatizado, conforme governança do projeto

**Target Platform**: iOS 17+, iPhone e iPad, Debug e destino `generic/platform=iOS`, portrait e
landscape

**Project Type**: aplicativo iOS nativo de alvo único, com backend Supabase compartilhado com o
Android

**Performance Goals**: manter interação fluida (SwiftUI/`List` nativa); compor ofertas por `List`
lazy com `id` estável; carregar cada página do catálogo uma vez por instância da View; processar
apenas uma confirmação por vez

**Constraints**: somente sessão autenticada; uma empresa por conta; proprietário nunca editável;
salvamento atômico e idempotente (garantido pelo backend); nenhuma chamada de criação por oferta;
nenhum limite de quantidade imposto pelo app; sem geocodificação, mapa, consulta de CEP, cache local
ou logs de CNPJ/payload/erro bruto; nenhuma migration nova

**Scale/Scope**: um destino autenticado com formulário e resumo, três seções, cinco tabelas de
domínio já existentes, um Repository, um ViewModel, uma RPC já existente e uma lista de ofertas
limitada apenas pelo catálogo e pelos limites técnicos do transporte/banco

## Constitution Check

### Gate pré-design

- **Simplicidade/YAGNI — PASS**: adiciona apenas um Repository porque há acesso real ao Supabase, e
  estende `BrazilianInputValidation`/formatação de máscara (de `005`) porque passam a ter dois
  consumidores reais. Sem framework de DI, cache ou dependência nova.
- **iOS nativo/MVVM — PASS**: SwiftUI, `@Observable`, `NavigationStack` e `SessionStore` existente
  permanecem a arquitetura oficial. Fluxo: View → ViewModel → Repository → Supabase.
- **Estado/experiência — PASS**: estados mutuamente exclusivos são `enum`s Swift; a View é
  stateless, rolável, acessível e responsiva; loading, vazio, falha, edição, envio, existente e
  sucesso são explícitos.
- **Dados/segurança — PASS**: `SessionStore` continua a única fonte de autenticação; `auth.uid()` é
  a autoridade no banco (já aplicado); DML direto revogado (já aplicado); RLS protege leituras (já
  aplicada); validações duplicadas no client e no banco; erros convertidos para tipos sanitizados.
- **Qualidade proporcional — PASS**: nenhum teste não solicitado é gerado; a implementação deve
  compilar, manter comportamento fora do escopo intacto e usar verificação manual de schema, fluxo,
  acessibilidade e privacidade.
- **Navegação — PASS**: rotas e intenção pós-cadastro centralizadas (`SignUpOrigin`,
  `PitGoRoute.providerRegistration`); nenhuma rota carrega IDs ou PII; componentes SwiftUI nativos
  reutilizados.

### Gate pós-design

**PASS**. Os artefatos de Phase 1 mantêm uma única fronteira de escrita (RPC já existente), não
adicionam arquitetura especulativa e detalham ownership, transação, RLS, estados, acessibilidade,
retry e limpeza de sessão — tudo herdado do contrato já validado pelo Android. Nenhuma exceção à
constitution foi necessária.

## Project Structure

### Documentation (this feature)

```text
specs/007-provider-registration/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── navigation-ui.md
│   └── supabase-provider-registration.md   # contrato do schema/RPC já existentes; nenhuma migration aqui
└── tasks.md                              # criado apenas por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/
├── Core/
│   ├── Common/Validation/BrazilianInputValidation.swift   # +CEP, +UFs; SignUp (005) passa a delegar
│   ├── UI/BrazilianTextFormatting.swift                    # +máscara de CEP; SignUp passa a reutilizar
│   ├── Navigation/
│   │   ├── UnauthenticatedRoute.swift    # .signUp(origin:) com SignUpOrigin
│   │   ├── PitGoRoute.swift               # + .providerRegistration
│   │   └── PitGoRootView.swift            # consome SignUpOrigin.provider uma única vez, em memória
├── Features/
│   ├── Profile/Views/ProfileView.swift                    # entrada "Área da empresa"
│   ├── SignUp/
│   │   ├── Model/SignUpModels.swift                       # + SignUpOrigin
│   │   └── Views/SignUpView.swift                         # usa formatação compartilhada
│   └── ProviderRegistration/
│       ├── Model/ProviderRegistrationModels.swift
│       ├── Data/ProviderRegistrationDTOs.swift
│       ├── Repository/ProviderRegistrationRepository.swift
│       ├── Validation/ProviderRegistrationValidation.swift
│       ├── ViewModel/ProviderRegistrationViewModel.swift
│       └── Views/ProviderRegistrationView.swift

# Nenhum diretório supabase/ novo — a migration continua vivendo apenas no repositório Android.
```

**Structure Decision**: manter a organização feature-first já adotada. A feature contém somente
Model, Data, Repository, Validation, ViewModel e View necessários. Validação e formatação de
telefone/CNPJ/CEP saem de `SignUp` para `Core` porque passam a ser reutilizadas de fato; nenhum
framework genérico de formulário é criado. O schema e a RPC não pertencem a este repositório.

## Implementation Design

### Entrada e continuidade do CTA público

1. `UnauthenticatedRoute.signUp(origin: SignUpOrigin)` substitui o caso simples de `005`.
2. `PitGoRootView` guarda a origem em memória (`@State`) durante a transição SignUp →
   `.authenticated` e, se `.provider`, monta `ProviderRegistrationView` antes da `TabView`.
3. A aba Perfil ganha uma linha "Área da empresa" que empurra `PitGoRoute.providerRegistration` na
   sua própria `NavigationStack`.

### Destino único (formulário + resumo)

1. `ProviderRegistrationViewModel` faz bootstrap consultando o agregado próprio; se completo, emite
   `.alreadyRegistered` diretamente.
2. Se ausente, emite `.editing` com `authEmail` como e-mail inicial e uma primeira oferta vazia.
3. Falha de bootstrap emite `.startupFailure` com retry.

### Catálogo e ofertas

1. `ProviderRegistrationRepository` pagina categorias e serviços por categoria sob demanda.
2. O ViewModel cacheia `LoadState` por `categoryID` enquanto a View existir.
3. Adicionar/remover ofertas opera sobre `[OfferDraft]` por `id` estável (`UUID`), sem reindexação.

### Submissão atômica

1. Validação local produz `ProviderRegistrationCommand` sem nenhum ID de owner.
2. Repository chama a RPC já existente, decodifica `CreateProviderRegistrationResult` e recarrega o
   agregado antes de emitir `.success`/`.alreadyRegistered`.
3. Uma guarda síncrona (`EditingSubmission != .submitting`) e um único `Task` impedem confirmações
   duplicadas.

### Sessão e privacidade

1. O ViewModel captura o `userID` esperado no bootstrap e observa `SessionStore`.
2. Perda/troca de sessão cancela `Task`s em andamento, zera o rascunho e emite `.sessionExpired`.
3. Nenhum `Error` bruto, payload, CNPJ completo ou ID interno é logado — apenas classes/status/
   nomes de constraint allowlisted.

## Complexity Tracking

Nenhuma violação constitucional ou complexidade excepcional. `ProviderRegistrationRepository` e a
extração de `BrazilianInputValidation`/formatação compartilhada têm consumidores reais (SignUp de
`005` e esta feature); a RPC já existente e revisada no Android é reutilizada sem alteração porque o
schema é compartilhado.

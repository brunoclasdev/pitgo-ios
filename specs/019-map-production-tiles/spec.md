# Feature Specification: Mapa iOS em paridade de produção com o Android

**Feature Branch**: `019-map-production-tiles`

**Created**: 2026-09-13

**Status**: Draft

**Input**: User description: "Implementação mapa no ios. Implementar maplibre, deixar funcional
assim como no Android. Pegar as chaves/url necessarias no arquivo local.gradle (local.properties)
do projeto Android. Deixar o mapa funcionando igual no Android."

**Contexto**: O app iOS já integra o MapLibre Native (mesma engine do Android) desde a feature
`010-osm-realtime-map` — a lacuna não é técnica/de engine, é de **configuração**: o iOS hoje aponta
para o estilo de demonstração pública do MapLibre (`demotiles.maplibre.org`), enquanto o Android já
usa um provedor de tiles gerenciado real em produção. Esta spec fecha essa lacuna, sem reabrir
decisões de arquitetura já tomadas em `009`/`010`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ver o mapa de produção, não o de demonstração (Priority: P1)

Como cliente ou prestador que abre uma tela com mapa (acompanhamento de atendimento, mapa de
serviço, PitTec), quero ver o mesmo estilo de mapa "de verdade" que já aparece no app Android, para
ter uma experiência visual completa e confiável, sem marca d'água ou indício de ambiente de teste.

**Why this priority**: É o valor central da feature — sem isso, o mapa do iOS continua parecendo
inacabado mesmo estando tecnicamente funcional.

**Independent Test**: Pode ser testado abrindo qualquer tela com mapa no iOS e no Android lado a
lado e comparando o estilo visual renderizado (ruas, cores, rótulos) e a ausência de qualquer aviso
de "estilo de avaliação".

**Acceptance Scenarios**:

1. **Given** o app iOS configurado com as credenciais de produção do provedor de tiles, **When** o
   usuário abre uma tela com mapa, **Then** o mapa carrega o estilo gerenciado real (o mesmo
   provedor já usado pelo Android), não o estilo de demonstração público.
2. **Given** o mapa carregado, **When** o usuário compara visualmente com a mesma tela no app
   Android, **Then** o estilo base (ruas, água, parques, rótulos) é equivalente entre as
   plataformas, pois ambas consomem o mesmo Style JSON gerenciado.

---

### User Story 2 - Atribuição correta do provedor de produção (Priority: P2)

Como usuário atento a créditos/licenciamento, quero ver a atribuição correta do provedor de mapa
real (não do estilo de demonstração) ao usar o app, para que a informação exibida seja verdadeira.

**Why this priority**: Consequência direta de trocar o provedor — a atribuição exibida hoje
(`MapLibre (estilo de avaliação)`) ficaria incorreta/desatualizada se não for trocada junto.

**Independent Test**: Pode ser testado abrindo o mapa e conferindo que o texto/link de atribuição
exibido corresponde ao provedor de produção configurado, igual ao que aparece no Android.

**Acceptance Scenarios**:

1. **Given** o provedor de produção configurado, **When** o usuário visualiza a atribuição no
   mapa, **Then** o nome do provedor e o link exibidos correspondem ao provedor real (o mesmo do
   Android), não ao estilo de demonstração.

---

### User Story 3 - Build falha de forma clara sem configuração de produção (Priority: P3)

Como desenvolvedor preparando um build de release, quero que o build falhe com uma mensagem clara
se a configuração de produção do mapa estiver ausente ou ainda apontando para um endpoint de
demonstração, para nunca publicar acidentalmente o app com o estilo de avaliação.

**Why this priority**: É uma rede de segurança — a mecânica de validação em build já existe
(criada em `004`/estendida em `010`); esta história garante que ela continue barrando
especificamente o cenário "esqueci de configurar o provedor real".

**Independent Test**: Pode ser testado limpando a configuração local do provedor de mapa e
confirmando que o build falha citando o campo ausente/inválido, sem gerar um app funcional com o
estilo de demonstração.

**Acceptance Scenarios**:

1. **Given** a configuração local do mapa ausente, **When** o build é executado, **Then** o build
   falha citando explicitamente qual valor de configuração do mapa está ausente.
2. **Given** a configuração local do mapa apontando para um host de demonstração conhecido,
   **When** o build é executado, **Then** o build falha em vez de aceitar o endpoint de
   demonstração como válido para produção.

---

### Edge Cases

- O que acontece se a chave do provedor de tiles for revogada ou expirar depois de publicado? O
  mapa deixa de carregar tiles novos; o comportamento de estado de erro/carregamento já definido em
  `010` (sem tiles = sem fabricar conteúdo) permanece válido — esta spec não adiciona um novo
  estado de erro para essa situação.
- O que acontece se, no futuro, o provedor de tiles for trocado por outro (não mais o mesmo do
  Android)? É suportado apenas trocando a configuração local (URL/nome/atribuição), sem alterar
  código — mecanismo já garantido por `010`.
- O que acontece se alguém tentar configurar um provedor de produção diferente do usado pelo
  Android (URLs distintas por plataforma)? É permitido pelo mecanismo técnico, mas está fora do
  objetivo desta spec, cujo requisito de produto é usar o **mesmo** provedor nas duas plataformas.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O app iOS DEVE, em builds de produção, carregar o mapa a partir de um provedor de
  tiles gerenciado real — o mesmo provedor já usado pelo app Android — em vez do estilo de
  demonstração público do MapLibre.
- **FR-002**: O app iOS DEVE exibir nome e atribuição do provedor de produção real configurado,
  substituindo os valores de demonstração atualmente exibidos.
- **FR-003**: O app iOS DEVE validar em tempo de build os quatro campos de configuração do mapa e
  falhar o build — citando o campo específico — quando algum estiver ausente, com placeholder, ou
  apontando para um host de demonstração/público conhecido, estendendo o mesmo Run Script Build
  Phase já usado para a configuração do Supabase (`004`), sem introduzir um segundo mecanismo.
- **FR-004**: As credenciais/URL do provedor de tiles de produção NÃO DEVEM ser adicionadas ao
  controle de versão — permanecem apenas na configuração local não rastreada, seguindo o mesmo
  mecanismo já usado para as credenciais do Supabase e para as demais chaves de mapa.
- **FR-005**: O estilo visual do mapa renderizado no iOS DEVE ser equivalente ao renderizado no
  Android para a mesma tela/contexto, por consumirem o mesmo Style JSON gerenciado.
- **FR-006**: Nenhuma tela, fluxo de navegação ou comportamento de mapa já existente (alternância
  Mapa/Lista, marcador em tempo real, cache de estilo) MUDA nesta spec — o escopo é exclusivamente
  a origem/configuração do estilo consumido.

### Key Entities

- **Configuração de estilo do mapa**: conjunto de valores (URL do estilo, nome do provedor,
  atribuição, link de atribuição) que descreve qual provedor de tiles o app consome — já modelado
  em `010`; esta spec troca os *valores* de demonstração pelos *valores* de produção, sem alterar a
  forma como são modelados ou validados.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% das telas com mapa no iOS carregam o estilo de produção configurado, com zero
  ocorrências do estilo de demonstração em builds de release.
- **SC-002**: A atribuição exibida no mapa do iOS corresponde ao provedor de produção real em 100%
  das verificações manuais, igual ao texto/link exibidos no Android.
- **SC-003**: Um build de release sem a configuração de produção do mapa falha antes de gerar um
  artefato instalável, em vez de publicar silenciosamente com o estilo de demonstração.
- **SC-004**: Em comparação lado a lado, uma pessoa sem conhecimento técnico não consegue apontar
  diferença perceptível no estilo base do mapa entre o app iOS e o app Android.

## Assumptions

- O provedor de tiles gerenciado já usado em produção pelo Android (configurado localmente no
  projeto Android, fora do controle de versão) é reaproveitado como o mesmo provedor de produção
  para o iOS — não é objetivo desta spec avaliar ou trocar de provedor, apenas espelhar a decisão
  já tomada para o Android.
- As credenciais de produção já existem e são válidas (o Android já as usa em produção); esta spec
  cobre apenas levá-las à configuração local do iOS, não emiti-las ou renová-las.
- O mecanismo de configuração via arquivo local não rastreado + validação em build, já existente no
  iOS desde `004`, é **estendido** (não substituído) para também cobrir os quatro campos do mapa —
  que ainda não tinham validação de build própria, apesar de já modelados desde `010` — sem
  introduzir um segundo mecanismo de configuração.
- "Igual ao Android" refere-se a paridade de **estilo visual do mapa** (mesmo Style JSON/provedor)
  e de **comportamento de configuração** (mesma validação/mesmo tratamento de ausência) — não
  implica paridade de código-fonte entre as duas bases (Kotlin/Gradle vs. Swift/xcconfig
  permanecem mecanismos distintos por plataforma, como em todas as specs anteriores).

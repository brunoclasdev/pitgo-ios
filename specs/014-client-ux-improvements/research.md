# Research: Melhoria de UX das telas do cliente (iOS)

Todas as decisões abaixo foram resolvidas por inspeção direta dos specs iOS já portados (`005`–`013`),
não do código (que ainda não foi implementado neste repositório). Uma descoberta corrige uma
suposição do `spec.md` (endereço do cliente); as demais distinguem trabalho genuinamente novo de
comportamento que os specs iOS anteriores já exigem corretamente por design.

## 0. Backend compartilhado — nenhuma migration nova

**Decision**: reutilizar integralmente `public.client_addresses`, `public.client_current_locations`
e as quatro RPCs (`get_my_client_address`, `upsert_my_client_address`, `publish_client_location`,
`get_appointment_client_location`) já criadas e aplicadas pela feature Android equivalente, no
mesmo projeto compartilhado. Nenhuma migration nova é criada por esta feature iOS; os contratos
exatos estão em `contracts/`.

**Rationale**: mesmo racional de `005`–`013` — o schema é compartilhado; a única migration nova
desta feature (Android) já existe e é agnóstica de plataforma cliente.

## 1. Endereço do cliente (Home/Perfil — FR-005, FR-007)

**Decision**: criar `ClientAddressRepository` chamando as duas RPCs já existentes
(`get_my_client_address`/`upsert_my_client_address`), reaproveitando `ViaCepAddressLookupRepository`
(`011`, promovido de `Features/ProviderRegistration` para `Core/Address` para uso compartilhado
entre client e provider) e a mesma validação de endereço BR (`BrazilianInputValidation`, `005`/`007`)
já usada no cadastro do prestador. Criar `ClientAddressView`/`ClientAddressViewModel` novos.

**Rationale**: idêntico ao racional do Android — o spec original supunha que "endereço do cliente"
já existia; nos specs iOS `001`–`013` ele nunca existiu (a Home só mostra o texto neutro
"Endereço não cadastrado" desde `006`, sem tabela nem rota por trás). É preciso criar essa
capacidade de forma proporcional, reaproveitando validação/busca de CEP/padrão de RPC já
estabelecidos.

**Alternatives considered**: idênticas ao Android — estender `public.addresses` (do prestador) com
um `client_id` opcional, rejeitado pelo mesmo motivo (acoplaria geocodificação pública/descoberta a
um dado privado de cliente); não persistir e só pedir um fix de GPS a cada solicitação, rejeitado
porque os critérios de aceite pedem "ver ou editar o endereço atual" — implica um dado persistente.

## 2. Posição do cliente nos mapas (FR-011, FR-012, FR-014)

**Decision**: reaproveitar `DeviceLocationRepository` (`009`, já usado por
`ClientMobileDispatchViewModel`/`ProviderMapViewModel` para leituras pontuais de GPS) para obter a
posição do cliente ao abrir/reabrir `AppointmentTrackingView`, sem nenhum tracking em background do
lado cliente — mesma decisão de clarificação do Android, igualmente válida para iOS (nenhum
`CLLocationManager` em background é necessário para o cliente, só `.requestLocation()` one-shot).

**Rationale**: idêntico ao racional do Android — reduz permissões/bateria/complexidade e reusa uma
capacidade já especificada em `013` para a busca de serviço.

## 3. Mapa do prestador durante o atendimento (US3, FR-013 a FR-015)

**Decision**: adicionar um `MapLibreMapHost` (`010`) dentro do estado "atendimento aceito" de
`ProviderIncomingRequestView` (`013`) — hoje 100% textual, sem mapa, no meu próprio port de `013`.
A câmera inicial enquadra os dois pontos (posição do provider via tracking já publicado, `009`;
posição do cliente via `get_appointment_client_location`, nova). Após o enquadramento inicial,
gestos manuais do provider (arrastar/zoom) não são revertidos automaticamente — generalização do
`followProvider`/`.stale` já especificado em `010`/`013` para dois pontos.

**Rationale**: idêntico ao racional do Android — `ProviderIncomingRequestView` (`013`) de fato não
tem mapa no meu próprio port dessa feature; reaproveitar o host de mapa e o padrão de câmera já
especificados evita duplicar lógica de estilo/erro/fallback.

**Alternatives considered**: idênticas ao Android — navegar para `AppointmentTrackingView`
compartilhada em vez de embutir o mapa na tela do provider, rejeitado pelo mesmo motivo (aquela tela
centraliza só o provider e não atende ao pedido de "mapa na tela do próprio guincho"); a decisão é
complementar ao botão "Abrir acompanhamento" já existente, não substituí-lo.

## 4. Câmera dupla em `AppointmentTrackingView` (FR-011, SC-006)

**Decision**: estender `AppointmentTrackingViewModel` (`009`/`010`) para considerar as duas
coordenadas (cliente e provider) ao montar o comando de câmera inicial, publicando ambas via
`publish_client_location`/consumo de `provider_current_locations` no mesmo canal privado
`appointment-location:<id>` já existente (nenhuma nova policy de `realtime.messages`).

**Rationale**: diferente do Android (que corrigia um `moveCameraTo` já implementado só com a
coordenada do provider), meu port de `010` nunca especificou explicitamente centralizar a posição
do cliente — é uma lacuna de especificação, não uma regressão de código. Esta feature preenche essa
lacuna corretamente desde já.

## 5. Botão voltar/retomada automática (US4, FR-017, FR-018)

**Decision**: especificar explicitamente que `DispatchResumeCoordinator` (`013`) só dispara a
navegação automática para a tela de um atendimento ativo quando a `revision` do
snapshot/appointment observado for **maior** que a última revisão para a qual essa navegação já foi
disparada nesta sessão do app (um `lastTriggeredRevision: Int64?` guardado no próprio coordinator).
Um "voltar" manual do usuário não altera nem reseta essa última revisão observada; ele apenas move o
`NavigationPath`. Ao iniciar/retomar a sessão, a navegação automática é avaliada uma vez a partir da
revisão restaurada.

**Rationale**: meu port de `013 contracts/mobile-dispatch-ui-navigation.md` já dizia "não rouba
navegação quando o usuário já está numa rota relacionada", mas não especificava o mecanismo exato
de comparação por revisão — a mesma ambiguidade que, no Android, causou o bug real de "botão voltar
travado" quando implementada ingenuamente (reagir a toda emissão de estado, não a uma mudança real).
Esta feature fecha essa lacuna de especificação para o iOS antes que o mesmo erro de implementação
possa ocorrer.

**Alternatives considered**: idênticas ao Android — remover completamente a navegação automática,
rejeitado (quebraria a retomada esperada ao reabrir o app); uma flag "usuário saiu manualmente" em
`UserDefaults`, rejeitado por adicionar estado extra quando a comparação por `revision` (já existente
no domínio) resolve o mesmo problema de forma mais simples.

## 6. Feedback de carregamento em botões (FR-002)

**Decision**: quando `pendingAction != nil` (cliente ou provider, `013 data-model.md`), mostrar um
`ProgressView` pequeno inline junto ao botão (ou substituir o texto por "Processando…"), nunca
apenas desabilitar silenciosamente, em `ClientMobileDispatchView` e `ProviderIncomingRequestView`
(ambas de `013`).

**Rationale**: meu port de `013` já modela `PendingDispatchAction` para bloquear toques duplicados,
mas não especificava explicitamente um indicador visual inline — esta feature fecha essa lacuna.

## 7. Formatação de distância (FR-003)

**Decision**: ao formatar `CandidateProposal.distanceMeters` (`013`), quando o valor for menor que
um limiar pequeno (ex.: 500m), exibir um texto amigável ("Muito próximo") em vez do número; acima do
limiar, manter o formato em km já especificado.

**Rationale**: meu port de `013` especifica `distanceMeters: Double` sem regra de apresentação para
valores muito pequenos — o mesmo "0,0 km" que pareceria dado ausente/quebrado no Android aconteceria
igualmente no iOS sem esta regra.

**Alternatives considered**: idêntica ao Android — ocultar a distância totalmente quando pequena,
rejeitado (perde informação útil e positiva para o cliente).

## 8. Itens do spec já corretamente especificados (sem mudança de spec necessária)

Confirmados por inspeção dos specs iOS `013` já portados; mantidos como comportamento esperado, não
como trabalho novo desta feature — apenas verificação de não regressão na implementação:

- **FR-001 (contagem regressiva)**: `013 data-model.md` já especifica countdown a partir de
  `serverNow`/`responseDeadline`, recalculado localmente a cada segundo, não autoritativo.
- **FR-004 (busca esgotada)**: `013` já especifica `.exhausted`/`.empty` com "Buscar novamente".
- **FR-006 (Home sem veículo)**: `006`/`009` já especificam o estado `.noVehicle` da Home com ação
  de cadastro.

## 9. Preferência de aparência (FR-008)

**Decision**: criar `AppearanceMode` (`enum { light, dark, system }`) persistido via `@AppStorage`
(equivalente iOS ao DataStore Android para uma preferência simples — mesma categoria de "preferência
local não sensível" já usada para `VehicleOnboardingStore`, `006`, embora esta use `UserDefaults`
puro). `pitgoApp.swift` lê essa preferência e aplica `.preferredColorScheme(_:)` na raiz da árvore de
Views: `nil` (associado a `.system`) segue o tema do sistema; `.light`/`.dark` fixam o tema.

**Rationale**: a constitution do projeto já exige suporte a Light/Dark/Sistema com persistência;
nenhum spec iOS anterior havia implementado a superfície de troca manual. `.preferredColorScheme`
é o modificador SwiftUI nativo para esse propósito, aplicado uma única vez na raiz.

**Alternatives considered**: `SwiftData` para a preferência, rejeitado por desproporcional a um
único enum; `UserDefaults` bruto em vez de `@AppStorage`, equivalente em efeito mas `@AppStorage` já
integra observação reativa ao SwiftUI sem código adicional.

## 10. Estrutura da aba Perfil (FR-007, FR-008)

**Decision**: introduzir um `ProfileViewModel` (`@Observable`) que agrega o estado hoje ausente
(endereço do cliente via §1, veículo padrão via `SessionStore`/Garagem já existente, `AppearanceMode`
via §9), mantendo `ProfileView` (`006`) como View de apresentação. O card de veículo padrão
reaproveita a navegação já existente para a aba Garagem/`VehicleFormView` (`006`); nenhuma View nova
de veículo é criada.

**Rationale**: `ProfileView` (`006`) hoje não tem ViewModel próprio (recebe o `AccountSnapshot`
pronto de `SessionStore`); as novas seções exigem estado e ações que não cabem só na View.

**Alternatives considered**: idêntica ao Android — expandir `SessionStore` diretamente, rejeitado
por misturar responsabilidade de sessão/autenticação com apresentação específica da aba Perfil.

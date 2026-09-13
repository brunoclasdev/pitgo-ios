# Research: Busca e despacho de prestadores móveis (iOS)

## 0. Backend compartilhado — nenhuma migration/Cron nova

**Decision**: reutilizar integralmente `services.dispatch_kind`, `provider_discovery_locations`,
`service_searches`, `private.dispatch_candidates`, os campos de despacho em `appointments`, todas
as RPCs (`publish_mobile_provider_location`/`stop_mobile_provider_location`,
`start_mobile_dispatch`, `get_my_active_mobile_dispatch`, `next_mobile_dispatch_candidate`,
`request_mobile_dispatch_candidate`, `get_my_pending_mobile_dispatch`,
`respond_to_mobile_dispatch`, `start_mobile_appointment`, `cancel_mobile_appointment`,
`complete_mobile_appointment`), o job `private.expire_due_mobile_dispatch_requests` agendado via
Supabase Cron e os tópicos Broadcast privados já criados e aplicados pela feature Android
equivalente, no mesmo projeto compartilhado. Nenhuma migration nem job novo é criado por esta
feature iOS; os contratos exatos estão em `contracts/`.

**Rationale**: mesmo racional de `005`–`012` — o PostgreSQL/Supabase é a autoridade única de
disponibilidade, ordenação, preço congelado, prazo de 60 segundos, exclusividade, cancelamento e
retomada, e essa autoridade é agnóstica de plataforma cliente. Um Cron job em Postgres não tem
"lado Android" nem "lado iOS" — ele expira propostas de qualquer client que as tenha criado.

## 1. Fluxo dedicado por semântica de catálogo (client iOS)

**Decision**: `ServiceCatalogRepository` (`009`) já expõe `dispatch_kind` no DTO de serviço
(campo compartilhado). O card de guincho na Home empurra `PitGoRoute.mobileDispatch(serviceID:)`
quando `dispatchKind == .mobileSequential`; serviços `BROWSE` continuam abrindo
`PitGoRoute.serviceMap(serviceID:)` (`009`/`010`). Nenhuma decisão por texto/nome do serviço — o
iOS usa exclusivamente `dispatchKind` e o UUID do catálogo, exatamente como o Android.

**Rationale**: idêntico ao racional do Android — `ServiceMapView` lista providers por endereço;
despacho móvel exige candidato único ordenado pelo servidor, resposta do provider, cotação
congelada e retomada persistente, um fluxo estruturalmente diferente.

## 2. Posição móvel de discovery separada do tracking privado (backend compartilhado, inalterado)

Nenhuma ação — `provider_discovery_locations` (posição pública-condicional de descoberta) e
`provider_current_locations` (posição privada do atendimento aceito, `009`) continuam duas tabelas
distintas no backend compartilhado. O client iOS publica na primeira enquanto `DISCOVERY` e na
segunda quando há um `appointment` `ACCEPTED`/`IN_PROGRESS` — a mesma RPC decide qual tabela recebe
o fix, não o client.

## 3. Um `ProviderLocationTracker` com dois alvos (substitui o Foreground Service Android)

**Decision**: generalizar o `ProviderLocationTracker` (`009`) para aceitar um alvo
`ProviderTrackingTarget` (`.discovery` ou `.appointment(appointmentID:)`). O toggle "Disponível" no
`ProviderDashboardView`, acionado com o app em primeiro plano após as permissões já concedidas,
inicia `.discovery` (chamando `publish_mobile_provider_location` a cada fix); o aceite de uma
solicitação troca o alvo para `.appointment(appointmentID:)` (chamando `publish_provider_location`,
já existente desde `009`); o encerramento do atendimento volta para `.discovery` quando a intenção
`providers.available` continuar ativa. Como já registrado em `009 §8`, o iOS não precisa de uma
notificação persistente construída manualmente — `allowsBackgroundLocationUpdates = true` já produz
o indicador de sistema de uso de localização em background, cobrindo os dois alvos sem distinção de
UI adicional. O tracker inicializa a sessão idempotentemente se o processo for recriado, e nunca
promete retomada automática após o sistema finalizar o app (mesma limitação do `START_STICKY`
"best-effort" do Android). Após alterar modo/disponibilidade, `ProviderDashboardViewModel` aplica o
snapshot confirmado em `SessionStore`, evitando que o tracker leia uma cópia antiga.

**Rationale**: o app iOS já possui `CLLocationManager` em background (`009`), alta precisão a
aproximadamente 10 segundos, permissões e estado de sessão. Generalizar para dois alvos evita dois
loops de sensor concorrentes — mesmo racional do Android.

**Alternatives considered**: idênticas ao Android — dois trackers separados duplicariam sensores/
estado; `BGTaskScheduler`/`BGAppRefreshTask` não atende cadência contínua de 10 segundos (desenhado
para tarefas oportunistas); Push Notifications (APNs) como transporte de localização, rejeitado pela
mesma razão do FCM no Android — não é necessário enquanto o provider elegível mantém o app com
localização em background ativa.

## 4. Intenção disponível separada da elegibilidade efetiva (backend compartilhado, inalterado)

Nenhuma ação — `providers.available` continua a intenção do provider; a elegibilidade efetiva
(`active`, `available`, modo `MOBILE`, posição recente, oferta exata válida, ausência de
appointment ativo) é derivada inteiramente no servidor, já aplicada. O client iOS só reflete o
snapshot recebido.

## 5. Estado persistente mínimo (backend compartilhado, inalterado)

Nenhuma ação — `service_searches`, `private.dispatch_candidates` e a extensão de `appointments` já
existem e são a fonte de verdade para retomada após encerramento do processo, não repetição de
candidato, distinção recusa/skip/expiração e preço congelado. O client iOS mantém apenas
`snapshot`s imutáveis e estado transitório de interação em memória — exatamente como o Android.

## 6. Seleção sequencial autoritativa e idempotência natural (backend compartilhado, inalterado)

Nenhuma ação — a seleção sob row lock, expansão 10→25→50km e constraints naturais
(`UNIQUE(search_id, provider_id)`, `UNIQUE(dispatch_candidate_id)`) já garantem ordem, não
repetição e reexecução segura de comandos, independentemente do client que os disparar.

## 7. Prazo de 60 segundos no banco (backend compartilhado, inalterado)

Nenhuma ação — `response_deadline` e o Supabase Cron de expiração já garantem que somente o relógio
do servidor decide aceite tardio, mesmo com o app fechado em qualquer plataforma. O client iOS
mostra um countdown a partir de `serverNow`/`deadline` (calculado uma vez ao receber o snapshot e
avançado localmente por um `Timer`/`Task.sleep` não autoritativo); ao chegar a zero, o client busca
o snapshot novamente em vez de inventar a transição localmente — mesma regra do Android.

## 8. RPCs seguras e snapshot único (backend compartilhado, inalterado — consumo Swift)

**Decision**: `MobileDispatchRepository` chama cada RPC via `client.rpc("...", params:
payload).execute().value`, decodificando sempre a mesma projeção JSON fechada
(`MobileDispatchSnapshot`, ver `data-model.md`) com `Codable`. Nenhuma interpretação de mensagem
livre; outcomes são um `enum` fechado.

**Rationale**: idêntico ao racional do Android — uma projeção fechada evita múltiplas leituras
inconsistentes e reduz a superfície de dados exposta ao client.

## 9. Broadcast privado como invalidação

**Decision**: assinar os mesmos tópicos privados `mobile-dispatch:<searchID>` (cliente) e
`provider-dispatch:<providerID>` (provider) via o produto `Realtime` do `supabase-swift`
(já habilitado desde `009`), seguindo exatamente a sequência já estabelecida em
`009`/`010 contracts/realtime-marker.md`: `setAuth()` → assinar → aguardar confirmação → buscar
snapshot via RPC → mesclar somente quando `revision` for mais nova → remover o canal numa `Task`
desacoplada ao sair/logout.

**Rationale**: idêntico ao racional do Android — tratar o evento como invalidação (não como estado
de negócio completo) resolve perda, reconexão e ordem sem duplicar lógica de domínio no payload; a
autorização por RLS em `realtime.messages` já protege o canal independentemente da plataforma
assinante.

## 10. Telas, retomada e MapLibre

**Decision**: criar `ClientMobileDispatchView` (estado/proposta/ações textuais + `MapLibreMapHost`
com um único `MLNPointFeature` de carro, reaproveitando `010`) e
`ProviderIncomingRequestView` (destino dedicado do provider, aberto por uma linha de destaque no
Dashboard — iOS não tem o conceito de "abrir por notificação" da mesma forma que o Android
declarativo de Intent, mas uma futura notificação local/push poderia abrir a mesma rota; esta
feature não introduz notificações). Um `DispatchResumeCoordinator` (`@Observable`, análogo ao
`DispatchResumeViewModel` do Android) consulta `get_my_active_mobile_dispatch`/
`get_my_pending_mobile_dispatch` logo após `SessionStore` emitir `.authenticatedClient`/
`.authenticatedProviderReady`, e antes de estabilizar a Home/Dashboard, decidindo a rota inicial.
`MapMarkerKind.mobileProvider` usa um SF Symbol/imagem de carro distinto de `.address` (`010`);
seleção altera forma/contorno além de cor.

**Rationale**: idêntico ao racional do Android — `MapLibreMapHost`/`Coordinator` (`010`) já
atualizam GeoJSON sem recriar mapa/estilo; a proposta textual garante acessibilidade e funciona
quando estilo/tiles falham; a retomada centralizada elimina rota errada após reinício do app e
limpa dados na troca de identidade.

## 11. Dependências e manutenção

**Decision**: nenhuma dependência nova. Reutilizar `supabase-swift` (`Auth`/`PostgREST`/
`Functions`/`Realtime`, já habilitados), MapLibre Native iOS (`010`) e `CoreLocation` (`009`).
Manter as mesmas permissões (`NSLocationWhenInUseUsageDescription`/
`NSLocationAlwaysAndWhenInUseUsageDescription`) sem solicitar nada além do já pedido em `009`.

**Rationale**: idêntico ao racional do Android — toda capacidade técnica necessária já existe e
está integrada ao ciclo de vida do app; menos dependências reduzem conflitos e manutenção.

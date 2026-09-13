# Research: PitTec sob demanda (iOS)

## 0. Backend compartilhado — nenhuma migration/Edge Function nova

**Decision**: reutilizar integralmente `services.dispatch_kind = PITTEC_AUTO_SEQUENTIAL`,
`providers.location_mode = PITTEC` (+ `pending_location_mode`), `provider_discovery_locations`
anonimizado por `list_nearby_pittecs`, `appointments.arrived_at`/`offer_expires_at`,
`appointment_route_snapshots`, todas as RPCs (`list_nearby_pittecs`, `start_pittec_dispatch`,
`advance_pittec_dispatch` privada, `respond_to_mobile_dispatch` estendida, `expire_pittec_offer`,
`get_my_active_pittec_dispatch`, `cancel_pittec_search`, `arrive_pittec_appointment`,
`complete_mobile_appointment`/`cancel_mobile_appointment` estendidas) e a Edge Function
`pittec-route` (proxy autenticado de um serviço OSRM compatível) já criados e aplicados pela feature
Android equivalente, no mesmo projeto compartilhado. Nenhuma migration nem Edge Function nova é
criada por esta feature iOS; os contratos exatos estão em `contracts/`.

**Rationale**: mesmo racional de `009`–`014` — todo o modelo transacional, a anonimização por grade
de ~500m, o timeout de 60s e o proxy de rotas são responsabilidade de backend, agnóstica de
plataforma cliente.

## 1. Fronteira do produto (client iOS)

Nenhuma ação — `dispatchKind = .pittecAutoSequential` (extensão do `enum` já existente desde `009`)
e `ProviderLocationMode = .pittec` (extensão do `enum` desde `009`) já chegam decodificados do
backend. O PitTec continua uma conta `PROVIDER` comum; nenhuma mudança de `AppSessionState` (`006`/
`009`) é necessária.

## 2. Despacho automático e concorrência (backend compartilhado, inalterado)

Nenhuma ação — a seleção sequencial sem repetição, o lock transacional e a chave idempotente
(`p_request_id`, gerado uma vez no client como `UUID()`, reutilizado em retry) já garantem que
nenhum candidato seja repetido e que apenas um atendimento seja confirmado, independentemente da
plataforma cliente.

## 3. Estados do atendimento (backend compartilhado, inalterado)

Nenhuma ação — os estados `SEARCHING`/`AWAITING_PROVIDER`/`ACCEPTED`/`IN_PROGRESS`/terminais e a
semântica "`ACCEPTED` = a caminho, `IN_PROGRESS` = chegou" já são autoritativos no backend. O client
iOS apenas mapeia o snapshot para `enum`s Swift (`data-model.md`).

## 4. Privacidade da localização (backend compartilhado, inalterado)

Nenhuma ação — `list_nearby_pittecs` já retorna marcadores anonimizados por grade (~500m) com ID
opaco, sem nome/`providerID`/coordenada exata; a coordenada exata do cliente só vira acessível ao
provider designado após o aceite (`client_current_locations`). O client iOS só precisa consumir a
projeção pública já fechada.

## 5. Disponibilidade e mudança de modalidade (backend compartilhado, inalterado)

Nenhuma ação — `pending_location_mode` já resolve a troca de modalidade durante atendimento ativo,
aplicada atomicamente no backend na transição terminal.

## 6. Alertas em background e tela bloqueada (client iOS)

**Decision**: generalizar `ProviderLocationTracker` (`009`/`013`) para também operar quando o modo
efetivo do provider for `.pittec` disponível, além de `.mobile`. Nesse modo, o tracker mantém
`allowsBackgroundLocationUpdates = true` (mesma base de `013`) e, adicionalmente, assina o tópico
privado `provider-dispatch:<providerID>` via `Realtime`. Cada nova oferta detectada — seja pelo
evento de Realtime chegando enquanto o processo está ativo em background (a atualização periódica
de localização mantém uma janela de execução), seja por um polling de 5s como fallback quando a
conexão Realtime cair (mesmo racional do Android) — dispara uma notificação local
(`UNUserNotificationCenter`/`UNMutableNotificationContent`, com `sound: .default` e categoria
dedicada), deduplicada por `(appointmentID, revision)`. Habilitar disponibilidade PitTec exige
autorização de notificação (`UNAuthorizationOptions.alert/.sound`) concedida — equivalente iOS ao
`POST_NOTIFICATIONS`/canal habilitado do Android. **Não é usado APNs/push remoto** nesta entrega —
mesma decisão consciente do Android de não usar FCM: o app precisa estar com localização em
background ativa (processo vivo) para detectar a oferta; reinício do dispositivo e finalização
forçada do app pelo sistema não têm garantia de entrega nesta versão.

**Rationale**: idêntico ao racional do Android — o app já mantém uma janela de execução em
background via atualização de localização durante disponibilidade `MOBILE`/`PITTEC` (`009`/`013`);
estender esse mecanismo entrega alerta em primeiro plano, segundo plano e tela bloqueada sem
introduzir push remoto, token de dispositivo ou infraestrutura de notificação server-side.

**Alternatives considered**: idênticas ao Android — APNs (push remoto) como transporte, adiado pela
mesma razão (ampliaria backend, dependência de certificado/token e política de dados, e só seria
necessário para garantir entrega com processo morto/dispositivo reiniciado, fora do escopo atual);
notificação de baixa prioridade (silenciosa), rejeitada por não produzir alerta visível e sonoro
adequado.

## 7. Percurso e distância (client iOS, backend compartilhado)

**Decision**: `RoutingRepository` chama a Edge Function `pittec-route` (já existente) via
`client.functions.invoke("pittec-route", options: .init(body: payload))`, decodificando a resposta
GeoJSON `LineString` com `Codable`. Renderização usa `MLNShapeSource`/`MLNLineStyleLayer` (MapLibre
Native iOS, `010`) para a linha sólida (rota real) ou tracejada (estimativa direta), atualizando a
`source` sem recriar o mapa. Quando a Edge Function falhar/expirar, o client calcula distância
haversine localmente a partir dos dois pontos exatos já disponíveis (participante) e desenha uma
linha direta tracejada, identificada textualmente como estimativa.

**Rationale**: idêntico ao racional do Android — o proxy já protege credenciais/coordenadas e
garante a mesma rota aos dois participantes; o fallback local mantém o fluxo útil sem depender do
roteador. `MLNLineStyleLayer` é o equivalente iOS direto ao `LineLayer` do MapLibre Android, mesma
biblioteca cross-platform.

## 8. Organização iOS

**Decision**: criar `Features/PitTec` para a tela e a máquina de estados do cliente (descoberta,
solicitação, mapa). Estender os modelos/Repositories de `Features/MobileDispatch` (`013`) para o
transporte compartilhado; adaptar `AppointmentTracking` (`009`/`010`/`014`), `ProviderTracking`
(`009`/`013`), `ProviderRegistration` (`007`/`009`) e `ProviderDashboard` (`009`/`013`). Criar
`Core/Routing` apenas para o contrato/acesso ao snapshot de rota via a Edge Function.

**Rationale**: idêntico ao racional do Android — acompanha a estrutura feature-first já
estabelecida, evita duplicar infraestrutura Supabase/Realtime e mantém regras específicas fora de
componentes genéricos.

## 9. Realtime, recuperação e segurança (backend compartilhado, consumo Swift)

**Decision**: reutilizar exatamente o padrão de canais privados, payloads de invalidação mínimos
(sem coordenadas) e RPC de snapshot como fonte de verdade, já estabelecido em `009`/`010`/`013`.
Tópicos lógicos `provider-dispatch:<providerID>`, `client-dispatch:<clientID>`,
`appointment:<appointmentID>` (nomeação concreta compatível com os helpers de migration já
existentes). Reconexão sempre rebusca o snapshot autoritativo; um evento com `revision` mais antiga
que a última aplicada é ignorado.

**Rationale**: idêntico ao racional do Android — esse padrão já existe nos specs iOS anteriores e
tolera eventos perdidos ou fora de ordem; RLS mais autorização dentro do RPC fornece defesa em
profundidade.

## 10. Fora do escopo consciente (idêntico ao Android)

Push remoto (APNs) e garantia de entrega após reinício/finalização forçada do app; navegação
curva-a-curva ou instruções por voz; histórico de rotas/localização; chat, preço exibido, cobrança,
avaliação ou descrição de especialidade; testes automatizados novos.

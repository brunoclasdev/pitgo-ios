# Contract: UI e navegação do despacho móvel (iOS)

## Entrada por catálogo

- `HomeService.dispatchKind == .mobileSequential` → `PitGoRoute.mobileDispatch(serviceID:)` (nova
  busca, cria/restaura).
- `.browse` → `PitGoRoute.serviceMap(serviceID:)` (`009`/`010`), preservando providers fixos.
- A rota de nova busca é substituída por `PitGoRoute.mobileDispatch(searchID:)` assim que a busca
  existe.
- Incoming request do provider abre `PitGoRoute.providerRequest(appointmentID:)`.
- Argumentos são somente `UUID`s opacos; preço, owner, coordenadas e status vêm do snapshot.

## Estados do cliente

| Estado | Conteúdo/Ação |
|---|---|
| `.restoring` | progresso textual; sem Home prematura |
| `.locationRequired` | propósito, solicitar novamente, abrir Ajustes do sistema |
| `SEARCHING` | "Buscando prestador", raio confirmado e cancelamento explícito |
| `OPTION_FOUND` | proposta completa, carro no mapa, "Solicitar este guincho" e "Próximo" |
| `AWAITING_PROVIDER` | preço garantido, countdown visual e cancelamento explícito |
| `ACCEPTED` | confirmação e acesso ao tracking autorizado (`009`/`010`) |
| `IN_PROGRESS` | status, tracking e concluir/cancelar conforme ações permitidas |
| `EXHAUSTED` | vazio após 50km, "Buscar novamente" |
| `CANCELLED`/`COMPLETED` | confirmação terminal e retorno seguro |
| Offline/Failure | último snapshot preservado e retry idempotente |
| `.sessionExpired` | dados limpos antes do refresh/login |

Recusa, expiração e cancelamento pelo provider aparecem como `notice` persistido antes de voltar a
`SEARCHING`/`OPTION_FOUND`. "Próximo" representa decisão do cliente e não usa o mesmo texto/status.

## Proposta

O card textual é a fonte acessível e contém: nome público da empresa; preço exibido (após request,
rótulo "Preço garantido nesta solicitação"); localidade pública aproximada (cidade/UF), enquanto
distância e marcador usam exclusivamente a posição móvel corrente; distância estimada; status e
ações permitidas pelo snapshot.

Não mostra CNPJ, telefone, endereço completo, histórico ou dados de outras solicitações. Enquanto
uma mutation está pendente (`PendingDispatchAction`), ambas as ações conflitantes ficam
desabilitadas; falha mantém a proposta e permite repetir a mesma intenção.

## Provider

`ProviderDashboardView` mostra estados `Indisponível`, `Iniciando`, `Publicando`, `Degradado` e
`Reservado`. Incoming request tem destaque acima do conteúdo comum e um destino dedicado
(`ProviderIncomingRequestView`) com preço, serviço, localidade segura, distância, deadline e ações
Aceitar/Recusar. Recusa pré-aceite não exige motivo; cancelamento pós-aceite exige.

Aceitar/recusar não dispara duas vezes (guarda síncrona); o resultado confirmado determina
navegação para tracking ou Dashboard.

## Cancelamento

Após aceite, cliente e provider abrem um `.sheet` rolável com motivo multiline (`TextEditor`)
obrigatório, erro inline e confirmação. Com Dynamic Type grande/teclado aberto, o conteúdo
permanece alcançável (`.scrollDismissesKeyboard`). Voltar/gesto não contorna o motivo. Cancelamento
do provider retoma a busca; do cliente encerra o fluxo.

## MapLibre e acessibilidade

- `MapMarkerKind.mobileProvider` usa um SF Symbol/imagem de carro; seleção altera forma/contorno
  além de cor.
- Provider FIXED mantém `.address` (`010`).
- A tela de proposta mostra um único carro e, opcionalmente, referência do cliente; sem clustering.
- O `Coordinator` atualiza `source.shape = ...`, sem recriar `MLNMapView`/estilo nem recentralizar
  após um gesto salvo (`010`).
- O mapa é uma região semântica; proposta/status/ações fora dele contêm toda informação essencial.
- Controles têm alvo `>=44×44pt`; ação primária `>=56pt`; estados relevantes usam
  `.accessibilityAddTraits(.updatesFrequently)`, mas countdown e updates de 10s não são anunciados
  continuamente.
- Largura compacta/Dynamic Type grande usa uma única coluna (`List`) e mapa colapsável; largura
  expandida (iPad/landscape) pode usar mapa + painel lateral. Sem `TabView` no fluxo ativo.

## Retomada e back stack

Após autenticação, `DispatchResumeCoordinator` consulta o contexto ativo antes de estabilizar a
Home ou o Dashboard:

```text
.none -> raiz comum da conta
.clientSearch(searchID) -> mobileDispatch(searchID:)
.clientTracking(appointmentID) -> appointmentTracking(appointmentID:)
.providerIncoming(appointmentID) -> providerRequest(appointmentID:)
.providerTracking(appointmentID) -> providerAppointmentTracking(appointmentID:)
```

Não rouba navegação quando o usuário já está numa rota relacionada. A mesma conta reautenticada
restaura o snapshot; troca/logout cancela `Task`s/canais, apaga proposta/coordenadas e nunca
reaproveita um ID anterior. Voltar não cancela silenciosamente uma busca: informa que ela continua
recuperável ou oferece o cancelamento explícito permitido.

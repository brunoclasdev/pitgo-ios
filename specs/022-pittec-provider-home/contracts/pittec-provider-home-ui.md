# Contract: Home do PitTec (iOS, UI)

Nenhuma RPC, Edge Function ou schema novo — este é um contrato de comportamento de UI, análogo ao
de `specs/020-pittec-client-map-centering/contracts/pittec-client-map-centering-ui.md`. Todas as
chamadas mencionadas já existem e são reaproveitadas sem alteração de assinatura.

## Roteamento (quem vê o quê)

| `provider.locationMode` | Tela raiz do provider |
|---|---|
| `FIXED` | `ProviderDashboardView` (atual, inalterada) |
| `MOBILE` | `ProviderDashboardView` (atual, inalterada) |
| `PITTEC` | `PitTecHomeView` (nova, 4 abas) |

## Aba "Mapa"

| Situação | `PitGoMapView` | Card de disponibilidade |
|---|---|---|
| Fix de localização disponível | `centerCoordinate` = último fix; `showsUserLocation: true` | "Disponível"/"Indisponível" conforme `provider.available`, tocável para alternar |
| Permissão negada / serviço desligado | mensagem substitui o mapa (mesmo texto de `TrackingDegradedReason.permissionDenied`/`.locationServicesDisabled` já usado em `ProviderDashboardView.discoveryDegradedMessage`) | continua visível e tocável — disponibilidade não depende de localização |
| Fix momentaneamente ausente (sinal fraco) mas já houve um fix antes | mantém o último `centerCoordinate` conhecido | inalterado |
| Alternância de disponibilidade falha (offline/erro de servidor) | mapa inalterado | card reverte visualmente ao estado anterior e mostra a mesma mensagem de erro já usada em `ProviderDashboardView.message(for:)` |

## Barra inferior (4 abas, ordem fixa)

| Aba | Símbolo sugerido (SF Symbols) | Conteúdo |
|---|---|---|
| Mapa | `map.fill` | Ver tabela acima |
| Dados da corrida | `car.fill` | Resumo do atendimento PitTec ativo (ver `data-model.md`) ou mensagem vazia |
| Valores | `dollarsign.circle.fill` | Preço configurado do PitTec, somente leitura |
| Perfil | `person.crop.circle.fill` | Nome/e-mail + ação de sair (reaproveita `signOutButton`/`confirmationDialog` já existentes em `ProviderDashboardView`) |

A aba "Mapa" é a seleção inicial ao abrir a tela.

## Notificação de nova solicitação (inalterado)

Uma nova solicitação `PENDING` continua sendo detectada por `PitTecRepository.
subscribeToProvider`/`getActiveDispatch` (já ligado em `ProviderDashboardViewModel.onAppear`) e
continua abrindo `PitTecIncomingRequestView` via push na `NavigationStack`, por cima de qualquer
aba em que o PitTec esteja no momento — a `TabView` de 4 abas não substitui nem atrasa esse fluxo.

## Estados explicitamente fora deste contrato (inalterados)

- Fluxo de aceitar/recusar uma solicitação nova (`PitTecIncomingRequestView`): inalterado, apenas
  referenciado pela aba "Dados da corrida" quando já em andamento.
- `ProviderDashboardView` para Fixo/Móvel: inalterada, nenhuma linha de código compartilhada além
  do `Core/UI/PitGoBottomTabs` generalizado.
- Fluxo de pagamento/checkout do cliente: fora de escopo, não referenciado por esta tela.

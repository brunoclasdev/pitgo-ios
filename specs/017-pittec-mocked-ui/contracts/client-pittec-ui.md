# UI Contract: Jornada mockada do cliente PitTec (iOS)

## Boundary

Este contrato começa quando o cliente abre o card PitTec existente (`015`). Autenticação,
carregamento do catálogo e o card da Home não mudam. Nenhuma ação desta View chama Supabase,
Realtime, tracking, rota ou pagamento.

## Initial screen

- O mapa, barra superior, localização do cliente, marcadores aproximados e apresentação visual
  atuais (`015`) são preservados.
- Os marcadores PitTec são fixtures locais posicionadas em relação à âncora do mapa; não vêm de
  `list_nearby_pittecs`.
- O CTA é "Buscar PitTec". Antes dele, nenhum card de preço ou estado de busca aparece.
- Recusa/indisponibilidade da localização do cliente seguem os estados acionáveis já existentes;
  não impedem que o restante do app seja usado.

## Estimate interaction

Evento: `onSearchRequested()`.

1. Aceito somente em `.discovery`; toques adicionais são ignorados.
2. A UI pode mostrar `.estimating` brevemente e então `.awaitingClientConfirmation(estimate)`.
3. O card exibe, em texto: perímetro encontrado; parcela fixa de R$ 50,00; adicional de R$ 10,00 por
   faixa e quantidade de faixas; total com duas casas decimais; ações "Confirmar" e "Voltar".
4. `onEstimateDismissed()` volta a `.discovery` sem criar busca.
5. `onEstimateConfirmed()` é aceito uma vez, desabilita a ação no mesmo frame e cria uma única
   `MockSearch`.

Tabela de referência:

| Perímetro | Faixas | Fixo | Adicional | Total |
|---|---:|---:|---:|---:|
| 5 km | 1 | R$ 50,00 | R$ 10,00 | R$ 60,00 |
| 10 km | 2 | R$ 50,00 | R$ 20,00 | R$ 70,00 |
| 15 km | 3 | R$ 50,00 | R$ 30,00 | R$ 80,00 |

## Search interaction

- A UI sempre apresenta um destes feedbacks textuais: Procurando, Aguardando resposta,
  Recusado — continuando, Encontrado ou Nenhum PitTec encontrado.
- O candidato atual responde após o delay determinístico da fixture (`Task.sleep`).
- Em recusa, seu ID entra em `rejectedCandidateIDs` e não pode reaparecer.
- Havendo outro candidato na mesma faixa, ele é consultado antes da expansão.
- Sem candidato restante, o perímetro aumenta exatamente 5km, preço/total são recalculados e uma
  Live Region anuncia a mudança; a mesma busca continua sem nova confirmação.
- Em aceite, o total fica congelado na faixa aceita e o estágio muda uma única vez para tracking.
- Em esgotamento, o loop para e a tela mostra "Tentar novamente" e "Voltar". Retry inicia a próxima
  fixture determinística, sem reaproveitar IDs tentados.

## Accepted appointment

- O acompanhamento permanece na própria experiência mockada; não cria ID real nem empurra
  `PitGoRoute.appointmentTracking(appointmentID:)`.
- Ao entrar, o mapa enquadra cliente e PitTec, e o card textual informa participantes, distância
  estimada, total e estado.
- A ação "Já nos encontramos" aparece em deslocamento. Depois da ação local, ela fica desabilitada e
  a UI informa que aguarda o PitTec; 3s depois, a resposta simulada muda para Em andamento.
- A ação "Finalizar serviço" aparece em andamento. Depois da ação local, a UI informa que aguarda o
  PitTec; 3s depois, muda para Concluído.
- Concluído interrompe posição/stale e oferece "Voltar para a Home".

## Lifecycle and navigation

- `.onAppear`/`.onDisappear` sinalizam visibilidade ao ViewModel; movimento simulado pausa quando a
  experiência não está visível e retoma com snapshot imediato ao voltar.
- O ViewModel pertence a um owner acima das rotas (`pitgoApp.swift`/`PitGoRootView`) e preserva o
  estágio se o cliente navegar para fora e reabrir o card na mesma sessão/processo.
- Nova sessão autenticada recebe uma nova instância/estado. Encerrar o processo pode reiniciar a
  fixture.
- Voltar antes de confirmar não inicia busca; voltar durante busca/atendimento apenas navega, sem
  transformar isso em cancelamento real.

## Accessibility contract

- Estado, distância, preço, participantes e ações existem em texto, mesmo quando o mapa falha.
- Mudanças de busca usam `.accessibilityAddTraits(.updatesFrequently)` (Live Region educada);
  encontrado/sem resultado podem usar um anúncio mais enfático sem repetir em recriação de View.
- Botões têm `.accessibilityLabel` explícita e alvo mínimo de 44×44pt; preço não é transmitido só
  por alinhamento visual.
- Cards e conteúdo aceitam Dynamic Type e rolagem; o mapa nunca é o único portador de informação.

## Forbidden side effects

Os seguintes componentes não podem ser chamados por eventos deste contrato:

- `PitTecRepository` e `DispatchResumeCoordinator` (`013`/`015`);
- `AppointmentTrackingRepository` e `RoutingRepository` (`009`/`010`/`014`/`015`);
- `MobileDispatchRepository` (`013`);
- qualquer notificador local, Edge Function, cobrança ou escrita de disponibilidade/localização.

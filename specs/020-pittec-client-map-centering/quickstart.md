# Quickstart: validar o mapa do PitTec centralizado no cliente

Validação manual em simulador/dispositivo — sem testes automatizados (não solicitados para esta
feature, regra V da constituição). Referências: [data-model.md](./data-model.md),
[contracts/pittec-client-map-centering-ui.md](./contracts/pittec-client-map-centering-ui.md).

## Pré-requisitos

- App rodando em simulador iOS 17+ (ou dispositivo) com uma localização simulada definida
  (Simulator: Features → Location → Custom Location, ou um local pré-definido como "Apple").
- Usuário cliente autenticado com o serviço PitTec disponível no catálogo (`015`).
- Acesso para simular ao menos dois cenários de dados de PitTec elegíveis: **nenhum** e **um ou
  mais** próximos (via dados de teste no Supabase compartilhado ou o mesmo mecanismo já usado para
  validar `015`).

## Cenário 1 — Sem nenhum PitTec disponível

1. Garanta que não há PitTec elegível cadastrado/ativo na região da localização simulada.
2. Abra o app, conceda permissão de localização quando solicitado.
3. Toque no card "PitTec" na Home.
4. **Esperado**: a tela mostra `PitGoMapView` centralizado na localização simulada do cliente (ponto
   azul de posição do usuário visível), sem nenhum marcador de PitTec e **sem nenhuma indicação
   textual de disponibilidade** *(revisado — a descoberta não informa proativamente se há ou não
   PitTec; ver `spec.md` FR-006)*. O botão "Chamar PitTec" continua visível abaixo.

## Cenário 2 — Com PitTec disponível

1. Garanta ao menos um PitTec elegível próximo da localização simulada.
2. Repita os passos 2–3 do Cenário 1.
3. **Esperado**: o mapa aparece centralizado na localização do cliente, com o(s) marcador(es)
   aproximado(s) de PitTec visíveis, sem nenhum texto de contagem/disponibilidade sobreposto.

## Cenário 3 — Busca esgotada (sem PitTec disponível após chamar)

1. A partir do Cenário 1, toque em "Chamar PitTec" e conclua o checkout mockado/real (`018`).
2. Aguarde a busca percorrer toda a área de cobertura sem nenhum PitTec aceitar (ou simule o estado
   `status == .exhausted` conforme o mecanismo de teste já usado em `015`).
3. **Esperado**: em vez da tela terminal só-texto anterior, o mapa aparece centralizado na
   localização do cliente, com a mensagem "Nenhum PitTec disponível nesta região no momento." e os
   botões "Buscar novamente"/"Voltar" sobrepostos.

## Regressão — estados não afetados

- Localização negada/desativada: `locationRequiredState` continua bloqueando o mapa como antes.
- Um atendimento aceito (`.accepted`/`.inProgress`): mapa continua mostrando cliente + PitTec
  exatos com linha estimada, via `routeContext` (inalterado).
- Busca concluída (`.completed`) ou cancelada (`.cancelled`): telas terminais continuam só-texto,
  sem mapa (fora de escopo desta feature).
- Mapa genérico de outros serviços (`ServiceMapView`, fora do card PitTec): comportamento
  inalterado, incluindo o gap equivalente hoje existente lá (fora de escopo, ver
  [research.md](./research.md) §4).

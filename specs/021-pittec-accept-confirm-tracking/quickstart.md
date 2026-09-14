# Quickstart: validar o aceite do PitTec com confirmação de valor e mapa conjunto

Validação manual em dois aparelhos/simuladores (cliente e PitTec) — sem testes automatizados (não
solicitados, regra V da constituição). Referências: [data-model.md](./data-model.md),
[contracts/confirm-pittec-value-rpc.md](./contracts/confirm-pittec-value-rpc.md),
[contracts/pittec-confirmation-tracking-ui.md](./contracts/pittec-confirmation-tracking-ui.md).

## Pré-requisitos

- **A RPC `confirm_pittec_appointment` e a coluna `confirmed_at` já implantadas no backend
  compartilhado** (dependência externa desta feature — ver contrato correspondente). Sem isso, o
  passo 3 do Cenário 1 abaixo não avança.
- Dois aparelhos/simuladores: um logado como cliente, outro como um PitTec disponível (`Disponível`
  ligado, modalidade PitTec — ver notas da sessão anterior sobre pré-requisitos de disponibilidade).
- Pagamento aprovado disponível para o cliente iniciar a chamada (checkout `018`, inalterado).

## Cenário 1 — Confirmar o valor e ver o mapa conjunto

1. No cliente, toque no card "PitTec" e depois em "Chamar PitTec"; conclua o checkout já existente.
2. No PitTec, aceite a solicitação recebida.
3. **Esperado (PitTec)**: a tela mostra "Aguardando confirmação do cliente", sem mapa de
   acompanhamento ainda.
4. **Esperado (cliente)**: um card aparece mostrando o valor do atendimento (já pago) com os botões
   "Confirmar" e "Recusar", antes de qualquer mapa de acompanhamento.
5. No cliente, toque em "Confirmar".
6. **Esperado (cliente)**: a tela passa a mostrar o mapa de acompanhamento, com sua própria posição
   e a do PitTec visíveis juntas, sem exigir zoom/pan manual.
7. **Esperado (PitTec)**, em até alguns segundos (mesmo intervalo de Realtime já usado hoje): sua
   tela sai de "Aguardando confirmação" e passa a mostrar o mapa de acompanhamento com as duas
   posições juntas.

## Cenário 2 — Recusar o valor

1. Repita os passos 1–4 do Cenário 1.
2. No cliente, toque em "Recusar".
3. **Esperado (cliente)**: o atendimento é encerrado, com uma mensagem clara do motivo — nenhum mapa
   de acompanhamento chega a aparecer.
4. **Esperado (PitTec)**, em até alguns segundos: sua tela de espera também é encerrada/informada do
   cancelamento, sem nunca ter mostrado o mapa de acompanhamento.

## Cenário 3 — Acompanhar a posição do PitTec se aproximando

1. A partir do Cenário 1 já confirmado (passo 6/7), mova a localização simulada do PitTec (Simulator
   → Features → Location, ou um trajeto com `xcrun simctl location start`).
2. **Esperado**: em até o mesmo intervalo já usado hoje pelo sistema (~10s), o marcador do PitTec no
   mapa do cliente se desloca para refletir a nova posição, com o enquadramento conjunto se ajustando
   para manter as duas posições visíveis, sem exigir nenhuma ação do cliente.

## Regressão — estados não afetados

- Busca em andamento (`searching`), sem PitTec disponível, busca esgotada: comportamento de `020`
  inalterado.
- Atendimento concluído (`completed`) ou cancelado por outro motivo (`cancelled`) após o
  acompanhamento já iniciado: telas terminais já existentes, inalteradas.
- Guincho móvel (`013-mobile-provider-dispatch`): nenhum passo de confirmação é introduzido nesse
  fluxo — ele não usa `PitTecAppointment`/`confirmedAt`.
- Mapa genérico de outros serviços (`ServiceMapView`): `centerCoordinate` continua funcionando como
  hoje; a nova capacidade de enquadrar múltiplas coordenadas em `PitGoMapView` é aditiva, não altera
  esse consumidor.

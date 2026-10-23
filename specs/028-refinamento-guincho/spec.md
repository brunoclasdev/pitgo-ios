# Feature Specification: Refinamento do fluxo de Guincho (porte iOS)

**Feature Branch**: `028-refinamento-guincho`

**Created**: 2026-10-22

**Status**: Draft

**Origin**: Porte do `specs/028-refinamento-guincho` do app Android (mesmo backend Supabase
compartilhado) — seleção explícita de guincheiro no mapa, pagamento só após o aceite, aceite com
dados liberados ao prestador, chegada/transporte, conclusão bilateral com contestação resolvida pelo
suporte (fora do app). O texto abaixo segue a especificação original; aqui só se registram os ajustes
de escopo específicos deste porte.

## Ajustes de escopo deste porte (iOS)

- **Resolução de contestação (FR-022) é fora do escopo mobile**: no Android, a resolução por
  "Concluir sem reembolso"/"Cancelar com reembolso integral" acontece num dashboard web separado
  (RPCs `dashboard_resolve_guincho_dispute` etc.), nunca no app Android em si. O app iOS também não
  implementa essa resolução — só abre/acompanha a contestação (FR-021) e reflete o resultado quando o
  suporte resolve.
- **Sem GPS ao vivo do guincheiro neste porte**: a tela de acompanhamento mostra retirada/destino em
  um mapa estático (dois marcadores) e o status textual do atendimento, mas não publica/consome a
  posição em tempo real do guincheiro (o Android usa `ProviderTrackingStateRepository`/canal de
  localização dedicado para isso — fica para uma iteração futura deste porte, junto da spec 031
  "guincho-vistoria-rota" do Android, que depende da mesma infraestrutura).
- **Avaliação (rating) e vistoria fotográfica não fazem parte deste porte**: pertencem às specs 030
  (`guincho-vistoria-fotos`) e 034 (`avaliacao-guincheiros-pittecs`) do Android, ainda não portadas.
- **Guincheiro é o mesmo pool de prestadores Móvel já existente** (`ProviderLocationMode.mobile`) —
  nenhum cadastro/modalidade nova; `GuinchoMapView` descobre esses mesmos prestadores por
  `discover_guincho_providers`.
- **Destino digitado não pode ser substituído por movimento programático do mapa**: somente pan/zoom
  iniciado pela pessoa invalida a busca e resolve o centro do mapa como novo destino. Atualizações
  de câmera feitas pelo app não equivalem a um gesto manual.
- **Mapa interativo no Guincho**: todos os cartões do fluxo ficam fixos no topo. Só a área visível
  do cartão intercepta toques; o mapa aceita pan e zoom sem mover o cartão, preservando o centro e o
  nível de zoom escolhidos pela pessoa após cada gesto.
- **Seleção de endereço**: ao escolher uma sugestão e informar o número, a sugestão permanece no
  campo de destino e não reaparece como uma segunda linha de endereço.

O restante do conteúdo original (user stories, requisitos funcionais, critérios de sucesso) está em
`../../../android/pitgo/specs/028-refinamento-guincho/spec.md` e se aplica integralmente ao app iOS,
ressalvados os três pontos acima.

## Resumo funcional (para referência rápida)

1. **Cliente** abre o card Guincho na Home → confirma retirada (automática por GPS, ou manual no
   mapa se indisponível), destino (busca de endereço) e veículo → vê guincheiros disponíveis no mapa
   → seleciona um → vê o total final num mini card → toca em "Contratar".
2. **Contratar** cria a solicitação (`PENDING`) vinculada só a esse guincheiro — sem pagamento ainda.
3. **Guincheiro** vê a solicitação com sua remuneração (sem os dados do cliente ainda) e tem um prazo
   para aceitar/recusar.
4. Aceito → **cliente paga** o total final (Pix ou cartão salvo) → aprovado → ambos ganham acesso aos
   dados completos (nome, veículo, retirada, destino) e ao acompanhamento.
5. Guincheiro toca **Cheguei** → depois **Iniciar transporte** → depois **Concluir atendimento**.
6. Cliente recebe o card de conclusão: **Confirmar** (encerra, ambos voltam ao início) ou
   **Informar problema** (abre contestação, suporte resolve fora do app).

## Requirements / Success Criteria

Idênticos aos do Android (ver link acima) — FR-001 a FR-023, SC-001 a SC-008 — exceto onde os
"Ajustes de escopo" desta página os restringem (FR-022 fica só como "visualização da contestação",
nunca resolução).

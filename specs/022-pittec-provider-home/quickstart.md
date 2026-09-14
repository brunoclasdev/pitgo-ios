# Quickstart: Home do PitTec

## Pré-requisitos

- Uma conta de prestador com `providers.location_mode = 'PITTEC'` (ex.: a mesma conta de teste já
  usada em `specs/021-pittec-accept-confirm-tracking/quickstart.md`).
- Permissão de localização concedida no simulador/device (When In Use é suficiente para ver o
  mapa; Always só é pedida quando o PitTec fica "Disponível", comportamento já existente de
  `ProviderDiscoveryTracker`).
- Build local (`xcodebuild -scheme pitgo build` ou Xcode) com as mudanças desta feature.

## Cenário 1 — Mapa + disponibilidade ao abrir (US1)

1. Fazer login com a conta PitTec de teste.
2. Observar que a home abre direto na aba "Mapa", com o mapa centralizado na posição atual do
   dispositivo e o card no topo mostrando "Disponível" ou "Indisponível".
3. Tocar no card para alternar o estado; confirmar que ele muda imediatamente e que
   `ProviderDiscoveryTracker` começa/para de publicar (mesmo indicador que já existe hoje).
4. Mover o simulador/device (Debug > Location > uma rota, ou mover fisicamente) e confirmar que o
   mapa acompanha a posição em até ~10s (intervalo já existente de publicação).

**Resultado esperado**: mapa e card refletem a realidade sem nenhum toque adicional; SC-001/SC-002
do spec.md satisfeitos.

## Cenário 2 — Navegar pelas 4 abas (US2)

1. Com a home aberta, tocar em "Dados da corrida" sem nenhum atendimento ativo → mensagem vazia.
2. Tocar em "Valores" → preço configurado do PitTec aparece (view-only, sem campo editável).
3. Tocar em "Perfil" → nome/e-mail e botão de sair aparecem; cancelar o diálogo de saída.
4. Voltar para "Mapa" → mapa e card seguem funcionando normalmente.

**Resultado esperado**: cada aba mostra o conteúdo esperado; SC-003 do spec.md satisfeito (≤3
toques para ir e voltar de qualquer aba).

## Cenário 3 — Solicitação nova chega em qualquer aba

1. Com a home do PitTec aberta em qualquer aba diferente de "Mapa" (ex.: "Perfil"), disparar uma
   nova solicitação PitTec de outro dispositivo/conta de cliente (mesmo fluxo de
   `specs/021-pittec-accept-confirm-tracking/quickstart.md`).
2. Confirmar que a tela de aceitar/recusar (`PitTecIncomingRequestView`) abre por cima,
   independentemente da aba em que o PitTec estava.

**Resultado esperado**: SC-004 do spec.md satisfeito — nenhuma regressão no aviso já existente.

## Cenário 4 — Fixo/Móvel inalterados

1. Fazer login com uma conta prestador em modalidade Fixo ou Móvel.
2. Confirmar que a tela continua sendo a `ProviderDashboardView` atual (sem mapa, sem 4 abas).

**Resultado esperado**: nenhuma regressão para as outras duas modalidades (FR-012 do spec.md).

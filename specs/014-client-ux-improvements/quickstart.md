# Quickstart: validar a melhoria de UX das telas do cliente (iOS)

Guia manual de ponta a ponta (sem testes automatizados, por decisão da governança do produto). Use
duas contas reais (uma `CLIENT`, uma `PROVIDER MOBILE` já configurada) e, quando possível, dois
dispositivos/simuladores — o mesmo setup já usado para validar a feature `013`.

## 1. Pré-requisitos

- Verificar (leitura, `supabase db diff`) que `client_addresses`/`client_current_locations` e as
  quatro RPCs (`contracts/client-address-rpcs.md`, `contracts/client-location-rpcs.md`) já estão
  aplicadas no projeto Supabase de desenvolvimento.
- Conta `CLIENT` sem endereço cadastrado (para testar o estado vazio) e outra com endereço já salvo
  (para testar edição).
- Conta `PROVIDER MOBILE` ativa, publicando localização (mesmo pré-requisito de `013`).

## 2. Home acionável (US5 — FR-005, FR-006)

1. Entre com a conta `CLIENT` sem endereço: confirme que a linha de endereço na Home não é mais um
   texto estático — ela reage ao estado real (`get_my_client_address` → `.notFound`) e é tocável.
2. Toque na linha de endereço: `ClientAddressView` abre diretamente.
3. Cadastre um endereço com CEP válido (reaproveitando a busca de CEP já especificada em `011`) e
   volte à Home: a linha agora mostra o endereço salvo e continua tocável para editar.
4. Confirme que o card de veículo continua funcionando como já especificado em `006`/`009`
   (`.noVehicle`/conteúdo — sem regressão).

## 3. Perfil completo (US6 — FR-007, FR-008)

1. Abra a aba Perfil: confirme que endereço e veículo padrão aparecem (ou o aviso de ausência), cada
   um com ação de cadastrar/editar, sem sair da aba.
2. Troque o tema para Escuro, depois Claro, depois Padrão do sistema: cada escolha deve refletir
   imediatamente em toda a tela e persistir ao fechar/reabrir o app.
3. Confirme que "Sair" continua pedindo confirmação e funcionando como já especificado em `006`.

## 4. Feedback durante a solicitação (US1 — FR-002, FR-003)

1. Como cliente, solicite o serviço de guincho e chegue ao estado de proposta encontrada.
2. Toque em "Solicitar" e observe: o botão mostra um `ProgressView`/"Processando…" em vez de apenas
   ficar acinzentado sem explicação.
3. Force uma distância pequena entre cliente e provider (mesma posição, como no teste manual de
   `013`): confirme que a tela mostra "Muito próximo" em vez de "0,0 km".
4. Force o esgotamento da busca (nenhum provider em 50km): confirme que o estado vazio com "Buscar
   novamente" continua funcionando (já especificado em `013` — não deve regredir).
5. Deixe uma solicitação expirar (60s) com ambos os apps abertos: confirme que a contagem regressiva
   chega a zero visivelmente, sem parecer travada (comportamento já especificado — apenas confirmar
   ausência de regressão).

## 5. Mapa do cliente em tempo real (US2 — FR-011 a FR-013)

1. Com o atendimento aceito, abra `AppointmentTrackingView` como cliente.
2. Confirme que a própria posição aparece centralizada no mapa, com um marcador visualmente distinto
   do marcador do guincho.
3. Movimente o dispositivo do provider (ou simule publicação de nova posição): confirme que o
   marcador do guincho se desloca no mapa do cliente em poucos segundos, sem recarregar a tela.
4. Saia da tela (voltar) e reabra: confirme que uma nova leitura de posição do cliente é feita (não
   uma posição antiga parada).

## 6. Mapa do provider em tempo real (US3 — FR-014, FR-015)

1. Como provider, aceite um atendimento e abra `ProviderIncomingRequestView`: confirme que agora
   existe um mapa (novo) mostrando sua posição e a do cliente, ambas visíveis sem precisar mover o
   mapa manualmente.
2. Movimente o dispositivo do provider: confirme que o marcador dele se atualiza em tempo real,
   mantendo o marcador do cliente visível.
3. Arraste/dê zoom manualmente no mapa: confirme que uma nova posição do provider não força a câmera
   de volta ao enquadramento automático.

## 7. Botão voltar sem travar (US4 — FR-016 a FR-018)

1. Com um atendimento aceito, como cliente, na tela de acompanhamento, toque em voltar: confirme que
   a navegação retorna à Home e **permanece** lá (sem ser redirecionado de volta automaticamente).
2. Repita o mesmo teste do lado do provider, a partir da tela de atendimento, voltando ao Dashboard.
3. Finalize o app (encerrar via multitarefa) com o atendimento ainda ativo e reabra do zero: confirme
   que o app leva automaticamente de volta à tela do atendimento — esse comportamento deve continuar
   funcionando apenas neste cenário (início de sessão), não como reação ao "voltar" manual dos
   passos 1/2.
4. Aceite/recuse/cancele o atendimento enquanto a outra parte está numa tela diferente: confirme que
   a navegação automática dispara corretamente para essa mudança real de status (revisão nova),
   distinguindo do caso de "voltar" manual sem mudança nenhuma.

## 8. Critério de encerramento

A feature está pronta quando todos os cenários acima passam nos dois papéis (cliente e provider),
sem regressão nos comportamentos já especificados em `research.md §8` (contagem regressiva, busca
esgotada, Home sem veículo), e sem nenhuma chamada de rede nova além das duas RPCs de endereço do
cliente e das já existentes de `009`/`013`.

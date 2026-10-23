# Feature Specification: Ambientes iOS (Dev/Homol/Prod)

**Feature Branch**: `027-ios-environment-flavors`

**Created**: 2026-10-22

**Status**: Draft

**Origin**: Porte do `specs/027-android-environment-flavors` do app Android, adaptado ao modelo de
build do Xcode (build configurations/xcconfig/schemes em vez de Gradle product flavors). O backend
de Homol/Prod é o MESMO projeto Supabase já usado pelo app iOS (`eetbrkznuqbdrnybnyhf`); Dev usa o
mesmo backend de desenvolvimento já provisionado pelo Android (`ljnqlaiiwreuczbdghxn`), reaproveitado
aqui para os dois apps continuarem testando contra o mesmo ambiente de desenvolvimento.

**Input**: User description (herdada do Android): "Criar ambientes diferentes no app. Dev, Homol e
Prod. Utilizar chaves, tokens e secrets nos 3 ambientes por enquanto. O ambiente de Dev não fará
transação com Mercado Pago, ele criará um fluxo igual, mas sem transação, para testar as telas, os
demais sim."

## Clarifications

Herdadas da especificação original (Android, sessão 2026-09-29) — nenhuma nova clarificação foi
necessária para o porte iOS:

- Homol usa o mesmo backend e a mesma integração Mercado Pago de Prod (decisão de 30/09/2026).
- Só um ambiente fica instalado por vez no mesmo dispositivo — a instalação seguinte substitui a
  anterior (iOS: mesmo `PRODUCT_BUNDLE_IDENTIFIER` `com.trustarx.pitgo` nas três configurações,
  nunca um sufixo por ambiente — ver plan.md).
- Cada ambiente tem configuração local separada, fora do controle de versão.
- Dev usa um backend próprio; Homol e Prod compartilham o backend de produção.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Selecionar o ambiente do aplicativo (Priority: P1)

Como responsável por desenvolver, homologar ou publicar o app iOS, quero gerar/rodar uma build
identificada como Dev, Homol ou Prod, para que cada build use o contexto correto sem alteração
manual no código.

**Independent Test**: Rodar a app com o scheme `pitgo` (Dev), `pitgo-Homol` e `pitgo-Prod`;
confirmar no Perfil que a identificação e o backend correspondem ao ambiente escolhido.

**Acceptance Scenarios**:

1. **Given** uma build do scheme `pitgo` (Dev), **When** ela é aberta, **Then** identifica Dev e
   usa somente o backend de Dev.
2. **Given** uma build do scheme `pitgo-Homol` ou `pitgo-Prod`, **When** ela é aberta, **Then**
   identifica o ambiente correspondente e usa o mesmo backend/credenciais de produção.
3. **Given** uma sessão autenticada de um ambiente, **When** uma build de outro ambiente é instalada
   no mesmo dispositivo (mesmo bundle identifier), **Then** o app invalida a sessão local antes de
   qualquer chamada autenticada.

### User Story 2 - Testar pagamentos sem cobrança em Dev (Priority: P1)

Como pessoa desenvolvedora ou de QA, quero executar em Dev o mesmo fluxo visual de pagamento sem
criar transação no Mercado Pago, para testar checkout, aprovação, falha, cancelamento e retorno sem
risco financeiro.

**Independent Test**: No scheme `pitgo` (Dev), iniciar um pedido MOBILE_SEQUENTIAL ou
PITTEC_AUTO_SEQUENTIAL e usar os botões de simulação (Aprovar/Rejeitar/Expirar/Simular falha) no
checkout; confirmar que os estados aparecem como no fluxo normal e nenhuma Edge Function do Mercado
Pago é chamada.

**Acceptance Scenarios**:

1. **Given** o app em Dev num fluxo que exige pagamento, **When** a pessoa escolhe Pix ou cartão,
   **Then** o app cria um pagamento simulado local, sem chamar `mp-create-payment`.
2. **Given** um pagamento simulado pendente, **When** a pessoa toca em Aprovar/Rejeitar/Expirar,
   **Then** o checkout reflete o estado correspondente.
3. **Given** uma build Dev, **When** qualquer etapa de pagamento é executada, **Then** nenhuma
   Edge Function `mp-*` é chamada e o SDK nativo do Mercado Pago nunca é inicializado.

### User Story 3 - Usar pagamentos reais nos ambientes autorizados (Priority: P1)

Como responsável por homologação ou produção, quero que Homol e Prod usem as mesmas credenciais e
integração de pagamento reais, para validar o comportamento real do Mercado Pago.

**Acceptance Scenarios**:

1. **Given** Homol, **When** um pagamento é iniciado, **Then** usa as mesmas credenciais e destino
   de Prod (`Homol.xcconfig` inclui o mesmo arquivo de secrets de `Prod.xcconfig` — ver plan.md).
2. **Given** Prod, **When** um pagamento é iniciado, **Then** usa as credenciais e o destino reais.
3. **Given** Dev, **When** a mesma operação é iniciada, **Then** nenhuma credencial de Homol/Prod é
   usada (`mercadoPagoPublicKey` é sempre vazia em `Dev.xcconfig`).

### User Story 4 - Diagnosticar o ambiente com segurança (Priority: P2)

Como pessoa de desenvolvimento, suporte ou QA, quero identificar o ambiente ativo sem expor
tokens/chaves/secrets.

**Acceptance Scenarios**:

1. **Given** qualquer build instalada, **When** a pessoa abre a aba Perfil, **Then** vê o
   identificador do ambiente e o modo de pagamento (simulado/integrado), sem valor sensível.
2. **Given** um `Dev.secrets.xcconfig`/`Prod.secrets.xcconfig` ausente ou inválido, **When** o build
   roda, **Then** falha no "Validate Supabase Config" antes de compilar (nunca um fallback
   silencioso).

### Edge Cases

- Uma build Dev não pode mudar para cobrança real por nenhum estado em tempo de execução —
  `mercadoPagoPublicKey` é zerada na última linha de `Dev.xcconfig`, vencendo qualquer valor de
  `Dev.secrets.xcconfig`.
- Troca de ambiente no mesmo device (mesmo bundle identifier) não pode reaproveitar sessão
  Supabase incompatível — `EnvironmentStateRepository` compara um fingerprint salvo antes do
  primeiro `bootstrap()`.
- Tokens administrativos/secrets privados nunca entram no repositório — `Config/*.secrets.xcconfig`
  está no `.gitignore`; só os `.example` são versionados.

## Requirements *(mandatory)*

- **FR-001**: O projeto Xcode DEVE oferecer exatamente três ambientes selecionáveis (Dev/Homol/Prod)
  via scheme (`pitgo`, `pitgo-Homol`, `pitgo-Prod`) e build configuration (`Debug`/`Release`,
  `Debug-Homol`/`Release-Homol`, `Debug-Prod`/`Release-Prod`).
- **FR-002**: Cada ambiente DEVE ter um arquivo de secrets local separado, fora do controle de
  versão; Homol DEVE reutilizar literalmente o arquivo de Prod (nunca uma cópia que possa divergir).
- **FR-003**: A build instalada DEVE exibir identificação clara do ambiente (Perfil) sem expor
  valores sensíveis.
- **FR-004**: Dev DEVE usar `SimulatedPaymentGateway` para todo pagamento — nunca inicia o SDK do
  Mercado Pago nem chama `mp-create-payment`/`mp-refund-payment`.
- **FR-005**: Dev DEVE reproduzir os estados de pagamento necessários para testar telas
  (selecionando método, aguardando confirmação, aprovado, recusado, expirado, falha) sem cobrança
  externa.
- **FR-006**: Homol e Prod DEVEM usar o backend e as credenciais reais de Mercado Pago, através do
  mesmo `PaymentRepository` já existente.
- **FR-007**: O "Validate Supabase Config" Run Script Build Phase DEVE rejeitar configuração
  ausente/inválida antes de compilar, incluindo a consistência entre `supabaseUrl` e
  `supabaseProjectRef`.
- **FR-008**: Trocar de ambiente no mesmo dispositivo (mesmo bundle identifier) DEVE invalidar a
  sessão Supabase local antes do primeiro `bootstrap()` do ambiente novo.
- **FR-009**: Build time DEVE rejeitar Dev apontando para o mesmo `supabaseProjectRef` de Prod.
- **FR-010**: Nenhum secret privado/token administrativo pode estar no código versionado.

## Success Criteria *(mandatory)*

- **SC-001**: 100% das builds geradas pelos três schemes são identificadas corretamente no Perfil.
- **SC-002**: 100% das tentativas de pagamento em Dev terminam sem nenhuma chamada de rede às Edge
  Functions `mp-*`.
- **SC-003**: Aprovação, rejeição e expiração são exercitáveis em Dev sem credenciais financeiras
  reais.
- **SC-004**: 100% dos pagamentos em Homol/Prod usam as credenciais de produção.
- **SC-005**: Build falha (não silencia) quando `supabaseProjectRef` não corresponde a `supabaseUrl`,
  ou quando Dev aponta para o projeto de Prod.

## Assumptions

- Os três ambientes compartilham o mesmo `PRODUCT_BUNDLE_IDENTIFIER` — apenas um fica instalado por
  vez no mesmo dispositivo/simulador, igual ao Android.
- O backend de Dev é o mesmo projeto Supabase de desenvolvimento já usado pelo Android
  (`ljnqlaiiwreuczbdghxn`) — nenhum projeto novo foi criado por este porte.
- `SimulatedPaymentGateway` cobre os fluxos MOBILE_SEQUENTIAL/PITTEC_AUTO_SEQUENTIAL já existentes
  no app iOS; não cobre nenhum fluxo de Guincho dedicado (specs 028+ do Android, ainda não portadas).

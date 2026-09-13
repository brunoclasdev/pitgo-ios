# Research: Corrigir cadastro de veículos e erros por campo (iOS)

## 0. Backend compartilhado — nenhuma migration nova

**Decision**: reutilizar a migration de restauração `20260823000000_restore_vehicle_rpcs.sql`
(já aplicada pela feature Android equivalente) que recria `create_vehicle`/`set_primary_vehicle`
com `create or replace function`, reset de `EXECUTE` e `NOTIFY pgrst, 'reload schema'`. Nenhuma
migration nova é criada por esta feature iOS; o contrato exato está em
[contracts/vehicle-rpcs.md](contracts/vehicle-rpcs.md).

**Rationale**: mesmo racional de `005 §0` em diante — o schema/RPCs são compartilhados; a
restauração foi um problema de ambiente remoto (funções ausentes apesar de uma migration histórica
já as registrar), não um problema de contrato entre plataformas. O client iOS já chama as mesmas
assinaturas desde `006`; a correção de disponibilidade beneficia ambas as plataformas
automaticamente assim que a migration é aplicada no projeto compartilhado.

## 1. Autorização e ownership dentro das funções (inalterado, backend-only)

Nenhuma ação — `create_vehicle`/`set_primary_vehicle` já exigem `auth.uid()` não nulo,
`private.has_account_type('CLIENT')` e um `profiles` ativo com o mesmo ID; `create_vehicle` nunca
recebe `user_id`. Ver `contracts/vehicle-rpcs.md`.

## 2. Unicidade do veículo principal (inalterado, backend-only)

Nenhuma ação — o `pg_advisory_xact_lock` por `auth.uid()` e o índice parcial
`one_primary_vehicle_per_user` já garantem exatamente um principal por conta, mesmo sob toques
concorrentes de qualquer plataforma.

## 3. Normalização e validação local (client iOS)

**Decision**: portar as mesmas regras de `VehicleValidation` (`006`) para Swift, sem alteração de
regra: marca e modelo usam `trim()` e não podem ficar vazios; opcionais textuais viram `nil` quando
vazios; placa é normalizada sem separadores e em maiúsculas, aceitando `AAA9999` e `AAA9A99`;
Renavam aceita exatamente 11 dígitos; chassi usa 17 caracteres maiúsculos sem I, O ou Q; anos ficam
entre 1900 e `Calendar.current.component(.year, from: .now) + 1`; quilometragem é inteira não
negativa.

**Rationale**: idêntico ao racional do Android — validação local reduz round trips e permite
mensagens imediatas, mas o banco continua sendo a autoridade definitiva (inalterada).

## 4. Consumo do contrato estável de erros remotos

**Decision**: `VehicleRepository` (`006`) mapeia exclusivamente os SQLSTATEs allowlisted já
definidos pela RPC (`P2001`..`P2008`, `P2011`..`P2013`) para `FieldFailure(field, error)` — nenhuma
interpretação de `message`/`details`/`hint`. `PGRST202`, `PGRST203`, `42883` ou função ausente/
incompatível tornam-se `.rpcUnavailable`; `401`/`403`/`42501` continuam `.sessionExpired`; timeout,
offline e 5xx continuam falhas gerais. O `Error` do `supabase-swift`, sua mensagem completa,
`details`, `hint`, URL e payload nunca são enviados à UI nem registrados — mesma disciplina de
`005`–`011`.

**Rationale**: idêntico ao racional do Android — códigos próprios eliminam parsing de texto livre e
impedem que o detalhe padrão do PostgreSQL (que pode conter o identificador completo) atravesse a
fronteira.

## 5. Estado e correção progressiva do formulário

**Decision**: manter `VehicleFormOperation` (`006`) como `enum` mutuamente exclusivo e ampliar
`VehicleMutationResult` para carregar `.fieldFailure(field, error)`. A submissão valida todos os
campos em ordem visual, grava o mapa completo de erros (`[VehicleField: VehicleFieldError]`) e
incrementa um `focusRequestID` (`Int`). Durante `.submitting`, eventos e novos submits são no-op
(guarda síncrona). Ao editar um campo que já possui erro, o ViewModel revalida apenas o resultado
daquele campo: substitui o tipo do erro se ainda inválido e só o remove quando o valor se torna
válido. Dados e erros alheios permanecem.

**Rationale**: idêntico ao racional do Android — revalidar somente campos já tocados evita
mensagens prematuras e cumpre a permanência do erro até correção.

**Alternatives considered**: idênticas ao Android — limpar erro em toda edição (rejeitado, um valor
ainda inválido pareceria corrigido); validar tudo a cada tecla (rejeitado, ruído antes da primeira
tentativa); persistir o rascunho (rejeitado, sem requisito de restauração após encerramento do
processo).

## 6. Rolagem, foco e mensagens acessíveis

**Decision**: associar um `@FocusState<VehicleField?>` e um identificador de `ScrollViewReader` a
cada linha do formulário. Quando `focusRequestID` muda, a View chama
`scrollViewProxy.scrollTo(field, anchor: .center)` seguido de `focusState = field` (numa próxima
tick de runloop, via `Task { @MainActor in ... }` ou `.onChange` encadeado, para garantir que a
rolagem termine antes do foco assumir — equivalente ao "aguardar composição" do
`BringIntoViewRequester` do Android). Cada campo usa indicação visual de erro + texto de apoio +
`.accessibilityLabel` combinando rótulo e erro. O banner geral usa
`.accessibilityAddTraits(.updatesFrequently)`. O botão continua desabilitado com `ProgressView`
durante o salvamento. A linha de "Tornar principal" usa um único `Toggle` acessível, e o gesto de
Voltar não descarta o destino durante `.submitting`.

**Rationale**: `ScrollViewReader` + `@FocusState` é o par nativo SwiftUI equivalente ao
`BringIntoViewRequester`/`FocusRequester` do Compose — mesmo racional de "pedir foco em um controle
fora da viewport sem trazê-lo explicitamente não garante visibilidade".

## 7. Conclusão e navegação por origem

**Decision**: a ação "Cadastrar veículo" da `VehicleOnboardingView` (`006`) empurra a rota do
formulário diretamente e não resolve a pendência nem grava um evento persistente no estado do
`VehicleOnboardingViewModel`; esse ViewModel continua dono apenas da operação de pular/resolver. A
pendência de onboarding (`VehicleOnboardingStore`, `006`) é resolvida **depois** de `create_vehicle`
retornar sucesso (ou no fluxo explícito de pular) — não antes, corrigindo a ordem que hoje marca o
onboarding como concluído cedo demais. Só depois o formulário entra em `.success`. Para
`.onboarding`, `PitGoRootView` troca `RootPhase` para `.home` (equivalente ao `navigate` com raiz);
para `.garage`, a `NavigationStack` da aba Garagem faz `path.removeLast()` e o `.task`/`.onAppear`
da `GarageView` recarrega a lista. O formulário concluído sai do `NavigationPath` em ambos os casos.
`SessionStore` aceita uma atualização local restrita de `AccountSnapshot.primaryVehicle` somente com
a linha autoritativa retornada pela RPC, desde que pertença ao cliente atual e esteja ativa/
principal; `GarageViewModel` aplica a mesma projeção após `set_primary_vehicle`, mantendo a Home
atualizada sem colocar a sessão global em `.verifying`.

**Rationale**: idêntico ao racional do Android — associar a resolução da pendência ao sucesso
preserva a regra de negócio e a origem tipada já existente (`VehicleFormOrigin`, `006`). O gate
também considera o onboarding concluído quando o snapshot remoto já contém veículo principal,
recuperando um commit confirmado seguido de encerramento do app antes da limpeza local do
`UserDefaults`.

**Alternatives considered**: idênticas ao Android — resolver a pendência antes de abrir o formulário
(rejeitado, voltar ou falhar deixaria o onboarding falsamente concluído); sempre navegar para Home
ou sempre para Garagem (rejeitado pela clarificação de produto); fazer o Repository de veículo
controlar navegação/preferência (rejeitado, mistura persistência remota com apresentação); refazer
`SessionStore.initialize()` completo após toda mutação na Garagem (rejeitado, colocaria a sessão em
`.verifying` desnecessariamente — aplicar a resposta autoritativa é mais direto).

## 8. Falha ambígua e atualização posterior

**Decision**: nenhum retry automático de `create_vehicle`. Em timeout ou perda de resposta, o
rascunho permanece e a falha geral orienta nova tentativa; ao sair e reabrir a Garagem, a lista
autoritativa é consultada e um veículo já confirmado aparece. Uma resposta de sucesso dispara
refresh da sessão/Home ou da Garagem, conforme a origem.

**Rationale**: idêntico ao racional do Android — a RPC não recebe chave de idempotência e Marca/
Modelo não formam chave natural; retry automático poderia duplicar um veículo sem identificadores
após commit com resposta perdida.

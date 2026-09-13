# State Contract: Atendimento mockado compartilhado na UI (iOS)

## Purpose

Este contrato define comportamento idêntico nas Views cliente e prestador. Cada perfil executa sua
própria instância; "a outra pessoa" é sempre uma resposta automática local, não outro dispositivo.

## Creation

Um atendimento só pode ser criado por: aceite do candidato da fixture cliente após busca confirmada;
ou aceite explícito do card de solicitação no fluxo prestador.

Na criação: `status = .travelling`; preço é congelado conforme o perímetro aceito; cliente e PitTec
possuem marcadores identificados e resumo textual; `acceptedAt` é registrado uma vez; o primeiro
comando de câmera do `MapLibreMapHost` enquadra os dois pontos; nenhum ID, posição ou estado é
enviado para fora do processo.

## Position timeline

1. Ao aceitar, emitir o snapshot inicial. Enquanto a experiência está visível e `status == .travelling`,
   manter exatamente uma `Task` de movimento.
2. Aguardar `Task.sleep(for: .seconds(30))` entre passos; cada passo avança no máximo um índice de
   `movementPath`, incrementa `revision` e recalcula distância local.
3. Não emitir comando de câmera em passos periódicos.
4. Se o usuário toca "Centralizar", enquadrar os dois pontos atuais e incrementar a revisão do
   comando de câmera.
5. Se a experiência sai de visível (`.onDisappear`), cancelar a `Task` preservando o último
   snapshot. Ao voltar (`.onAppear`), reavaliar stale imediatamente e então reiniciar a cadência de
   30s; não criar uma posição nova apenas para limpar o aviso.
6. Se não há novo snapshot por mais de 35.000ms monotônicos (`ContinuousClock`), usar marcador stale
   e mensagem "Última posição desatualizada"; manter o último ponto.
7. Ao atingir menos de 100m, mostrar "menos de 100 m". Marcadores continuam distintos mesmo em
   coordenadas iguais; o resumo textual identifica ambos.
8. Em `.inProgress`, `.awaitingCompletionConfirmation` ou `.completed`, não avançar o percurso.

## Meeting confirmation

Evento local: `onMeetingConfirmed()`.

- Válido apenas em `.travelling` e somente se ainda não houver confirmação local.
- Atualiza atomicamente para `.awaitingMeetingConfirmation`, registra timestamp local, desabilita a
  ação e mostra "Aguardando confirmação da outra pessoa".
- Agenda exatamente uma `Task` de 3.000ms com token `appointmentID + confirmationRevision`.
- Ao terminar, a `Task` revalida ID, revisão e estado. Se válidos, registra a contraparte, muda para
  `.inProgress` e registra `startedAt` uma única vez.
- Repetição, recriação de View ou `Task` obsoleta não altera estado nem agenda outra `Task`.

## Completion confirmation

Evento local: `onCompletionConfirmed()`.

- Válido apenas em `.inProgress` e somente sem confirmação local anterior.
- Atualiza atomicamente para `.awaitingCompletionConfirmation`, registra timestamp local, desabilita
  a ação e mostra "Aguardando confirmação da outra pessoa".
- Agenda exatamente uma `Task` de 3.000ms com token revisionado.
- Após revalidação, registra a contraparte, muda para `.completed`, registra `completedAt` e
  cancela `Task`s de movimento/stale.
- Nenhuma atualização de posição ou confirmação é aceita depois de `.completed`.

## Rendering contract

Em qualquer estado, o card textual apresenta: nomes/papéis de cliente e PitTec; estado em
linguagem natural; distância restante ou última distância conhecida; perímetro e total do serviço;
atualidade/horário da posição; confirmação que já ocorreu e qual falta, quando aplicável.

O mapa apresenta dois marcadores e uma linha direta tracejada identificada como estimativa. A
indisponibilidade do estilo/tiles produz aviso e retry, mas não remove o card nem bloqueia as ações
de confirmação.

## Event and job ownership

- A View apenas emite eventos e renderiza o `@Observable` state.
- O ViewModel é a única fonte de verdade e mantém referências das `Task`s.
- `onVisible()`/`onHidden()` (chamados de `.onAppear`/`.onDisappear`) são idempotentes.
- Cada `Task` é cancelada antes de ser substituída; a desalocação do ViewModel cancela todas.
- Delays são representados exclusivamente por `Task.sleep`, nunca por `Timer`/`DispatchQueue`
  aninhados ou callbacks de terceiros.

## External-effect invariant

Todo evento deste contrato modifica somente objetos Swift em memória e, quando aplicável, a câmera
MapLibre local. Não existe Repository, API, banco, `UserDefaults`/`SwiftData`, notificação,
cobrança, analytics com coordenadas ou comunicação entre as instâncias cliente/prestador.

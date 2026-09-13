# Contract: Account Registration (iOS)

## Purpose

Define a fronteira entre o `SignUpViewModel`, o `SignUpRepository`, a sessão Auth e a navegação
raiz. A View nunca recebe `SupabaseClient`, DTOs do SDK ou `Error` bruto.

## Environment prerequisites (shared, already satisfied)

- Provedor Email habilitado no projeto Supabase compartilhado.
- Signup por e-mail/senha habilitado.
- Confirm email desabilitado, para que o signup produza/importe uma sessão imediatamente.
- Senha mínima de 8 caracteres, sem regra adicional além da já refletida na UI/spec.
- A migration de `profiles` em [profiles-schema.md](profiles-schema.md) já está aplicada (ver
  [research.md §0](../research.md) — nenhuma ação de schema é feita por esta feature iOS).
- O app iOS usa somente uma chave publishable/legacy anon; nenhuma chave admin/service-role está
  presente no bundle (garantido por `004-configure-supabase`).

Se o signup completar sem sessão ativa, o registro retorna `.environmentMisconfigured` e não navega
para Home.

## Repository input

```swift
func register(_ registration: AccountRegistration) async -> RegistrationResult
func retryProfile(_ registration: AccountRegistration) async -> RegistrationResult
// retryProfile não exige senha quando já existe sessão ativa
```

`AccountRegistration` já é localmente válido e normalizado (ver [data-model.md](../data-model.md)).
O Repository ainda o trata como não confiável na fronteira remota. Suas invariantes são as mesmas
definidas em `data-model.md`.

O Repository recebe `SupabaseClient` por `init`. Ele possui as chamadas Auth/PostgREST e a
classificação de exceções. Um Use Case não faz parte deste contrato.

## Normal registration sequence

1. Ler a sessão atual (`client.auth.session`) antes de assumir ausência, para não confundir uma
   sessão persistida com a falta dela.
2. Se a sessão atual pertencer ao mesmo e-mail normalizado, pular o signup duplicado e garantir seu
   perfil.
3. Caso contrário, chamar `client.auth.signUp(email:password:data:)` com a metadata normalizada de
   perfil.
4. Não usar o valor de retorno opcional do signup como sinal de sessão — ler a sessão atual
   novamente depois da chamada.
5. Exigir `id` e `email` não nulos na sessão atual.
6. Selecionar `profiles` pelo `id` da sessão.
7. Se presente e consistente, retornar `.success`.
8. Se ausente, executar a sequência de recuperação idempotente.

### Metadata payload

| Key | Value |
|---|---|
| `name` | nome normalizado |
| `phone` | telefone normalizado |
| `cpf` | CPF apenas para pessoa física |
| `cnpj` | CNPJ apenas para pessoa jurídica |

Não enviar senha, e-mail duplicado, `active`, tokens ou documentos formatados como metadata.

## Profile recovery sequence

1. Exigir uma sessão ativa e extrair ID/e-mail exclusivamente dela.
2. Selecionar primeiro o perfil do mesmo ID.
3. Se ausente, inserir/upsert um `ProfileInsertDTO` com conflito no `id`, ignorando duplicidade.
4. Nunca enviar `active`; o default do banco é autoritativo.
5. Selecionar o perfil do mesmo ID novamente.
6. Retornar `.success` somente se existir exatamente uma linha com ID/e-mail correspondentes e
   formato de documento válido.
7. Caso contrário, retornar `.profileRecoveryRequired`; Home permanece bloqueada e o retry aciona a
   recuperação, não um novo signup.

Para uma resposta anterior ambígua sem sessão local, um conflito de signup posterior pode disparar
uma única tentativa de `signIn(email:password:)` com as credenciais enviadas. Se produzir uma
sessão, a recuperação continua. Não deve haver loop nem nova tentativa automática sem limite.

## Result contract

| Result | Trigger | Required presentation |
|---|---|---|
| `.success` | Sessão + perfil confirmados | Navega para Home e descarta a pilha não autenticada |
| `.emailUnavailable` | Conflito estável e allowlisted de e-mail | Erro neutro no campo e-mail |
| `.documentUnavailable` | Unique de CPF/CNPJ allowlisted violada | Erro neutro no campo documento |
| `.invalidServerInput` | Validação do backend/senha fraca | Campo relevante ou mensagem genérica de entrada |
| `.rateLimited` | Código/status estável de rate-limit | Pedir para aguardar; sem retry automático imediato |
| `.offline` | Falha de rede sanitizada | Preserva valores não sensíveis; ação de retry |
| `.serviceUnavailable` | Timeout/5xx/provedor desabilitado | Banner genérico acionável |
| `.profileRecoveryRequired` | Identidade autenticada mas perfil não confirmado | Estado somente leitura pendente + retry |
| `.environmentMisconfigured` | Sem sessão imediata após signup aceito | Bloqueia Home; mensagem genérica de configuração |
| `.unknown` | Qualquer outro caso | Mensagem genérica de retry |

## Error sanitization

- Nunca tratar `CancellationError`/`Task` cancelada como falha de domínio — retornar sem side
  effect visível.
- Mapear somente códigos estáveis de `AuthError`, status HTTP e nomes de constraint allowlisted.
- Tratar conflito genérico como genérico, a menos que o código estável nomeie o recurso.
- Nunca logar ou propagar o `Error` bruto do SDK, sua mensagem completa, headers de
  request/response, `details` do PostgREST, metadata, senha, token, CPF ou CNPJ.
- O texto de UI não deve confirmar qual outra conta possui um e-mail ou documento.

## ViewModel/UI contract

- O ViewModel aceita eventos explícitos por campo e possui a validação/submissão.
- Campos e CTA ficam desabilitados durante `.submitting`; envio repetido é um no-op.
- Envio local inválido define todos os erros de campo e foca o primeiro na ordem visual.
- Conclusão remota limpa senha e confirmação.
- `.success` é estado de UI durável; a raiz de navegação observa e troca `RootPhase` para `.home`.
- Voltar usa o mesmo caminho para o botão de navegação e o gesto de sistema; rascunho sujo exige
  confirmação.
- Voltar é bloqueado enquanto uma operação remota potencialmente commitada está sendo finalizada.

## Navigation contract

```text
Welcome --Criar conta--> SignUp   (empilha .signUp no NavigationStack não autenticado)
SignUp --Voltar (rascunho vazio ou descarte confirmado)--> Welcome
SignUp --Success--> Home          (RootPhase.unauthenticated → .home)
```

A transição de `Success` troca `RootPhase` para `.home`, o que descarta inteiramente a
`NavigationStack` não autenticada (Welcome + SignUp, incluindo qualquer senha residual em memória) —
equivalente ao `popUpTo(Welcome){inclusive=true}` + `launchSingleTop` do Android, mas obtido pela
própria identidade de View do SwiftUI em vez de uma chamada explícita de back stack.

# Quickstart: Validar criação de conta (iOS)

## 1. Prerequisites

- Xcode estável mais recente, SDK iOS 17+ instalado.
- Supabase CLI instalado apenas para **verificação** de schema (nenhuma migration é criada ou
  aplicada por esta feature).
- O mesmo projeto Supabase de desenvolvimento já usado para validar a feature Android equivalente.
- `supabaseUrl`/`supabaseKey` válidos e client-safe, fornecidos conforme `004-configure-supabase`.
- Nas configurações de Auth do projeto (já configuradas pela feature Android, apenas confirmar):
  - Provedor Email habilitado;
  - novos signups habilitados;
  - Confirm email desabilitado;
  - senha mínima de 8 caracteres sem regra de composição oculta.

Nunca usar um banco de produção ou uma chave service-role neste roteiro.

## 2. Verify the shared schema (no migration applied here)

A partir do repositório iOS, apenas **ler** o estado remoto — não rodar `db reset`/`db push` aqui:

```bash
supabase link
supabase db diff
```

Esperado:

- `supabase db diff` não mostra diferença pendente relevante — o schema documentado em
  [profiles-schema.md](contracts/profiles-schema.md) já está presente, aplicado pela migration do
  repositório Android.
- Se houver divergência, ela deve ser corrigida na migration do repositório Android (fonte de
  verdade), nunca criando uma migration paralela neste repositório.

No Dashboard, reconfirmar as configurações de Auth da seção 1; nenhuma delas é definida por SQL.

## 3. Build the iOS app

Configurar `supabaseUrl`/`supabaseKey` conforme `004-configure-supabase/quickstart.md`, então:

```bash
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build

xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'generic/platform=iOS' clean build
```

Esperado:

- `** BUILD SUCCEEDED **` em ambos os destinos;
- os produtos `Auth`/`PostgREST` do `supabase-swift` resolvem sem novo Swift Package externo;
- o cliente instala somente Auth/PostgREST além do core, mesmo escopo do Android;
- nenhuma tarefa/arquivo de teste automatizado é adicionado.

Instalar o build Debug num simulador/dispositivo conectado ao projeto de desenvolvimento.

## 4. Primary flow — individual

1. Abrir o app e tocar **Criar conta** na Welcome.
2. Selecionar **Pessoa física**.
3. Confirmar que o rótulo do nome é **Nome completo** e que somente CPF é exibido.
4. Preencher dados de fixture não produtivos válidos, incluindo um CPF válido e senha com 8+
   caracteres.
5. Enviar uma vez, depois tocar repetidamente enquanto processa.

Esperado:

- apenas uma submissão remota ativa por vez;
- progresso aparece em até um segundo;
- sucesso abre a Home imediatamente (`RootPhase` muda para `.home`);
- Voltar a partir da Home não retorna a SignUp/Welcome (a `NavigationStack` não autenticada foi
  descartada junto com a troca de `RootPhase`);
- Auth contém um usuário e `profiles` contém exatamente uma linha do mesmo ID;
- valores do perfil são canônicos, CNPJ é nulo e `active=true`.

## 5. Primary flow — company

Repetir com **Pessoa jurídica** usando os dois tipos de CNPJ de fixture aprovados, em contas
separadas:

- CNPJ numérico legado;
- CNPJ alfanumérico no formato vigente da Receita Federal (2026).

Esperado:

- o rótulo vira **Razão social / nome da empresa**;
- somente CNPJ é exibido e aceita letras maiúsculas/números com máscara;
- CPF é nulo no perfil da empresa armazenada;
- checksum inválido é bloqueado localmente e rejeitado pelo banco se enviado por um client
  modificado.

## 6. Form and interaction matrix

Verificar cada caso independentemente:

| Scenario | Expected result |
|---|---|
| Nenhum tipo de pessoa | Erro no grupo; foco no seletor de tipo |
| Nome/e-mail/telefone/documento/senha/confirmação em branco | Todos os erros aplicáveis exibidos; foco no primeiro |
| Senha com 7 caracteres | Bloqueio local com orientação de 8 caracteres |
| Confirmação diferente | Bloqueio local na confirmação |
| E-mail/DDD/CPF/CNPJ com DV inválido | Bloqueio local; nenhuma linha em Auth/perfil |
| Trocar pessoa física → jurídica | Documento é limpo; teclado/máscara de CNPJ substitui CPF |
| Colar telefone/CPF/CNPJ mascarado | Valor canônico correto (cursor pode ir ao fim; ver `research.md §9`) |
| Mostrar/ocultar senha | Toggles acessíveis independentes; valor inalterado |
| Voltar com formulário limpo | Retorna imediatamente à Welcome |
| Voltar com rascunho preenchido | Diálogo de descarte; continuar preserva o rascunho; descartar retorna |
| Voltar durante processamento | Operação permanece protegida; nenhuma navegação parcial |

Repetir em um dispositivo compacto, landscape, teclado aberto, Dynamic Type grande, tema escuro e
VoiceOver. Todos os controles/erros/CTA devem permanecer alcançáveis, o estado selecionado não pode
depender só de cor, e o VoiceOver deve anunciar rótulos, erros, carregamento e as ações de
visibilidade de senha.

## 7. Conflict and failure behavior

Usando apenas fixtures de desenvolvimento:

1. Tentar outro cadastro com um e-mail já existente.
2. Tentar novos e-mails com um CPF ou CNPJ já existente.
3. Desconectar a rede antes do envio e durante uma requisição.
4. Restaurar a conectividade e tentar novamente.
5. Provocar o rate limit ou um endpoint temporariamente indisponível do projeto de desenvolvimento
   somente em ambiente controlado.

Esperado:

- a UI usa mensagens neutras de disponibilidade de e-mail/documento sem identificar o proprietário;
- offline, timeout, rate limit e falhas de serviço têm apresentação distinta e acionável quando o
  SDK fornece um sinal confiável;
- campos não sensíveis permanecem; senha e confirmação são limpas após falha remota;
- nenhuma mensagem de `Error`, headers, token, senha ou documento completo aparece em logs/crash
  do app;
- retry nunca produz linhas duplicadas em Auth/perfil.

## 8. Atomicity and recovery

### Trigger rollback (backend, verificação apenas)

No ambiente de desenvolvimento, chamar signup com metadata de perfil deliberadamente inválida
usando um cliente de API que não contenha credenciais admin. A UI iOS já bloqueia isso localmente,
então esta é uma checagem do contrato de backend (idêntica à já validada pelo Android — nenhuma
mudança de comportamento é esperada por rodar a partir do iOS).

Esperado: falha de CHECK no perfil bloqueia o signup e nenhum usuário/perfil Auth committed
permanece.

### Missing-profile recovery

1. Criar uma conta de desenvolvimento válida pelo app iOS e manter sua sessão normal.
2. Como administrador do banco no projeto de desenvolvimento, remover somente seu perfil para
   simular um estado parcial histórico.
3. Reentrar no caminho de cadastro/recuperação com as mesmas credenciais e o mesmo rascunho
   normalizado.
4. Repetir a ação de retry rapidamente.

Esperado:

- Home permanece bloqueada até o perfil ser confirmado;
- a recuperação insere exatamente um perfil do mesmo ID com `active=true`;
- recuperação repetida converge para a mesma linha;
- nenhuma segunda identidade Auth é criada.

## 9. RLS verification

Criar dois usuários de desenvolvimento e exercitar a Data API com o access token de cada um
(pode ser feito via `curl`/Postman, independente de plataforma — a RLS é aplicada pelo Postgres):

- SELECT do próprio perfil retorna exatamente uma linha;
- SELECT entre usuários diferentes não retorna linha;
- INSERT do próprio perfil ausente pode ter sucesso quando todas as constraints passam;
- INSERT entre usuários diferentes é negado;
- SELECT/INSERT anônimo é negado;
- UPDATE/DELETE é negado para clientes autenticados.

Não imprimir access tokens ou CPF/CNPJ retornados no terminal, nem retê-los no histórico do shell.

## 10. Completion evidence

A feature está pronta quando:

- build iOS passa em simulador e `generic/platform=iOS`;
- a verificação de schema (seção 2) confirma que nada precisa ser migrado;
- fluxos de pessoa física e jurídica abrem a Home com sessão + perfil do mesmo ID;
- validação, acessibilidade, `RootPhase`/navegação e matriz de falhas passam;
- rollback atômico e recuperação idempotente são demonstrados (reaproveitando o mesmo ambiente já
  validado pelo Android, sem repetir a criação de schema);
- RLS/grants negam todo caso cross-user/anônimo;
- revisão de código/logs encontra zero `Error` bruto, token, senha ou documento completo.

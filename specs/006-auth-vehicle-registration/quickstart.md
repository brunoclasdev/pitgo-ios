# Quickstart: validar sessão autenticada e cadastro de veículos (iOS)

## 1. Prerequisites

- Xcode estável mais recente, SDK iOS 17+ instalado, simulador/dispositivo iOS 17+;
- Supabase CLI instalado apenas para **verificação** de schema (nenhuma migration é criada ou
  aplicada por esta feature — ver seção 2);
- o mesmo projeto Supabase de desenvolvimento já usado para validar a feature Android equivalente,
  com o schema/RPCs de [contracts/supabase.md](contracts/supabase.md) já aplicados;
- `Config/Secrets.xcconfig` com `supabaseUrl`/uma publishable/legacy anon key, conforme
  `004-configure-supabase`;
- provedor Email habilitado, signup habilitado, confirmação de e-mail desabilitada e senha mínima de
  oito caracteres no projeto usado para a validação;
- nenhuma secret/service-role key no app.

Leia antes:

- [modelo de dados](data-model.md);
- [contrato Supabase](contracts/supabase.md);
- [contrato de navegação](contracts/navigation.md).

## 2. Verify the shared schema (no migration applied here)

A tabela `vehicles` e as RPCs já foram criadas e conciliadas pela migration do repositório Android.
A partir do repositório iOS, apenas **ler** o estado remoto:

```bash
supabase link
supabase db diff
```

Esperado:

- nenhuma diferença pendente relevante — `profiles`, `vehicles`, os triggers e as RPCs
  `create_vehicle`/`set_primary_vehicle` já existem exatamente como documentado em
  [contracts/supabase.md](contracts/supabase.md);
- `authenticated` consegue SELECT nas próprias linhas, mas não pode INSERT/UPDATE/DELETE veículos
  diretamente;
- `authenticated` pode executar somente as duas RPCs de veículo.

Qualquer divergência encontrada deve ser corrigida na migration do repositório Android (fonte de
verdade), nunca com uma migration paralela neste repositório.

## 3. Build the iOS app

```bash
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build

xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'generic/platform=iOS' clean build
```

Esperado: ambos sucedem, sem teste automatizado gerado ou executado. Instalar o build Debug:

```bash
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/pitgo.app
xcrun simctl launch booted com.trustarx.pitgo
```

## 4. Validate session startup and login

### No stored session

1. Apagar os dados do app (ou reinstalar) e abrir o PitGo.
2. Confirmar que nenhuma Home/perfil/veículo aparece antes da Welcome.
3. Tocar `Entrar`.
4. Enviar e-mail/senha vazios/inválidos.

Esperado: erros locais de campo, nenhuma requisição para formulário inválido, `ScrollView`/teclado
responsivos e sem `TabView` em Login.

### Valid login and restoration

1. Entrar com um perfil ativo existente.
2. Confirmar que a Home mostra o nome e as iniciais/avatar dessa conta.
3. Se a conta tiver veículo principal, confirmar marca/modelo/ano/placa exatos.
4. Encerrar o app (forçar) e reabrir.

Esperado: uma superfície de verificação aparece até sessão/perfil serem autorizados; então a Home
abre sem pedir credenciais e sem piscar dado demonstrativo.

### Invalid credentials and repeated taps

1. Informar um e-mail válido com senha errada.
2. Tocar o envio repetidamente enquanto carrega.

Esperado: uma requisição em andamento, mensagem neutra de credenciais inválidas, senha limpa e
nenhuma rota privada aberta.

### Offline stored session

1. Entrar com sucesso, encerrar o app, desativar a rede e reabrir.
2. Tocar `Tentar novamente` ainda offline.
3. Restaurar a rede e tentar novamente.

Esperado: a sessão é preservada; Home e dados personalizados antigos permanecem ocultos; nenhum
logout automático; o retry bem-sucedido volta para a mesma conta.

### Missing/inactive/inconsistent profile

Usando uma conta/banco descartável, tornar o perfil associado ausente, inativo ou inválido e
reabrir.

Esperado: a Home fica bloqueada; somente `Tentar novamente` e `Sair` são oferecidos; nenhum perfil é
inserido, atualizado ou reativado pelo client iOS.

### Logout

1. Abrir Perfil pela `TabView`.
2. Confirmar `Sair`.
3. Voltar/gesto após a Welcome.

Esperado: snapshot de conta, Home, Garagem e rascunhos de veículo desaparecem; Voltar nunca revela
conteúdo privado; a sessão local do `supabase-swift` é removida mesmo se o logout ocorrer offline.

## 5. Validate signup onboarding

### Persistent pending choice

1. Criar uma conta nova válida.
2. Quando o convite de veículo aparecer, encerrar o app sem escolher.
3. Reabrir com rede disponível.

Esperado: após a verificação de sessão, o convite aparece novamente antes da Home.

### `Agora não`

1. Escolher `Agora não`.
2. Confirmar que a Home abre no estado sem veículo.
3. Reabrir o app.

Esperado: o convite não se repete; a Home oferece acesso à Garagem.

### `Cadastrar veículo`

1. Criar outra conta ou marcar um cadastro descartável como pendente.
2. Escolher `Cadastrar veículo`.
3. Voltar com formulário vazio ou confirmar descarte de um formulário sujo.

Esperado: a escolha explícita é considerada resolvida; a Home abre sem veículo e o convite não se
repete. Nenhum veículo é inserido.

## 6. Validate vehicle form

### Local rules

Verificar cada condição independentemente:

- marca/modelo em branco → erros obrigatórios;
- placa legado e placa Mercosul → aceitas/canonicalizadas;
- placa malformada → rejeitada;
- Renavam mais curto/mais longo/não numérico → rejeitado, preservando zeros à esquerda quando válido;
- chassi com menos/mais de 17 caracteres ou contendo I/O/Q → rejeitado;
- anos antes de 1900 ou depois do próximo ano civil → rejeitados;
- quilometragem negativa/não numérica → rejeitada;
- todo campo opcional em branco → aceito como `nil`.

Esperado: todo dado inválido é bloqueado antes da rede, o primeiro erro recebe foco e máscaras nunca
alteram o valor canônico persistido.

### First vehicle

1. Com uma conta sem veículo, enviar somente marca e modelo.
2. Inspecionar Home, Garagem e a linha no banco.

Esperado: exatamente uma linha pertence a `auth.uid()`, `active = true`, `is_primary = true`, e a
Home a exibe. Os campos de owner/status nunca foram editáveis.

### Additional vehicle and primary choice

1. Adicionar um segundo veículo sem selecioná-lo como principal.
2. Confirmar que o original permanece principal.
3. Adicionar/selecionar um veículo como principal.

Esperado: a RPC termina com exatamente um principal; a Garagem atualiza imediatamente e a Home
reflete o mesmo veículo quando revisitada.

### Duplicate identifiers

Em duas contas descartáveis, tentar placa, Renavam e chassi canônicos duplicados.

Esperado: cada tentativa é rejeitada com uma mensagem neutra de indisponibilidade por campo; nenhum
proprietário, valor de documento ou detalhe de backend é revelado.

### Concurrency/idempotency

1. Tocar criar/definir-principal repetidamente.
2. Se possível, disparar seleções de principal concorrentes para a mesma conta a partir de dois
   clientes.

Esperado: uma operação de formulário por client, nenhum veículo duplicado por toques repetidos de UI
e o banco termina com exatamente um principal porque a RPC serializa por usuário.

## 7. Validate Garage and authorization

1. Abrir uma conta sem veículos: verificar estado vazio e ação de adicionar.
2. Abrir uma conta com várias linhas incluindo uma inativa: verificar que só linhas ativas aparecem.
3. Usar duas contas e tentar consultar/alterar o veículo conhecido da outra via um cliente REST,
   usando o JWT normal de cada usuário (independente de plataforma — a RLS é aplicada pelo Postgres).

Esperado: SELECT entre contas não retorna linha e a RPC de mutação retorna negado/não-encontrado
neutro; veículos inativos nunca aparecem nem se tornam principal. Nunca usar credenciais
service-role neste teste.

## 8. Validate session expiry during vehicle entry

1. Preencher valores identificáveis no formulário de veículo sem enviar.
2. Expirar/revogar a sessão ou forçar o SDK a um estado de sessão inválido.
3. Autenticar novamente, inclusive uma vez com uma conta diferente.

Esperado: o formulário antigo desaparece, todos os campos ficam vazios, nenhum veículo foi inserido
e nenhum valor é restaurado para qualquer conta. Se a expiração não puder ser verificada por o
dispositivo estar offline, a tela de verificação de sessão aparece e o rascunho ainda é descartado.

## 9. Visual, accessibility and privacy pass

Validar em um iPhone compacto, landscape, Dynamic Type grande, teclado aberto e VoiceOver:

- todos os campos/CTAs do formulário permanecem alcançáveis;
- alvos de toque têm pelo menos 44×44pt;
- carregamento e erros são anunciados;
- o principal selecionado é comunicado por texto/semântica, não somente pela cor roxa;
- o carregamento do avatar (`AsyncImage`) tem tamanho limitado, placeholder e fallback de iniciais;
- a `TabView` permanece fixa sem cobrir o conteúdo de Garagem/Home.

Inspecionar o console/crash reporter após sucesso e cada falha. Esperado zero senha completa, token,
CPF/CNPJ, Renavam, chassi, mensagem de `Error`, URL de request ou header de autorização.

## 10. Completion evidence

Registrar o seguinte antes de considerar a feature pronta:

- build `xcodebuild` bem-sucedido em simulador e `generic/platform=iOS`;
- resultado de `supabase db diff` confirmando que nada precisa ser migrado (seção 2);
- capturas de tela do session gate, Home personalizada/sem veículo, convite persistente, Garagem e
  formulário;
- evidência de banco de que duas contas não conseguem ver/mutar uma à outra e que uma conta tem no
  máximo um principal;
- confirmação de que nenhuma credencial real ou valor sensível de teste entrou em arquivo rastreado
  ou artefato de log.

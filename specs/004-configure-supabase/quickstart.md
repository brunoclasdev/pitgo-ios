# Quickstart Validation: Configurar Supabase (iOS)

## Prerequisites

- Xcode estável mais recente, SDK iOS 17+ instalado.
- Um `supabaseUrl` HTTPS e uma chave **publishable** (`sb_publishable_...`) ou legacy `anon`.
- Nunca usar ou compartilhar chave `sb_secret_...` ou `service_role`.
- Simulador ou dispositivo iOS 17+ para regressão manual.
- O mesmo projeto Supabase já usado pelo app Android pode ser reutilizado; nenhuma alteração de
  schema/backend é necessária para esta feature.

## Configure local values

Criar `pitgo/Config/Secrets.xcconfig` (já listado no `.gitignore` do projeto):

```text
supabaseUrl = https:/$()/<project-ref>.supabase.co
supabaseKey = sb_publishable_<client-value>
```

> Nota de sintaxe `.xcconfig`: `//` inicia um comentário nesse formato de arquivo, por isso a URL
> usa o escape `/$()/`  para representar `//` sem iniciar um comentário.

Não copiar valores reais para `Config/Shared.xcconfig` (rastreado), `Info.plist` versionado, specs,
código, comandos registrados ou mensagens. `Config/Secrets.xcconfig` é incluído automaticamente por
`Config/Shared.xcconfig` via `#include? "Secrets.xcconfig"`.

Em CI, exportar como variáveis de ambiente e gerar/injetar um `.xcconfig` equivalente na invocação,
por exemplo:

```bash
printf 'supabaseUrl = %s\nsupabaseKey = %s\n' "$SUPABASE_URL_CI" "$SUPABASE_KEY_CI" > CI-Secrets.xcconfig
xcodebuild -project pitgo.xcodeproj -scheme pitgo -xcconfig CI-Secrets.xcconfig ...
```

Nunca colocar o valor real diretamente na linha de comando/log do CI; usar variáveis de ambiente
marcadas como secretas pela plataforma de CI.

O contrato completo está em [supabase-configuration.md](contracts/supabase-configuration.md).

## Positive build validation

Com valores válidos configurados:

```bash
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build

xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'generic/platform=iOS' clean build
```

Resultado esperado:

- `** BUILD SUCCEEDED **` em ambos os destinos (simulador e dispositivo/Release-like).
- Nenhum Swift Package novo além de `supabase-swift`, nenhum módulo funcional (`Auth`, `PostgREST`,
  `Storage`, `Realtime`, `Functions`) referenciado.
- `SupabaseClientProvider.client` compila como o único cliente compartilhado.
- Nenhum request ou log contendo URL/chave ocorre durante build ou inicialização.

## Negative build matrix

Executar cada caso somente com valores sintéticos em `Config/Secrets.xcconfig`, restaurando o
arquivo válido entre casos. Nunca colocar a chave real em uma fixture negativa.

| Case | Synthetic input | Expected result |
|---|---|---|
| URL ausente/blank | `supabaseUrl` omitida ou espaços | Build interrompido; cita apenas o campo |
| URL sem scheme | `project.supabase.co` | Build interrompido |
| URL insegura | `http:/$()/project.supabase.co` | Build interrompido |
| URL sem host/opaca | URI HTTPS malformada | Build interrompido |
| URL com user-info | `https:/$()/user@project.supabase.co` | Build interrompido |
| Chave publishable | `sb_publishable_validation_only` | Build permitido sem request |
| Chave secret | `sb_secret_validation_only` | Build interrompido sem ecoar valor |
| JWT legacy anon | fixture JWT com payload `role=anon` | Build permitido sem validar assinatura |
| JWT service role | fixture JWT com payload `role=service_role` | Build interrompido sem ecoar payload |
| Formato desconhecido | String não vazia fora da allowlist | Build interrompido |

Para cada falha, validar destino simulador e destino `generic/platform=iOS` (equivalente a
Debug/Release do Android). A saída do Run Script Build Phase deve mencionar correção/fonte aceita e
não conter input completo, payload ou segmento da chave.

## Source precedence and normalization

1. Configurar fixtures diferentes em `Config/Secrets.xcconfig` e em um override `-xcconfig` de linha
   de comando.
2. Confirmar que o override de linha de comando vence.
3. Configurar a fonte superior como blank e confirmar falha, sem fallback silencioso para
   `Config/Secrets.xcconfig`.
4. Adicionar espaços externos a URL/chave válidas em `Config/Secrets.xcconfig` e confirmar build
   bem-sucedido.
5. Confirmar que o conteúdo interno da URL/chave não foi alterado (apenas espaços externos são
   removidos).

## Repository and log inspection

Sem imprimir o valor, pesquisar a chave real por stdin:

```bash
printf '%s\n' "$SUPABASE_KEY_CI" |
  git grep --files-with-matches --fixed-strings -f - -- .
```

Resultado esperado: nenhuma saída. Também revisar:

```bash
git status --short
git diff --check
git ls-files pitgo/Config/Secrets.xcconfig
```

`Config/Secrets.xcconfig` não deve estar rastreado. Referências textuais a `sb_secret_`/`service_role`
em specs, script de validação e fixtures são regras/exemplos sintéticos, não credenciais.

## Runtime regression and offline behavior

1. Instalar o build Debug no simulador/dispositivo e abrir o app.
2. Percorrer Welcome → Home → RequestService e usar Back.
3. Confirmar que não há nova tela, loading, erro, permissão de sistema ou mudança visual.
4. Encerrar e reabrir o processo; o app permanece funcional.
5. Ativar o Modo Avião e repetir a abertura: configuração continua válida e nenhum health check
   falha.
6. Confirmar em inspeção de código que acessos repetidos a `SupabaseClientProvider.client` retornam
   a mesma instância (`static let`) e que nenhum módulo Auth/PostgREST/Storage/Realtime/Functions
   foi instalado.

## Scope confirmation

A validação termina com o cliente central disponível. Não são esperados autenticação, sessão,
tabela, DTO, consulta, escrita, upload, assinatura Realtime, função remota, Repository, UI de erro,
persistência ou teste automatizado.

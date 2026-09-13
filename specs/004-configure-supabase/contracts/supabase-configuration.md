# Build Configuration Contract: Supabase (iOS)

## Purpose

Definir a fronteira verificável entre valores de configuração externos ao repositório e o
`SupabaseClient` único disponibilizado ao app. Este contrato substitui, para o alvo iOS, o contrato
Gradle/`BuildConfig` do Android — os nomes canônicos e as regras de validação são idênticos; apenas
o mecanismo de resolução/injeção muda (Xcode Build Settings + `.xcconfig` + Run Script Build Phase,
em vez de `providers.gradleProperty`/`buildConfigField`).

## Canonical names

- `supabaseUrl` — User-Defined Build Setting, case-sensitive.
- `supabaseKey` — User-Defined Build Setting, case-sensitive.

Nenhum alias adicional (`SUPABASE_URL`/`SUPABASE_KEY` só existem como as **chaves do `Info.plist`**
gerado, nunca como nomes alternativos de Build Setting).

## Source precedence

1. Valor passado na invocação de `xcodebuild` (`xcodebuild -xcconfig <arquivo>` ou
   `SUPABASE_URL=... SUPABASE_KEY=...` como override de build setting) — usado em CI.
2. `Config/Secrets.xcconfig`, arquivo local **não rastreado** (listado no `.gitignore`), incluído
   pelo `.xcconfig` base do projeto via `#include? "Secrets.xcconfig"`.
3. Ausência de qualquer fonte acima é tratada como valor ausente — **não há terceiro fallback**.

Uma fonte de precedência mais alta presente, ainda que em branco, prevalece e falha a validação —
não há queda silenciosa para uma fonte inferior.

## Validation contract (Run Script Build Phase)

Script: `Scripts/validate-supabase-config.sh`, executado como Run Script Build Phase **antes** da
fase "Compile Sources" do target principal.

### `supabaseUrl`

| Regra | Resultado |
|---|---|
| Ausente ou somente espaços após `trim` | Build interrompido; mensagem cita apenas o campo |
| Sem `https://` como esquema | Build interrompido |
| Esquema `http://` | Build interrompido |
| URI opaca ou sem host (ex.: malformada) | Build interrompido |
| Contém user-info (`https://user@host`) | Build interrompido |
| HTTPS absoluta, com host, sem user-info | Build permitido, sem request de rede |

### `supabaseKey`

| Regra | Resultado |
|---|---|
| Ausente ou somente espaços após `trim` | Build interrompido; mensagem cita apenas o campo |
| Prefixo `sb_publishable_` (case-sensitive) com sufixo ASCII não vazio | Build permitido |
| Prefixo `sb_secret_` | Build interrompido, sem ecoar o valor |
| JWT de 3 segmentos Base64URL com payload `role == "anon"` | Build permitido, sem validar assinatura |
| JWT de 3 segmentos com payload `role == "service_role"` ou múltiplos roles | Build interrompido, sem ecoar o payload |
| Qualquer outro formato não vazio | Build interrompido |

### Diagnostic rules

- Toda mensagem de erro cita **somente** o nome do campo (`supabaseUrl` ou `supabaseKey`) e a regra
  aceita/violada — nunca o valor recebido, nem um trecho ou hash dele.
- Nenhuma etapa do script grava o valor em um arquivo de log persistente; a saída fica restrita ao
  console de build do Xcode/`xcodebuild`.
- O script termina com código de saída diferente de zero para qualquer violação, interrompendo o
  build antes de "Compile Sources" — nenhum `.app`/`.ipa` é gerado com configuração inválida.

## Build output contract

Com valores válidos:

- `Info.plist` do target contém `SUPABASE_URL` e `SUPABASE_KEY` resolvidos e normalizados
  (`trim` aplicado, conteúdo interno preservado).
- `SupabaseClientProvider.client` compila e é a única instância de `SupabaseClient` acessível ao
  restante do app.
- Nenhum request de rede ocorre durante o build ou a inicialização do provider.
- Nenhum módulo de produto (`Auth`, `PostgREST`, `Storage`, `Realtime`, `Functions`) é instalado ou
  referenciado nesta feature.

Com qualquer valor ausente/inválido/elevado:

- O Run Script Build Phase falha antes de "Compile Sources".
- Nenhum artefato (`.app` em simulador, `.ipa`/arquivo assinado) é produzido para a variante afetada.
- Debug e Release (e qualquer configuração adicional futura) recebem a mesma validação, sem exceção.

## Consumer contract

- **Ownership**: `Core/Network/SupabaseClientProvider.swift`.
- Views, ViewModels e futuros Repositories consomem `SupabaseClientProvider.client` (ou recebem o
  cliente por injeção de `init`); nenhum desses componentes lê `Info.plist`/`Bundle.main` ou cria um
  `SupabaseClient` próprio.
- Nenhuma UI, navegação ou permissão de sistema muda em função desta feature.

## Repository hygiene contract

- `Config/Secrets.xcconfig` MUST estar listado em `.gitignore` e nunca ser commitado com valores
  reais.
- Nenhum arquivo rastreado (código, `Info.plist` versionado no repositório antes do build, specs,
  scripts, mensagens de commit) MUST conter uma chave `sb_publishable_`/JWT/`sb_secret_` real.
- Referências textuais a `sb_secret_`/`service_role` nesta spec e no script de validação são
  regras/fixtures sintéticas, não credenciais.

## Invariants

- Os nomes canônicos `supabaseUrl`/`supabaseKey` (Build Settings) e `SUPABASE_URL`/`SUPABASE_KEY`
  (`Info.plist`) são estáveis e não mudam entre Debug/Release/CI.
- Uma chave `sb_secret_`/`service_role` nunca chega a ser embutida em um artefato de build, em
  nenhuma variante.
- `SupabaseClientProvider.client` é a única fronteira de acesso ao cliente Supabase no app iOS.
- O mesmo backend/projeto Supabase (schema, RLS, Edge Functions) já utilizado pelo app Android é
  reutilizado sem nenhuma alteração — esta feature configura apenas o lado cliente iOS.

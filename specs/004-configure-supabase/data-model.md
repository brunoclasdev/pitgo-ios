# Data Model: Configurar Supabase (iOS)

Esta feature não introduz entidades de domínio, apenas um fluxo de configuração de build e uma
fronteira de acesso ao cliente remoto compartilhado. Os "tipos" abaixo existem apenas durante a
preparação do app (build) e na leitura pontual do `Info.plist`; nenhum é persistido.

## 1. `SupabaseBuildInput` (conceitual, sem tipo Swift correspondente)

Representa os dois valores brutos fornecidos externamente ao projeto, antes de qualquer validação.

| Campo | Origem | Regras |
|---|---|---|
| `supabaseUrl` | User-Defined Build Setting `supabaseUrl`, resolvido a partir de `Config/Secrets.xcconfig` (local) ou de override de `-xcconfig`/`xcodebuild` (CI) | `trim`; deve resultar em URI absoluta HTTPS com host e sem user-info |
| `supabaseKey` | User-Defined Build Setting `supabaseKey`, mesma origem | `trim`; deve casar com a allowlist da seção 4 de `research.md` |

Este par não existe como `struct` Swift — ele só existe como texto de Build Setting, lido e validado
pelo Run Script Build Phase descrito em `contracts/supabase-configuration.md`. Nenhum código do app
manipula `SupabaseBuildInput` diretamente.

## 2. `ValidatedSupabaseConfig` (conceitual, materializado no `Info.plist`)

Resultado da validação bem-sucedida: os mesmos dois valores, garantidamente normalizados e seguros
para embutir no app.

| Campo | Tipo (Info.plist) | Regra de aceitação |
|---|---|---|
| `SUPABASE_URL` | String | HTTPS absoluta, host válido, sem user-info, sem espaços externos |
| `SUPABASE_KEY` | String | `sb_publishable_<sufixo não vazio>` **ou** JWT legado de 3 segmentos com payload `role == "anon"` |

Um valor que falhe qualquer regra impede a existência deste par — o Run Script Build Phase termina
com código de saída diferente de zero antes que o `Info.plist` processado chegue a ser embutido no
produto de build, e a compilação do target não prossegue.

## 3. Runtime: leitura via `Bundle.main`

Em runtime, o app lê os dois campos do `Info.plist` do próprio bundle:

```swift
Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
Bundle.main.object(forInfoDictionaryKey: "SUPABASE_KEY") as? String
```

Como a validação já ocorreu em tempo de build, esta leitura runtime nunca precisa revalidar o
conteúdo — apenas materializa o `SupabaseClient` (ver seção 4). Um `nil`/valor vazio aqui só seria
possível se a fase de validação tivesse sido contornada manualmente fora do fluxo de build padrão,
o que está fora do escopo desta feature.

## 4. `SupabaseClientProvider` (tipo Swift real)

```swift
enum SupabaseClientProvider {
    static let client: SupabaseClient = {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_KEY") as? String
        else {
            preconditionFailure("Supabase configuration missing at runtime — build validation should have prevented this.")
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()
}
```

- `client` é a **única** instância de `SupabaseClient` do app (equivalente ao `object` Kotlin do
  Android); `static let` garante inicialização única, preguiçosa e thread-safe.
- Nenhum plugin de produto (`Auth`, `PostgREST`, `Storage`, `Realtime`, `Functions`) é instalado
  nesta feature — apenas o cliente central, mesmo escopo do Android.
- O `preconditionFailure` é uma rede de segurança para um estado que a validação de build já deveria
  ter impedido; não é o mecanismo de validação em si (que é o Run Script Phase, ver contrato).

## Relações e fluxo

```text
Config/Secrets.xcconfig (local, não rastreado)         override -xcconfig / env (CI)
                    \                                        /
                     \                                      /
                      v                                    v
              User-Defined Build Settings: supabaseUrl, supabaseKey
                                    |
                                    v
              Run Script Build Phase: validate-supabase-config.sh
                     (falha o build sem ecoar valores em caso de erro)
                                    |
                                    v
                    Info.plist: SUPABASE_URL, SUPABASE_KEY
                                    |
                                    v
                Bundle.main.object(forInfoDictionaryKey:) em runtime
                                    |
                                    v
                     SupabaseClientProvider.client (SupabaseClient)
                                    |
                                    v
              Futuras Views/ViewModels/Repositories (fora do escopo desta feature)

# Research: Configurar Supabase (iOS)

## 1. SDK, versões e módulos mínimos

**Decision**: usar `supabase-swift` (Swift Package Manager, versão estável mais recente compatível
com Swift 6/iOS 17+) e adicionar somente o produto `Supabase` (o pacote central, que expõe
`SupabaseClient`/`createClient`). Não adicionar os produtos `Auth`, `PostgREST`, `Storage`,
`Realtime` ou `Functions` isoladamente nesta feature.

**Rationale**: `supabase-swift` já reexporta `SupabaseClient` a partir do produto central e os
submódulos de produto apenas o estendem, mesmo racional do `supabase-kt` no Android. Diferente do
Ktor no Android, `supabase-swift` usa `URLSession` da própria `Foundation` como engine HTTP —
**não há engine adicional a declarar**, o que remove uma dependência inteira presente no Android
(`ktor-client-android`). Fontes: [supabase-swift README](https://github.com/supabase/supabase-swift),
[Supabase Swift quickstart](https://supabase.com/docs/reference/swift/initializing).

**Alternatives considered**: adicionar `Auth`/`PostgREST` apenas para obter o cliente, rejeitado
pelo mesmo motivo do Android (core é publicável sozinho, consultas são proibidas nesta feature);
usar `URLSession` manual sem o SDK, rejeitado porque não entrega um `SupabaseClient` reutilizável;
fixar uma versão antiga do pacote, rejeitado por ausência de qualquer incompatibilidade conhecida
com o toolchain Swift 6 atual (diferente do Android, não há gate de metadata Kotlin a evitar aqui).

## 2. Compatibilidade iOS e permissão de rede

**Decision**: alvo mínimo iOS 17+, sem qualquer entrada de permissão em `Info.plist` para acesso
geral à internet.

**Rationale**: iOS não possui um equivalente à permissão `INTERNET` do Android — qualquer app pode
abrir conexões de rede por padrão, sujeito apenas a App Transport Security (ATS), que já exige
HTTPS por padrão e é satisfeito porque `supabaseUrl` é validado como HTTPS. Nenhuma exceção de ATS
é necessária. Fonte: [App Transport Security](https://developer.apple.com/documentation/security/preventing-insecure-network-connections).

**Alternatives considered**: declarar `NSAppTransportSecurity` com exceções, rejeitado porque o
endereço já é HTTPS e nenhuma exceção é necessária; elevar o alvo mínimo além de iOS 17+, rejeitado
por não ser exigido por `supabase-swift` nem pelo restante do projeto portado.

## 3. Origem, nomes e precedência da configuração

**Decision**: os nomes canônicos e case-sensitive continuam `supabaseUrl` e `supabaseKey`, agora
como User-Defined Build Settings do target Xcode, com o mesmo valor exposto em `Info.plist` via
`$(supabaseUrl)`/`$(supabaseKey)`. Um arquivo `Config/Secrets.xcconfig`, **não rastreado** (adicionado
ao `.gitignore` do projeto), define os valores localmente e é referenciado pelo `.xcconfig` base do
projeto (`#include? "Secrets.xcconfig"`, com `?` para não falhar quando o arquivo não existir ainda
em um clone novo). Em CI, os mesmos nomes são exportados como variáveis de ambiente e injetados via
`xcodebuild -xcconfig <arquivo gerado pelo CI>` ou substituição de build setting na invocação do
`xcodebuild`.

**Rationale**: `.xcconfig` é o mecanismo nativo do Xcode para valores de build externos ao código,
equivalente direto ao `local.properties`/`providers.gradleProperty` do Gradle — arquivo texto
simples, sem necessidade de plugin adicional, com precedência clara (build setting de linha de
comando > `.xcconfig` do target > `.xcconfig` incluído > default). Uma fonte superior presente,
ainda que em branco, deve falhar em vez de cair silenciosamente para outra credencial — mesma regra
do Android. Fontes: [Xcode Build Settings Reference](https://developer.apple.com/documentation/xcode/build-settings-reference),
[Adding a build configuration file to your project](https://developer.apple.com/documentation/xcode/adding-a-build-configuration-file-to-your-project).

**Alternatives considered**: valores hardcoded em `Info.plist` rastreado, rejeitado por segurança;
`ProcessInfo.processInfo.environment` lido em runtime, rejeitado porque não bloqueia o build (a
clarificação exige falha *durante* a preparação, não em runtime) e porque variáveis de ambiente de
execução não estão disponíveis de forma confiável ao processo do app instalado (diferente de um
script de CI); um arquivo `.plist` de segredos separado, rejeitado por duplicar o mecanismo que o
próprio `Info.plist` + `.xcconfig` já cobre nativamente.

## 4. Validação antecipada de URL e chave

**Decision**: validar ambos os valores em um Run Script Build Phase (`Scripts/validate-supabase-config.sh`,
rastreado, executado **antes** da fase de compilação), acumulando falhas e terminando com código de
saída diferente de zero (interrompendo o build) sem nunca ecoar o valor recebido. O script lê os
valores resolvidos das Build Settings via as variáveis de ambiente que o Xcode expõe automaticamente
a todo Run Script Phase (`${supabaseUrl}`/`${supabaseKey}`), aplica as mesmas regras do Android:

- `supabaseUrl`: `trim`, deve ser URI absoluta, não opaca, HTTPS, com host e sem user-info;
- `supabaseKey`: `trim`, allowlist idêntica —
  - aceitar `sb_publishable_` case-sensitive com sufixo ASCII não vazio;
  - rejeitar `sb_secret_` e formatos opacos desconhecidos;
  - para JWT legado, exigir três segmentos Base64URL, decodificar somente o payload (via `base64`
    do próprio shell, sem verificar assinatura) e aceitar apenas um claim `role` igual a `anon`;
  - rejeitar `service_role`, múltiplos roles, payload inválido ou qualquer outro papel.

**Rationale**: um Run Script Build Phase é o equivalente direto, no ecossistema Xcode, à validação
executada durante a configuração do módulo Gradle — roda antes de qualquer artefato ser gerado,
recebe as Build Settings já resolvidas (incluindo as vindas de `.xcconfig` ou de override de CI) e
pode abortar o build retornando um código de saída não-zero. Mesmo racional de segurança do Android:
Supabase classifica publishable/anon como client-safe e secret/service_role como credenciais
elevadas; a allowlist impede empacotar uma chave administrativa. Fonte: [Run Script Build Phases](https://developer.apple.com/documentation/xcode/customizing-the-build-schemes-for-a-project#Run-scripts-during-a-build),
[API keys do Supabase](https://supabase.com/docs/guides/getting-started/api-keys).

**Alternatives considered**: validar somente em runtime dentro do `SupabaseClientProvider` (via
`fatalError`/`precondition`), rejeitado porque não impede a geração do `.ipa`/arquivo de arquivo,
apenas trava o app ao abrir — a clarificação exige interromper o *build*; usar um plugin de Swift
Package (build tool plugin) para validar, rejeitado por adicionar superfície nova e complexidade
sem necessidade, quando um script de shell simples já resolve; buscar a substring `service_role` no
JWT bruto, rejeitado porque o payload está codificado, mesma razão do Android.

## 5. Geração dos valores para o código (equivalente ao BuildConfig)

**Decision**: expor `SUPABASE_URL` e `SUPABASE_KEY` no `Info.plist` do target, com valor
`$(supabaseUrl)`/`$(supabaseKey)` (o Xcode substitui a variável de build setting pelo valor
resolvido no momento do build). Em runtime, ler com
`Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String`. Não gerar um arquivo Swift
adicional (`Secrets.swift`) porque `Info.plist` já cumpre o mesmo papel do `BuildConfig` gerado pelo
Gradle: um valor resolvido em tempo de build, somente leitura em runtime, sem lógica.

**Rationale**: essa é a forma idiomática e amplamente documentada da Apple para propagar valores de
`.xcconfig` até o código em runtime, sem exigir geração de código nem scripts adicionais de
templating. Fontes: [Include a build setting value in Info.plist](https://developer.apple.com/documentation/xcode/build-settings-reference)
e [quickstart Swift](https://supabase.com/docs/guides/getting-started/quickstarts/swift).

**Alternatives considered**: gerar um `Secrets.swift` via script de pré-build, rejeitado por
duplicar o que `Info.plist` já resolve nativamente, introduzindo um artefato gerado adicional para
manter fora do Git; ler `ProcessInfo.processInfo.environment` diretamente em runtime, rejeitado pela
mesma razão da seção 3 (não confiável fora de um processo de CI).

## 6. Ownership do cliente e arquitetura

**Decision**: criar um `enum SupabaseClientProvider` (namespace sem instâncias) em
`Core/Network/SupabaseClientProvider.swift` com uma única propriedade `static let client:
SupabaseClient`, inicializada lendo os dois valores do `Info.plist` e chamando
`SupabaseClient(supabaseURL:supabaseKey:)`. Nenhum módulo de produto adicional é instalado e nenhuma
requisição é executada na inicialização. Futuras Views/ViewModels recebem o cliente por injeção
(parâmetro de `init`) ou o consultam por essa única fronteira nomeada; nenhuma View lê `Info.plist`
diretamente ou cria clientes próprios.

**Rationale**: `static let` em Swift é preguiçoso e thread-safe por definição da linguagem —
equivalente direto ao `by lazy {}` do Kotlin usado no `internal object SupabaseClientProvider` do
Android, sem exigir `DispatchOnce`, Singleton manual ou `@MainActor` (a criação do cliente não toca
UI). Um `enum` sem casos é o idioma Swift para "namespace utilitário sem instâncias", equivalente ao
`object` do Kotlin. Fonte: [Supabase Swift initializing](https://supabase.com/docs/reference/swift/initializing).

**Alternatives considered**: armazenar somente `String`s em constantes, rejeitado porque não entrega
integração pronta; criar o cliente dentro de uma View ou ViewModel específico, rejeitado por
multiplicar instâncias/engines; usar `@Observable`/`EnvironmentObject` para o cliente, rejeitado por
YAGNI — não há necessidade de reatividade para um valor que nunca muda após a criação; um
Swift Package local (DI container), rejeitado pela mesma razão do Android.

## 7. Logs, chave pública e validação

**Decision**: não instalar logging de rede nem emitir log de sucesso na criação do cliente. Erros do
script de validação citam apenas o nome do campo e a regra aceita, nunca o valor. Reconhecer
explicitamente que a chave publishable/anon é extraível de qualquer binário iOS decompilado e não é
segredo; a proteção dos dados depende de RLS no Supabase (compartilhado com o Android). Validar com
builds Debug/Release em simulador e dispositivo, casos negativos do Run Script, inspeção do
Git/logs, abertura offline e regressão dos fluxos existentes (Welcome → Home → RequestService),
sem testes automatizados — mesma decisão do Android e da governança atual do projeto.

**Rationale**: mesmo racional de segurança do Android; o objetivo é impedir chaves elevadas e
vazamento desnecessário, não fingir que uma chave de cliente é secreta.

**Alternatives considered**: mascarar e logar parte da chave, rejeitado por não agregar diagnóstico;
teste de conectividade na validação, rejeitado por misturar validade local com disponibilidade de
rede; testes automatizados (XCTest), rejeitados por falta de autorização explícita do usuário.

## Resolution status

Todas as decisões do Technical Context foram resolvidas; não restam `NEEDS CLARIFICATION`.

<!--
Sync Impact Report
- Version change: scaffold sem versão -> 1.0.0
- Origem: adaptada da Constitution 1.0.0 do PitGo Android (mesmo produto, stack iOS nativa)
- Modified principles:
  - scaffold principle 1 -> I. Simplicidade e entrega orientada ao requisito
  - scaffold principle 2 -> II. iOS nativo moderno com MVVM
  - scaffold principle 3 -> III. Estado previsível e experiência consistente
  - scaffold principle 4 -> IV. Dados, segurança e falhas explícitas
  - scaffold principle 5 -> V. Qualidade proporcional e evolução sustentável
- Added sections:
  - Restrições Técnicas e de Produto
  - Fluxo de Desenvolvimento e Qualidade
- Removed sections: nenhuma
- Follow-up TODOs: confirmar iOS mínimo suportado (assumido iOS 17+) quando o time definir a
  matriz de aparelhos alvo.
-->
# PitGo Constitution (iOS)

## Core Principles

### I. Simplicidade e entrega orientada ao requisito

Toda implementação DEVE resolver completamente o requisito atual pela solução mais simples,
moderna, segura e sustentável. Funcionalidade, experiência do usuário, legibilidade,
manutenção, segurança e performance DEVEM ser priorizadas, nessa ordem, antes de abstração.
KISS e YAGNI são obrigatórios: features futuras não solicitadas, infraestrutura sem uso,
camadas especulativas, boilerplate e abstrações prematuras NÃO DEVEM ser criados. DRY DEVE
eliminar duplicação relevante, mas uma duplicação pequena é preferível a uma abstração sem
responsabilidade clara.

Cada dependência (Swift Package), camada, pattern e arquivo DEVE ter uso atual demonstrável.
Entre soluções equivalentes, a de menor complexidade que preserve qualidade, segurança e
manutenção DEVE ser escolhida. Essa disciplina mantém o desenvolvimento rápido sem transformar
escalabilidade em overengineering.

### II. iOS nativo moderno com MVVM

O aplicativo DEVE usar Swift (versão estável mais recente disponível), SwiftUI, Swift Concurrency
(`async`/`await`, `Task`, `actor`), Swift Package Manager e as Human Interface Guidelines (HIG) da
Apple. O alvo mínimo assumido é **iOS 17+**; qualquer redução dessa versão mínima é uma decisão de
produto explícita, não uma escolha técnica silenciosa. O SDK oficial `supabase-swift` DEVE ser
usado para Auth, Postgrest, Realtime, Functions e Storage — o mesmo backend Supabase do app
Android é compartilhado, então nenhuma migração de schema, RPC ou Edge Function é feita por este
app; apenas o cliente muda. SwiftData PODE ser usado somente quando houver persistência local
necessária; `UserDefaults`/`@AppStorage` para preferências simples. Uma dependência externa só
PODE ser adicionada quando Swift, SwiftUI ou os frameworks da Apple não oferecerem solução
adequada e houver benefício claro e manutenção ativa (ex.: MapLibre Native iOS para manter o mesmo
provedor de mapa self-hosted já usado no Android, em vez de MapKit).

MVVM é a arquitetura oficial e DEVE seguir o fluxo View (SwiftUI) -> ViewModel
(`@Observable`/`ObservableObject`) -> Repository -> Data Source. Use Case PODE ser inserido entre
ViewModel e Repository somente quando encapsular lógica de negócio relevante; ele NÃO DEVE apenas
repassar chamadas. MVI, MVP, VIPER, Clean Architecture completa, múltiplas camadas sem
necessidade e arquiteturas híbridas NÃO DEVEM ser introduzidos. Injeção de dependência DEVE
permanecer simples — inicializadores e `@Environment`/`EnvironmentObject` bastam; frameworks de DI
com geração de código NÃO DEVEM ser adicionados sem necessidade demonstrada.

A organização DEVE ser por feature (grupos/pastas do Xcode espelhando o disco, sem depender de
`Groups` virtuais desalinhados do sistema de arquivos). Cada feature PODE conter apenas os grupos
necessários entre `Data`, `Model`, `Repository`, `Views` e `ViewModels`; recursos compartilhados
DEVEM possuir responsabilidade clara em áreas como `Core/Network`, `Core/Persistence`,
`Core/Navigation`, `Core/UI`, `Core/DesignSystem` ou `Core/Common`. Pacotes/grupos genéricos como
`Helpers`, `Managers`, `Utils` soltos e `Misc` NÃO DEVEM existir sem responsabilidade específica.

### III. Estado previsível e experiência consistente

As Views SwiftUI DEVEM apenas renderizar estado e emitir eventos (closures/bindings). Elas NÃO
DEVEM conter regra de negócio nem acessar API, banco ou Repository diretamente. ViewModels DEVEM
controlar o estado da tela, processar ações, aplicar regras de apresentação, chamar Repository ou
Use Case e representar loading, sucesso, erro e vazio quando aplicável. ViewModels NÃO DEVEM reter
`UIViewController`, `UIView` ou referências de navegação, salvo necessidade estrita documentada.

Estado de tela DEVE ser imutável, previsível e exposto preferencialmente via `@Observable` (ou
`@Published` em `ObservableObject` onde `@Observable` não se aplicar) e `AsyncStream`/
`AsyncSequence` para fluxos contínuos (equivalente ao uso de `StateFlow` no app Android — ex.:
status de despacho e de pagamento via Supabase Realtime). Estados mutuamente exclusivos DEVEM ser
modelados por um único `enum` explícito (associated values quando necessário) em vez de vários
`Bool` independentes. Views DEVEM ser pequenas, previsíveis, preferencialmente sem estado próprio
além do estritamente local de UI, usar state hoisting (bindings vindos do ViewModel) e delegar
lógica de negócio ao ViewModel.

A interface DEVE usar componentes nativos do SwiftUI sempre que atendam ao requisito
(`NavigationStack`, `TabView`, `List`, `Button`, `TextField`, `.sheet`, `.alert`,
`.confirmationDialog`, `Form`) e um design system centralizado para cores, tipografia, formas,
espaçamento, componentes, ícones (SF Symbols preferencialmente) e elevação/sombra. Um componente
compartilhado só DEVE ser criado quando houver reutilização real. Cada tela DEVE apresentar
hierarquia clara, ação principal identificável, navegação simples, feedback imediato, mensagens
compreensíveis e o menor número razoável de interações.

O tema claro DEVE usar roxo como cor de destaque (`accentColor`), fundo e superfícies
predominantemente brancos, texto primário preto e texto secundário cinza-escuro. O tema escuro
DEVE usar roxo como cor de destaque, fundo preto, superfícies próximas ao preto, texto primário
branco e texto secundário cinza-claro; ele NÃO DEVE ser mera inversão automática do sistema. O
aplicativo DEVE oferecer Claro, Escuro e Padrão do sistema, respeitar `colorScheme` do sistema por
padrão e persistir seleção manual (`UserDefaults`/`@AppStorage`).

Telas DEVEM ser responsivas nos tamanhos e classes de tamanho suportados (iPhone e iPad, quando
aplicável), usar unidades e `Dynamic Type` em vez de tamanhos fixos, e respeitar `size classes`
(`horizontalSizeClass`/`verticalSizeClass`) quando o layout exigir. Conteúdo DEVE suportar aumento
de fonte (Dynamic Type), contraste adequado, áreas de toque mínimas (44x44pt, conforme a HIG),
labels compreensíveis e `accessibilityLabel`/`accessibilityHint` quando aplicável; informação NÃO
DEVE depender apenas de cor.

### IV. Dados, segurança e falhas explícitas

Repositories DEVEM centralizar APIs, banco local, cache e serviços externos. Modelos de API,
domínio e UI só DEVEM ser separados quando a separação trouxer benefício real; mapeamentos
redundantes NÃO DEVEM ser criados. Swift Concurrency DEVE executar operações assíncronas
respeitando o ciclo de vida da View/ViewModel, com `Task` escopada ao `ViewModel`/View (cancelada
em `deinit`/`.task` do SwiftUI conforme apropriado); `DispatchQueue` manual, `Thread` cru e
completion handlers aninhados NÃO DEVEM ser usados onde `async`/`await` resolve com mais clareza.

Comunicação de rede DEVE distinguir loading, sucesso, erro HTTP, timeout, ausência de internet,
erro de servidor e erro desconhecido quando aplicável. Erros DEVEM ser classificados
(`enum: Error`) e tratados de forma centralizada quando isso reduzir repetição. A UI NÃO DEVE
expor detalhes técnicos e DEVE apresentar mensagens acionáveis. Entradas como telefone, e-mail,
CPF/CNPJ, endereço, valores, datas e horários DEVEM ser validadas localmente antes do envio quando
possível, sem substituir a validação definitiva do backend.

Secrets, service role keys, tokens administrativos, senhas, chaves privadas e credenciais de
infraestrutura NÃO DEVEM ser incluídos no aplicativo. Informações sensíveis NÃO DEVEM aparecer em
logs (`Logger`/`print`). Tokens de autenticação e outros segredos locais (quando existirem) DEVEM
usar o **Keychain**, nunca `UserDefaults`; dados recebidos do backend DEVEM ser tratados como não
confiáveis até validação. O estado de autenticação DEVE ser centralizado e cobrir login, logout,
sessão expirada, renovação de token e usuário não autenticado; cada tela NÃO DEVE implementar sua
própria verificação manual.

Estados relevantes do marketplace on-demand DEVEM ser tipos explícitos (`enum`), e NÃO textos
arbitrários. O fluxo de solicitação, disponibilidade, aceite, execução, conclusão, pagamento,
cancelamento e avaliação DEVE preservar transições válidas entre estados como `PENDING`,
`ACCEPTED`, `IN_PROGRESS`, `COMPLETED` e `CANCELLED` — os mesmos nomes e transições já definidos
pelo backend Supabase compartilhado com o app Android, nunca uma nomenclatura paralela do lado
iOS. Somente entidades exigidas pela funcionalidade atual entre User, Provider, Company, Service,
Product, Category, Order, Booking, Address, Payment, Review, Favorite e Notification DEVEM ser
criadas.

Quando localização for necessária, permissões (`CLLocationManager`, `NSLocationWhenInUseUsageDescription`)
DEVEM ser solicitadas no momento de uso, com tratamento de recusa, indisponibilidade, localização
desativada e precisão adequada. A ausência de localização NÃO DEVE bloquear todo o aplicativo
quando ela não for essencial ao fluxo.

### V. Qualidade proporcional e evolução sustentável

Código DEVE ter nomes claros, funções pequenas, responsabilidade única, alta coesão e baixo
acoplamento. Comentários DEVEM explicar por que uma decisão existe, não narrar código. Patterns
como Repository, Factory, Strategy, Adapter, Observer e injeção de dependência simples só PODEM
ser adotados quando reduzirem complexidade real.

Testes unitários (XCTest), de UI (XCTest UI/`XCUIApplication`), mocks, fixtures e utilitários de
teste NÃO DEVEM ser gerados automaticamente. Eles só DEVEM ser implementados quando forem
explicitamente solicitados; nessa situação, lógica de negócio relevante e ViewModels têm
prioridade. A ausência de testes não solicitados NÃO DEVE bloquear a entrega de uma feature.

Código gerado DEVE compilar, ser necessário, seguir o padrão existente e estar integrado ao fluxo.
Placeholders, TODOs desnecessários, arquivos vazios e classes/structs sem uso NÃO DEVEM ser
adicionados. Mudanças DEVEM preservar comportamento funcional fora do escopo, evitar grandes
refatorações não relacionadas e remover código obsoleto diretamente relacionado somente quando for
seguro.

Performance DEVE evitar recomputação desnecessária de `body` em SwiftUI, chamadas de API
repetidas, trabalho pesado na main thread/`@MainActor`, cópias excessivas de valor durante
recomposição de View e carregamento de imagens maior que o necessário. Listas extensas DEVEM usar
`List`/`LazyVStack`/`LazyHStack` e paginação quando o volume justificar. Imagens remotas DEVEM ter
carregamento assíncrono, cache, placeholder, loading, erro e fallback; `AsyncImage` nativo DEVE ser
preferido, com uma biblioteca de cache (ex.: Nuke) só quando `AsyncImage` comprovadamente não
atender.

## Restrições Técnicas e de Produto

- O produto é um marketplace on-demand iOS nativo que conecta usuários a prestadores,
  estabelecimentos, produtos ou serviços sob demanda — mesma plataforma de produto do app Android,
  backend Supabase compartilhado.
- `NavigationStack` (ou `NavigationSplitView` em iPad quando aplicável) DEVE ser usado. Rotas DEVEM
  ser centralizadas (`enum`/`Hashable` de destino) e não strings dispersas; os fluxos relevantes
  entre Splash, Onboarding, Login, Home, Search, Details, Checkout, Orders e Profile DEVEM
  respeitar corretamente a navegação de voltar (gesto de borda e botão nativo).
- As Human Interface Guidelines vigentes DEVEM ser seguidas. Componentes oficiais do SwiftUI como
  `NavigationStack`, `.toolbar`, `TabView`, `List`, `Button`, `TextField`, `.alert`, `.sheet`,
  `.confirmationDialog` e `ProgressView` NÃO DEVEM ser recriados manualmente sem necessidade
  demonstrável.
- Valores visuais duplicados diretamente em Views DEVEM ser movidos ao design system quando forem
  tokens compartilhados (cores, espaçamento, tipografia). Abstrações visuais de uso único NÃO
  DEVEM ser criadas sem outra razão.
- SwiftData/Core Data e persistência local só DEVEM existir quando houver requisito atual.
  Preferências simples, inclusive tema manual, DEVEM usar `UserDefaults`/`@AppStorage`.
- Logs DEVEM ser úteis e proporcionais ao ambiente (`Logger` do `os` framework, com níveis
  apropriados). Senhas, tokens, cartões, documentos completos e dados confidenciais NÃO DEVEM ser
  registrados; logs excessivos NÃO DEVEM permanecer em produção.
- Segurança e privacidade são requisitos funcionais: dados sensíveis, permissões (`Info.plist`
  `NSUsageDescription`) e respostas de backend DEVEM receber tratamento explícito no design e na
  implementação.
- Segredos de build (URL/chave pública do Supabase, chaves públicas de SDKs de terceiros como o
  Mercado Pago) DEVEM vir de configuração de build não versionada (`.xcconfig` local ou variáveis
  de ambiente do CI), nunca hardcoded; chaves privadas/Access Tokens NUNCA pertencem ao app,
  apenas às Edge Functions do Supabase compartilhado com o Android.

## Fluxo de Desenvolvimento e Qualidade

Para cada nova feature, a implementação DEVE:

1. confirmar o fluxo e o requisito atual;
2. localizar a feature responsável;
3. criar somente componentes necessários;
4. implementar View (SwiftUI) e ViewModel;
5. adicionar Repository apenas quando houver acesso a dados;
6. integrar API (Supabase) ou persistência somente quando requerido;
7. representar loading, erro, vazio e sucesso quando aplicável;
8. integrar navegação e verificar o fluxo completo;
9. não gerar documentação extensa nem testes sem solicitação explícita.

Refatorações DEVEM declarar objetivo ligado ao escopo, preservar comportamento existente e
reutilizar estruturas adequadas. Dependências novas (Swift Packages) DEVEM ser justificadas pela
ausência de solução nativa/Apple adequada, redução verificável de complexidade, manutenção ativa e
benefício atual.

Toda revisão de mudança DEVE verificar, conforme o risco: compilação (`xcodebuild build`), fluxo
funcional, estados de UI, tratamento de falhas, acessibilidade, segurança, performance e ausência
de complexidade especulativa. Exceções a esta constituição DEVEM conter justificativa explícita no
artefato de planejamento ou revisão correspondente.

Commits DEVEM ser pequenos e representar uma mudança lógica. Mensagens DEVEM ser descritivas,
preferencialmente no formato `feat:`, `fix:`, `refactor:`, `style:` ou `chore:`; mensagens genéricas
como `update`, `changes`, `fix`, `teste` ou `alterações` NÃO DEVEM ser usadas isoladamente.

## Governance

Esta constituição prevalece sobre práticas, templates e decisões conflitantes do projeto. Toda
spec, plano, tarefa, implementação e revisão DEVE comprovar conformidade proporcional ao seu
escopo. Complexidade adicional DEVE ser justificada por requisito concreto; caso contrário, DEVE
ser removida do plano ou da mudança.

Emendas DEVEM ser propostas com motivação, impacto, itens afetados e eventual plano de migração.
Uma emenda só entra em vigor após aprovação explícita dos responsáveis pelo projeto e atualização
deste documento. A data de última alteração DEVE refletir a adoção da emenda.

O versionamento segue SemVer para governança: MAJOR para remoções ou redefinições incompatíveis de
princípios; MINOR para princípio ou seção nova e para expansão material de orientação; PATCH para
clareza, correção ou refinamento sem mudança normativa. Revisões DEVEM conferir se a versão e o
Sync Impact Report correspondem à alteração.

Conformidade DEVE ser revista durante especificação, planejamento e revisão de código. Violações
conhecidas DEVEM ser corrigidas antes da conclusão ou registradas como exceção aprovada, com razão,
responsável e prazo. A constituição DEVE ser reavaliada quando decisões arquiteturais ou de produto
alterarem seus pressupostos — em particular, quando o iOS mínimo suportado mudar.

**Version**: 1.0.0 | **Ratified**: 2026-09-12 | **Last Amended**: 2026-09-12

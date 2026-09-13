# Contract: Validação de build da configuração do mapa (iOS)

Esta feature **implementa** o gate de build que `specs/010-osm-realtime-map/contracts/
maplibre-style-runtime.md` (seção "Build boundary" / "Falhas obrigatórias") já especificava, mas
que nunca foi codificado (ver `research.md` §0). A grammar de validação em si **não muda** — só
passa a ser efetivamente aplicada. Este contrato descreve exclusivamente a parte nova: onde e como
a validação roda.

## Onde roda

Uma única Run Script Build Phase, a mesma já existente no alvo `pitgo`
(`Scripts/validate-supabase-config.sh`, executa antes de "Compile Sources"). Nenhuma phase nova é
criada. O script ganha uma segunda seção/função de validação, chamada em sequência após a validação
do Supabase já existente — mesma estrutura de duas funções no mesmo arquivo já usada pelo
`app/build.gradle.kts` do Android (`validateSupabaseConfiguration` +
`validateMapStyleConfiguration`).

## O que valida

Os quatro campos de `data-model.md` (`mapStyleUrl`, `mapStyleProviderName`, `mapStyleAttribution`,
`mapStyleAttributionUrl`), expostos como variáveis de ambiente pelo Xcode a partir das Build
Settings de mesmo nome (mecanismo idêntico ao já usado para `supabaseUrl`/`supabaseKey`). A grammar
completa está em `data-model.md` desta feature (copiada de `010`, não alterada).

## Contrato de falha

- Falha com código de saída != 0, interrompendo o build antes de "Compile Sources".
- A mensagem cita o **nome do campo** e a **regra violada**, nunca o valor recebido — mesmo padrão
  de `fail()` já usado no script para os campos do Supabase.
- Uma fonte de maior precedência inválida (`Config/Secrets.xcconfig`) não cai silenciosamente para
  o default de `Config/Shared.xcconfig` — se `Secrets.xcconfig` define um valor, é esse valor
  (válido ou não) que é validado.
- A ausência total de `Config/Secrets.xcconfig` (clone novo, CI sem override) faz os quatro campos
  resolverem para os defaults de avaliação de `Config/Shared.xcconfig` — que **são** um host demo
  conhecido — então o build falha nesse cenário também, a menos que um override real seja fornecido
  via `-xcconfig` ou Build Settings de CI. Isso é intencional: não deve existir build "de produção"
  que compile silenciosamente com o estilo de demonstração.

## O que não muda

- `ManagedMapStyleConfiguration.swift` continua com o fallback defensivo em runtime
  (`evaluationFallback`) — ele deixa de ser alcançável em qualquer build que passe pela validação
  acima, mas permanece como rede de segurança para o caso (não esperado) de o `Info.plist` não
  refletir os Build Settings por algum outro motivo. Não é o mecanismo que satisfaz FR-003 — o
  script é.
- Nenhuma outra Build Setting, target ou scheme é alterado.

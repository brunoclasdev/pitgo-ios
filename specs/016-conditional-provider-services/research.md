# Research: Seleção de serviços condicionada à modalidade do prestador (iOS)

## 0. Nenhum backend novo

**Decision**: nenhuma migration ou mudança de RPC — `services.dispatch_kind`
(`.browse`/`.mobileSequential`/`.pittecAutoSequential`, já decodificado desde `009`/`013`/`015`) e
`create_provider_registration` (`007`/`009`) já existem e são compartilhados com o Android. Esta
feature é inteiramente client-side.

## 1. Como identificar o serviço implícito de Móvel/PitTec sem depender do nome

**Decision**: identificar o serviço implícito de cada modalidade pelo `dispatchKind` já lido pelo
catálogo de cadastro (`ServiceCatalogRepository`, `009`) — `.mobileSequential` para Móvel,
`.pittecAutoSequential` para PitTec — em vez de comparar pelo nome ("Guincho"/"PitTec").

**Rationale**: idêntico ao racional do Android — `dispatchKind` já é a distinção de negócio real
usada em todo o app iOS (catálogo da Home, despacho automático desde `009`/`013`/`015); é resiliente
a renomeações do serviço no catálogo. O campo já é lido pela mesma consulta do catálogo de cadastro
(`007`); não exige nenhuma migração, apenas expor o campo já existente no modelo Swift.

**Alternatives considered**: idênticas ao Android — comparar por nome exato (rejeitado, frágil a
acentuação/tradução); criar uma coluna nova exclusiva para "serviço implícito de cadastro"
(rejeitado, duplicaria uma distinção que `dispatchKind` já expressa).

## 2. Onde resolver o serviço implícito e como validá-lo

**Decision**: adicionar um método dedicado em `ProviderRegistrationRepository` (`007`/`009`) que
busca até 2 serviços ativos com um `dispatchKind` específico, distinguindo três resultados:
exatamente um (uso normal), nenhum (catálogo sem esse serviço) e mais de um (catálogo duplicado) —
os dois últimos bloqueiam o envio do cadastro com uma falha compreensível
(`.catalogChanged`, já existente desde `007`), sem exigir constraint nova no banco.

**Rationale**: idêntico ao racional do Android — mantém a regra de unicidade como verificação de
leitura no momento do cadastro, sem introduzir uma constraint de banco nova para um cenário já
improvável e administrado por quem mantém o catálogo.

**Alternatives considered**: idênticas ao Android — confiar cegamente no primeiro resultado sem
checar duplicidade (rejeitado, mascararia um catálogo mal configurado); adicionar constraint de
unicidade parcial em `services` (rejeitado, mudança de banco desproporcional ao requisito atual).

## 3. Como reaproveitar o formulário de oferta existente para Móvel

**Decision**: continuar usando a mesma estrutura de rascunho (`OfferDraft`, `007`) e a mesma
validação já existentes (`ProviderRegistrationValidation`); ao selecionar a modalidade `.mobile`, o
`ProviderRegistrationViewModel` substitui `offers` por uma única oferta pré-vinculada ao serviço
"Guincho" resolvido (categoria e serviço já preenchidos e não editáveis na View), mantendo preço e
duração como os únicos campos que a View mostra e que o prestador ainda preenche.

**Rationale**: idêntico ao racional do Android — reaproveita 100% da validação de preço/duração e
do envio já existentes (nenhuma mudança em `ProviderRegistrationValidation` nem no payload da RPC);
a View apenas deixa de renderizar os seletores de categoria/serviço para essa oferta.

**Alternatives considered**: idêntica ao Android — criar um formulário de submissão paralelo
específico para Móvel/PitTec fora do fluxo de `OfferDraft`/validação atual (rejeitado, duplicaria
validação sem necessidade).

## 4. Como tratar PitTec sem nenhum campo de preço

**Decision**: ao selecionar a modalidade `.pittec`, o ViewModel substitui `offers` por uma única
oferta pré-vinculada ao serviço "PitTec" resolvido, já marcada como gratuita (`isFree = true`, preço
zero) e com uma duração padrão interna (não editável, não exibida). A View não renderiza nenhum
campo de oferta para essa modalidade.

**Rationale**: idêntico ao racional do Android — consistente com a clarificação já registrada no
spec: o valor cobrado pelo PitTec (fixo + variável por distância) é definido centralmente pela
plataforma (`015`), não pelo prestador nem por oferta de catálogo; `provider_services.price` não
representa esse valor e não deve ser exposto/preenchido manualmente. A duração é apenas um dado
técnico exigido pelo contrato de envio já existente; um valor padrão interno satisfaz a validação
sem significado de negócio para o cliente.

**Alternatives considered**: idêntica ao Android — alterar `create_provider_registration` para
aceitar ofertas sem preço/duração quando o serviço for PitTec (rejeitado, exigiria migração para um
requisito que o app já resolve sem mudança de contrato).

## 5. Impacto em código já existente

**Decision**: nenhuma mudança de backend. Todas as mudanças ficam no client iOS: modelo do catálogo
de cadastro (expor `dispatchKind`, já decodificado desde `009`), `ProviderRegistrationViewModel`
(gestão do rascunho de ofertas por modalidade) e `ProviderRegistrationView` (ocultar/mostrar a
seção de oferta).

**Rationale**: idêntico ao racional do Android — a tabela `services` já expõe `dispatch_kind`; a
RPC já aceita qualquer oferta válida independentemente da modalidade do prestador. O requisito é
inteiramente sobre o que a View pede e o que o ViewModel monta antes de enviar.

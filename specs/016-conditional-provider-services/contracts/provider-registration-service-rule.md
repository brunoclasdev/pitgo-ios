# Contract: Resolução do serviço implícito no cadastro de prestador (iOS)

Esta feature não expõe nenhuma API nova ao backend. O único contrato relevante é a leitura
estendida do catálogo (campo adicional já decodificado) e a garantia de que o envio final à RPC
existente continua igual. Documentado aqui para deixar explícito o que a implementação iOS pode/deve
assumir.

## Leitura do catálogo (estendida, campo já decodificado desde `009`)

Consulta direta à tabela `public.services` (sem RPC), já usada pelo cadastro (`007`).

### Antes (`007`)

Campos lidos: `id`, `categoryID`, `name`, `description`.

### Depois

Campos lidos: `id`, `categoryID`, `name`, `description`, `dispatchKind`.

Nenhuma mudança de RLS ou de coluna no banco — `dispatch_kind` já existe e já é legível pelo mesmo
papel que hoje lê `name`/`description` nesta consulta.

## Resolução do serviço implícito de uma modalidade

Entrada: `dispatchKind` alvo (`.mobileSequential` para Móvel, `.pittecAutoSequential` para PitTec).

Regra:

1. Buscar até 2 serviços ativos com esse `dispatchKind`.
2. Se exatamente 1 for encontrado: esse é o serviço implícito da modalidade (`.found`).
3. Se 0 forem encontrados: a modalidade não pode ser usada para cadastro nesta instalação —
   cadastro bloqueado com falha compreensível (`.missing`).
4. Se 2 ou mais forem encontrados: catálogo está em estado inconsistente para essa modalidade —
   cadastro bloqueado com falha compreensível, sem tentar adivinhar qual usar (`.duplicated`).

Esta resolução roda ao selecionar a modalidade `.mobile`/`.pittec` (e novamente, silenciosamente,
antes do envio) — nunca ao selecionar `.fixed`.

## Envio do cadastro (`create_provider_registration`) — inalterado

O RPC e seu contrato de entrada/saída não mudam. O que muda é apenas como o array de ofertas
(`p_offers`) é montado no app iOS antes da chamada:

| Modalidade | Como a oferta enviada é montada |
|---|---|
| `.fixed` | como hoje: uma ou mais ofertas escolhidas manualmente pelo prestador |
| `.mobile` | uma oferta com o `serviceID` do serviço implícito resolvido; `price`/`durationMinutes` vêm do que o prestador digitou; `isFree` conforme o prestador marcar |
| `.pittec` | uma oferta com o `serviceID` do serviço implícito resolvido; `price = 0`, `isFree = true`, `durationMinutes` com um valor padrão interno (não exibido, sem significado de cobrança) |

Todas as validações de formato já existentes na RPC (categoria/serviço ativos, duração entre 1 e
10080 minutos, preço coerente com `isFree`) continuam se aplicando sem exceção — a oferta montada
automaticamente para Móvel/PitTec já é construída para satisfazê-las.

## Erros

Nenhum código de erro novo é necessário. O bloqueio por serviço implícito ausente/duplicado é
tratado inteiramente no app antes de chamar a RPC, reaproveitando a mensagem de "catálogo
indisponível/alterado" já usada pelo cadastro para outras inconsistências de catálogo
(`ProviderRegistrationFailureReason.catalogChanged`, `007`).

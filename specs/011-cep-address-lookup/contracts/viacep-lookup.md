# Contract: Consulta ViaCEP (iOS)

## Escopo

Este contrato define a única operação externa adicionada pela feature. Ela consulta um endereço
para assistir o preenchimento do rascunho; não autentica, não persiste dados e não valida posse ou
localização geográfica.

## Operação

```http
GET https://viacep.com.br/ws/{postalCode}/json/
Accept: application/json
```

Chamada via `URLSession` nativo:

```swift
let (data, response) = try await urlSession.data(for: request)
```

### Pré-condições

- `postalCode` contém exatamente oito caracteres ASCII entre `0` e `9`;
- host, scheme e caminho base são constantes do app;
- nenhum query parameter, body, cookie ou header de autenticação é enviado;
- valor inválido é rejeitado localmente e não chega à rede;
- existe no máximo uma `Task` ativa por ViewModel.

## Resposta encontrada

Campos consumidos:

```json
{
  "cep": "01001-000",
  "logradouro": "Praça da Sé",
  "complemento": "lado ímpar",
  "bairro": "Sé",
  "localidade": "São Paulo",
  "uf": "SP"
}
```

Mapeamento:

| ViaCEP | Domínio | Formulário |
|---|---|---|
| `cep` | `postalCode` normalizado | CEP |
| `logradouro` | `street` | Rua |
| `complemento` | `complement` | Complemento |
| `bairro` | `neighborhood` | Bairro |
| `localidade` | `city` | Cidade |
| `uf` | `state` | UF |

`cep`, cidade e UF válidos são obrigatórios para aceitar a resposta. Rua, complemento e bairro
vazios viram `nil` e não substituem valor manual. Campos desconhecidos são ignorados pelo
`JSONDecoder`. Número nunca é lido ou escrito por esta operação.

## CEP inexistente

O endpoint retorna HTTP 200 com um campo `erro` verdadeiro. O `Decodable` customizado aceita as
formas observadas e compatíveis:

```json
{ "erro": "true" }
```

```json
{ "erro": true }
```

Ambas produzem `.notFound`. Outros valores não são tratados como inexistência automaticamente; o
restante do contrato ainda precisa ser válido.

## Compatibilidade e confiança

Uma resposta 2xx só produz `.found` quando: (1) o JSON é decodificável; (2) `erro` não é verdadeiro;
(3) o CEP retornado normalizado é idêntico ao solicitado; (4) cidade não está vazia; (5) UF pertence
à allowlist brasileira. Se uma condição falhar, o resultado é `.unexpectedResponse` e nenhum dado do
rascunho muda.

## Status e falhas

| Sinal | Resultado |
|---|---|
| 200 + contrato válido | `.found` |
| 200 + `erro=true` | `.notFound` |
| `URLError.timedOut`, 408 ou 504 | `.failure(.timeout)` |
| `URLError.notConnectedToInternet`/`.cannotFindHost`/`.cannotConnectToHost` | `.failure(.offline)` |
| 429, 500–599 ou conexão transitória interrompida | `.failure(.serviceUnavailable)` |
| 400 ou outro status/contrato/JSON/TLS inesperado | `.failure(.unexpectedResponse)` |
| cancelamento da `Task` | relançar `CancellationError`; não produzir resultado de UI |

Timeouts do cliente: `timeoutIntervalForRequest`/`timeoutIntervalForResource` = 2,5s (ver
`research.md §4`).

Não existe retry automático. A nova chamada depende da ação "Buscar CEP"/"Tentar novamente".

## Privacidade e observabilidade

- `URLSession` dedicada (`.ephemeral`), sem plugin Auth ou sessão Supabase;
- somente CEP no path e metadados normais da conexão HTTP;
- sem logging HTTP, corpo, resposta, URL completa ou `Error` bruto;
- sem cache persistente (`URLCache.shared` não é usado para esta sessão);
- nenhum token, CNPJ, e-mail, telefone, número residencial ou endereço parcial;
- erros expostos à UI pertencem somente ao `enum` fechado de domínio.

## Ausências explícitas

- busca por rua/cidade/UF;
- geocodificação;
- proxy Supabase;
- API key;
- persistência ou alteração do endereço remoto;
- prefetch, consulta automática e batch de CEPs.

Fonte do contrato externo: [ViaCEP](https://viacep.com.br/).

# Data Model: Seleção de serviços condicionada à modalidade do prestador (iOS)

## Convenções

Nenhuma tabela nova e nenhuma migration são necessárias; este documento descreve apenas os campos
adicionais que o client iOS passa a ler/derivar a partir de dados já existentes. `dispatch_kind` já
existe em `public.services` e já é a fonte de verdade para outras partes do app iOS (catálogo da
Home, despacho automático, `009`/`013`/`015`).

## Entidades existentes lidas de forma nova

### `CatalogService` (leitura de cadastro, `007`/`009`)

```swift
struct CatalogService: Decodable {
    let id: UUID
    let categoryID: UUID
    let name: String
    let description: String?
    let dispatchKind: ServiceDispatchKind   // já decodificado desde 009; agora também consumido aqui
}
```

Nenhuma outra View além do cadastro de prestador precisa desse campo adicional; ele já é lido
normalmente pela mesma consulta existente.

### `ProviderRegistrationDraft`/`OfferDraft` (estado de View, não persistido, `007`)

Estrutura já existente, reaproveitada sem novos campos. Mudança é de **comportamento**, não de
forma:

| Modalidade | Ofertas no rascunho ao selecionar a modalidade |
|---|---|
| `.fixed` | lista de ofertas controlada manualmente pelo prestador (uma vazia inicialmente, podendo adicionar mais); categoria, serviço, preço, duração e descrição continuam editáveis |
| `.mobile` | exatamente uma oferta, com categoria e serviço travados no serviço de `dispatchKind == .mobileSequential` resolvido; apenas preço e duração continuam editáveis |
| `.pittec` | exatamente uma oferta, com categoria e serviço travados no serviço de `dispatchKind == .pittecAutoSequential` resolvido, preço zero, `isFree = true` e duração padrão interna; nenhum campo de oferta é editável ou exibido |

Trocar a modalidade durante o preenchimento substitui `offers` pela combinação acima; não há
mesclagem entre o que foi preenchido para uma modalidade e o que vale para outra.

### Oferta enviada ao backend (`create_provider_registration`, inalterada)

Sem mudança de forma. Continua exigindo `serviceID`, `price`, `durationMinutes`, `isFree`,
`description?`. Para Móvel e PitTec, esses valores agora são montados automaticamente pelo
ViewModel em vez de digitados pelo prestador (exceto preço/duração de Móvel, que continuam vindo do
prestador).

## Resultado de resolução do serviço implícito (novo, em memória)

Não é uma entidade persistida; representa o resultado de localizar o serviço de uma modalidade pelo
`dispatchKind`.

```swift
enum ImplicitServiceResolution {
    case found(CatalogService)
    case missing        // catálogo sem o serviço dessa modalidade
    case duplicated      // catálogo com mais de um serviço para o mesmo dispatchKind
}
```

`.missing`/`.duplicated` bloqueiam o envio do cadastro com `.catalogChanged` (falha já existente
desde `007`).

## Regras de validação (inalteradas, apenas reafirmadas)

- `.fixed`: pelo menos uma oferta válida é obrigatória para envio (`ProviderField.offers = .required`
  se vazio) — comportamento já existente, preservado.
- `.mobile`/`.pittec`: a oferta implícita sempre está presente no rascunho antes do envio (nunca
  vazia), então a validação de "pelo menos uma oferta" já passa sem mudança de código na validação.
- Duplicidade de serviço por prestador (`provider_services_provider_service_unique`, backend
  inalterado) continua válida e inatingível nestes fluxos, já que cada modalidade produz no máximo
  uma oferta.

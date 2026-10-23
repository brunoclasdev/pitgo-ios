# Contract: Seleção de serviços no cadastro do prestador (herdado do backend compartilhado)

Mesmo contrato já vigente no backend Supabase compartilhado (`eetbrkznuqbdrnybnyhf`), descrito em
`../../../../android/pitgo/specs/026-service-catalog-map-card/contracts/provider-service-selection.md`.
Reproduzido aqui apenas para referência do cliente iOS — nenhuma RPC é criada ou alterada por este
porte.

## Read flow

1. App carrega categorias ativas (`ServiceCatalogRepository`/`ProviderRegistrationRepository`).
2. Prestador `FIXED` seleciona uma categoria principal (`primaryCategoryID` do rascunho).
3. App carrega serviços ativos dessa categoria e permite selecionar vários.
4. Cada oferta selecionada recebe preço, duração, descrição e regra de gratuidade já existentes.

Móvel e PitTec mantêm a resolução implícita existente e não exibem seleção manual nem categoria.

## Registration payload (já implementado em `ProviderRegistrationDTOs.swift`)

```json
{
  "p_provider": {},
  "p_address": {},
  "p_offers": [
    {
      "service_id": "uuid",
      "price": "100.00",
      "duration_minutes": 60,
      "description": "opcional",
      "is_free": false
    }
  ]
}
```

Nenhum `category_id` é enviado por oferta — o backend resolve a categoria a partir do `service_id`.

## Server validation

O RPC `create_provider_registration` rejeita payload sem ofertas para `FIXED`, duplicado, serviço
inexistente/inativo, categoria inativa ou oferta incompatível com a modalidade, retornando erros já
classificados por `ProviderRegistrationRepository.classify(_:)` (`DUPLICATE_SERVICE`,
`CATALOG_CHANGED` etc.).

## Troca de categoria e compatibilidade (comportamento de cliente — novo neste porte)

A categoria principal pertence ao rascunho `FIXED`; todas as ofertas a herdam. Trocar uma categoria
já selecionada com ofertas preenchidas exige confirmação explícita
(`ProviderRegistrationViewModel.selectPrimaryCategory`/`confirmPrimaryCategoryChange`/
`cancelPrimaryCategoryChange`); confirmar substitui as ofertas por uma oferta vazia da nova
categoria, descartando preços, durações e descrições anteriores. Cancelar conserva o rascunho.

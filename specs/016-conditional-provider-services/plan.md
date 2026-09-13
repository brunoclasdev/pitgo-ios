# Implementation Plan: Seleção de serviços condicionada à modalidade do prestador (iOS)

**Branch**: `016-conditional-provider-services` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/016-conditional-provider-services/spec.md`

## Summary

Ao cadastrar um prestador, a etapa de escolha de serviço no catálogo passa a depender da
modalidade: Fixo continua exigindo a escolha manual de pelo menos um serviço; Móvel (Guincho) e
PitTec deixam de exibir essa etapa, pois cada um tem um único serviço implícito no catálogo
(`dispatchKind = .mobileSequential`/`.pittecAutoSequential`, já decodificado desde `009`),
atribuído automaticamente. Móvel continua coletando preço/duração do prestador para esse serviço
implícito; PitTec não coleta preço nem duração, pois seu valor é definido centralmente pela
plataforma (`015`). A implementação é inteiramente no client iOS — nenhuma migration ou mudança de
RPC é necessária.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: `supabase-swift` (`PostgREST`, já habilitado desde `004`). Nenhuma
dependência nova.

**Storage**: PostgreSQL gerenciado pelo Supabase (backend compartilhado, inalterado); nenhuma
tabela ou coluna nova — leitura estendida de `public.services.dispatch_kind`, já existente

**Testing**: validação manual orientada por cenários (`quickstart.md`), build via `xcodebuild`;
nenhum teste automatizado, conforme a governança do projeto

**Target Platform**: iOS 17+, iPhone e iPad

**Project Type**: aplicativo iOS nativo de módulo único; funcionalidade inteiramente client-side

**Performance Goals**: resolução do serviço implícito de Móvel/PitTec completa dentro do tempo já
aceitável de carregamento do catálogo de cadastro; nenhum requisito de performance novo

**Constraints**: nenhuma migration; nenhuma mudança de contrato na RPC
`create_provider_registration`; comportamento de Fixo não pode regredir; comportamento de Guincho/
PitTec já especificado (`013`/`015`) não pode ser afetado

**Scale/Scope**: um fluxo existente (`ProviderRegistrationView`, `007`) ajustado; três modalidades;
nenhuma View nova, nenhuma rota nova

## Constitution Check

*GATE inicial e pós-design: aprovado sem exceções.*

- **Simplicidade/YAGNI — PASS**: resolve exatamente a regra pedida, sem infraestrutura nova;
  nenhuma migration, RPC nova ou abstração especulativa; reaproveita 100% da validação/envio já
  especificados em `007`.
- **iOS nativo/MVVM — PASS**: mudança fica em Model/DTO, ViewModel e View já existentes de
  `Features/ProviderRegistration`; nenhum novo padrão arquitetural.
- **Estado/UX — PASS**: reaproveita `ProviderRegistrationDraft`/`EditingContent`, estados já
  explícitos; modalidade continua um campo único controlando a UI, sem booleans paralelos.
- **Dados/segurança — PASS**: nenhuma nova superfície de dados sensíveis; falha de catálogo
  inconsistente reaproveita a classificação de erro já existente (`.catalogChanged`).
- **Qualidade proporcional — PASS**: sem testes automatizados não solicitados; mudança pequena e
  localizada.

## Project Structure

### Documentation (this feature)

```text
specs/016-conditional-provider-services/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
    └── provider-registration-service-rule.md
```

### Source Code (repository root)

```text
pitgo/Features/ProviderRegistration/
├── Model/ProviderRegistrationModels.swift     # CatalogService ganha dispatchKind (já lido desde 009)
├── Data/ProviderRegistrationDTOs.swift        # CatalogServiceDTO ganha dispatch_kind
├── Repository/ProviderRegistrationRepository.swift  # novo método: resolver serviço implícito por dispatchKind
├── ViewModel/ProviderRegistrationViewModel.swift    # seleção de modalidade monta/limpa a oferta implícita
└── Views/ProviderRegistrationView.swift             # esconde a seção de oferta para Móvel/PitTec; forma reduzida para Móvel

# Nenhum diretório/arquivo novo além do já existente; nenhuma mudança em backend.
```

**Structure Decision**: manter a organização feature-first já adotada; toda a mudança fica contida
em `Features/ProviderRegistration`, sem tocar `ProviderDashboard`, `PitTec` ou `MobileDispatch`, que
já resolvem Guincho/PitTec por outros meios depois do cadastro.

## Complexity Tracking

Nenhuma violação: a funcionalidade reduz a complexidade do fluxo existente (uma etapa a menos para
Móvel e PitTec) sem introduzir camada, dependência ou padrão novo.

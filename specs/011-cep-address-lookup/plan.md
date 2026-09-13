# Implementation Plan: Busca de endereço por CEP (iOS)

**Branch**: `011-cep-address-lookup` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/011-cep-address-lookup/spec.md`

## Summary

Adicionar ao cadastro de empresa (`007`/`009`) uma consulta explícita de CEP pelo ViaCEP. A pessoa
informa oito dígitos e aciona "Buscar CEP"; rua, complemento, bairro, cidade e UF são preenchidos em
uma única atualização do rascunho, enquanto o número permanece manual. Os campos continuam editáveis
e uma mudança posterior do CEP invalida somente os valores que vieram da consulta anterior.

A integração usa `URLSession` nativo e `Codable`, por meio de um `ViaCepAddressLookupRepository`
dedicado, sem autenticação, cache persistente, backend intermediário ou dependência nova. O
`ProviderRegistrationViewModel` existente é o dono da `Task`, do `attemptID` monotônico e do estado
explícito da consulta. A View atual ganha o controle responsivo de busca, feedback acessível e
correções no mecanismo geral de erro/foco para marcar todos os campos inválidos com seus respectivos
motivos.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: `URLSession`/`Codable` (Foundation, nativo — nenhuma dependência nova);
SwiftUI. `supabase-swift` do cadastro (`007`/`009`) permanece inalterado.

**Storage**: N/A para a consulta; resultado permanece somente no `@Observable` state em memória e o
cadastro existente continua responsável pela persistência final no Supabase

**Testing**: sem testes automatizados, conforme a governança do projeto; validação manual com build,
dispositivo/simulador, ViaCEP real e cenários de falha em `quickstart.md`

**Target Platform**: iOS 17+, iPhone e iPad, portrait e landscape, teclado aberto e Dynamic Type
grande

**Project Type**: aplicativo iOS nativo de alvo único, organizado por feature

**Performance Goals**: 95% das consultas válidas produzem endereço ou mensagem conclusiva em até 3
segundos; apenas uma chamada por tentativa; nenhuma recriação de View deve reiniciar a consulta

**Constraints**: consulta somente por ação explícita; exatamente oito dígitos; preenchimento manual
continua possível após falha temporária; nenhum dado além do CEP é enviado ao ViaCEP; sem
dependência de terceiros, proxy Supabase, cache, persistência, busca automática, testes ou mudança
de navegação

**Scale/Scope**: um formulário existente, um endpoint GET, cinco campos derivados e uma tentativa
ativa por `ProviderRegistrationViewModel`

## Constitution Check

*GATE inicial e pós-design: aprovado sem exceções.*

- **Simplicidade/YAGNI — PASS**: a View, o ViewModel, a validação existentes são estendidos. Sem
  View nova, Use Case, dependência de terceiros, proxy, cache ou infraestrutura especulativa.
- **iOS nativo/MVVM — PASS**: a View somente renderiza e emite eventos; o ViewModel coordena estado
  e concorrência; o Repository é a fronteira exclusiva da API externa. `@Observable`/Swift
  Concurrency permanecem o padrão da feature.
- **Estado/UX — PASS**: consulta, submissão, catálogo e verificação de endereço permanecem estados
  separados. Erros de campo são completos, acionáveis, associados semanticamente e o primeiro
  inválido fica visível.
- **Dados/segurança — PASS**: o client ViaCEP não recebe sessão, token, CNPJ, e-mail ou endereço
  parcial. Respostas são validadas como não confiáveis e erros técnicos nunca chegam à UI/log.
- **Qualidade proporcional — PASS**: nenhuma dependência é adicionada; `Task`s são canceláveis,
  respostas tardias são rejeitadas por identidade da tentativa e a validação manual cobre rede,
  lifecycle, acessibilidade e responsividade sem criar testes não solicitados.

O design pós-Phase 1 mantém o gate aprovado. O novo Repository tem uso atual demonstrável porque
centraliza o único acesso ao serviço externo; os demais artefatos apenas estendem
responsabilidades já existentes.

## Project Structure

### Documentation (this feature)

```text
specs/011-cep-address-lookup/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── provider-registration-ui.md
│   └── viacep-lookup.md
└── tasks.md                         # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/Features/ProviderRegistration/
├── Model/ProviderRegistrationModels.swift
├── Repository/
│   ├── ProviderRegistrationRepository.swift
│   └── ViaCepAddressLookupRepository.swift
├── Validation/ProviderRegistrationValidation.swift
├── ViewModel/ProviderRegistrationViewModel.swift
└── Views/ProviderRegistrationView.swift
```

**Structure Decision**: manter o alvo único e a organização feature-first. O client e o DTO privado
do ViaCEP ficam juntos no novo Repository porque existe somente um endpoint; separá-los em
DataSource/DTO públicos não reduziria complexidade. Não há nova rota, asset, arquivo de build,
migration ou função Supabase.

## Complexity Tracking

Nenhuma violação constitucional foi identificada.

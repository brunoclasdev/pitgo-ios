# Implementation Plan: Ambientes iOS (Dev/Homol/Prod)

**Branch**: `027-ios-environment-flavors` | **Date**: 2026-10-22 | **Spec**: [spec.md](spec.md)

## Summary

Três ambientes via build configuration/xcconfig/scheme do Xcode (equivalente aos product flavors do
Android), mesmo bundle identifier `com.trustarx.pitgo` nos três (só um instalado por vez). Dev usa
um backend Supabase separado e `SimulatedPaymentGateway` (pagamento inteiramente local, sem Mercado
Pago); Homol e Prod compartilham o backend de produção e `PaymentRepository` real — `Homol.xcconfig`
inclui literalmente o mesmo arquivo de secrets de `Prod.xcconfig`, então a igualdade entre os dois é
garantida pela estrutura do arquivo, não por uma verificação que poderia divergir.

## Technical Context

**Language/Version**: Swift 5.10+, SwiftUI, iOS 16+

**Primary Dependencies**: nenhuma nova — reutiliza Supabase Swift, MapLibre, MercadoPagoSDK já
presentes.

**Storage**: dois projetos Supabase — `eetbrkznuqbdrnybnyhf` (Homol/Prod, já usado por todo o app) e
`ljnqlaiiwreuczbdghxn` (Dev, mesmo projeto de desenvolvimento do Android). Nenhuma migration nova.

**Testing**: build dos três schemes (`pitgo`, `pitgo-Homol`, `pitgo-Prod`) via `xcodebuild`;
inspeção funcional em simulador/dispositivo. Sem suíte automatizada nova.

**Target Platform**: iOS 16+; dois backends Supabase conforme o ambiente.

**Constraints**: nunca inicializar `MercadoPagoSDK` em Dev; nunca reaproveitar sessão entre
ambientes; `Config/*.secrets.xcconfig` nunca versionado; `Homol.xcconfig` nunca duplica o arquivo de
secrets de Prod — inclui o mesmo arquivo.

## Project Structure

```text
specs/027-ios-environment-flavors/
├── plan.md
├── spec.md
├── tasks.md
└── contracts/
    └── payment-gateway.md

Config/
├── Shared.xcconfig              (base comum, sem secrets)
├── Dev.xcconfig                 (ENVIRONMENT_ID=DEV; zera mercadoPagoPublicKey)
├── Homol.xcconfig                (ENVIRONMENT_ID=HOMOL; inclui Prod.secrets.xcconfig)
├── Prod.xcconfig                 (ENVIRONMENT_ID=PROD)
├── Dev.secrets.xcconfig          (local, gitignored — backend de Dev)
├── Prod.secrets.xcconfig         (local, gitignored — backend de Homol/Prod)
└── *.secrets.xcconfig.example    (tracked)

pitgo/Core/Environment/
├── EnvironmentConfig.swift       (ENVIRONMENT_ID → DEV/HOMOL/PROD, paymentMode, fingerprint)
└── EnvironmentStateRepository.swift (invalida sessão/estado ao trocar de ambiente)

pitgo/Features/Payment/Repository/
├── PaymentGateway.swift          (protocolo; PaymentRepository passa a conformar)
└── SimulatedPaymentGateway.swift (actor — só usado quando EnvironmentConfig.current.simulated)

pitgo.xcodeproj/
├── project.pbxproj               (6 build configurations, 3 novos PBXFileReference)
└── xcshareddata/xcschemes/
    ├── pitgo.xcscheme             (inalterado — Debug/Release agora = Dev)
    ├── pitgo-Homol.xcscheme       (novo)
    └── pitgo-Prod.xcscheme        (novo)
```

**Structure Decision**: scheme `pitgo` (já existente) passa a representar Dev sem nenhuma mudança de
arquivo — só o `baseConfigurationReference` de `Debug`/`Release` muda de `Shared.xcconfig` para
`Dev.xcconfig`. Dois schemes novos cobrem Homol/Prod. Nenhum alvo (target) novo — mesmo app, três
configurações.

## Constitution Check

- **Simplicidade**: PASS — reaproveita `PaymentRepository`/`PaymentCheckoutViewModel`/
  `PaymentCheckoutView` existentes; `SimulatedPaymentGateway` é a única peça nova de domínio.
  `Homol.xcconfig` inclui o arquivo de Prod em vez de duplicar valores que precisariam ficar
  sincronizados manualmente.
- **MVVM/estado previsível**: PASS — `EnvironmentConfig.current` é computado uma vez (estático,
  igual a `ManagedMercadoPagoConfiguration`/`ManagedMapStyleConfiguration`); o gateway é escolhido
  uma vez na raiz (`PitGoRootView.init`), nunca trocado em runtime.
  `PaymentCheckoutViewModel.simulated`/`simulate(_:)` são a única superfície nova de ViewModel.
- **Dados e segurança**: PASS — `Config/*.secrets.xcconfig` gitignored; `Validate Supabase Config`
  falha o build antes de compilar se a configuração do ambiente ativo for inválida; nenhum secret
  novo exposto a logs/UI (`EnvironmentDiagnostics.label` nunca inclui URL/chave/token).
- **Qualidade proporcional**: PASS — build dos três schemes cobre o risco principal (configuração
  de ambiente); o escopo de `SimulatedPaymentGateway` cobre só os fluxos de pagamento que o app iOS
  já tinha (MOBILE_SEQUENTIAL/PITTEC_AUTO_SEQUENTIAL) — nenhuma peça da espec Guincho do Android
  (specs 028+, ainda não portadas) foi replicada aqui.

## Complexity Tracking

Nenhuma violação da constituição exige justificativa.

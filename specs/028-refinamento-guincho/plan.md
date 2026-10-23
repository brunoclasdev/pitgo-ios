# Implementation Plan: Refinamento do fluxo de Guincho (porte iOS)

**Branch**: `028-refinamento-guincho` | **Date**: 2026-10-22 | **Spec**: [spec.md](spec.md)

## Summary

Spec 028 do Android não é uma feature isolada: `MobileDispatchKind.GUINCHO_DIRECT` reaproveita toda
a infraestrutura de despacho compartilhado já portada em `013` (`MobileDispatchRepository`,
`ClientMobileDispatchView(Model)`, `ProviderIncomingRequestView(Model)`). O porte iOS segue a mesma
estratégia: **estender**, nunca duplicar. Só a etapa pré-pagamento (escolha de retirada/destino/
veículo/guincheiro no mapa, cotação) é genuinamente nova — vive em `pitgo/Features/Guincho/`.

## Technical Context

**Language/Version**: Swift 5.10+, SwiftUI, iOS 16+

**Primary Dependencies**: reutiliza `PitGoMapView` (`026`), `PaymentGateway`/`PaymentCheckoutView`
(`027`), `VehicleRepository`, `DeviceLocationRepository` já existentes; `CLGeocoder` nativo no lugar
do `android.location.Geocoder`.

**Storage**: mesmo backend Supabase compartilhado (`eetbrkznuqbdrnybnyhf`) — todas as RPCs/migrations
de `028` já estão implantadas pelo porte Android; nenhuma migration nova.

**Testing**: build dos três schemes (`pitgo`, `pitgo-Homol`, `pitgo-Prod`); sem suíte automatizada
nova, seguindo a prática já adotada pelo projeto.

## Project Structure

```text
pitgo/Features/Guincho/                      (novo — etapa pré-pagamento)
├── Model/GuinchoModels.swift                 (draft, provider, quote, failure)
├── Model/GuinchoDTOs.swift                   (DTOs + GuinchoTripDTO/GuinchoDisputeDTO compartilhados)
├── Repository/GuinchoRepository.swift        (save_guincho_trip_draft, discover_guincho_providers,
│                                               Edge Function guincho-quote, create_guincho_request_before_payment)
├── Repository/GuinchoAddressRepository.swift (Edge Function guincho-address-search + CLGeocoder)
├── ViewModel/GuinchoMapViewModel.swift        (estágios pickup→destination→confirm→discovery)
└── Views/GuinchoMapView.swift

pitgo/Features/MobileDispatch/                (estendido, não duplicado)
├── Model/MobileDispatchModels.swift          (+ MobileDispatchKind, + ARRIVE/START/CONFIRM_COMPLETION/
│                                               DISPUTE, + AWAITING_CLIENT_COMPLETION_CONFIRMATION/DISPUTED,
│                                               + trip/dispute/quote dual-field em DispatchAppointment)
├── Repository/MobileDispatchRepository.swift  (+ arriveGuincho, startGuinchoTransport,
│                                               disputeCompletion, confirmCompletion)
├── ViewModel/ProviderIncomingRequestViewModel.swift (+ arrive(), startTransport())
├── Views/ProviderIncomingRequestView.swift    (+ guinchoReservedState)
├── ViewModel/ClientMobileDispatchViewModel.swift (+ confirmCompletion(), dispute(reason:),
│                                               guinchoPaymentContext)
├── Views/ClientMobileDispatchView.swift       (+ guinchoAwaitingPaymentState/guinchoAcceptedState/
│                                               guinchoDisputedState/guinchoDisputeSheet)
└── Coordinator/DispatchResumeCoordinator.swift (retomada nunca usa a tela genérica de tracking p/ Guincho)

pitgo/Features/Payment/
├── Model/PaymentModels.swift                  (+ PaymentDispatchKind.guinchoDirect)
├── Repository/SimulatedPaymentGateway.swift    (+ delega GUINCHO_DIRECT ao backend real via
│                                               simulate_guincho_payment, mesmo em Dev)
└── ViewModel/PaymentCheckoutViewModel.swift    (+ GuinchoPaymentContext)

pitgo/Features/ProviderDashboard/ViewModel/ProviderDashboardViewModel.swift
  (checkIncoming() roteia Guincho sempre para ProviderIncomingRequestView, nunca ProviderTrackingView)

pitgo/Core/Navigation/
├── PitGoRoute.swift                           (+ case guincho(serviceID:))
└── PitGoRootView.swift                        (Home → dispatchKind .mobileSequential abre .guincho;
                                               .guincho navega para GuinchoMapView; onContract empurra
                                               .mobileDispatchSearch — reaproveita a retomada existente)
```

**Structure Decision**: nenhum módulo novo de domínio além de `Features/Guincho` (a etapa
genuinamente nova); tudo que é compartilhado com PitTec/mobile dispatch clássico foi estendido in
loco, preservando FR-019 ("preservar os demais fluxos de serviço").

## Constitution Check

- **Simplicidade**: PASS — reaproveita `MobileDispatchSnapshot`/`PaymentGateway`/`PitGoMapView`
  quase integralmente; a única peça de estado genuinamente nova é `GuinchoMapState` (estágios da
  escolha pré-pagamento).
- **MVVM/estado previsível**: PASS — `GuinchoMapViewModel` segue o mesmo padrão `@Published state`
  já usado em todo o app; os novos status (`AWAITING_CLIENT_COMPLETION_CONFIRMATION`/`DISPUTED`) e
  ações (`ARRIVE`/`START`/`CONFIRM_COMPLETION`/`DISPUTE`) são só mais casos nos enums/switches já
  existentes de `MobileDispatchModels`.
- **Dados e segurança**: PASS — nome/veículo/endereço do cliente só chegam via `snapshot.guinchoTrip`,
  que o backend já restringe a pagamento aprovado (nenhuma lógica de ocultação nova no client).
- **Qualidade proporcional**: PASS — build dos três schemes cobre o risco de compilação; os ajustes
  de escopo documentados em `spec.md` evitam reconstruir GPS ao vivo/vistoria/avaliação que outras
  specs do Android (029-034) ainda vão trazer.

## Complexity Tracking

- GPS ao vivo do guincheiro e navegação externa ficam para quando as specs 031/033 do Android forem
  portadas (dependem da mesma infraestrutura de rota/localização em tempo real) — registrado em
  `spec.md` "Ajustes de escopo", não uma dívida silenciosa.

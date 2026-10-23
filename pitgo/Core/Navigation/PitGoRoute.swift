//
//  PitGoRoute.swift
//  pitgo
//
//  Rotas empilhadas dentro das abas/pilhas autenticadas. Carrega somente UUIDs opacos de serviço/
//  atendimento — nunca papel, ID de owner, coordenadas, endereço, token, e-mail ou documento (ver
//  contracts/navigation-session.md "Central routes" de `009`).
//
//  `.providerRegistration`/`.providerDashboard`/`.providerMigrationClaim` não são casos deste enum:
//  são raízes autenticadas inteiras decididas por `AppSessionState` em `PitGoRootView`, nunca
//  destinos empilhados numa `NavigationStack` (ver `009 §"Session destination matrix"`).
//

import Foundation

enum PitGoRoute: Hashable {
    /// Empurrada pela aba Início ao tocar num card do catálogo real (`009` — substitui
    /// `.requestService` de `003`/`DemoServiceID`).
    case serviceMap(serviceID: UUID)

    /// Empurrada pelo CTA "SOLICITAR ATENDIMENTO" do resumo de um provider no mapa de descoberta
    /// (`010` — contracts/map-ui-navigation.md "Provider summary and request"). `providerID` é
    /// opaco e usado somente pelo callback mockado de confirmação.
    case requestService(serviceID: UUID, providerID: UUID)

    /// Empurrada pela aba Perfil para uma conta CLIENT com empresa legada pendente.
    case providerMigrationStart

    /// Acompanhamento privado de atendimento — lado cliente.
    case appointmentTracking(appointmentID: UUID)
    /// Revisão explícita de uma vistoria pendente, aberta pelo aviso interno.
    case guinchoInspectionReview(appointmentID: UUID)

    /// Acompanhamento/controle de tracking — lado provider.
    case providerAppointmentTracking(appointmentID: UUID)

    /// Empurrada pelo card de guincho da Home (`dispatchKind == .mobileSequential`) para iniciar uma
    /// nova busca (`013`). Duas variantes por origem — Swift não admite dois casos com o mesmo nome
    /// e assinaturas diferentes, então "substituída por `.mobileDispatch(searchID:)`" do contrato
    /// vira uma troca de caso no `NavigationPath`, não uma sobrecarga do mesmo caso.
    ///
    /// `028`: só continua alcançável por retomada de uma busca antiga pré-existente — o card de
    /// guincho da Home agora empurra `.guincho(serviceID:)` em vez deste caso (ver nota lá).
    case mobileDispatchNewSearch(serviceID: UUID)
    /// Retomada de uma busca já existente (ex.: `DispatchResumeCoordinator`) — serve tanto o guincho
    /// móvel clássico quanto o Guincho com seleção no mapa (`028`), que usam o mesmo
    /// `service_searches`/snapshot; `ClientMobileDispatchView` decide pelo `dispatchKind` recebido.
    case mobileDispatchSearch(searchID: UUID)

    /// `028` — card de Guincho da Home (`dispatchKind == .mobileSequential`): escolha de retirada/
    /// destino/veículo e seleção explícita do guincheiro no mapa, antes de qualquer pagamento.
    /// Substitui `.mobileDispatchNewSearch` como destino desse card (que continua existindo só para
    /// retomar uma busca antiga incompatível, ver FR-019/Assumptions de `028`).
    case guincho(serviceID: UUID)

    /// Solicitação pendente destinada ao provider — aberta automaticamente ao detectar
    /// `get_my_pending_mobile_dispatch` com uma oferta `PENDING`.
    case providerRequest(appointmentID: UUID)
    /// Histórico compartilhado de atendimentos do prestador móvel.
    case providerGuinchoHistory
    case storeCatalog

    /// Card PitTec da Home (`015`) — descoberta + despacho automático sob demanda.
    case pitTec(serviceID: UUID)
    /// Cadastro/edição do endereço do cliente (`014`), aberto pela Home ou pelo Perfil.
    case clientAddress
    /// Solicitação PitTec pendente destinada ao provider.
    case pitTecProviderRequest(appointmentID: UUID)

    /// Área "Formas de pagamento" do Perfil (`018`) — cadastro/lista/remoção de cartões salvos.
    /// Nunca aberta a partir do checkout em si (FR-019: cadastro de cartão só aqui, nunca inline).
    case paymentMethods
}

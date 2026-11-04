//
//  ClientMobileDispatchView.swift
//  pitgo
//
//  Tela dedicada de busca/proposta/decisão do guincho móvel (`013`). Sem `TabView` — View filha
//  focada, mesmo padrão de `AppointmentTrackingView` (`009`/`010`). O card textual é a fonte
//  acessível; o mapa permanece como fundo em todas as etapas do atendimento.
//

import CoreLocation
import SwiftUI
import UIKit

struct ClientMobileDispatchView: View {
    @Environment(\.pitGoTokens) private var tokens
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: ClientMobileDispatchViewModel
    @State private var showCancellationSheet = false
    @State private var guinchoPaymentDismissed = false
    /// `028` — campo de motivo do "Informar problema" (`AWAITING_CLIENT_COMPLETION_CONFIRMATION`).
    @State private var showDisputeSheet = false
    @State private var showInspection = false
    @State private var ratingAppointmentID: UUID?
    @State private var ratedAppointmentID: UUID?
    @State private var disputeReason = ""

    let trackingRepository: AppointmentTrackingRepository
    let catalogRepository: ServiceCatalogRepository
    let paymentRepository: PaymentGateway
    let savedCardRepository: SavedCardRepository
    let inspectionRepository: GuinchoInspectionRepository
    let ratingRepository: ServiceRatingRepository
    let onBack: () -> Void
    let onOpenTracking: (UUID) -> Void
    let onSessionExpired: () -> Void
    let onInspectionVisibility: (UUID?) -> Void

    init(
        serviceID: UUID?,
        repository: MobileDispatchRepository,
        locationRepository: DeviceLocationRepository,
        trackingRepository: AppointmentTrackingRepository,
        catalogRepository: ServiceCatalogRepository,
        paymentRepository: PaymentGateway,
        savedCardRepository: SavedCardRepository,
        inspectionRepository: GuinchoInspectionRepository,
        ratingRepository: ServiceRatingRepository,
        onBack: @escaping () -> Void,
        onOpenTracking: @escaping (UUID) -> Void,
        onSessionExpired: @escaping () -> Void,
        onInspectionVisibility: @escaping (UUID?) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: ClientMobileDispatchViewModel(
            serviceID: serviceID,
            repository: repository,
            paymentRepository: paymentRepository,
            locationRepository: locationRepository
        ))
        self.trackingRepository = trackingRepository
        self.catalogRepository = catalogRepository
        self.paymentRepository = paymentRepository
        self.savedCardRepository = savedCardRepository
        self.inspectionRepository = inspectionRepository
        self.ratingRepository = ratingRepository
        self.onBack = onBack
        self.onOpenTracking = onOpenTracking
        self.onSessionExpired = onSessionExpired
        self.onInspectionVisibility = onInspectionVisibility
    }

    var body: some View {
        ZStack {
            dispatchMap.ignoresSafeArea(edges: .bottom)
            ServiceMapCard { content }
        }
            .background(tokens.background)
            .navigationTitle("Guincho")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: handleBack) {
                        Image(systemName: "chevron.left")
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Voltar")
                }
            }
            .task { viewModel.start() }
            .onDisappear { viewModel.stop() }
            .onChange(of: scenePhase) { phase in
                if phase == .active { viewModel.refresh() }
            }
            .onChange(of: isSessionExpired) { expired in
                if expired { onSessionExpired() }
            }
            .onChange(of: acceptedAppointmentID) { appointmentID in
                if let appointmentID { onOpenTracking(appointmentID) }
            }
            .onChange(of: isPendingCancel) { pending in
                if !pending { showCancellationSheet = false }
            }
            .sheet(isPresented: $showCancellationSheet) {
                DispatchCancellationSheet(isSubmitting: isPendingCancel) { reason in
                    viewModel.cancel(reason: reason)
                }
                .interactiveDismissDisabled(isPendingCancel)
            }
            .sheet(isPresented: paymentSheetBinding) {
                if let serviceID = paymentServiceID {
                    PaymentCheckoutView(
                        serviceID: serviceID,
                        dispatchKind: .mobileSequential,
                        catalogRepository: catalogRepository,
                        paymentRepository: paymentRepository,
                        savedCardRepository: savedCardRepository,
                        onApproved: { requestID in viewModel.beginPaidSearch(searchID: requestID) },
                        onSessionExpired: onSessionExpired
                    )
                }
            }
            // `028`: guincheiro já aceitou — paga o orçamento exato, nunca recalculado aqui.
            .sheet(item: Binding(
                get: { guinchoPaymentDismissed ? nil : viewModel.guinchoPaymentContext },
                set: { if $0 == nil { guinchoPaymentDismissed = true } }
            )) { context in
                PaymentCheckoutView(
                    serviceID: guinchoServiceID ?? context.appointmentID,
                    dispatchKind: .guinchoDirect,
                    catalogRepository: catalogRepository,
                    paymentRepository: paymentRepository,
                    savedCardRepository: savedCardRepository,
                    guinchoContext: context,
                    onApproved: { _ in
                        guinchoPaymentDismissed = true
                        viewModel.refresh()
                    },
                    onCancelled: {
                        guinchoPaymentDismissed = true
                        viewModel.cancel(reason: "Cliente cancelou na tela de pagamento")
                    },
                    onSessionExpired: onSessionExpired
                )
            }
            .sheet(isPresented: $showDisputeSheet) {
                guinchoDisputeSheet
            }
            .sheet(isPresented: $showInspection, onDismiss: { onInspectionVisibility(nil) }) {
                if let appointmentID = currentGuinchoAppointmentID {
                    NavigationStack {
                        GuinchoInspectionView(appointmentID: appointmentID, repository: inspectionRepository)
                    }
                    .onAppear { onInspectionVisibility(appointmentID) }
                }
            }
            .sheet(isPresented: Binding(
                get: { ratingAppointmentID != nil },
                set: { if !$0 { ratingAppointmentID = nil } }
            )) {
                if let appointmentID = ratingAppointmentID {
                    NavigationStack {
                        ServiceRatingView(appointmentID: appointmentID, repository: ratingRepository) {
                            ratingAppointmentID = nil
                        } onSaved: {
                            ratedAppointmentID = appointmentID
                        }
                    }
                }
            }
    }

    /// `018`: cancelar a tela de pagamento sem aprovar volta para a tela anterior — nenhuma RPC de
    /// despacho é chamada nesse caso (FR-013).
    private var paymentSheetBinding: Binding<Bool> {
        Binding(
            get: { paymentServiceID != nil },
            set: { isPresented in if !isPresented && paymentServiceID != nil { onBack() } }
        )
    }

    private var paymentServiceID: UUID? {
        guard case let .paymentRequired(serviceID) = viewModel.state else { return nil }
        return serviceID
    }

    private func handleBack() {
        guard case let .content(snapshot, nil) = viewModel.state else {
            onBack()
            return
        }
        if snapshot.appointment != nil {
            // Existe solicitação/atendimento vinculado — sair sem decidir não é silencioso.
            showCancellationSheet = true
        } else {
            onBack()
        }
    }

    private var isSessionExpired: Bool {
        if case .sessionExpired = viewModel.state { return true }
        return false
    }

    /// `028`: Guincho nunca navega para `AppointmentTrackingView` — o acompanhamento inteiro
    /// (retirada→destino, chegada, transporte, conclusão, contestação) fica nesta mesma tela (ver
    /// `guinchoAcceptedState`), reaproveitando a mesma assinatura/canal Realtime já conectados.
    private var acceptedAppointmentID: UUID? {
        guard case let .content(snapshot, _) = viewModel.state,
              snapshot.dispatchKind != .guinchoDirect,
              let appointment = snapshot.appointment,
              appointment.status == .accepted || appointment.status == .inProgress else { return nil }
        return appointment.appointmentID
    }

    private var guinchoServiceID: UUID? {
        guard case let .content(snapshot, _) = viewModel.state, snapshot.dispatchKind == .guinchoDirect else { return nil }
        return snapshot.serviceID
    }

    private var currentGuinchoAppointmentID: UUID? {
        guard case let .content(snapshot, _) = viewModel.state, snapshot.dispatchKind == .guinchoDirect else { return nil }
        return snapshot.appointment?.appointmentID
    }

    private var isPendingCancel: Bool {
        guard case let .content(_, pending) = viewModel.state, let pending else { return false }
        if case .cancel = pending.kind { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .restoring, .paymentRequired:
            ProgressView("Buscando prestador…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .locationRequired(reason):
            locationRequiredState(reason)
        case let .content(snapshot, pendingAction):
            contentState(snapshot, pendingAction: pendingAction)
        case let .terminal(snapshot):
            terminalState(snapshot)
        case let .failure(reason, lastConfirmed):
            failureState(reason, lastConfirmed: lastConfirmed)
        case .sessionExpired:
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var mapSnapshot: MobileDispatchSnapshot? {
        switch viewModel.state {
        case let .content(snapshot, _), let .terminal(snapshot): snapshot
        case let .failure(_, snapshot): snapshot
        default: nil
        }
    }

    @ViewBuilder private var dispatchMap: some View {
        if let snapshot = mapSnapshot, let trip = snapshot.guinchoTrip,
           let appointment = snapshot.appointment {
            GuinchoClientRouteMap(appointmentID: appointment.appointmentID, trip: trip,
                phase: appointment.serviceStartedAt != nil || appointment.status == .inProgress || appointment.status == .awaitingClientCompletionConfirmation
                    ? .transporting : .approaching,
                repository: trackingRepository)
        } else {
            PitGoMapView(annotations: candidateAnnotations, centerCoordinate: candidateAnnotations.first?.coordinate ?? clientCoordinate,
                showsUserLocation: true, fitBottomPadding: 300)
                .overlay(alignment: .topLeading) { MapAttributionView().padding(12) }
        }
    }

    private var clientCoordinate: CLLocationCoordinate2D? {
        viewModel.lastFix.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var candidateAnnotations: [PitGoMapAnnotationItem] {
        guard let candidate = mapSnapshot?.candidate, candidate.hasValidLocation,
              let latitude = candidate.latitude, let longitude = candidate.longitude else { return [] }
        return [PitGoMapAnnotationItem(id: candidate.candidateID.uuidString,
            coordinate: .init(latitude: latitude, longitude: longitude), title: candidate.providerName, symbolName: "car.fill")]
    }

    // MARK: - Location required

    private func locationRequiredState(_ reason: LocationRequiredReason) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "location.slash")
                .font(.system(size: 40))
                .foregroundStyle(tokens.textSecondary)
            Text(locationRequiredMessage(reason))
                .font(PitGoTypography.body)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.updatesFrequently)
            Button("Tentar novamente") { viewModel.retry() }
                .frame(minHeight: 44)
            if reason == .permissionDenied {
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .frame(minHeight: 44)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func locationRequiredMessage(_ reason: LocationRequiredReason) -> String {
        switch reason {
        case .permissionDenied: "Precisamos da sua localização para buscar o guincho mais próximo. Permita o acesso nos Ajustes."
        case .serviceDisabled: "Ative os Serviços de Localização nas Configurações do sistema."
        case .timeout: "Não foi possível obter sua localização a tempo. Tente novamente."
        case .unknown: "Não foi possível obter sua localização. Tente novamente."
        }
    }

    // MARK: - Content (SEARCHING/OPTION_FOUND/AWAITING_PROVIDER/ACCEPTED/IN_PROGRESS)

    @ViewBuilder
    private func contentState(_ snapshot: MobileDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        switch snapshot.status {
        case .searching:
            searchingState(snapshot)
        case .optionFound:
            optionFoundState(snapshot, pendingAction: pendingAction)
        case .awaitingProvider:
            awaitingProviderState(snapshot, pendingAction: pendingAction)
        case .awaitingClientConfirmation:
            // `021`/migration `20260913010000` — exclusivo do PitTec; o Guincho nunca alcança este
            // status. Tratado como "aguardando prestador" por segurança, nunca travando a tela.
            awaitingProviderState(snapshot, pendingAction: pendingAction)
        case .awaitingPayment:
            if snapshot.dispatchKind == .guinchoDirect {
                // `028`: o prestador já aceitou — o pagamento é aberto pelo `.sheet(item:)` ligado a
                // `viewModel.guinchoPaymentContext`; esta tela só informa o estado por trás dele.
                guinchoAwaitingPaymentState(snapshot)
            } else {
                awaitingProviderState(snapshot, pendingAction: pendingAction)
            }
        case .accepted, .inProgress, .awaitingClientCompletionConfirmation:
            if snapshot.dispatchKind == .guinchoDirect {
                guinchoAcceptedState(snapshot, pendingAction: pendingAction)
            } else {
                acceptedState(snapshot, pendingAction: pendingAction)
            }
        case .disputed:
            guinchoDisputedState(snapshot)
        case .cancelled, .completed, .exhausted:
            terminalState(snapshot)
        }
    }

    private func searchingState(_ snapshot: MobileDispatchSnapshot) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
            Text("Buscando prestador")
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Text("Procurando guinchos num raio de \(formattedRadius(snapshot.radiusMeters)).")
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textSecondary)
                .multilineTextAlignment(.center)
            if snapshot.allowedActions.contains(.cancel) {
                Button("Cancelar busca") { handleCancelTap(snapshot) }
                    .frame(minHeight: 44)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func optionFoundState(_ snapshot: MobileDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 16) {
                if let candidate = snapshot.candidate {
                    proposalCard(candidate)
                }
                HStack(spacing: 12) {
                    Button(action: { viewModel.requestCandidate() }) {
                        actionLabel("Solicitar este guincho", isLoading: isPending(pendingAction, matching: .request))
                    }
                    .foregroundStyle(.white)
                    .background(tokens.accent)
                    .clipShape(Capsule())
                    .frame(minHeight: 56)
                    .disabled(pendingAction != nil || !snapshot.allowedActions.contains(.request))

                    Button(action: { viewModel.requestNext() }) {
                        actionLabel("Próximo", isLoading: isPending(pendingAction, matching: .next))
                    }
                    .frame(minHeight: 56)
                    .disabled(pendingAction != nil || !snapshot.allowedActions.contains(.next))
                }
            }
            .padding(16)
        }
    }

    private func awaitingProviderState(_ snapshot: MobileDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
            Text("Aguardando prestador")
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            if let appointment = snapshot.appointment {
                Text("Preço garantido: \(formattedPrice(appointment.quotedPrice, isFree: appointment.isFree))")
                    .font(PitGoTypography.body)
                if let deadline = appointment.responseDeadline {
                    // Lê `viewModel.localNow` para recompor a cada segundo — sem isso o countdown
                    // parece travado (`014` FR-001, achado real desta sessão).
                    Text(countdownText(deadline, now: viewModel.localNow))
                        .font(PitGoTypography.body)
                        .foregroundStyle(tokens.textSecondary)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            if snapshot.allowedActions.contains(.cancel) {
                Button("Cancelar solicitação") { handleCancelTap(snapshot) }
                    .frame(minHeight: 44)
                    .disabled(pendingAction != nil)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func acceptedState(_ snapshot: MobileDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text(snapshot.status == .inProgress ? "Atendimento em andamento" : "Atendimento aceito!")
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            if let appointment = snapshot.appointment {
                Text("Preço garantido: \(formattedPrice(appointment.quotedPrice, isFree: appointment.isFree))")
                    .font(PitGoTypography.body)
            }
            Text("Abrindo o acompanhamento…")
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textSecondary)
            if snapshot.allowedActions.contains(.cancel) {
                Button("Cancelar atendimento") { handleCancelTap(snapshot) }
                    .frame(minHeight: 44)
                    .disabled(pendingAction != nil)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - `028` — Guincho (pagamento pós-aceite, acompanhamento, conclusão, contestação)

    private func guinchoAwaitingPaymentState(_ snapshot: MobileDispatchSnapshot) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("\(snapshot.providerName ?? "O guincheiro") aceitou!")
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            if let appointment = snapshot.appointment {
                Text(formattedPrice(appointment.quotedPrice, isFree: appointment.isFree))
                    .font(PitGoTypography.body)
            }
            Button("Abrir pagamento") { guinchoPaymentDismissed = false }
                .frame(minHeight: 44)
            if snapshot.allowedActions.contains(.cancel) {
                Button("Cancelar atendimento", role: .destructive) { handleCancelTap(snapshot) }
                    .frame(minHeight: 44)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `028`: mapa fixo com retirada/destino (sem publicação de localização em tempo real do
    /// guincheiro neste porte — ver nota em `ProviderIncomingRequestView.startedAppointmentID`) +
    /// resumo com as ações do estado atual.
    private func guinchoAcceptedState(_ snapshot: MobileDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        let trip = snapshot.guinchoTrip
        let transporting = snapshot.appointment?.serviceStartedAt != nil
            || snapshot.appointment?.status == .inProgress
            || snapshot.appointment?.status == .awaitingClientCompletionConfirmation
        return Group {
                VStack(alignment: .leading, spacing: 12) {
                    Text(snapshot.providerName ?? "Guincheiro")
                        .font(PitGoTypography.sectionTitle)
                        .accessibilityAddTraits(.isHeader)
                    if let appointment = snapshot.appointment {
                        Text(formattedPrice(appointment.quotedPrice, isFree: appointment.isFree))
                            .font(PitGoTypography.body)
                    }
                    if let trip {
                        Text(transporting ? "Destino: \(trip.destinationAddress)" : "Retirada: \(trip.pickupAddress)")
                            .font(PitGoTypography.caption)
                            .foregroundStyle(tokens.textSecondary)
                    }

                    if let inspection = snapshot.inspection, inspection.required {
                        Text(inspectionStatusText(inspection.state))
                            .font(PitGoTypography.body)
                            .accessibilityAddTraits(.updatesFrequently)
                        if inspection.state != nil {
                            Button("Ver vistoria do veículo") { showInspection = true }
                                .frame(minHeight: 48)
                        }
                    }

                    switch snapshot.appointment?.status {
                    case .accepted:
                        Text(snapshot.appointment?.arrivedAt == nil ? "O guincheiro está a caminho." : "O guincheiro chegou à retirada.")
                            .font(PitGoTypography.body)
                            .accessibilityAddTraits(.updatesFrequently)
                    case .inProgress:
                        Text("Transporte em andamento.")
                            .font(PitGoTypography.body)
                            .accessibilityAddTraits(.updatesFrequently)
                    case .awaitingClientCompletionConfirmation:
                        Text("O guincheiro informou que concluiu o atendimento.")
                            .font(PitGoTypography.body)
                            .accessibilityAddTraits(.isHeader)
                        if snapshot.allowedActions.contains(.confirmCompletion) {
                            Button(action: { viewModel.confirmCompletion() }) {
                                actionLabel("Deu tudo certo", isLoading: isPending(pendingAction, matching: .confirmCompletion))
                            }
                            .foregroundStyle(.white)
                            .background(tokens.accent)
                            .clipShape(Capsule())
                            .frame(minHeight: 56)
                            .disabled(pendingAction != nil)
                        }
                        if snapshot.allowedActions.contains(.dispute) {
                            Button("Informar problema") { showDisputeSheet = true }
                                .frame(minHeight: 44)
                                .disabled(pendingAction != nil)
                        }
                    default:
                        EmptyView()
                    }

                    if snapshot.allowedActions.contains(.cancel) {
                        Button("Cancelar atendimento") { handleCancelTap(snapshot) }
                            .frame(minHeight: 44)
                            .disabled(pendingAction != nil)
                    }
                }
                .padding(16)
        }
    }

    private func guinchoDisputedState(_ snapshot: MobileDispatchSnapshot) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 40))
                .foregroundStyle(tokens.textSecondary)
            Text("Seu caso está em análise pelo suporte.")
                .font(PitGoTypography.body)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.updatesFrequently)
            if let dispute = snapshot.guinchoDispute {
                Text(dispute.reason)
                    .font(PitGoTypography.caption)
                    .foregroundStyle(tokens.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button("Voltar", action: onBack)
                .frame(minHeight: 44)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var guinchoDisputeSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("O que não deu certo?")
                    .font(PitGoTypography.body)
                TextEditor(text: $disputeReason)
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(tokens.outline, lineWidth: 1))
                Button("Enviar") {
                    viewModel.dispute(reason: disputeReason)
                    showDisputeSheet = false
                    disputeReason = ""
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(.white)
                .background(tokens.accent)
                .clipShape(Capsule())
                .disabled(disputeReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }
            .padding(24)
            .navigationTitle("Informar problema")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { showDisputeSheet = false }
                }
            }
        }
    }

    private func handleCancelTap(_ snapshot: MobileDispatchSnapshot) {
        if snapshot.appointment != nil {
            showCancellationSheet = true
        } else {
            onBack()
        }
    }

    // MARK: - Terminal/failure

    private func terminalState(_ snapshot: MobileDispatchSnapshot) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: terminalSymbol(snapshot.status))
                .font(.system(size: 40))
                .foregroundStyle(tokens.textSecondary)
            Text(terminalMessage(snapshot.status))
                .font(PitGoTypography.body)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.updatesFrequently)
            if snapshot.status == .completed, let appointmentID = snapshot.appointment?.appointmentID {
                if snapshot.ratingState?.submitted == true || ratedAppointmentID == appointmentID {
                    Text("Avaliação registrada · definitiva").font(PitGoTypography.caption)
                } else if snapshot.ratingState?.canRate == true {
                    Button("Avaliar atendimento") { ratingAppointmentID = appointmentID }
                        .frame(minHeight: 44)
                }
            }
            if let refundMessage = refundMessage(for: viewModel.refundStatus) {
                Text(refundMessage)
                    .font(PitGoTypography.caption)
                    .foregroundStyle(tokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if snapshot.status == .exhausted {
                Button("Buscar novamente") { viewModel.retry() }
                    .frame(minHeight: 44)
            }
            Button("Voltar", action: onBack)
                .frame(minHeight: 44)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `018` FR-015/FR-017/FR-018 — feedback de estorno, nunca silencioso.
    private func refundMessage(for status: PaymentStatus?) -> String? {
        switch status {
        case .refunded: "Valor estornado."
        case .refundFailed: "Reembolso em andamento — nossa equipe já foi avisada."
        default: nil
        }
    }

    private func terminalSymbol(_ status: ServiceSearchStatus) -> String {
        switch status {
        case .completed: "checkmark.circle"
        case .cancelled: "xmark.circle"
        default: "magnifyingglass"
        }
    }

    private func terminalMessage(_ status: ServiceSearchStatus) -> String {
        switch status {
        case .completed: "Atendimento concluído."
        case .cancelled: "Atendimento cancelado."
        case .exhausted: "Nenhum guincho disponível nesta região no momento."
        default: "Busca encerrada."
        }
    }

    private func failureState(_ reason: ClientMobileDispatchFailureReason, lastConfirmed: MobileDispatchSnapshot?) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(message(for: reason))
                .font(PitGoTypography.body)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.updatesFrequently)
            Button("Tentar novamente") { viewModel.retry() }
                .frame(minHeight: 44)
            Button("Voltar", action: onBack)
                .frame(minHeight: 44)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(for reason: ClientMobileDispatchFailureReason) -> String {
        switch reason {
        case .offline: "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .timeout: "Não foi possível concluir agora. Tente novamente."
        case .sessionExpired: "Sua sessão expirou. Entre novamente."
        case .paymentRequired: "É necessário concluir o pagamento antes de buscar um guincho."
        case .notFound: "Esta busca não está mais disponível."
        case .serviceUnavailable: "Não foi possível concluir agora. Tente novamente em instantes."
        case .contract: "Não foi possível concluir esta ação. Tente novamente."
        case .unknown: "Não foi possível concluir a busca. Tente novamente."
        }
    }

    // MARK: - Proposal card / map

    private func proposalCard(_ candidate: CandidateProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(candidate.providerName, systemImage: "car.fill")
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Text(candidate.locality)
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textSecondary)
            Text(formattedDistance(candidate.distanceMeters))
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textSecondary)
            Text(formattedPrice(candidate.price, isFree: candidate.isFree))
                .font(PitGoTypography.body)
                .bold()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private func isPending(_ pendingAction: PendingDispatchAction?, matching kind: DispatchActionKind) -> Bool {
        pendingAction?.kind == kind
    }

    private func actionLabel(_ text: String, isLoading: Bool) -> some View {
        ZStack {
            if isLoading { ProgressView() }
            Text(text).opacity(isLoading ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func countdownText(_ deadline: Date, now: Date) -> String {
        let remaining = Int(deadline.timeIntervalSince(now).rounded(.up))
        if remaining <= 0 { return "Tempo esgotado. Atualizando…" }
        return "Aguardando resposta — expira em \(remaining)s"
    }

    private func formattedRadius(_ meters: Int) -> String {
        meters >= 1000 ? "\(meters / 1000) km" : "\(meters) m"
    }

    /// `014` FR-003 — nunca um número que pareça "0,0 km"/placeholder; abaixo de 50m o texto vira
    /// "Muito próximo de você" em vez de "A 0 m de você".
    private func formattedDistance(_ meters: Double) -> String {
        if meters < 50 { return "Muito próximo de você" }
        return meters >= 1000 ? String(format: "A %.1f km de você", meters / 1000) : String(format: "A %.0f m de você", meters)
    }

    private func formattedPrice(_ value: Decimal, isFree: Bool) -> String {
        if isFree { return "Gratuito" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: value as NSDecimalNumber) ?? "R$ \(value)"
    }

    private func inspectionStatusText(_ state: GuinchoInspectionVersionState?) -> String {
        switch state {
        case .draft: "O guincheiro está preparando as fotos do veículo."
        case .submitted: "A vistoria aguarda sua aprovação."
        case .correctionRequested: "Uma correção da vistoria foi solicitada."
        case .approved: "Fotos do veículo aprovadas."
        case nil: "Vistoria ainda não registrada."
        }
    }
}

//
//  ClientMobileDispatchView.swift
//  pitgo
//
//  Tela dedicada de busca/proposta/decisão do guincho móvel (`013`). Sem `TabView` — View filha
//  focada, mesmo padrão de `AppointmentTrackingView` (`009`/`010`). O card textual é a fonte
//  acessível; o mapa (quando a posição do candidato é válida) é complementar.
//

import CoreLocation
import SwiftUI
import UIKit

struct ClientMobileDispatchView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: ClientMobileDispatchViewModel
    @State private var showCancellationSheet = false

    let catalogRepository: ServiceCatalogRepository
    let paymentRepository: PaymentRepository
    let savedCardRepository: SavedCardRepository
    let onBack: () -> Void
    let onOpenTracking: (UUID) -> Void
    let onSessionExpired: () -> Void

    init(
        serviceID: UUID?,
        repository: MobileDispatchRepository,
        locationRepository: DeviceLocationRepository,
        catalogRepository: ServiceCatalogRepository,
        paymentRepository: PaymentRepository,
        savedCardRepository: SavedCardRepository,
        onBack: @escaping () -> Void,
        onOpenTracking: @escaping (UUID) -> Void,
        onSessionExpired: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ClientMobileDispatchViewModel(
            serviceID: serviceID,
            repository: repository,
            paymentRepository: paymentRepository,
            locationRepository: locationRepository
        ))
        self.catalogRepository = catalogRepository
        self.paymentRepository = paymentRepository
        self.savedCardRepository = savedCardRepository
        self.onBack = onBack
        self.onOpenTracking = onOpenTracking
        self.onSessionExpired = onSessionExpired
    }

    var body: some View {
        content
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
            .onChange(of: isSessionExpired) { expired in
                if expired { onSessionExpired() }
            }
            .onChange(of: acceptedAppointmentID) { appointmentID in
                if let appointmentID { onOpenTracking(appointmentID) }
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
    }

    /// `018`: cancelar a tela de pagamento sem aprovar volta para a tela anterior — nenhuma RPC de
    /// despacho é chamada nesse caso (FR-013).
    private var paymentSheetBinding: Binding<Bool> {
        Binding(
            get: { paymentServiceID != nil },
            set: { isPresented in if !isPresented { onBack() } }
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

    private var acceptedAppointmentID: UUID? {
        guard case let .content(snapshot, _) = viewModel.state,
              let appointment = snapshot.appointment,
              appointment.status == .accepted || appointment.status == .inProgress else { return nil }
        return appointment.appointmentID
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
        case .awaitingClientConfirmation, .awaitingPayment:
            // `021`/migration `20260913010000` — exclusivos do PitTec (`PITTEC_AUTO_SEQUENTIAL`);
            // o guincho móvel nunca alcança esses status, mas o enum é compartilhado. Tratado como
            // "aguardando prestador" por segurança, nunca travando a tela.
            awaitingProviderState(snapshot, pendingAction: pendingAction)
        case .accepted, .inProgress:
            acceptedState(snapshot, pendingAction: pendingAction)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let candidate = snapshot.candidate {
                    candidateMap(candidate)
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

    private func candidateMap(_ candidate: CandidateProposal) -> some View {
        Group {
            if candidate.hasValidLocation, let latitude = candidate.latitude, let longitude = candidate.longitude {
                PitGoMapView(
                    annotations: [PitGoMapAnnotationItem(
                        id: candidate.candidateID.uuidString,
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                        title: candidate.providerName,
                        symbolName: "car.fill"
                    )],
                    centerCoordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    zoomLevel: 14
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomLeading) { MapAttributionView() }
                .accessibilityHidden(true) // o card textual abaixo já contém toda a informação
            } else {
                VStack {
                    Image(systemName: "location.slash")
                        .foregroundStyle(tokens.textSecondary)
                    Text("Posição do guincho indisponível no momento.")
                        .font(PitGoTypography.caption)
                        .foregroundStyle(tokens.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(tokens.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

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
}

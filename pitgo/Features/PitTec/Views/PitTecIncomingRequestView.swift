//
//  PitTecIncomingRequestView.swift
//  pitgo
//
//  Destino do provider para uma chamada PitTec pendente/reservada (`015`). Antes do aceite mostra
//  apenas distância aproximada + região (nunca nome/posição exata do cliente); depois do aceite,
//  mapa com as duas posições e as ações "Cheguei"/"Concluir"/"Cancelar".
//

import CoreLocation
import SwiftUI

struct PitTecIncomingRequestView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: PitTecIncomingRequestViewModel
    @State private var showCancellationSheet = false
    @State private var mapCoordinate: CLLocationCoordinate2D?

    let onBack: () -> Void
    let onSessionExpired: () -> Void

    init(
        providerID: UUID,
        repository: PitTecRepository,
        onBack: @escaping () -> Void,
        onSessionExpired: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: PitTecIncomingRequestViewModel(providerID: providerID, repository: repository))
        self.onBack = onBack
        self.onSessionExpired = onSessionExpired
    }

    var body: some View {
        ZStack {
            providerMap.ignoresSafeArea(edges: .bottom)
            ServiceMapCard { content }
        }
            .background(tokens.background)
            .navigationTitle("Chamada PitTec")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Voltar")
                }
            }
            .task {
                viewModel.start()
                await locateMap()
            }
            .onDisappear { viewModel.stop() }
            .onChange(of: isSessionExpired) { expired in
                if expired { onSessionExpired() }
            }
            .sheet(isPresented: $showCancellationSheet) {
                DispatchCancellationSheet(isSubmitting: isPendingCancel) { reason in
                    viewModel.cancel(reason: reason)
                }
                .interactiveDismissDisabled(isPendingCancel)
            }
    }

    private var providerMap: some View {
        // The background may show the provider before payment; client coordinates remain gated.
        let context: PitTecRouteContext? = {
            guard case let .reserved(snapshot, _) = viewModel.state,
                  snapshot.appointment?.status == .accepted || snapshot.appointment?.status == .inProgress else { return nil }
            return viewModel.routeContext
        }()
        let points: [CLLocationCoordinate2D] = context.map { [
            .init(latitude: $0.providerLatitude, longitude: $0.providerLongitude),
            .init(latitude: $0.clientLatitude, longitude: $0.clientLongitude)
        ] } ?? []
        let annotations: [PitGoMapAnnotationItem] = points.count == 2 ? [
            .init(id: "provider", coordinate: points[0], title: "Você", symbolName: "wrench.and.screwdriver.fill"),
            .init(id: "client", coordinate: points[1], title: "Cliente")
        ] : []
        return PitGoMapView(annotations: annotations, centerCoordinate: mapCoordinate,
            showsUserLocation: true, fitCoordinates: points.count >= 2 ? points : nil,
            fitBottomPadding: 340, routeLine: points)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) { MapAttributionView().padding(12) }
    }

    private func locateMap() async {
        let location = DeviceLocationRepository()
        switch location.authorizationStatus {
        case .denied, .restricted: return
        case .notDetermined: location.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: break
        }
        if case let .success(fix) = await location.requestOneShotFix(), !Task.isCancelled {
            mapCoordinate = .init(latitude: fix.latitude, longitude: fix.longitude)
        }
    }

    private var isSessionExpired: Bool {
        if case .sessionExpired = viewModel.state { return true }
        return false
    }

    private var isPendingCancel: Bool {
        guard case let .reserved(_, pending) = viewModel.state, let pending else { return false }
        if case .cancel = pending.kind { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .noIncoming:
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "bell.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(tokens.textSecondary)
                Text("Nenhuma chamada no momento.")
                    .font(PitGoTypography.body)
                    .foregroundStyle(tokens.textSecondary)
                Button("Voltar", action: onBack)
                    .frame(minHeight: 44)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .incoming(snapshot, pendingAction):
            incomingState(snapshot, pendingAction: pendingAction)
        case let .reserved(snapshot, pendingAction):
            // Client tracking remains gated until payment; the provider's map stays visible.
            switch snapshot.appointment?.status {
            case .awaitingClientConfirmation, .awaitingPayment:
                awaitingConfirmationState(snapshot)
            default:
                reservedState(snapshot, pendingAction: pendingAction)
            }
        case .sessionExpired:
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failure(reason):
            failureState(reason: reason)
        }
    }

    private func incomingState(_ snapshot: PitTecDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 16) {
                Text("Nova chamada PitTec")
                    .font(PitGoTypography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 8) {
                    if let offer = snapshot.offer {
                        Text(offer.region)
                            .font(PitGoTypography.body)
                        Text(formattedDistance(offer.approximateDistanceMeters))
                            .font(PitGoTypography.body)
                            .foregroundStyle(tokens.textSecondary)
                        Text(formattedAmount(offer.quotedPrice))
                            .font(PitGoTypography.sectionTitle)
                    }
                    if let deadline = snapshot.appointment?.responseDeadline {
                        Text(countdownText(deadline, now: viewModel.localNow))
                            .font(PitGoTypography.body)
                            .foregroundStyle(tokens.textSecondary)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tokens.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 12) {
                    Button(action: { viewModel.accept() }) {
                        actionLabel("Aceitar", isLoading: isPending(pendingAction, .accept))
                    }
                    .foregroundStyle(.white)
                    .background(Color.green)
                    .clipShape(Capsule())
                    .frame(minHeight: 56)
                    .disabled(pendingAction != nil || !snapshot.allowedActions.contains(.accept))

                    Button(action: { viewModel.decline() }) {
                        actionLabel("Recusar", isLoading: isPending(pendingAction, .decline))
                    }
                    .foregroundStyle(.red)
                    .overlay(Capsule().stroke(Color.red, lineWidth: 1.5))
                    .frame(minHeight: 56)
                    .disabled(pendingAction != nil || !snapshot.allowedActions.contains(.decline))
                }
            }
            .padding(16)
        }
    }

    /// Card de espera entre o aceite e `ACCEPTED`, sobre o mapa do próprio prestador. Sai sozinha assim que o status muda pelo mesmo canal Realtime já usado
    /// (`subscribeToProvider`), sem nenhum polling adicional.
    private func awaitingConfirmationState(_ snapshot: PitTecDispatchSnapshot) -> some View {
        let paymentWasRejected = snapshot.payment?.status == "REJECTED"
        return VStack(spacing: 16) {
            Spacer()
            if paymentWasRejected {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(tokens.textSecondary)
            } else {
                ProgressView()
            }
            Text(paymentWasRejected ? "Pagamento recusado" : waitingTitle(for: snapshot.appointment?.status))
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Text(paymentWasRejected
                 ? "O pagamento do cliente foi recusado. O atendimento continua aguardando uma nova tentativa."
                 : waitingMessage(for: snapshot.appointment?.status))
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.updatesFrequently)
            if snapshot.allowedActions.contains(.cancel) {
                Button("Cancelar atendimento") { viewModel.cancel(reason: "PAYMENT_REJECTED") }
                    .frame(minHeight: 44)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func waitingTitle(for status: AppointmentStatus?) -> String {
        status == .awaitingPayment ? "Aguardando pagamento" : "Aguardando confirmação do cliente"
    }

    private func waitingMessage(for status: AppointmentStatus?) -> String {
        status == .awaitingPayment
            ? "O cliente já confirmou o orçamento — falta só o pagamento."
            : "O cliente está revisando o valor do atendimento."
    }

    private func reservedState(_ snapshot: PitTecDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        reservedActions(snapshot, pendingAction: pendingAction)
    }

    private func reservedActions(_ snapshot: PitTecDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snapshot.appointment?.status == .inProgress ? "Atendimento em andamento." : snapshot.hasArrived ? "Você chegou ao local." : "A caminho do cliente.")
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            if snapshot.appointment?.status == .accepted && !snapshot.hasArrived {
                ExternalNavigationButton { await viewModel.externalNavigationDestination() }
            }

            if !snapshot.hasArrived && snapshot.allowedActions.contains(.arrive) {
                Button(action: { viewModel.arrive() }) {
                    actionLabel("Cheguei", isLoading: isPending(pendingAction, .start))
                }
                .foregroundStyle(.white)
                .background(tokens.accent)
                .clipShape(Capsule())
                .frame(minHeight: 56)
                .disabled(pendingAction != nil)
            } else if snapshot.allowedActions.contains(.start) {
                Button(action: { viewModel.startAppointment() }) {
                    actionLabel("Iniciar atendimento", isLoading: isPending(pendingAction, .start))
                }
                .foregroundStyle(.white)
                .background(tokens.accent)
                .clipShape(Capsule())
                .frame(minHeight: 56)
                .disabled(pendingAction != nil)
            } else if snapshot.allowedActions.contains(.complete) {
                Button(action: { viewModel.complete() }) {
                    actionLabel("Concluir atendimento", isLoading: isPending(pendingAction, .complete))
                }
                .foregroundStyle(.white)
                .background(tokens.accent)
                .clipShape(Capsule())
                .frame(minHeight: 56)
                .disabled(pendingAction != nil)
            }

            if snapshot.allowedActions.contains(.cancel) {
                Button("Cancelar atendimento") { showCancellationSheet = true }
                    .frame(minHeight: 44)
                    .disabled(pendingAction != nil)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.surface)
    }

    private func failureState(reason: PitTecFailureReason) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(failureMessage(for: reason))
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

    private func failureMessage(for reason: PitTecFailureReason) -> String {
        switch reason {
        case .paymentRequired:
            return "O pagamento ainda não foi liberado pelo Mercado Pago. Aguarde a confirmação e tente novamente."
        case .sessionExpired:
            return "Sua sessão expirou. Entre novamente para continuar."
        case .offline:
            return "Sem conexão com a internet. Verifique sua rede e tente novamente."
        default:
            return "Não foi possível concluir agora. Tente novamente."
        }
    }

    private func isPending(_ pendingAction: PendingDispatchAction?, _ kind: DispatchActionKind) -> Bool {
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
        return "Responda em até \(remaining)s"
    }

    private func formattedDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "~%.0f km do cliente", meters / 1000) : String(format: "~%.0f m do cliente", meters)
    }

    private func formattedAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: amount as NSDecimalNumber) ?? "R$ \(amount)"
    }
}

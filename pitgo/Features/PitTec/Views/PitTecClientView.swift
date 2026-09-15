//
//  PitTecClientView.swift
//  pitgo
//
//  Tela dedicada do PitTec sob demanda (`015`) — descoberta aproximada, "Chamar PitTec", busca e
//  acompanhamento pós-aceite, tudo nesta mesma tela (evita depender de `AppointmentTrackingView`,
//  que não conhece rota/distância PitTec; ver nota em `PitTecRepository.swift` sobre a Edge
//  Function `pittec-route` ausente — a linha exibida é sempre a estimativa direta tracejada).
//

import CoreLocation
import SwiftUI

struct PitTecClientView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: PitTecClientViewModel
    @State private var showCancellationSheet = false
    /// `021`/migration `20260913010000`: o checkout só abre DEPOIS que o cliente confirma o
    /// orçamento (`AWAITING_PAYMENT`), nunca antes de `startDispatch` — a busca em si não exige
    /// mais pagamento prévio (ao contrário do que `018` originalmente implementou).
    @State private var pittecPaymentContext: PitTecPaymentContext?

    let serviceID: UUID
    let catalogRepository: ServiceCatalogRepository
    let paymentRepository: PaymentRepository
    let savedCardRepository: SavedCardRepository
    let onBack: () -> Void
    let onSessionExpired: () -> Void

    init(
        serviceID: UUID,
        repository: PitTecRepository,
        locationRepository: DeviceLocationRepository,
        catalogRepository: ServiceCatalogRepository,
        paymentRepository: PaymentRepository,
        savedCardRepository: SavedCardRepository,
        onBack: @escaping () -> Void,
        onSessionExpired: @escaping () -> Void
    ) {
        self.serviceID = serviceID
        _viewModel = StateObject(wrappedValue: PitTecClientViewModel(
            serviceID: serviceID,
            repository: repository,
            paymentRepository: paymentRepository,
            locationRepository: locationRepository
        ))
        self.catalogRepository = catalogRepository
        self.paymentRepository = paymentRepository
        self.savedCardRepository = savedCardRepository
        self.onBack = onBack
        self.onSessionExpired = onSessionExpired
    }

    var body: some View {
        content
            .background(tokens.background)
            .navigationTitle("PitTec")
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
            .sheet(isPresented: $showCancellationSheet) {
                DispatchCancellationSheet(isSubmitting: isPendingCancel) { reason in
                    viewModel.cancel(reason: reason)
                }
                .interactiveDismissDisabled(isPendingCancel)
            }
            .sheet(item: $pittecPaymentContext) { context in
                PaymentCheckoutView(
                    serviceID: serviceID,
                    dispatchKind: .pittecAutoSequential,
                    catalogRepository: catalogRepository,
                    paymentRepository: paymentRepository,
                    savedCardRepository: savedCardRepository,
                    pittecContext: context,
                    onApproved: { _ in
                        pittecPaymentContext = nil
                        viewModel.refreshAfterPayment()
                    },
                    onSessionExpired: onSessionExpired
                )
            }
    }

    private func handleBack() {
        guard case let .content(snapshot, nil) = viewModel.state, snapshot.appointment != nil else {
            onBack()
            return
        }
        if viewModel.requiresCancellationReason {
            showCancellationSheet = true
        } else {
            onBack()
        }
    }

    private var isSessionExpired: Bool {
        if case .sessionExpired = viewModel.state { return true }
        return false
    }

    private var isPendingCancel: Bool {
        guard case let .content(_, pending) = viewModel.state, let pending else { return false }
        if case .cancel = pending.kind { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .restoring:
            ProgressView("Carregando…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .locationRequired(reason):
            locationRequiredState(reason)
        case let .discovering(markers):
            discoveringState(markers)
        case let .content(snapshot, pendingAction):
            contentState(snapshot, pendingAction: pendingAction)
        case let .terminal(snapshot):
            terminalState(snapshot)
        case .failure:
            failureState()
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
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func locationRequiredMessage(_ reason: LocationRequiredReason) -> String {
        switch reason {
        case .permissionDenied: "Precisamos da sua localização para mostrar os PitTecs próximos. Permita o acesso nos Ajustes."
        case .serviceDisabled: "Ative os Serviços de Localização nas Configurações do sistema."
        case .timeout: "Não foi possível obter sua localização a tempo. Tente novamente."
        case .unknown: "Não foi possível obter sua localização. Tente novamente."
        }
    }

    // MARK: - Descoberta

    /// `020` (revisado): a descoberta não informa proativamente se há ou não PitTec na região — só
    /// mostra o mapa centralizado no cliente (com os marcadores aproximados quando existirem). A
    /// ausência de PitTec só é comunicada depois que o cliente toca em "Chamar PitTec" e a busca
    /// de fato se esgota (`terminalState`, `status == .exhausted`), nunca antes disso.
    private func discoveringState(_ markers: [PitTecMarker]) -> some View {
        VStack(spacing: 0) {
            PitGoMapView(
                annotations: markers.map {
                    PitGoMapAnnotationItem(id: $0.markerID, coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude), symbolName: "wrench.and.screwdriver.fill")
                },
                centerCoordinate: clientCoordinate,
                showsUserLocation: true
            )
            .overlay(alignment: .bottomLeading) { MapAttributionView() }
            callButton
        }
    }

    /// `020` FR-001: posição do cliente já obtida na descoberta (`viewModel.lastFix`), reaproveitada
    /// para centralizar o mapa em qualquer estado — nunca um novo fix pedido só para isso.
    private var clientCoordinate: CLLocationCoordinate2D? {
        viewModel.lastFix.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// `020` FR-002/FR-003/FR-004/FR-006: mapa sempre centralizado no cliente, sem marcador de
    /// prestador, com uma mensagem (e ações opcionais) sobrepostas — usado tanto na descoberta sem
    /// PitTec quanto na busca esgotada, nunca como tela substituta do mapa.
    private func mapCenteredOnClient(icon: String, message: String, @ViewBuilder actions: () -> some View) -> some View {
        PitGoMapView(annotations: [], centerCoordinate: clientCoordinate, showsUserLocation: true)
            .overlay(alignment: .bottomLeading) { MapAttributionView() }
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 32))
                        .foregroundStyle(tokens.textSecondary)
                    Text(message)
                        .font(PitGoTypography.body)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.updatesFrequently)
                    actions()
                }
                .padding(20)
                .background(tokens.surface, in: RoundedRectangle(cornerRadius: 16))
                .padding(24)
            }
    }

    private var callButton: some View {
        Button(action: { viewModel.callPitTec() }) {
            Text("Chamar PitTec")
                .frame(maxWidth: .infinity)
                .padding()
        }
        .foregroundStyle(.white)
        .background(tokens.accent)
        .clipShape(Capsule())
        .frame(minHeight: 56)
        .padding(16)
    }

    // MARK: - Content

    @ViewBuilder
    private func contentState(_ snapshot: PitTecDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        switch snapshot.status {
        case .searching:
            searchingState(snapshot, pendingAction: pendingAction)
        case .optionFound:
            // PitTec não expõe candidato ao cliente antes do aceite — este status não deveria
            // ocorrer no snapshot PitTec (só existe no vocabulário do guincho móvel), mas é tratado
            // como "buscando" por segurança, nunca travando a tela.
            searchingState(snapshot, pendingAction: pendingAction)
        case .awaitingProvider:
            searchingState(snapshot, pendingAction: pendingAction)
        case .awaitingClientConfirmation:
            confirmationState(snapshot, pendingAction: pendingAction)
        case .awaitingPayment:
            paymentPendingState(snapshot)
        case .accepted, .inProgress:
            acceptedState(snapshot, pendingAction: pendingAction)
        case .cancelled, .completed, .exhausted:
            terminalState(snapshot)
        }
    }

    private func searchingState(_ snapshot: PitTecDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
            Text("Procurando PitTec")
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            if let notice = snapshot.recentNotice {
                Text(noticeMessage(notice))
                    .font(PitGoTypography.body)
                    .foregroundStyle(tokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Text("Buscando num raio de \(formattedRadius(snapshot.radiusMeters)).")
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textSecondary)
            if snapshot.allowedActions.contains(.cancel) {
                Button("Cancelar chamada") { viewModel.cancel() }
                    .frame(minHeight: 44)
                    .disabled(pendingAction != nil)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func noticeMessage(_ notice: PitTecLastEvent) -> String {
        switch notice {
        case .providerRejected: "Um PitTec recusou a chamada. Procurando o próximo…"
        case .offerExpired: "O prazo de resposta esgotou. Procurando o próximo…"
        case .providerCancelled: "O PitTec cancelou. Procurando o próximo…"
        case .searchContinues: "Nenhum PitTec disponível até agora. Ampliando a área de busca…"
        // `021`: só ocorrem em status terminal (`CANCELLED`); `recentNotice` nunca os expõe aqui
        // (gated em `status == .searching`), mas o switch precisa ser exaustivo.
        case .clientConfirmationTimeout, .quoteDeclined: "Busca encerrada."
        }
    }

    /// `021`/migration `20260913010000`: card do orçamento ofertado pelo PitTec ao aceitar
    /// (`AWAITING_CLIENT_CONFIRMATION`) — o valor AINDA NÃO foi cobrado (o pagamento só acontece
    /// depois, em `AWAITING_PAYMENT`). "Recusar" cancela o atendimento (`QUOTE_DECLINED`, tratado
    /// pelo próprio backend); "Confirmar" avança para a etapa de pagamento. O backend também libera
    /// `CANCEL` nesse estado (junto de `CONFIRM_QUOTE`/`DECLINE_QUOTE`) — a tela nunca usava essa
    /// terceira ação, deixando o cliente sem uma saída explícita de "desistir" sem ter que recusar o
    /// orçamento em si.
    private func confirmationState(_ snapshot: PitTecDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Label(snapshot.provider?.displayName ?? "PitTec", systemImage: "wrench.and.screwdriver.fill")
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Text("aceitou seu chamado.")
                .font(PitGoTypography.body)
            VStack(spacing: 4) {
                Text("Valor do atendimento")
                    .font(PitGoTypography.caption)
                    .foregroundStyle(tokens.textSecondary)
                Text(formattedAmount(snapshot.appointment?.quotedPrice ?? 0))
                    .font(PitGoTypography.sectionTitle)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(tokens.surface)
            Text("Confirme para seguir com o atendimento — o pagamento acontece no próximo passo.")
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button {
                    viewModel.declineQuote()
                } label: {
                    // Sem isso o botão só ficava cinza ao tocar, sem nenhum sinal de que o toque foi
                    // registrado — parecia travado enquanto a RPC ainda estava em voo.
                    if pendingAction?.kind == .cancel(reason: "QUOTE_DECLINED") {
                        ProgressView().tint(tokens.textSecondary)
                    } else {
                        Text("Recusar")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(pendingAction != nil || !snapshot.allowedActions.contains(.declineQuote))
                Button {
                    viewModel.confirmQuote()
                } label: {
                    if pendingAction?.kind == .confirm {
                        ProgressView().tint(.white)
                    } else {
                        Text("Confirmar")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(.white)
                .background(tokens.accent)
                .clipShape(Capsule())
                .disabled(pendingAction != nil || !snapshot.allowedActions.contains(.confirmQuote))
            }
            if snapshot.allowedActions.contains(.cancel) {
                Button {
                    viewModel.cancel()
                } label: {
                    if pendingAction?.kind == .cancel(reason: "") {
                        ProgressView().tint(tokens.textSecondary)
                    } else {
                        Text("Cancelar")
                    }
                }
                .frame(minHeight: 44)
                .disabled(pendingAction != nil)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `021`/migration `20260913010000`: orçamento já confirmado, aguardando o pagamento em si —
    /// abre `PaymentCheckoutView` amarrado ao atendimento/versão do orçamento (`mp-create-payment`
    /// valida os dois server-side); aprovado, o backend avança para `ACCEPTED` sozinho.
    private func paymentPendingState(_ snapshot: PitTecDispatchSnapshot) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Label(snapshot.provider?.displayName ?? "PitTec", systemImage: "wrench.and.screwdriver.fill")
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Text("Orçamento confirmado — falta só pagar.")
                .font(PitGoTypography.body)
            Text(formattedAmount(snapshot.appointment?.quotedPrice ?? 0))
                .font(PitGoTypography.sectionTitle)
            if let appointment = snapshot.appointment, snapshot.allowedActions.contains(.openPayment) {
                Button("Pagar agora") {
                    pittecPaymentContext = PitTecPaymentContext(
                        searchID: snapshot.searchID,
                        appointmentID: appointment.appointmentID,
                        quoteVersion: appointment.quoteVersion,
                        amount: appointment.quotedPrice
                    )
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(.white)
                .background(tokens.accent)
                .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formattedAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: amount as NSDecimalNumber) ?? "R$ \(amount)"
    }

    private func acceptedState(_ snapshot: PitTecDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        VStack(spacing: 0) {
            if let context = viewModel.routeContext {
                PitGoMapView(
                    annotations: [
                        PitGoMapAnnotationItem(id: "pittec", coordinate: CLLocationCoordinate2D(latitude: context.providerLatitude, longitude: context.providerLongitude), title: snapshot.provider?.displayName, symbolName: "wrench.and.screwdriver.fill"),
                        PitGoMapAnnotationItem(id: "client", coordinate: CLLocationCoordinate2D(latitude: context.clientLatitude, longitude: context.clientLongitude), title: "Você"),
                    ],
                    // `021` FR-008: enquadra cliente + PitTec juntos, em vez de depender do zoom padrão.
                    fitCoordinates: [
                        CLLocationCoordinate2D(latitude: context.providerLatitude, longitude: context.providerLongitude),
                        CLLocationCoordinate2D(latitude: context.clientLatitude, longitude: context.clientLongitude),
                    ],
                    routeLine: [
                        CLLocationCoordinate2D(latitude: context.providerLatitude, longitude: context.providerLongitude),
                        CLLocationCoordinate2D(latitude: context.clientLatitude, longitude: context.clientLongitude),
                    ]
                )
                .overlay(alignment: .bottomLeading) { MapAttributionView() }
            } else {
                VStack {
                    Spacer()
                    ProgressView("Aguardando localização…")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            statusCard(snapshot, pendingAction: pendingAction)
        }
    }

    private func statusCard(_ snapshot: PitTecDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(snapshot.provider?.displayName ?? "PitTec", systemImage: "wrench.and.screwdriver.fill")
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Text(snapshot.hasArrived ? "O PitTec chegou." : "O PitTec está a caminho.")
                .font(PitGoTypography.body)
            Text(distanceText())
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textSecondary)
                .accessibilityAddTraits(.updatesFrequently)
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

    private func distanceText() -> String {
        guard let context = viewModel.routeContext else { return "Distância estimada indisponível no momento." }
        let providerLocation = CLLocation(latitude: context.providerLatitude, longitude: context.providerLongitude)
        let clientLocation = CLLocation(latitude: context.clientLatitude, longitude: context.clientLongitude)
        let meters = providerLocation.distance(from: clientLocation)
        let km = meters / 1000
        return String(format: "Estimativa direta: %.1f km (linha reta, não é a rota real)", km)
    }

    // MARK: - Terminal/failure

    @ViewBuilder
    private func terminalState(_ snapshot: PitTecDispatchSnapshot) -> some View {
        if snapshot.status == .exhausted {
            // `020` FR-004: busca esgotada também mantém o mapa centralizado no cliente — as
            // mensagens e ações terminais ficam sobrepostas, em vez da tela só-texto anterior. Os
            // demais status terminais (`.completed`/`.cancelled`) continuam inalterados abaixo.
            mapCenteredOnClient(icon: terminalSymbol(snapshot.status), message: terminalMessage(snapshot.status)) {
                terminalActions(snapshot)
            }
        } else {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: terminalSymbol(snapshot.status))
                    .font(.system(size: 40))
                    .foregroundStyle(tokens.textSecondary)
                Text(terminalMessage(snapshot.status))
                    .font(PitGoTypography.body)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
                terminalActions(snapshot)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func terminalActions(_ snapshot: PitTecDispatchSnapshot) -> some View {
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
        case .cancelled: "Chamada cancelada."
        case .exhausted: "Nenhum PitTec disponível nesta região no momento."
        default: "Busca encerrada."
        }
    }

    private func failureState() -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Não foi possível concluir agora. Tente novamente.")
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

    private func formattedRadius(_ meters: Int) -> String {
        meters >= 1000 ? "\(meters / 1000) km" : "\(meters) m"
    }
}

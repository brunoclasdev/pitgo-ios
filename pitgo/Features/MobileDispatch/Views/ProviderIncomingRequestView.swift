//
//  ProviderIncomingRequestView.swift
//  pitgo
//
//  Destino dedicado do provider para uma solicitação pendente/atendimento reservado (`013`,
//  contracts/mobile-dispatch-ui-navigation.md "Provider"). Recusa pré-aceite não exige motivo;
//  cancelamento pós-aceite exige (`DispatchCancellationSheet`, compartilhado com o cliente).
//

import SwiftUI
import CoreLocation

struct ProviderIncomingRequestView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: ProviderIncomingRequestViewModel
    @StateObject private var routeViewModel: GuinchoRouteViewModel
    @State private var showCancellationSheet = false
    @State private var showInspection = false
    @State private var mapFix: DeviceLocationFix?
    @State private var locallySubmittedInspectionAppointmentID: UUID?

    let onBack: () -> Void
    let inspectionRepository: GuinchoInspectionRepository
    let onOpenTracking: (UUID) -> Void
    let onSessionExpired: () -> Void

    init(
        providerID: UUID,
        repository: MobileDispatchRepository,
        inspectionRepository: GuinchoInspectionRepository,
        routeRepository: GuinchoRouteRepository,
        discoveryTracker: ProviderDiscoveryTracker,
        onBack: @escaping () -> Void,
        onOpenTracking: @escaping (UUID) -> Void,
        onSessionExpired: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ProviderIncomingRequestViewModel(providerID: providerID, repository: repository))
        _routeViewModel = StateObject(wrappedValue: GuinchoRouteViewModel(repository: routeRepository, tracker: discoveryTracker))
        self.inspectionRepository = inspectionRepository
        self.onBack = onBack
        self.onOpenTracking = onOpenTracking
        self.onSessionExpired = onSessionExpired
    }

    var body: some View {
        ZStack {
            providerMap.ignoresSafeArea(edges: .bottom)
            ServiceMapCard { content }
        }
            .background(tokens.background)
            .navigationTitle("Solicitação")
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
                syncRoute()
                await locateMap()
            }
            .onDisappear { viewModel.stop(); routeViewModel.stop() }
            .onChange(of: viewModel.state) { _ in syncRoute() }
            .onChange(of: isSessionExpired) { expired in
                if expired { onSessionExpired() }
            }
            .onChange(of: startedAppointmentID) { appointmentID in
                if let appointmentID { onOpenTracking(appointmentID) }
            }
            .onChange(of: viewModel.didFinishGuincho) { finished in
                if finished { onBack() }
            }
            .onChange(of: isPendingCancel) { pending in
                if !pending { showCancellationSheet = false }
            }
            .sheet(isPresented: $showInspection) {
                if let appointmentID = mapSnapshot?.appointment?.appointmentID {
                    NavigationStack {
                        GuinchoInspectionView(appointmentID: appointmentID, repository: inspectionRepository) {
                            locallySubmittedInspectionAppointmentID = appointmentID
                            showInspection = false
                            viewModel.refreshNow()
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Fechar") { showInspection = false }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showCancellationSheet) {
                DispatchCancellationSheet(isSubmitting: isPendingCancel) { reason in
                    viewModel.cancel(reason: reason)
                }
                .interactiveDismissDisabled(isPendingCancel)
            }
    }

    private var mapSnapshot: MobileDispatchSnapshot? {
        switch viewModel.state {
        case let .incoming(snapshot, _), let .reserved(snapshot, _): snapshot
        case let .failure(snapshot): snapshot
        default: nil
        }
    }

    private var activeRoute: GuinchoRouteSnapshot? {
        switch routeViewModel.state {
        case let .ready(route), let .loading(route?), let .waiting(route?, _), let .unavailable(route?, _): route
        default: nil
        }
    }

    /// A single map stays behind the request, payment wait, pickup and transport cards.
    private var providerMap: some View {
        let trip = mapSnapshot?.guinchoTrip
        let transporting = mapSnapshot?.appointment?.status == .inProgress
        let route = transporting ? activeRoute : nil
        let fix = routeViewModel.latestFix ?? mapFix
        let current: CLLocationCoordinate2D? = fix.flatMap {
            guard Date().timeIntervalSince($0.timestamp) <= 30,
                  $0.horizontalAccuracy > 0, $0.horizontalAccuracy <= 100 else { return nil }
            return CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        let points: [CLLocationCoordinate2D] = route?.coordinates ?? trip.map { trip in
            transporting ? [trip.pickup, trip.destination] : current.map { [$0, trip.pickup] } ?? [trip.pickup]
        } ?? []
        var annotations: [PitGoMapAnnotationItem] = []
        if let trip {
            annotations.append(.init(id: "pickup", coordinate: trip.pickup, title: "Retirada", symbolName: "car.fill"))
            annotations.append(.init(id: "destination", coordinate: trip.destination, title: "Destino contratado", symbolName: "flag.fill"))
        }
        if let current {
            annotations.append(.init(id: "provider", coordinate: current, title: "Você", symbolName: "truck.box.fill"))
        } else if let route {
            annotations.append(.init(id: "provider", coordinate: route.origin.point.coordinate, title: "Última posição usada na rota", symbolName: "truck.box.fill"))
        }
        return PitGoMapView(annotations: annotations, centerCoordinate: current ?? trip?.pickup,
            showsUserLocation: true, fitCoordinates: points.count >= 2 ? points : nil,
            fitTrigger: transporting ? Int(route?.routeVersion ?? 0) + 1 : 0, fitBottomPadding: 340,
            routeLine: route?.coordinates, routeVersion: route?.routeVersion, routeIsEstimated: false)
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
            mapFix = fix
        }
    }

    private var isSessionExpired: Bool {
        if case .sessionExpired = viewModel.state { return true }
        return false
    }

    /// `028`: Guincho fica inteiramente nesta tela (ver `guinchoReservedState`) — nunca navega para
    /// `ProviderTrackingView` (publicação de localização em tempo real do guincho móvel clássico,
    /// fora do escopo deste porte).
    private var startedAppointmentID: UUID? {
        guard case let .reserved(snapshot, _) = viewModel.state,
              snapshot.dispatchKind != .guinchoDirect,
              snapshot.appointment?.status == .inProgress else { return nil }
        return snapshot.appointment?.appointmentID
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
                Text("Nenhuma solicitação no momento.")
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
            reservedState(snapshot, pendingAction: pendingAction)
        case .sessionExpired:
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failure(lastConfirmed):
            failureState(lastConfirmed: lastConfirmed)
        }
    }

    private func incomingState(_ snapshot: MobileDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 16) {
                Text("Nova solicitação")
                    .font(PitGoTypography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 8) {
                    Text(snapshot.serviceName)
                        .font(PitGoTypography.body)
                    if let appointment = snapshot.appointment {
                        Text(formattedPrice(appointment.quotedPrice, isFree: appointment.isFree))
                            .font(PitGoTypography.body)
                            .bold()
                        if let deadline = appointment.responseDeadline {
                            // Lê `viewModel.localNow` (tick de 1s do ViewModel) para que a SwiftUI
                            // recomponha este texto a cada segundo — sem isso o countdown parece
                            // travado (`014` FR-001, achado real desta sessão).
                            Text(countdownText(deadline, now: viewModel.localNow))
                                .font(PitGoTypography.body)
                                .foregroundStyle(tokens.textSecondary)
                                .accessibilityAddTraits(.updatesFrequently)
                        }
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

    @ViewBuilder
    private func reservedState(_ snapshot: MobileDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        if snapshot.dispatchKind == .guinchoDirect {
            guinchoReservedState(snapshot, pendingAction: pendingAction)
        } else {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text(snapshot.appointment?.status == .inProgress ? "Atendimento em andamento" : "Atendimento reservado")
                    .font(PitGoTypography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                if let appointment = snapshot.appointment {
                    Text(formattedPrice(appointment.quotedPrice, isFree: appointment.isFree))
                        .font(PitGoTypography.body)
                }

                if snapshot.appointment?.status == .accepted, snapshot.allowedActions.contains(.complete) {
                    Button(action: { viewModel.startAppointment() }) {
                        actionLabel("Iniciar atendimento", isLoading: isPending(pendingAction, .start))
                    }
                    .foregroundStyle(.white)
                    .background(tokens.accent)
                    .clipShape(Capsule())
                    .frame(minHeight: 56)
                    .disabled(pendingAction != nil)
                }

                if snapshot.appointment?.status == .inProgress, snapshot.allowedActions.contains(.complete) {
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
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// `028`: nome/veículo/endereço do cliente só ficam disponíveis a partir do pagamento aprovado
    /// (`snapshot.guinchoTrip`, FR-012) — já garantido porque este estado só existe a partir de
    /// `ACCEPTED`. A remuneração mostrada é só a do guincheiro (`appointment.quotedPrice`, que já
    /// resolve para `provider_amount` do lado do prestador — nunca os 10%/taxas do cliente).
    @ViewBuilder
    private func guinchoReservedState(_ snapshot: MobileDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 16) {
                if snapshot.canStartGuinchoTransport {
                    Text(snapshot.inspection?.required == false ? "Tudo pronto para iniciar o trajeto." : "Vistoria aprovada. Tudo pronto para iniciar o trajeto.")
                        .font(PitGoTypography.body)
                        .accessibilityAddTraits(.updatesFrequently)
                    Button(action: { viewModel.startTransport() }) {
                        actionLabel("Iniciar trajeto", isLoading: isPending(pendingAction, .start))
                    }
                    .foregroundStyle(.white).background(tokens.accent).clipShape(Capsule())
                    .frame(minHeight: 56).disabled(pendingAction != nil)
                }

                switch snapshot.appointment?.status {
                case .awaitingPayment, .awaitingClientConfirmation:
                    ProgressView("Aguardando o pagamento do cliente…")
                case .accepted:
                    if snapshot.appointment?.arrivedAt == nil {
                        Text("A caminho da retirada.").font(PitGoTypography.body)
                        ExternalNavigationButton { await viewModel.externalNavigationDestination() }
                        if snapshot.allowedActions.contains(.arrive) {
                            Button(action: { viewModel.arrive() }) {
                                actionLabel("Cheguei", isLoading: isPending(pendingAction, .arrive))
                            }
                            .foregroundStyle(.white).background(tokens.accent).clipShape(Capsule())
                            .frame(minHeight: 56).disabled(pendingAction != nil)
                        }
                    } else {
                        Text("Chegou à retirada.").font(PitGoTypography.body)
                        if let appointmentID = snapshot.appointment?.appointmentID,
                           snapshot.inspection?.required == true {
                            if snapshot.inspection?.state == .submitted ||
                                (locallySubmittedInspectionAppointmentID == appointmentID && snapshot.inspection?.state != .approved) {
                                Text("Aguardando aprovação das fotos pelo cliente.").font(PitGoTypography.body)
                            } else if snapshot.inspection?.state == .approved {
                                Text("Vistoria aprovada pelo cliente.").font(PitGoTypography.body)
                            } else {
                                Button("Fazer vistoria do veículo") { showInspection = true }
                                    .frame(minHeight: 48)
                            }
                        }
                        if !snapshot.canStartGuinchoTransport {
                            Button("Atualizar situação da vistoria") { viewModel.refreshNow() }
                                .frame(minHeight: 44).disabled(pendingAction != nil)
                        }
                    }
                case .inProgress:
                    Text("Transporte em andamento.").font(PitGoTypography.body)
                    guinchoRouteContent(snapshot)
                    ExternalNavigationButton { await viewModel.externalNavigationDestination() }
                    if snapshot.allowedActions.contains(.complete) {
                        Button(action: { viewModel.complete() }) {
                            actionLabel("Concluir atendimento", isLoading: isPending(pendingAction, .complete))
                        }
                        .foregroundStyle(.white).background(tokens.accent).clipShape(Capsule())
                        .frame(minHeight: 56).disabled(pendingAction != nil)
                    }
                case .awaitingClientCompletionConfirmation:
                    Text("Aguardando confirmação do cliente.")
                        .font(PitGoTypography.body)
                        .foregroundStyle(tokens.textSecondary)
                        .accessibilityAddTraits(.updatesFrequently)
                case .disputed:
                    Text("O cliente informou um problema — em análise pelo suporte.")
                        .font(PitGoTypography.body)
                        .accessibilityAddTraits(.updatesFrequently)
                    if let dispute = snapshot.guinchoDispute {
                        Text(dispute.reason).font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                    }
                    Button("Voltar", action: onBack).frame(minHeight: 44)
                default:
                    EmptyView()
                }

                DisclosureGroup("Detalhes do atendimento") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let trip = snapshot.guinchoTrip {
                            Text(trip.clientName).font(PitGoTypography.sectionTitle).accessibilityAddTraits(.isHeader)
                            Text(trip.vehicle).font(PitGoTypography.body).foregroundStyle(tokens.textSecondary)
                            Text("Retirada: \(trip.pickupAddress)").font(PitGoTypography.body)
                            Text("Destino: \(trip.destinationAddress)").font(PitGoTypography.body)
                        }
                        if let appointment = snapshot.appointment {
                            Text(formattedPrice(appointment.quotedPrice, isFree: appointment.isFree))
                                .font(PitGoTypography.sectionTitle)
                        }
                    }
                }

                if snapshot.allowedActions.contains(.cancel) {
                    Button("Cancelar atendimento") { showCancellationSheet = true }
                        .frame(minHeight: 44)
                        .disabled(pendingAction != nil)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func guinchoRouteContent(_ snapshot: MobileDispatchSnapshot) -> some View {
        if let route = activeRoute {
            Text("Percurso viário · \(route.distanceMeters / 1000) km")
                .font(PitGoTypography.body).bold()
        }
        routeStatus
    }

    @ViewBuilder
    private var routeStatus: some View {
        switch routeViewModel.state {
        case .loading(_): ProgressView("Atualizando percurso…")
        case let .waiting(_, message), let .unavailable(_, message):
            Text(message).font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
            Button("Tentar novamente") { routeViewModel.retry() }.frame(minHeight: 44)
        default: EmptyView()
        }
    }

    private func syncRoute() {
        guard case let .reserved(snapshot, _) = viewModel.state,
              snapshot.dispatchKind == .guinchoDirect,
              snapshot.appointment?.status == .inProgress,
              let appointmentID = snapshot.appointment?.appointmentID,
              let destination = snapshot.guinchoTrip?.destination else {
            routeViewModel.stop()
            return
        }
        routeViewModel.activate(appointmentID: appointmentID, destination: destination)
    }

    private func failureState(lastConfirmed: MobileDispatchSnapshot?) -> some View {
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

    private func formattedPrice(_ value: Decimal, isFree: Bool) -> String {
        if isFree { return "Gratuito" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: value as NSDecimalNumber) ?? "R$ \(value)"
    }
}

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
        content
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
            .task { viewModel.start(); syncRoute() }
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
            .sheet(isPresented: $showCancellationSheet) {
                DispatchCancellationSheet(isSubmitting: isPendingCancel) { reason in
                    viewModel.cancel(reason: reason)
                }
                .interactiveDismissDisabled(isPendingCancel)
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
        ScrollView {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

                switch snapshot.appointment?.status {
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
                                guinchoWaitingMap(snapshot)
                                Button("Atualizar situação") { viewModel.refreshNow() }.frame(minHeight: 44)
                            } else if snapshot.inspection?.state == .approved {
                                Text("Vistoria aprovada pelo cliente.").font(PitGoTypography.body)
                                guinchoWaitingMap(snapshot)
                            } else {
                                GuinchoInspectionView(appointmentID: appointmentID, repository: inspectionRepository) {
                                    locallySubmittedInspectionAppointmentID = appointmentID
                                    viewModel.refreshNow()
                                }
                                .frame(minHeight: 320)
                            }
                        }
                        if snapshot.allowedActions.contains(.start),
                           let inspection = snapshot.inspection,
                           !inspection.required || inspection.state == .approved {
                            Button(action: { viewModel.startTransport() }) {
                                actionLabel("Iniciar transporte", isLoading: isPending(pendingAction, .start))
                            }
                            .foregroundStyle(.white).background(tokens.accent).clipShape(Capsule())
                            .frame(minHeight: 56).disabled(pendingAction != nil)
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
    private func guinchoWaitingMap(_ snapshot: MobileDispatchSnapshot) -> some View {
        if let trip = snapshot.guinchoTrip {
            PitGoMapView(annotations: [
                .init(id: "inspection-pickup", coordinate: trip.pickup, title: "Retirada", symbolName: "car.fill"),
                .init(id: "inspection-destination", coordinate: trip.destination, title: "Destino contratado", symbolName: "flag.fill")
            ], fitCoordinates: [trip.pickup, trip.destination], fitTrigger: 0)
            .frame(height: 280)
        }
    }

    @ViewBuilder
    private func guinchoRouteContent(_ snapshot: MobileDispatchSnapshot) -> some View {
        switch routeViewModel.state {
        case let .ready(route), let .loading(route?), let .waiting(route?, _), let .unavailable(route?, _):
            VStack(alignment: .leading, spacing: 10) {
                Text("Percurso viário · \(route.distanceMeters / 1000) km")
                    .font(PitGoTypography.body).bold()
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    guinchoRouteMap(route, now: timeline.date)
                }
                routeStatus
            }
        case .loading(nil):
            VStack(spacing: 10) {
                routeDestinationMap(snapshot)
                ProgressView("Calculando percurso…")
            }
        case let .waiting(_, message), let .unavailable(_, message):
            routeDestinationMap(snapshot)
            Text(message).font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
            Button("Tentar novamente") { routeViewModel.retry() }.frame(minHeight: 44)
        case .closed:
            EmptyView()
        }
    }

    @ViewBuilder
    private func routeDestinationMap(_ snapshot: MobileDispatchSnapshot) -> some View {
        if let destination = snapshot.guinchoTrip?.destination {
            PitGoMapView(annotations: [
                .init(id: "guincho-destination", coordinate: destination, title: "Destino contratado", symbolName: "flag.fill")
            ], centerCoordinate: destination, zoomLevel: 13)
            .frame(height: 220)
        }
    }

    private func guinchoRouteMap(_ route: GuinchoRouteSnapshot, now: Date) -> some View {
        let fix = routeViewModel.latestFix
        let isFresh = fix.map { now.timeIntervalSince($0.timestamp) <= 10 && $0.timestamp.timeIntervalSinceNow <= 5 && $0.horizontalAccuracy <= 100 } ?? false
        let current = isFresh ? fix.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } : nil
        let annotations = [
            PitGoMapAnnotationItem(id: "guincho-origin", coordinate: current ?? route.origin.point.coordinate,
                                   title: isFresh ? "Posição atual do guincho" : "Última posição usada na rota", symbolName: "car.fill"),
            PitGoMapAnnotationItem(id: "guincho-destination", coordinate: route.destination.coordinate, title: "Destino contratado", symbolName: "flag.fill")
        ]
        return VStack(alignment: .leading, spacing: 6) {
            PitGoMapView(annotations: annotations, fitCoordinates: route.coordinates, fitTrigger: Int(route.routeVersion),
                         routeLine: route.coordinates, routeVersion: route.routeVersion, routeIsEstimated: false)
                .frame(height: 280)
            if !isFresh {
                Text("Posição atual indisponível; o marcador mostra a origem registrada nesta rota.")
                    .font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
            }
        }
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

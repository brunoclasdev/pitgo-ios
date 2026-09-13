//
//  ProviderIncomingRequestView.swift
//  pitgo
//
//  Destino dedicado do provider para uma solicitação pendente/atendimento reservado (`013`,
//  contracts/mobile-dispatch-ui-navigation.md "Provider"). Recusa pré-aceite não exige motivo;
//  cancelamento pós-aceite exige (`DispatchCancellationSheet`, compartilhado com o cliente).
//

import SwiftUI

struct ProviderIncomingRequestView: View {
    @Environment(\.pitGoTokens) private var tokens
    @State private var viewModel: ProviderIncomingRequestViewModel
    @State private var showCancellationSheet = false

    let onBack: () -> Void
    let onOpenTracking: (UUID) -> Void
    let onSessionExpired: () -> Void

    init(
        providerID: UUID,
        repository: MobileDispatchRepository,
        onBack: @escaping () -> Void,
        onOpenTracking: @escaping (UUID) -> Void,
        onSessionExpired: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: ProviderIncomingRequestViewModel(providerID: providerID, repository: repository))
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
            .task { viewModel.start() }
            .onDisappear { viewModel.stop() }
            .onChange(of: isSessionExpired) { _, expired in
                if expired { onSessionExpired() }
            }
            .onChange(of: startedAppointmentID) { _, appointmentID in
                if let appointmentID { onOpenTracking(appointmentID) }
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

    private var startedAppointmentID: UUID? {
        guard case let .reserved(snapshot, _) = viewModel.state,
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

    private func reservedState(_ snapshot: MobileDispatchSnapshot, pendingAction: PendingDispatchAction?) -> some View {
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

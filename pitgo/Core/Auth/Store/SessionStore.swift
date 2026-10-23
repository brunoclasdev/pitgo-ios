//
//  SessionStore.swift
//  pitgo
//
//  Fronteira central de sessão (ver research.md §1 de `009`). `bootstrap()` é chamado explicitamente
//  na inicialização e após login/cadastro/retry — nunca implicitamente por um listener reativo de
//  `authStateChanges` para esses casos, para evitar corrida com convites/onboarding pós-cadastro.
//  `authStateChanges` é observado somente para reagir a sign-out remoto/fora de banda. O papel de
//  conta é sempre decidido por `get_my_account_context()` (via `AccountContextRepository`), nunca
//  por `raw_user_meta_data`.
//

import Combine
import Foundation
import Supabase

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var state: AppSessionState = .initializing

    private let client: SupabaseClient
    private let accountContextRepository: AccountContextRepository
    private var signOutWatcherTask: Task<Void, Never>?

    init(client: SupabaseClient) {
        self.client = client
        accountContextRepository = AccountContextRepository(client: client)
    }

    /// Chamado uma vez em `pitgoApp.swift`. Inicia a verificação inicial e o observador de sign-out
    /// remoto.
    func start() {
        guard signOutWatcherTask == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            // `027` FR-009/FR-010: detecta troca de ambiente (Dev/Homol/Prod substituem o mesmo
            // bundle identifier neste dispositivo) ANTES de validar a sessão local — nunca reaproveita
            // sessão/estado de um backend diferente do atual.
            await EnvironmentStateRepository().validate { [weak self] in
                await self?.clearIncompatibleEnvironmentState()
            }
            await self.bootstrap()
        }
        signOutWatcherTask = Task { [weak self] in
            guard let self else { return }
            for await authChangeEvent in client.auth.authStateChanges {
                if authChangeEvent.event == .signedOut {
                    await MainActor.run { self.state = .unauthenticated(reason: .sessionInvalid) }
                }
            }
        }
    }

    /// Valida a sessão local (se houver), consulta o papel autoritativo e emite o único estado
    /// exclusivo resultante. Chamado na inicialização e explicitamente após login/cadastro/retry.
    func bootstrap() async {
        state = .verifying
        do {
            let session = try await client.auth.session
            let email = session.user.email ?? ""
            switch await accountContextRepository.fetchContext(userID: session.user.id, authEmail: email) {
            case let .client(snapshot):
                state = .authenticatedClient(snapshot)
            case let .providerOnboarding(identity):
                state = .authenticatedProviderOnboarding(identity)
            case let .providerReady(snapshot):
                state = .authenticatedProviderReady(snapshot)
            case let .blocked(reason):
                state = .blocked(reason: reason)
            case .offline:
                state = .offlineVerification
            }
        } catch let authError as AuthError where authError.errorCode == .sessionNotFound {
            state = .unauthenticated(reason: nil)
        } catch is CancellationError {
            // Ignorado: a `Task` pai foi cancelada, não é uma falha de domínio.
        } catch {
            // Sessão local pode existir, mas não pôde ser validada/renovada (sem rede, timeout).
            state = .offlineVerification
        }
    }

    func signIn(email: String, password: String) async -> LoginFailureReason? {
        do {
            _ = try await client.auth.signIn(email: email, password: password)
        } catch {
            return classifyAuthFailure(error)
        }
        await bootstrap()
        return nil
    }

    func retry() async {
        await bootstrap()
    }

    /// Atualiza a projeção em memória do veículo principal com a linha autoritativa retornada por
    /// `create_vehicle`/`set_primary_vehicle` (`012`) — evita um novo `bootstrap()` só para refletir
    /// o veículo na Home/resumos. Nunca aceita um rascunho/ID vindo da UI: só o `Vehicle` devolvido
    /// pela RPC, e somente quando pertence à própria conta, está ativo e é o principal (ver
    /// data-model.md "Projeção do principal na sessão").
    func applyAuthoritativePrimaryVehicle(_ vehicle: Vehicle) {
        guard case .authenticatedClient(var snapshot) = state,
              vehicle.userID == snapshot.userID,
              vehicle.active,
              vehicle.isPrimary
        else { return }
        snapshot.primaryVehicle = vehicle
        state = .authenticatedClient(snapshot)
    }

    /// `027`: executado só quando `EnvironmentStateRepository.validate` detecta uma troca de
    /// ambiente — nunca em uso normal. Descarta a sessão local do Supabase (de outro projeto/backend,
    /// onde o JWT não tem nenhum significado) antes do primeiro `bootstrap()` do ambiente novo.
    private func clearIncompatibleEnvironmentState() async {
        try? await client.auth.signOut(scope: .local)
    }

    func signOut() async {
        try? await client.auth.signOut(scope: .local)
        state = .unauthenticated(reason: .loggedOut)
    }

    private func classifyAuthFailure(_ error: Error) -> LoginFailureReason {
        if let authError = error as? AuthError {
            switch authError.errorCode {
            case .invalidCredentials:
                return .invalidCredentials
            case .overRequestRateLimit, .overEmailSendRateLimit, .overSMSSendRateLimit:
                return .rateLimited
            case .requestTimeout:
                return .timeout
            case .unexpectedFailure, .signupDisabled, .emailProviderDisabled:
                return .service
            default:
                return .unknown
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .offline
            case .timedOut:
                return .timeout
            default:
                return .service
            }
        }
        return .unknown
    }
}

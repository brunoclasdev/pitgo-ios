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

    @Published private(set) var memberships: [RegistrationMembership] = []
    private static var recoveryKey: String { "pitgo.recoveryPending." + (Bundle.main.object(forInfoDictionaryKey: "ENVIRONMENT_ID") as? String ?? "") }
    private var recoveryActive = false {
        didSet { UserDefaults.standard.set(recoveryActive, forKey: Self.recoveryKey) }
    }
    private var verificationGeneration = 0
    private var startProviderOperation = UUID()
    private let client: SupabaseClient
    private let accountContextRepository: AccountContextRepository
    private var signOutWatcherTask: Task<Void, Never>?

    init(client: SupabaseClient) {
        self.client = client
        accountContextRepository = AccountContextRepository(client: client)
        recoveryActive = UserDefaults.standard.bool(forKey: Self.recoveryKey)
        if recoveryActive { state = .passwordRecovery(valid: false) }
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
                if authChangeEvent.event == .passwordRecovery {
                    self.recoveryActive = true
                    self.verificationGeneration += 1
                    self.state = .passwordRecovery(valid: true)
                }
                if authChangeEvent.event == .signedOut {
                    self.verificationGeneration += 1
                    self.recoveryActive = false
                    self.memberships = []
                    self.accountContextRepository.selectedMode = nil
                    self.state = .unauthenticated(reason: .sessionInvalid)
                }
            }
        }
    }

    /// Valida a sessão local (se houver), consulta o papel autoritativo e emite o único estado
    /// exclusivo resultante. Chamado na inicialização e explicitamente após login/cadastro/retry.
    func bootstrap() async {
        guard !recoveryActive else { return }
        verificationGeneration += 1
        let generation = verificationGeneration
        state = .verifying
        do {
            let session = try await client.auth.session
            let email = session.user.email ?? ""
            let result = await accountContextRepository.fetchContext(userID: session.user.id, authEmail: email)
            guard generation == verificationGeneration, !recoveryActive else { return }
            memberships = accountContextRepository.memberships
            switch result {
            case let .registration(identity, mode):
                state = .registrationRequired(identity, mode)
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
            guard generation == verificationGeneration, !recoveryActive else { return }
            state = .unauthenticated(reason: nil)
        } catch is CancellationError {
            // Ignorado: a `Task` pai foi cancelada, não é uma falha de domínio.
        } catch {
            // Sessão local pode existir, mas não pôde ser validada/renovada (sem rede, timeout).
            guard generation == verificationGeneration, !recoveryActive else { return }
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
        verificationGeneration += 1
        recoveryActive = false
        memberships = []
        accountContextRepository.selectedMode = nil
        try? await client.auth.signOut(scope: .local)
        state = .unauthenticated(reason: .loggedOut)
    }

    func selectMode(_ mode: AccountType) async {
        accountContextRepository.selectedMode = mode
        await bootstrap()
    }

    func beginProviderRegistration() async throws -> AuthIdentity {
        let session = try await client.auth.session
        _ = try await RegistrationVerificationRepository(client: client).start(.provider, operation: startProviderOperation)
        startProviderOperation = UUID()
        return AuthIdentity(userID: session.user.id, authEmail: session.user.email ?? "")
    }

    func handleRecoveryURL(_ url: URL) async {
        let expected = PasswordRecoveryViewModel.redirectURL
        guard url.scheme == expected.scheme, url.host == expected.host, url.path == expected.path else { return }
        verificationGeneration += 1
        recoveryActive = true
        state = .verifying
        do {
            // The SDK validates the PKCE verifier or recovery tokens with Auth before exposing a session.
            _ = try await client.auth.session(from: url)
            state = .passwordRecovery(valid: true)
        } catch {
            state = .passwordRecovery(valid: false)
        }
    }

    func completePasswordRecovery(password: String) async throws {
        guard recoveryActive, case .passwordRecovery(valid: true) = state else { throw CancellationError() }
        _ = try await client.auth.update(user: UserAttributes(password: password))
        recoveryActive = false
        await bootstrap()
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
